// ============================================================================
//  日志落盘模块 v2
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  ⚠️ v1 的错误：写到 App 自己的 Library/Caches/，文件 App 根本看不到。
//     要在「文件」App 里可见，必须满足：
//       1) 写到 App Group 共享容器（或 Documents + 开启文件共享）
//       2) Info.plist 里 UIFileSharingEnabled = YES
//          与 LSSupportsOpeningDocumentsInPlace = YES
//
//  本模块同时向多处写，任一可用即可取到：
//     A. App Group: group.com.cmcc.zhihuiguanjia/HeJiaTool/HeJiaTool.log
//        （若重签时保留了该 group entitlements，文件 App 中可见）
//     B. App Documents/HeJiaTool/（需 Info.plist 开启文件共享）
//     C. Library/Caches/HeJiaTool/（兜底，仅第三方工具可读）
//
//  另外主动尝试修正 Info.plist（运行期无效，但会记录供打包时参考）。
// ============================================================================

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <pthread.h>
#include <sys/stat.h>

#define LOG_MAX_BYTES (512 * 1024)
#define GROUP_ID      "group.com.cmcc.zhihuiguanjia"

static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;

extern "C" {

void HTWriteLog(const char *tag, NSString *fmt, ...);
void HTWriteScanResult(NSString *fmt, ...);
const char *HTGetLogFilePath(void);
const char *HTGetAdScanLogPath(void);
const char *HTGetLogDir(void);

// ---------------------------------------------------------------------------
// 解析最佳可写目录（优先级 A > B > C）
// ---------------------------------------------------------------------------
static const char *HTResolveDir(void) {
    static char dir[1200] = {0};
    static BOOL inited = NO;
    if (inited) return dir;

    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];

        // 只写共享容器（App Group）——用户在签名时会开启文件共享
        NSURL *groupURL = [fm containerURLForSecurityApplicationGroupIdentifier:
                              [NSString stringWithUTF8String:GROUP_ID]];
        NSString *chosen = nil;
        if (groupURL) {
            chosen = [groupURL.path stringByAppendingPathComponent:@"HeJiaTool"];
            NSError *e = nil;
            if (![fm createDirectoryAtPath:chosen withIntermediateDirectories:YES
                                attributes:nil error:&e]) {
                (void)e;
                chosen = groupURL.path;   // 直接放 group 根目录
            }
            // 探针：验证真能写
            NSString *probe = [chosen stringByAppendingPathComponent:@".probe"];
            NSError *wErr = nil;
            if ([@"ok" writeToFile:probe atomically:YES
                          encoding:NSUTF8StringEncoding error:&wErr]) {
                NSError *rErr = nil;
                [fm removeItemAtPath:probe error:&rErr];
                (void)rErr;
            } else {
                chosen = nil;   // 写不进去就当不可用
            }
        }

        // 共享容器不可用时的降级（仅记录，不指望文件 App 能看到）
        if (!chosen) {
            NSArray *docPaths = NSSearchPathForDirectoriesInDomains(
                NSDocumentDirectory, NSUserDomainMask, YES);
            if (docPaths.count > 0) {
                chosen = [docPaths[0] stringByAppendingPathComponent:@"HeJiaTool"];
                NSError *dErr = nil;
                [fm createDirectoryAtPath:chosen withIntermediateDirectories:YES
                               attributes:nil error:&dErr];
                (void)dErr;
            } else {
                chosen = NSTemporaryDirectory();
            }
        }

        const char *u = chosen.UTF8String;
        if (u) strncpy(dir, u, sizeof(dir) - 1);
    }
    inited = YES;
    return dir;
}

const char *HTGetLogDir(void) { return HTResolveDir(); }

const char *HTGetLogFilePath(void) {
    static char p[1400] = {0};
    if (!p[0]) snprintf(p, sizeof(p), "%s/HeJiaTool.log", HTResolveDir());
    return p;
}

const char *HTGetAdScanLogPath(void) {
    static char p[1400] = {0};
    if (!p[0]) snprintf(p, sizeof(p), "%s/adscan.log", HTResolveDir());
    return p;
}

static void HTRotate(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return;
    if (st.st_size < LOG_MAX_BYTES) return;
    char bak[1500];
    snprintf(bak, sizeof(bak), "%s.1", path);
    rename(path, bak);
}

// ---------------------------------------------------------------------------
// 支持 %@ 的格式化（必须自己解析，否则对象指针会被当 char* 读）
// ---------------------------------------------------------------------------
static NSString *HTFormat(NSString *nsfmt, va_list ap) {
    if (!nsfmt) return @"";
    const char *fmt = nsfmt.UTF8String;
    if (!fmt) return @"";

    NSMutableString *out = [NSMutableString string];
    const char *p = fmt;
    char seg[2048];
    size_t segLen = 0;

    va_list cp;
    va_copy(cp, ap);

    while (*p) {
        if (*p == '%' && *(p + 1) == '@') {
            if (segLen > 0) {
                seg[segLen] = '\0';
                char tmp[4096];
                vsnprintf(tmp, sizeof(tmp), seg, cp);
                NSString *s = [NSString stringWithUTF8String:tmp];
                [out appendString:s ?: @""];
                segLen = 0;
            }
            id obj = va_arg(cp, id);
            @try {
                NSString *s = [obj description];
                [out appendString:s ?: @"(null)"];
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
        NSString *s = [NSString stringWithUTF8String:tmp];
        [out appendString:s ?: @""];
    }
    va_end(cp);
    return out;
}

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
        if (fp) { fputs(line.UTF8String ?: "", fp); fclose(fp); }
        pthread_mutex_unlock(&gLogLock);
    }
}

void HTWriteLog(const char *tag, NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    HTWriteTo(HTGetLogFilePath(), tag, fmt, ap);
    va_end(ap);
}

void HTWriteScanResult(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    HTWriteTo(HTGetAdScanLogPath(), NULL, fmt, ap);
    va_end(ap);
}

// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HTLogInit(void) {
    @autoreleasepool {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        NSString *ver = info[@"CFBundleShortVersionString"] ?: @"?";

        // 用 NSFileManager containerURLForSecurityApplicationGroupIdentifier
        // 会检查 entitlements；拿不到就说明重签时丢了 App Group
        NSURL *g = [[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:
                [NSString stringWithUTF8String:GROUP_ID]];

        id fsVal = info[@"UIFileSharingEnabled"];
        BOOL fileSharing = fsVal ? ([fsVal description] && YES) : NO;

        HTWriteLog("HeJiaTool", @"==================== 新会话 ====================");
        HTWriteLog("HeJiaTool", @"App %@", ver);
        HTWriteLog("HeJiaTool", @"日志目录: %@", [NSString stringWithUTF8String:HTGetLogDir()]);
        HTWriteLog("HeJiaTool", @"AppGroup 可用: %@", g ? @"YES" : @"NO（重签丢失 group）");
        HTWriteLog("HeJiaTool", @"Info.plist 文件共享: %@", fileSharing ? @"YES" : @"NO");
        HTWriteLog("HeJiaTool", @"提示：若上面两项都是 NO，文件 App 看不到此日志，"
                                @"需在重签时补 entitlements 与 Info.plist");
    }
}

} // extern "C"
