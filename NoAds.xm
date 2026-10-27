// ============================================================================
//  广告 SDK 屏蔽 + 假生效（NoAds 重写版）
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  为什么之前无效：只 hook 了展示方法，但广告数据是 HTTP 拉下来的，
//  SDK 拿到数据后可能走 C/Swift 层直接渲染，ObjC 层 hook 抓不住。
//
//  本版改为「源头断流」四层：
//    1) 网络层：拦截广告接口，直接返回空数据（最彻底）
//    2) SDK 层：让初始化「假成功」，之后所有加载/展示调用都短路
//    3) 数据层：广告数据模型数组返回空
//    4) 展示层：show/render/present 兜底
//
//  已确认的广告接口（来自主二进制）：
//     %@/ms/v1/ads/page/start            开屏广告
//     %@/app/v2/ads/adv/common           通用广告
//     base/idx/getBannerContentList      首页 banner
//     /ad/report  /ad/click  /ad/impression   埋点（一并掐断）
// ============================================================================

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <string.h>
#import <stdlib.h>
#import <dlfcn.h>

#include <substrate.h>

extern "C" void HTLog(const char *tag, NSString *msg);
extern "C" void HTScan(NSString *msg);
extern "C" void HTLogC(const char *tag, const char *cfmt, ...);
#define NA_LOG(...) HTLog("HeJiaNoAds", [NSString stringWithFormat:__VA_ARGS__])
// 扫描输出：纯 C 格式（不含 %@），避免变参解析
#define NA_SCAN(cfmt, ...) HTLogC("SCAN", cfmt, ##__VA_ARGS__)

extern "C" {

// 与设置页共用的配置键
static NSString *const kNAEnabledKey = @"HeJiaTool_NoAds";

__attribute__((unused))
static BOOL na_isEnabled(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    id v = [ud objectForKey:kNAEnabledKey];
    if (!v) return YES;   // 默认开启
    return [ud boolForKey:kNAEnabledKey];
}

// ===========================================================================
// 广告接口特征表
// ===========================================================================
static const char *kAdURLMarkers[] = {
    // 只拦真正的广告/推广接口，绝不动核心业务接口
    "/ads/page/start",          // 开屏广告
    "/ads/adv/common",          // 通用广告位
    "/ad/report",               // 广告埋点
    "/ad/click",
    "/ad/impression",
    "/ad/statistics",
    "getBannerContentList",     // 首页 banner 推广
    "getTabBannerList",         // Tab 页 banner 推广
    NULL
};

// 明确排除：这些是核心业务接口，即使命中上面的关键字也不能拦
static const char *kNeverBlock[] = {
    "deviceListApp",            // 设备列表
    "getFrameList",             // 首页框架/布局
    "getPlaceList",             // 栏目配置
    "getDynamicPlaceList",
    "getTabContentList",        // Tab 内容
    "getTriggerMsgList",        // 消息
    "getYdnGuideBindList",      // 引导绑定
    "/photo/",                  // 图片资源
    ".png", ".jpg", ".webp",    // 静态资源
    NULL
};

static BOOL na_isAdURL(NSString *url) {
    if (![url isKindOfClass:[NSString class]]) return NO;
    const char *s = url.UTF8String;
    if (!s) return NO;

    // 先排除核心业务
    for (int i = 0; kNeverBlock[i]; i++) {
        if (strstr(s, kNeverBlock[i])) return NO;
    }
    // 再匹配广告特征
    for (int i = 0; kAdURLMarkers[i]; i++) {
        if (strstr(s, kAdURLMarkers[i])) return YES;
    }
    return NO;
}

// ===========================================================================
// 通用返回值（参数个数严格匹配，防止破坏调用约定）
// ===========================================================================
static BOOL na_NO0(id self, SEL _cmd) { return NO; }
__attribute__((unused))
static BOOL na_NO1(id self, SEL _cmd, id a) { (void)a; return NO; }

static void na_void0(id self, SEL _cmd) { }
static void na_void1(id self, SEL _cmd, id a) { (void)a; }
static void na_void2(id self, SEL _cmd, id a, id b) { (void)a; (void)b; }
static void na_void3(id self, SEL _cmd, id a, id b, id c) { (void)a; (void)b; (void)c; }
static void na_void4(id self, SEL _cmd, id a, id b, id c, id d) {
    (void)a; (void)b; (void)c; (void)d;
}

static id na_nil0(id self, SEL _cmd) { return nil; }
static id na_nil1(id self, SEL _cmd, id a) { (void)a; return nil; }
static id na_nil2(id self, SEL _cmd, id a, id b) { (void)a; (void)b; return nil; }
static id na_nil3(id self, SEL _cmd, id a, id b, id c) { (void)a; (void)b; (void)c; return nil; }
static id na_nil4(id self, SEL _cmd, id a, id b, id c, id d) {
    (void)a; (void)b; (void)c; (void)d; return nil;
}

static int na_argc(const char *sel) {
    int n = 0;
    if (!sel) return 0;
    for (const char *p = sel; *p; p++) if (*p == ':') n++;
    return n;
}

static IMP na_nilFor(int argc) {
    switch (argc) {
        case 0: return (IMP)na_nil0;
        case 1: return (IMP)na_nil1;
        case 2: return (IMP)na_nil2;
        case 3: return (IMP)na_nil3;
        default: return (IMP)na_nil4;
    }
}

static IMP na_voidFor(int argc) {
    switch (argc) {
        case 0: return (IMP)na_void0;
        case 1: return (IMP)na_void1;
        case 2: return (IMP)na_void2;
        case 3: return (IMP)na_void3;
        default: return (IMP)na_void4;
    }
}

static BOOL na_isAppClass(Class c) {
    Dl_info info;
    if (!dladdr((__bridge const void *)c, &info) || !info.dli_fname) return NO;
    if (strstr(info.dli_fname, "/System/Library/") ||
        strstr(info.dli_fname, "/usr/lib/")) return NO;
    return YES;
}

// ===========================================================================
// 第 1 层：网络层断流
//   NSURLSession 的 completionHandler 与 delegate 两条路径都拦
// ===========================================================================

// --- NSURLSession dataTaskWithRequest:completionHandler: ---
static IMP na_orig_dataTask = NULL;

static id na_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *req, id handler) {
    void (^h)(NSData *, NSURLResponse *, NSError *) = handler;
    if (req && na_isEnabled() && na_isAdURL([req.URL absoluteString])) {
        NSString *u = [req.URL absoluteString];
        NA_LOG(@"拦截广告请求: %@", u);
        NA_SCAN("[BLOCKED] %s\n", (u.UTF8String ?: "?"));
        if (h) {
            // 返回空 JSON，让上层认为「没广告」
            NSData *empty = [@"{\"data\":[],\"resultCode\":\"0\",\"code\":0}" dataUsingEncoding:NSUTF8StringEncoding];
            h(empty, nil, nil);
        }
        return nil;
    }
    typedef id (*fn_t)(id, SEL, NSURLRequest *, id);
    fn_t orig = (fn_t)na_orig_dataTask;
    return orig ? orig(self, _cmd, req, handler) : nil;
}

// ===========================================================================
// 第 2 层：SDK 初始化「假成功」
// ===========================================================================
static BOOL na_isAdSDKClass(const char *name) {
    static const char *prefixes[] = {
        "ABU", "BUAd", "BUNative", "BUSplash", "BUM",
        "GDT", "KSAd", "BaiduMobAd",
        "JAD", "CSJ", "DSP", "MIGUAd", "MIGUAD",
        "Sigmob", "Gromore", "MADX", "CXAd", "CXJAd",
        "MSAd", "MediaMobAd", "Pangle",
        NULL
    };
    for (int i = 0; prefixes[i]; i++) {
        size_t len = strlen(prefixes[i]);
        if (strncmp(name, prefixes[i], len) == 0) return YES;
    }
    return NO;
}

static void na_patchAdSDKClasses(void) {
    unsigned int total = 0;
    Class *all = objc_copyClassList(&total);
    if (!all) return;

    int patched = 0;
    NA_SCAN("\n===== 广告 SDK 扫描 =====\n");
    NA_SCAN("# 枚举到的类总数: %u\n", total);

    // 统计各家 SDK 命中情况
    int statABU = 0, statGDT = 0, statKS = 0, statBaidu = 0, statJAD = 0,
        statDSP = 0, statMIGU = 0, statOther = 0;

    for (unsigned int i = 0; i < total; i++) {
        Class c = all[i];
        if (!c) continue;
        const char *cn = class_getName(c);
        if (!cn || !na_isAdSDKClass(cn)) continue;
        if (!na_isAppClass(c)) continue;

        // 分类统计
        if (strncmp(cn, "ABU", 3) == 0 || strncmp(cn, "BUAd", 4) == 0) statABU++;
        else if (strncmp(cn, "GDT", 3) == 0) statGDT++;
        else if (strncmp(cn, "KSAd", 4) == 0) statKS++;
        else if (strncmp(cn, "BaiduMobAd", 10) == 0) statBaidu++;
        else if (strncmp(cn, "JAD", 3) == 0) statJAD++;
        else if (strncmp(cn, "DSP", 3) == 0) statDSP++;
        else if (strncmp(cn, "MIGU", 4) == 0) statMIGU++;
        else statOther++;

        NA_SCAN("[CLASS] %s\n", cn);

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

                BOOL retVoid = (types[0] == 'v');
                BOOL retObj  = (types[0] == '@');
                BOOL retBool __attribute__((unused)) = (types[0] == 'B');

                // ⚠️ 不碰初始化/注册/加载：
                //    屏蔽它们会让 SDK 内部状态不一致 → App 崩溃
                if (strstr(sn, "init") || strstr(sn, "start") ||
                    strstr(sn, "register") || strstr(sn, "setup") ||
                    strstr(sn, "load") || strstr(sn, "Load") ||
                    strstr(sn, "request") || strstr(sn, "Request") ||
                    strstr(sn, "fetch") || strstr(sn, "Fetch")) {
                    continue;
                }

                // 只屏蔽「展示」这一最安全子集
                BOOL isShow = (strstr(sn, "show") || strstr(sn, "Show") ||
                               strstr(sn, "render") || strstr(sn, "Render") ||
                               strstr(sn, "present") || strstr(sn, "Present"));
                if (!isShow) continue;
                if (!retVoid && !retObj) continue;

                if (retVoid)      { method_setImplementation(ms[j], na_voidFor(na_argc(sn))); patched++; }
                else if (retObj)  { method_setImplementation(ms[j], na_nilFor(na_argc(sn))); patched++; }
            }
            free(ms);
        }
    }
    free(all);

    NA_SCAN("\n# 分类统计\n");
    NA_SCAN("  穿山甲/ABU : %d\n", statABU);
    NA_SCAN("  优量汇/GDT : %d\n", statGDT);
    NA_SCAN("  快手/KSAd  : %d\n", statKS);
    NA_SCAN("  百度/Baidu : %d\n", statBaidu);
    NA_SCAN("  京准通/JAD : %d\n", statJAD);
    NA_SCAN("  阿里/DSP   : %d\n", statDSP);
    NA_SCAN("  咪咕/MIGU  : %d\n", statMIGU);
    NA_SCAN("  其他       : %d\n", statOther);
    NA_SCAN("  已屏蔽方法 : %d\n", patched);

    NA_LOG(@"广告 SDK 方法屏蔽 %d 个（明细见 adscan.log）", patched);
}

// ===========================================================================
// 第 3 层：广告数据模型数组 -> 空
// ===========================================================================
static NSArray *na_emptyArray(id self, SEL _cmd) { return @[]; }

static void na_patchAdDataGetters(void) {
    static const char *pairs[][2] = {
        {"HYLaunchAdManager",   "getLaunchViewData"},
        {"HYLaunchAdManager",   "safeAdDataArrayFromService:"},
        {"HYLaunchAdManager",   "safeAdDataArrayLoadData:"},
        {"HYBannerManager",     "bannerList"},
        {"HYBannerManager",     "getBannerList"},
        {NULL, NULL}
    };
    for (int i = 0; pairs[i][0]; i++) {
        Class c = objc_getClass(pairs[i][0]);
        if (!c) continue;
        SEL s = sel_registerName(pairs[i][1]);
        Method m = class_getInstanceMethod(c, s);
        if (!m) continue;
        const char *types = method_getTypeEncoding(m);
        if (types && types[0] == '@') {
            method_setImplementation(m, (IMP)na_nilFor(na_argc(pairs[i][1])));
            NA_LOG(@"数据层: -[%s %s] -> nil", pairs[i][0], pairs[i][1]);
        }
    }
    (void)na_emptyArray;
}

// ===========================================================================
// 第 4 层：总开关 + isShowAd*
// ===========================================================================
// ---------------------------------------------------------------------------
// 网络层 v2：AFNetworking 走 delegate 模式，completionHandler 版本抓不到，
// 必须 hook 最底层的 -[NSURLSession dataTaskWithRequest:]
// ---------------------------------------------------------------------------
static IMP na_orig_dataTaskReq = NULL;

static id na_dataTaskWithRequestOnly(id self, SEL _cmd, NSURLRequest *req) {
    if (req && na_isEnabled()) {
        NSString *u = [req.URL absoluteString];
        if (na_isAdURL(u)) {
            NA_LOG(@"拦截广告请求(task): %@", u);
            NA_SCAN("[BLOCKED] %s\n", (u.UTF8String ?: "?"));
            // 返回一个指向不可达地址的请求，让它必然失败且不产生流量
            NSURL *dead = [NSURL URLWithString:@"about:blank"];
            NSURLRequest *deadReq = [NSURLRequest requestWithURL:dead];
            typedef id (*fn_t)(id, SEL, NSURLRequest *);
            if (na_orig_dataTaskReq) {
                return ((fn_t)na_orig_dataTaskReq)(self, _cmd, deadReq);
            }
            return nil;
        }
    }
    typedef id (*fn_t)(id, SEL, NSURLRequest *);
    return na_orig_dataTaskReq ? ((fn_t)na_orig_dataTaskReq)(self, _cmd, req) : nil;
}

// ---------------------------------------------------------------------------
// 缓存层：NSURLCache 命中缓存时也返回空（否则拦截了请求仍显示旧数据）
// ---------------------------------------------------------------------------
static IMP na_orig_cachedResponse = NULL;

static NSCachedURLResponse *na_cachedResponse(id self, SEL _cmd, NSURLRequest *req) {
    if (req && na_isEnabled() && na_isAdURL([req.URL absoluteString])) {
        NA_SCAN("[CACHE-BLOCKED] %s\n", ([[req.URL absoluteString] UTF8String] ?: "?"));
        return nil;
    }
    typedef id (*fn_t)(id, SEL, NSURLRequest *);
    return na_orig_cachedResponse
         ? ((fn_t)na_orig_cachedResponse)(self, _cmd, req) : nil;
}

static void na_patchSwitch(void) {
    Class c = objc_getClass("HYGetAdSwitchState");
    if (!c) { NA_LOG(@"未找到 HYGetAdSwitchState"); return; }

    Method m = class_getInstanceMethod(c, @selector(getSwitchState));
    if (m) { method_setImplementation(m, (IMP)na_NO0); NA_LOG(@"总开关 getSwitchState ->NO"); }

    m = class_getInstanceMethod(c, @selector(switchState));
    if (m) { method_setImplementation(m, (IMP)na_NO0); NA_LOG(@"总开关 switchState ->NO"); }

    m = class_getInstanceMethod(c, @selector(setSwitchState:));
    if (m) { method_setImplementation(m, (IMP)na_void1); NA_LOG(@"setSwitchState: 置空"); }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:@"adSwitchCloseStateStr"];
}

static void na_patchShowFlags(void) {
    unsigned int total = 0;
    Class *all = objc_copyClassList(&total);
    if (!all) return;
    int n = 0;
    for (unsigned int i = 0; i < total; i++) {
        Class c = all[i];
        if (!c || !na_isAppClass(c)) continue;
        unsigned int cnt = 0;
        Method *ms = class_copyMethodList(c, &cnt);
        if (!ms) continue;
        for (unsigned int j = 0; j < cnt; j++) {
            const char *sn = sel_getName(method_getName(ms[j]));
            const char *types = method_getTypeEncoding(ms[j]);
            if (!sn || !types || types[0] != 'B' || na_argc(sn) != 0) continue;
            if (strncmp(sn, "isShowAd", 8) && strncmp(sn, "isShowAD", 8)) continue;
            method_setImplementation(ms[j], (IMP)na_NO0);
            n++;
        }
        free(ms);
    }
    free(all);
    NA_LOG(@"isShowAd* 屏蔽 %d 个", n);
}

// ===========================================================================
// 配置：由设置开关控制（写在 NSUserDefaults，插件与设置页共用）
// ===========================================================================


// ===========================================================================
// 入口
// ===========================================================================
__attribute__((constructor))
static void HeJiaNoAdsInit(void) {
    @autoreleasepool {
        NA_LOG(@"════ 广告屏蔽加载 ════");

        // 网络层
        Class NSURLSessionC = objc_getClass("NSURLSession");
        if (NSURLSessionC) {
            Method m = class_getInstanceMethod(NSURLSessionC,
                        @selector(dataTaskWithRequest:completionHandler:));
            if (m) {
                na_orig_dataTask = method_getImplementation(m);
                method_setImplementation(m, (IMP)na_dataTaskWithRequest);
                NA_LOG(@"hook -[NSURLSession dataTaskWithRequest:completionHandler:]");
            }
            // 关键：AFNetworking delegate 模式走这个
            Method m2 = class_getInstanceMethod(NSURLSessionC,
                          @selector(dataTaskWithRequest:));
            if (m2) {
                na_orig_dataTaskReq = method_getImplementation(m2);
                method_setImplementation(m2, (IMP)na_dataTaskWithRequestOnly);
                NA_LOG(@"hook -[NSURLSession dataTaskWithRequest:]  <-- AF 路径");
            }
        }

        // 缓存层
        Class cacheCls = objc_getClass("NSURLCache");
        if (cacheCls) {
            Method cm = class_getInstanceMethod(cacheCls,
                          @selector(cachedResponseForRequest:));
            if (cm) {
                na_orig_cachedResponse = method_getImplementation(cm);
                method_setImplementation(cm, (IMP)na_cachedResponse);
                NA_LOG(@"hook -[NSURLCache cachedResponseForRequest:]");
            }
        }

        // 只做最轻量的：总开关（几乎零成本）
        na_patchSwitch();

        // 全量类扫描很重（约 50 万类候选），绝不能放在启动同步路径，
        // 否则会和 UI 初始化叠加导致 0x8BADF00D 看门狗闪退。
        // 延后 2.5 秒到后台队列执行。
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                NA_LOG(@"开始延后扫描广告 SDK");
                na_patchAdSDKClasses();
                na_patchAdDataGetters();
                na_patchShowFlags();
                NA_LOG(@"════ 广告屏蔽完成 ════");
            }
        });

        // 诊断：记录「我的」页组件类型，便于定位推广位
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                Class mgr = objc_getClass("HYMyInfoComponentManager");
                if (mgr) {
                    NA_SCAN("\n===== 我的页组件诊断 =====\n");
                    unsigned int n = 0;
                    Method *ms = class_copyMethodList(mgr, &n);
                    for (unsigned int i = 0; i < n; i++) {
                        const char *sn = sel_getName(method_getName(ms[i]));
                        if (sn) NA_SCAN("[MGR-SEL] %s\n", sn);
                    }
                    free(ms);
                }
            }
        });

        NA_LOG(@"════ 广告屏蔽初始化完成（扫描已延后）════");
    }
}

} // extern "C"
