// ============================================================================
//  移动爱家 (zhihuiguanjia) 检测绕过 Tweak
//  Bundle : com.cmcc.zhihuiguanjia
//  Author : nanoMuse      Version: 1.0.0
// ----------------------------------------------------------------------------
//  说明
//   目标 App 内嵌 XJSpeechManager.framework，自带 5 个 Detector：
//     JailbreakDetector / TamperingDetector / InjectionDetector /
//     DebugDetector    / ProxyDetector
//   其中 TamperingDetector.isTampered 会读取 Info.plist 里的
//   embedded.mobileprovision，再与框架内置的 2 个 CDHash 白名单比对；
//   isTamperedWithExpectedTeamID: 会从 mobileprovision 中取
//   application-identifier 的 TeamID 段与期望值比较。
//   → 解密包 CDHash 必然变化 / 重签后 TeamID 必然变化，故两者都是 NO。
//   另覆盖 BlackbeesFrameworkSDK 的 BBJailbreakDetector 与常见 C 层检测。
// ============================================================================

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/proc.h>
#import <unistd.h>
#import <string.h>
#import <dlfcn.h>
// iOS SDK 不提供 <sys/ptrace.h>，直接内联声明（tweak 通用做法）
#ifndef PT_DENY_ATTACH
#define PT_DENY_ATTACH 31
#endif
extern int ptrace(int request, pid_t pid, caddr_t addr, int data);

#include <substrate.h>

// ---------------------------------------------------------------------------
// 日志
// ---------------------------------------------------------------------------
#define HM_LOG(fmt, ...) NSLog(@"[HeJiaBypass] " fmt, ##__VA_ARGS__)

// ---------------------------------------------------------------------------
// 工具：仅当方法真实存在才替换，避免向不存在的类注入导致崩溃
// ---------------------------------------------------------------------------
static IMP HMHookedClassMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel || !newImp) return NULL;
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        HM_LOG(@"[%@ %@] 不存在，跳过", NSStringFromClass(cls), NSStringFromSelector(sel));
        return NULL;
    }
    IMP old = method_setImplementation(m, newImp);
    HM_LOG(@"hook 类方法 [%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
    return old;
}

__attribute__((unused))
static IMP HMHookedInstanceMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel || !newImp) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        HM_LOG(@"[%@ %@] 不存在，跳过", NSStringFromClass(cls), NSStringFromSelector(sel));
        return NULL;
    }
    IMP old = method_setImplementation(m, newImp);
    HM_LOG(@"hook 实例方法 [%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
    return old;
}

// ---------------------------------------------------------------------------
// 通用「安全」返回值实现（签名必须与目标方法完全一致）
// ---------------------------------------------------------------------------
// 无参数，返回 BOOL（类方法 / 实例方法通用：self + _cmd）
static BOOL HMReturnNO(id self, SEL _cmd) { return NO; }
// 一个 id 参数，返回 BOOL
static BOOL HMReturnNO_arg1(id self, SEL _cmd, id a) { return NO; }
// 三个 id 参数，返回 void
static void HMReturnVoid_arg3(id self, SEL _cmd, id a, id b, id c) { }

// ---------------------------------------------------------------------------
// 1. XJSpeechManager —— 5 个 Detector
// ---------------------------------------------------------------------------
static void HMHookXJSpeechManager(void) {
    Class t;

    t = objc_getClass("_TtC15XJSpeechManager17JailbreakDetector");
    if (t) HMHookedClassMethod(object_getClass(t), @selector(isJailbroken), (IMP)HMReturnNO);

    t = objc_getClass("_TtC15XJSpeechManager17TamperingDetector");
    if (t) {
        Class meta = object_getClass(t);
        HMHookedClassMethod(meta, @selector(isTampered), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(isTamperedWithExpectedTeamID:), (IMP)HMReturnNO_arg1);
    }

    t = objc_getClass("_TtC15XJSpeechManager17InjectionDetector");
    if (t) HMHookedClassMethod(object_getClass(t), @selector(isInjected), (IMP)HMReturnNO);

    t = objc_getClass("_TtC15XJSpeechManager13DebugDetector");
    if (t) HMHookedClassMethod(object_getClass(t), @selector(isBeingDebugged), (IMP)HMReturnNO);

    t = objc_getClass("_TtC15XJSpeechManager13ProxyDetector");
    if (t) {
        Class meta = object_getClass(t);
        HMHookedClassMethod(meta, @selector(isProxyEnabled), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(isExternalProxyEnabled), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(isVPNTunnelActive), (IMP)HMReturnNO);
    }
}

// ---------------------------------------------------------------------------
// 2. BlackbeesFrameworkSDK —— 4 组检测类（全部是类方法）
//    BBJailbreakDetector : isJailbroken / hasSuspiciousFiles /
//                          canWriteOutsideSandbox / hasInjectedDynamicLibrary /
//                          hasCydiaURLScheme
//    BBHookDetector      : isHooked / hasSuspiciousFiles /
//                          hasSuspiciousEnv / hasFunctionHooked
//    BBProxyDetector     : isUsingProxy
//    BBAntiDebug         : enable / disableDebugger / checkDebugger  (void)
// ---------------------------------------------------------------------------
static void HMVoid(id self, SEL _cmd) { }

static void HMHookBlackbees(void) {
    Class c;

    c = objc_getClass("BBJailbreakDetector");
    if (c) {
        Class meta = object_getClass(c);
        HMHookedClassMethod(meta, @selector(isJailbroken), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(hasSuspiciousFiles), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(canWriteOutsideSandbox), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(hasInjectedDynamicLibrary), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(hasCydiaURLScheme), (IMP)HMReturnNO);
    }

    c = objc_getClass("BBHookDetector");
    if (c) {
        Class meta = object_getClass(c);
        HMHookedClassMethod(meta, @selector(isHooked), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(hasSuspiciousFiles), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(hasSuspiciousEnv), (IMP)HMReturnNO);
        HMHookedClassMethod(meta, @selector(hasFunctionHooked), (IMP)HMReturnNO);
    }

    c = objc_getClass("BBProxyDetector");
    if (c) {
        HMHookedClassMethod(object_getClass(c), @selector(isUsingProxy), (IMP)HMReturnNO);
    }

    // 调试器附加/阻断逻辑，直接置空，避免它调用 PT_DENY_ATTACH
    c = objc_getClass("BBAntiDebug");
    if (c) {
        Class meta = object_getClass(c);
        HMHookedClassMethod(meta, @selector(enable), (IMP)HMVoid);
        HMHookedClassMethod(meta, @selector(disableDebugger), (IMP)HMVoid);
        HMHookedClassMethod(meta, @selector(checkDebugger), (IMP)HMVoid);
    }
}

// ---------------------------------------------------------------------------
// 3. 主包里存在的防篡改 / andlink 环境检查（3 参数版本）
//    ⚠️ 这两种方法在主二进制中确实存在，但所属类名未在静态分析中确认，
//    因此改为「运行期按方法名全量扫描」：遍历所有已加载类，
//    谁实现了该选择器就 hook 谁，避免类名写错导致静默失效。
// ---------------------------------------------------------------------------
// 判断某个类是否属于主 App / 内嵌框架（非系统库）
static BOOL HMClassBelongsToApp(Class c) {
    Dl_info info;
    if (!dladdr((__bridge const void *)c, &info) || !info.dli_fname) {
        return NO;   // 拿不到镜像信息就跳过，宁缺勿滥
    }
    // 系统库直接跳过
    if (strstr(info.dli_fname, "/System/Library/") ||
        strstr(info.dli_fname, "/usr/lib/") ||
        strstr(info.dli_fname, "/Developer/")) {
        return NO;
    }
    return YES;
}

__attribute__((unused))
static int HMHookAllClassesImplementing(SEL sel, IMP newImp, const char *label) {
    int count = 0;
    unsigned int total = 0;
    Class *all = objc_copyClassList(&total);
    if (!all) return 0;

    for (unsigned int i = 0; i < total; i++) {
        Class c = all[i];
        if (!c) continue;

        // 先按方法表筛选：没有本类自己实现该选择器的直接跳过，
        // 这样绝大多数无关类都不会走到 dladdr，性能可控
        unsigned int mcount = 0;
        Method *methods = class_copyMethodList(c, &mcount);
        if (!methods) continue;

        Method hit = NULL;
        for (unsigned int j = 0; j < mcount; j++) {
            if (sel_isEqual(method_getName(methods[j]), sel)) {
                if (method_getImplementation(methods[j]) == newImp) {  // 已 hook
                    hit = NULL;
                    break;
                }
                hit = methods[j];
                break;
            }
        }

        if (hit && HMClassBelongsToApp(c)) {
            method_setImplementation(hit, newImp);
            HM_LOG(@"hook [%s %@] (%s)", class_getName(c),
                   NSStringFromSelector(sel), label);
            count++;
        }
        free(methods);
    }
    free(all);
    return count;
}

// 主包业务层：防篡改回调 + andlink 环境检查（3 个 id 参数、返回 void）
static void HMHookMainAppExtra(void) {
    static BOOL done = NO;
    if (done) return;
    done = YES;

    int n1 = HMHookAllClassesImplementing(
        @selector(deviceAntiTamperAction:value:callbackHandle:),
        (IMP)HMReturnVoid_arg3, "deviceAntiTamper");
    int n2 = HMHookAllClassesImplementing(
        @selector(andlinkCheckEnvironmentWithType:result:failure:),
        (IMP)HMReturnVoid_arg3, "andlinkEnvironment");

    HM_LOG(@"主包扫描：deviceAntiTamper 命中 %d 个类，andlinkCheckEnv 命中 %d 个类", n1, n2);
}

// ---------------------------------------------------------------------------
// 4. C 层：文件存在性 / sysctl / ptrace / 系统代理
// ---------------------------------------------------------------------------
static BOOL (*original_fileExistsAtPath)(id, SEL, NSString *, BOOL *) = NULL;

static BOOL HMFileExistsAtPath(id self, SEL _cmd, NSString *path, BOOL *isDirectory) {
    static NSArray<NSString *> *banned = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        banned = @[
            @"/Applications/Cydia.app",
            @"/Library/MobileSubstrate",
            @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/Library/MobileSubstrate/DynamicLibraries",
            @"/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            @"/System/Library/LaunchDaemons/com.ikey.bbot.plist",
            @"/private/var/lib/apt",
            @"/private/var/lib/cydia",
            @"/private/var/stash",
            @"/private/var/mobile/Library/SBSettings/Themes",
            @"/etc/apt",
            @"/bin/bash",
            @"/usr/sbin/sshd",
            @"/usr/libexec/ssh-keysign",
            @"/usr/bin/ssh",
            @"/etc/ssh/sshd_config",
            @"/usr/lib/libsubstrate.dylib",
            @"/usr/lib/libcycript.dylib",
            @"/usr/bin/cycript",
            @"/usr/local/bin/frida-server",
            @"/usr/bin/frida-server",
            @"/Applications/Frida.app",
            @"/var/jb",
        ];
    });

    if ([path isKindOfClass:[NSString class]]) {
        for (NSString *b in banned) {
            if ([path isEqualToString:b] ||
                [path hasPrefix:[b stringByAppendingString:@"/"]]) {
                if (isDirectory) *isDirectory = NO;
                return NO;
            }
        }
        // 越狱检测常用的「写沙盒外测试文件」
        if ([path hasPrefix:@"/private/jailbreak_test_"] ||
            [path containsString:@"jailbreak_test"]) {
            if (isDirectory) *isDirectory = NO;
            return NO;
        }
    }
    if (original_fileExistsAtPath) {
        return original_fileExistsAtPath(self, _cmd, path, isDirectory);
    }
    if (isDirectory) *isDirectory = NO;
    return NO;
}

// sysctl：只清理 kinfo_proc 里的 P_TRACED 标记，其余查询原样放行
static int (*original_sysctl)(int *, u_int, void *, size_t *, void *, size_t) = NULL;

#define HM_P_TRACED 0x00000800

static int HM_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp,
                     void *newp, size_t newlen) {
    if (!original_sysctl) return -1;

    int ret = original_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    // 调试检测惯用写法：sysctl([CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()])
    if (ret == 0 && name && namelen >= 4 &&
        name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID &&
        oldp && oldlenp && *oldlenp >= sizeof(struct kinfo_proc)) {
        struct kinfo_proc *kp = (struct kinfo_proc *)oldp;
        kp->kp_proc.p_flag &= ~HM_P_TRACED;
    }
    return ret;
}

static int (*original_ptrace)(int, pid_t, caddr_t, int) = NULL;

static int HM_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    // 屏蔽 PT_DENY_ATTACH（31）：直接返回 0，既不附加调试器也不阻止
    if (request == 31) return 0;
    if (original_ptrace) return original_ptrace(request, pid, addr, data);
    return 0;
}

// 系统代理：返回空字典（既无 HTTP 也无 HTTPS 代理）
static CFDictionaryRef (*original_copyProxySettings)(void) = NULL;
static CFDictionaryRef HM_CopySystemProxySettings(void) {
    if (original_copyProxySettings) {
        CFDictionaryRef d = original_copyProxySettings();
        if (d) CFRelease(d);
    }
    return CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                              &kCFTypeDictionaryKeyCallBacks,
                              &kCFTypeDictionaryValueCallBacks);
}

static void HMInstallCHooks(void) {
    Class NSFileMgr = objc_getClass("NSFileManager");
    if (NSFileMgr) {
        Method m = class_getInstanceMethod(NSFileMgr, @selector(fileExistsAtPath:isDirectory:));
        if (m) {
            original_fileExistsAtPath = (BOOL (*)(id, SEL, NSString *, BOOL *))
                                        method_getImplementation(m);
            method_setImplementation(m, (IMP)HMFileExistsAtPath);
            HM_LOG(@"hook -[NSFileManager fileExistsAtPath:isDirectory:]");
        }
    }

    MSHookFunction((void *)sysctl, (void *)HM_sysctl, (void **)&original_sysctl);
    HM_LOG(@"hook sysctl");

    MSHookFunction((void *)ptrace, (void *)HM_ptrace, (void **)&original_ptrace);
    HM_LOG(@"hook ptrace");

    MSHookFunction((void *)CFNetworkCopySystemProxySettings,
                   (void *)HM_CopySystemProxySettings,
                   (void **)&original_copyProxySettings);
    HM_LOG(@"hook CFNetworkCopySystemProxySettings");
}

// ---------------------------------------------------------------------------
// 5. 延迟钩子：兜住运行期 dlopen 的框架
// ---------------------------------------------------------------------------
static void HMScheduleLateHooks(void) {
    const int64_t delays[] = { 1, 3, 6, 12 };
    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delays[i] * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            HMHookBlackbees();
            HMHookMainAppExtra();
        });
    }
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HeJiaBypassInit(void) {
    @autoreleasepool {
        HM_LOG(@"════ 移动爱家检测绕过 v1.0.0 已加载 ════");

        HMHookXJSpeechManager();
        HMHookBlackbees();
        HMInstallCHooks();
        HMHookMainAppExtra();
        HMScheduleLateHooks();

        HM_LOG(@"════ 初始化完成 ════");
    }
}
