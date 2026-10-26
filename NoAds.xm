// ============================================================================
//  去广告 / 去推广模块（NoAds）
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  思路：不做「逐个广告 SDK hook」（App 内有 900+ 广告相关类、6 家 SDK），
//        而是从 App 自己的广告开关体系 + 开屏/横幅/信息流入口切入。
//
//  已确认的目标（均来自主二进制 ObjC 元数据，逐个核对过存在性）：
//    HYGetAdSwitchState           广告总开关
//      - (BOOL)getSwitchState     ← 内部 eor w0,w21,#1，返回「广告是否开启」
//      - (void)setSwitchState:
//      - (BOOL)switchState
//    持久化 key: adSwitchCloseStateStr
//
//    HYLaunchAdManager            开屏广告管理
//      startAdLaunch: / getLaunchViewData / launchAdView / launchAdForPadView
//    HYLaunchAdService            开屏广告服务
//      getLaunchAdWithTabID:withPassID: / setupService
//    HYLaunchAdView               开屏广告视图
//
//  策略：
//    1) 总开关强制返回「广告关闭」并写入持久化 key
//    2) 开屏广告入口返回 nil / 置空
//    3) isShowAd* 判断返回 NO
//    4) 兜底：按类名前缀识别主流广告 SDK，屏蔽 load*/show* 方法
//       ⚠️ 参数个数必须按类型编码动态匹配，否则会破坏调用约定导致崩溃
// ============================================================================

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <string.h>
#import <stdlib.h>
#import <dlfcn.h>

#include <substrate.h>

#define NA_LOG(fmt, ...) NSLog(@"[HeJiaNoAds] " fmt, ##__VA_ARGS__)

extern "C" {

// ---------------------------------------------------------------------------
// 通用返回值：参数个数必须与目标方法严格一致
// ---------------------------------------------------------------------------
static BOOL na_NO0(id self, SEL _cmd) { return NO; }
static BOOL na_NO1(id self, SEL _cmd, id a) { (void)a; return NO; }
static BOOL na_NO2(id self, SEL _cmd, id a, id b) { (void)a; (void)b; return NO; }

static void na_void0(id self, SEL _cmd) { }
static void na_void1(id self, SEL _cmd, id a) { (void)a; }
static void na_void2(id self, SEL _cmd, id a, id b) { (void)a; (void)b; }
static void na_void3(id self, SEL _cmd, id a, id b, id c) { (void)a; (void)b; (void)c; }

static id na_nil0(id self, SEL _cmd) { return nil; }
static id na_nil1(id self, SEL _cmd, id a) { (void)a; return nil; }
static id na_nil2(id self, SEL _cmd, id a, id b) { (void)a; (void)b; return nil; }
static id na_nil3(id self, SEL _cmd, id a, id b, id c) { (void)a; (void)b; (void)c; return nil; }

// 统计选择器里的冒号数量 = 参数个数
static int na_argCount(const char *sel) {
    int n = 0;
    if (!sel) return 0;
    for (const char *p = sel; *p; p++) if (*p == ':') n++;
    return n;
}

// 按参数个数挑选「返回 nil」的实现
static IMP na_nilFor(int argc) {
    switch (argc) {
        case 0: return (IMP)na_nil0;
        case 1: return (IMP)na_nil1;
        case 2: return (IMP)na_nil2;
        case 3: return (IMP)na_nil3;
        default: return (IMP)na_nil3;   // 更多参数：前三个之后不读，安全
    }
}

// 按参数个数挑选「返回 NO」的实现
__attribute__((unused))
static IMP na_noFor(int argc) {
    switch (argc) {
        case 0: return (IMP)na_NO0;
        case 1: return (IMP)na_NO1;
        case 2: return (IMP)na_NO2;
        default: return (IMP)na_NO2;
    }
}

// 按参数个数挑选「空实现」
static IMP na_voidFor(int argc) {
    switch (argc) {
        case 0: return (IMP)na_void0;
        case 1: return (IMP)na_void1;
        case 2: return (IMP)na_void2;
        default: return (IMP)na_void3;
    }
}

// 安全 hook：只在方法真实存在时替换
__attribute__((unused))
static IMP na_hookInst(Class cls, SEL sel, IMP imp, const char *tag) {
    if (!cls || !sel || !imp) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    IMP old = method_setImplementation(m, imp);
    NA_LOG(@"hook -[%s %s]%s", class_getName(cls), sel_getName(sel), tag ? tag : "");
    return old;
}

// 判断类是否属于 App 自身镜像（跳过系统框架，避免误伤 UIKit/Foundation）
static BOOL na_isAppClass(Class c) {
    Dl_info info;
    if (!dladdr((__bridge const void *)c, &info) || !info.dli_fname) return NO;
    if (strstr(info.dli_fname, "/System/Library/") ||
        strstr(info.dli_fname, "/usr/lib/")) return NO;
    return YES;
}

// ---------------------------------------------------------------------------
// 1. 广告总开关：HYGetAdSwitchState
// ---------------------------------------------------------------------------
static void na_hookMasterSwitch(void) {
    Class c = objc_getClass("HYGetAdSwitchState");
    if (!c) {
        NA_LOG(@"未找到 HYGetAdSwitchState");
        return;
    }
    // getSwitchState / switchState 实际语义是「广告是否开启」→ 强制 NO
    na_hookInst(c, @selector(getSwitchState), (IMP)na_NO0, " ->NO");
    na_hookInst(c, @selector(switchState),    (IMP)na_NO0, " ->NO");
    // 防止外部把开关改回开
    na_hookInst(c, @selector(setSwitchState:), (IMP)na_void1, " 置空");

    // 持久化层：写入「已关闭」
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:@"adSwitchCloseStateStr"];
    [ud synchronize];
    NA_LOG(@"写入 adSwitchCloseStateStr=YES");
}

// ---------------------------------------------------------------------------
// 2. 开屏广告入口
// ---------------------------------------------------------------------------
static void na_hookLaunchAd(void) {
    // HYLaunchAdManager：所有取数据/取视图的方法 -> nil
    Class mgr = objc_getClass("HYLaunchAdManager");
    if (mgr) {
        static const char *sels[] = {
            "getLaunchViewData",
            "launchAdView",
            "launchAdForPadView",
            "launchBirthdayView",
            "launchAdService",
            NULL
        };
        for (int i = 0; sels[i]; i++) {
            SEL s = sel_registerName(sels[i]);
            na_hookInst(mgr, s, na_nilFor(na_argCount(sels[i])), " ->nil");
        }
        // 启动开屏广告：直接返回，不加载
        SEL start = sel_registerName("startAdLaunch:");
        na_hookInst(mgr, start, na_nilFor(1), " 跳过");
    }

    // HYLaunchAdService：拉取开屏广告数据
    Class svc = objc_getClass("HYLaunchAdService");
    if (svc) {
        SEL fetch = sel_registerName("getLaunchAdWithTabID:withPassID:");
        na_hookInst(svc, fetch, na_nilFor(2), " ->nil");
        SEL setup = sel_registerName("setupService");
        na_hookInst(svc, setup, na_voidFor(0), " 置空");
    }
}

// ---------------------------------------------------------------------------
// 3. isShowAd* 系列判断（只处理无参 BOOL 方法）
// ---------------------------------------------------------------------------
static void na_hookShowFlags(void) {
    unsigned int total = 0;
    Class *all = objc_copyClassList(&total);
    if (!all) return;

    int hooked = 0;
    for (unsigned int i = 0; i < total; i++) {
        Class c = all[i];
        if (!c) continue;
        if (!na_isAppClass(c)) continue;   // 跳过系统类

        unsigned int cnt = 0;
        Method *ms = class_copyMethodList(c, &cnt);
        if (!ms) continue;

        for (unsigned int j = 0; j < cnt; j++) {
            const char *sn = sel_getName(method_getName(ms[j]));
            if (!sn) continue;
            const char *types = method_getTypeEncoding(ms[j]);
            // 必须是无参 BOOL：编码形如 "B16@0:8"
            if (!types || types[0] != 'B') continue;
            if (na_argCount(sn) != 0) continue;
            if (strncmp(sn, "isShowAd", 8) != 0 &&
                strncmp(sn, "isShowAD", 8) != 0) continue;

            method_setImplementation(ms[j], (IMP)na_NO0);
            hooked++;
            NA_LOG(@"hook -[%s %s] ->NO", class_getName(c), sn);
        }
        free(ms);
    }
    free(all);
    NA_LOG(@"isShowAd* 共处理 %d 个", hooked);
}

// ---------------------------------------------------------------------------
// 4. 兜底：主流广告 SDK
// ---------------------------------------------------------------------------
static BOOL na_isAdSDKClass(const char *name) {
    static const char *prefixes[] = {
        "ABU", "BUAd", "BUNative", "BUSplash", "BUM",
        "GDT", "KSAd", "BaiduMobAd",
        "JAD", "CSJ", "DSP", "MIGUAd", "MIGUAD",
        "Sigmob", "Gromore", "MADX", "CXAd", "CXJAd",
        NULL
    };
    for (int i = 0; prefixes[i]; i++) {
        size_t len = strlen(prefixes[i]);
        if (strncmp(name, prefixes[i], len) == 0) return YES;
    }
    return NO;
}

static void na_hookAdSDKs(void) {
    unsigned int total = 0;
    Class *all = objc_copyClassList(&total);
    if (!all) return;

    int hooked = 0;
    for (unsigned int i = 0; i < total; i++) {
        Class c = all[i];
        if (!c) continue;
        const char *cn = class_getName(c);
        if (!cn || !na_isAdSDKClass(cn)) continue;
        if (!na_isAppClass(c)) continue;

        for (int pass = 0; pass < 2; pass++) {
            Class target = (pass == 0) ? object_getClass(c) : c;
            unsigned int cnt = 0;
            Method *ms = class_copyMethodList(target, &cnt);
            if (!ms) continue;

            for (unsigned int j = 0; j < cnt; j++) {
                const char *sn = sel_getName(method_getName(ms[j]));
                if (!sn) continue;
                const char *types = method_getTypeEncoding(ms[j]);
                if (!types) continue;

                // 只处理「返回 void 或对象」的方法
                BOOL isVoid = (types[0] == 'v');
                BOOL isObj  = (types[0] == '@');
                if (!isVoid && !isObj) continue;

                BOOL isShow = (strstr(sn, "show")  || strstr(sn, "Show")  ||
                               strstr(sn, "render")|| strstr(sn, "Render")||
                               strstr(sn, "present"));
                BOOL isLoad = (strstr(sn, "loadAd") || strstr(sn, "LoadAd") ||
                               strstr(sn, "requestAd") || strstr(sn, "RequestAd"));
                if (!isShow && !isLoad) continue;

                int argc = na_argCount(sn);
                IMP imp = isVoid ? na_voidFor(argc) : na_nilFor(argc);
                method_setImplementation(ms[j], imp);
                hooked++;
            }
            free(ms);
        }
    }
    free(all);
    NA_LOG(@"广告 SDK 方法共处理 %d 个", hooked);
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HeJiaNoAdsInit(void) {
    @autoreleasepool {
        NA_LOG(@"════ 去广告模块加载 ════");
        na_hookMasterSwitch();
        na_hookLaunchAd();
        na_hookShowFlags();
        na_hookAdSDKs();
        NA_LOG(@"════ 去广告初始化完成 ════");
    }
}

} // extern "C"
