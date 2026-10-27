// ============================================================================
//  日志落盘模块
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  NSLog 只进系统日志缓冲，用户没有 Mac 就取不到。本模块把所有 [HeJia*]
//  日志同时写入沙盒文件：
//
//    <沙盒>/Library/Caches/HeJiaTool/HeJiaTool.log   主日志
//    <沙盒>/Library/Caches/HeJiaTool/adscan.log      广告扫描明细
//
//  ⚠️ 关键点：必须支持 %@（ObjC 对象）格式符。
//     直接把这些变参丢给 vsnprintf 会把对象指针当 char* 读，必定崩溃。
//     因此这里自己解析格式串，%@ 走 ObjC 分支。
// ============================================================================

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdarg.h>
#include <string.h>
#include <pthread.h>
#include <sys/stat.h>

#define LOG_MAX_BYTES (512 * 1024)

static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;

extern "C" {

void HTWriteLog(const char *tag, NSString *fmt, ...);
void HTWriteScanResult(NSString *fmt, ...);
const char *HTGetLogFilePath(void);
const char *HTGetAdScanLogPath(void);

// ---------------------------------------------------------------------------
// 沙盒日志目录
// ---------------------------------------------------------------------------
static const char *HTLogDir(void) {
    static char dir[1024] = {0};
    static BOOL inited = NO;
    if (inited) return dir;

    @autoreleasepool {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                             NSUserDomainMask, YES);
        NSString *cache = paths.count > 0 ? paths[0] : NSTemporaryDirectory();
        NSString *d = [cache stringByAppendingPathComponent:@"HeJiaTool"];
        NSError *dirErr = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:d
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&dirErr];
        (void)dirErr;
        const char *u = d.UTF8String;
        if (u) strncpy(dir, u, sizeof(dir) - 1);
    }
    inited = YES;
    return dir;
}

const char *HTGetLogFilePath(void) {
    static char p[1200] = {0};
    if (!p[0]) snprintf(p, sizeof(p), "%s/HeJiaTool.log", HTLogDir());
    return p;
}

const char *HTGetAdScanLogPath(void) {
    static char p[1200] = {0};
    if (!p[0]) snprintf(p, sizeof(p), "%s/adscan.log", HTLogDir());
    return p;
}

static void HTRotate(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return;
    if (st.st_size < LOG_MAX_BYTES) return;
    char bak[1300];
    snprintf(bak, sizeof(bak), "%s.1", path);
    rename(path, bak);
}

// ---------------------------------------------------------------------------
// 支持 %@ 的格式化
//   逐个解析格式串：遇到 %@ 取 id 转 UTF8；其余交给 vsnprintf 分段处理
// ---------------------------------------------------------------------------
static NSString *HTFormat(NSString *nsfmt, va_list ap) {
    if (!nsfmt) return @"";
    const char *fmt = nsfmt.UTF8String;
    if (!fmt) return @"";

    NSMutableString *out = [NSMutableString string];
    const char *p = fmt;
    char seg[2048];          // 累积「非 %@」的片段
    size_t segLen = 0;

    va_list cp;
    va_copy(cp, ap);

    while (*p) {
        if (*p == '%' && *(p + 1) == '@') {
            // 先把已累积片段按 C 格式输出
            if (segLen > 0) {
                seg[segLen] = '\0';
                char tmp[4096];
                vsnprintf(tmp, sizeof(tmp), seg, cp);
                [out appendString:[NSString stringWithUTF8String:tmp] ?: @""];
                segLen = 0;
            }
            // 取对象参数
            id obj = va_arg(cp, id);
            @try {
                NSString *s = [obj description];
                [out appendString:(s ?: @"(null)")];
            } @catch (NSException *e) {
                (void)e;
                [out appendString:@"<desc-error>"];
            }
            p += 2;
        } else {
            if (segLen < sizeof(seg) - 2) seg[segLen++] = *p;
            p++;
        }
    }

    if (segLen > 0) {
        seg[segLen] = '\0';
        char tmp[4096];
        vsnprintf(tmp, sizeof(tmp), seg, cp);
        [out appendString:[NSString stringWithUTF8String:tmp] ?: @""];
    }
    va_end(cp);
    return out;
}

// ---------------------------------------------------------------------------
// 写日志
// ---------------------------------------------------------------------------
static void HTWriteTo(const char *path, const char *tag, NSString *fmt, va_list ap) {
    @autoreleasepool {
        NSString *body = HTFormat(fmt, ap);
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"MM-dd HH:mm:ss.SSS";
        NSString *ts = [df stringFromDate:[NSDate date]];

        NSString *line = tag
            ? [NSString stringWithFormat:@"%@ [%@] %@\n", ts,
                                        [NSString stringWithUTF8String:tag], body]
            : [NSString stringWithFormat:@"%@ %@\n", ts, body];

        fprintf(stderr, "%s", line.UTF8String ?: "");

        pthread_mutex_lock(&gLogLock);
        HTRotate(path);
        FILE *fp = fopen(path, "a");
        if (fp) {
            fputs(line.UTF8String ?: "", fp);
            fclose(fp);
        }
        pthread_mutex_unlock(&gLogLock);
    }
}

void HTWriteLog(const char *tag, NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    HTWriteTo(HTGetLogFilePath(), tag, fmt, ap);
    va_end(ap);
}

void HTWriteScanResult(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    HTWriteTo(HTGetAdScanLogPath(), NULL, fmt, ap);
    va_end(ap);
}

// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HTLogInit(void) {
    @autoreleasepool {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        NSString *ver = info[@"CFBundleShortVersionString"] ?: @"?";
        NSString *build = info[@"CFBundleVersion"] ?: @"?";

        HTWriteLog("HeJiaTool", @"==================== 新会话 ====================");
        HTWriteLog("HeJiaTool", @"App %@ (%@)", ver, build);
        HTWriteLog("HeJiaTool", @"日志: %@", [NSString stringWithUTF8String:HTGetLogFilePath()]);
        HTWriteLog("HeJiaTool", @"扫描: %@", [NSString stringWithUTF8String:HTGetAdScanLogPath()]);
    }
}

} // extern "C"
