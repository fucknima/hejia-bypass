// ============================================================================
//  NoAdsPlus.xm —— 补齐「自家广告 / 运营位」
// ----------------------------------------------------------------------------
//  为什么上一版拦不住：
//    NoAds.xm 的 SDK 扫描只认 ABU/GDT/KSAd/BaiduMob/JAD/CSJ/DSP/MIGU/Sigmob/
//    MADX/CXJAd… 这些第三方前缀，但移动爱家真正天天露脸的广告是**自家 MCS 体系**：
//      · McsMemberAdManager        -showMemberFreeFlowPopup        会员免流推广弹窗
//      · McsMemBerAdPopupView      -showMcsAdPopupView             广告弹窗视图
//      · McsFamilyMainViewController -mcsCheckAdPopup              首页弹窗检查（调用上面两个）
//      · McsFamilyMainViewController -_requestAdvertRemind         广告提醒请求
//      · McsPhotoBackUpController / McsFamilyFileViewController     相册/文件页的推广提醒
//      · HYGetUserBannerContentListService                         banner 运营位（33 处引用）
//      · HYLaunchAdManager         -startAdLaunch:                 开屏（实测通过跳表可达）
//      · HYOperationPromotedManager                                推广消息位
//   这些都叫 Mcs* / HY*，不在任何“广告 SDK”名单里，按前缀扫永远扫不到。
//
//  本文件是**增量**：不动 NoAds.xm，只补上面这些点，并加了两个诊断钩子。
//  开关复用 HeJiaTool_NoAds，可在设置页一键关掉。
// ============================================================================

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <string.h>
#import <UIKit/UIKit.h>

extern "C" void HTLog(const char *tag, NSString *msg);
extern "C" void HTLogC(const char *tag, const char *cfmt, ...);

#define NP_LOG(...)  HTLog("HeJiaNoAds+", [NSString stringWithFormat:__VA_ARGS__])
#define NP_SCAN(fmt, ...) HTLogC("SCAN", fmt, ##__VA_ARGS__)

extern "C" {

// ---------------------------------------------------------------------------
// 开关
// ---------------------------------------------------------------------------
static BOOL np_on(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"HeJiaTool_NoAds"];
    if (!v) return YES;              // 与 NoAds.xm 一致：默认开启
    return [v boolValue];
}

// ---------------------------------------------------------------------------
// 空实现（参数个数按方法签名准备，多余实参在 ARM64 C ABI 下无害）
// ---------------------------------------------------------------------------
static void np_v0(id s, SEL c) { (void)s; (void)c; }
static void np_v1(id s, SEL c, id a) { (void)s; (void)c; (void)a; }
static void np_v2(id s, SEL c, id a, id b) { (void)s; (void)c; (void)a; (void)b; }
static BOOL np_yes(id s, SEL c) { (void)s; (void)c; return YES; }

// ---------------------------------------------------------------------------
// 钩子工具
// ---------------------------------------------------------------------------
static int np_ok = 0, np_miss = 0;

static void np_hook(const char *cls, const char *sel, IMP imp) {
    Class c = objc_getClass(cls);
    if (!c) { np_miss++; NP_LOG(@"[MISS-CLASS] %s", cls); return; }
    Method m = class_getInstanceMethod(c, sel_registerName(sel));
    if (!m) { np_miss++; NP_LOG(@"[MISS-SEL]   -[%s %s]", cls, sel); return; }
    method_setImplementation(m, imp);
    np_ok++;
    NP_LOG(@"[OK] -[%s %s]", cls, sel);
}

// ---------------------------------------------------------------------------
// 1. 开屏
// ---------------------------------------------------------------------------
static void np_patch_launch_ad(void) {
    np_hook("HYLaunchAdManager", "startAdLaunch:",            (IMP)np_v1);
    np_hook("HYLaunchAdManager", "updateAdViewWithDataArray:", (IMP)np_v1);
    np_hook("HYLaunchAdManager", "updateAdViewFromCache",      (IMP)np_v0);
}

// ---------------------------------------------------------------------------
// 2. 自家广告位 / 推广消息
// ---------------------------------------------------------------------------
static void np_patch_own_ads(void) {
    np_hook("McsAdvertsModuleService", "fetchAdvertNewReq:block:", (IMP)np_v2);
    np_hook("HYOperationPromotedManager",
            "getOperationPromotedViewWithCallBack:",              (IMP)np_v1);
}

// ---------------------------------------------------------------------------
// 3. MCS 弹窗（首页/相册/文件页的“推广”大头）
// ---------------------------------------------------------------------------
static void np_patch_mcs_popups(void) {
    np_hook("McsMemberAdManager",           "showMemberFreeFlowPopup", (IMP)np_v0);
    np_hook("McsMemBerAdPopupView",         "showMcsAdPopupView",      (IMP)np_v0);

    np_hook("McsFamilyMainViewController",  "mcsCheckAdPopup",         (IMP)np_v0);
    np_hook("McsFamilyMainViewController",  "_requestAdvertRemind",    (IMP)np_v0);
    np_hook("McsFamilyMainViewController",  "isShowAdPopView",         (IMP)np_yes);

    np_hook("McsPhotoBackUpController",     "_requestAdvertRemind",    (IMP)np_v0);

    np_hook("McsFamilyFileViewController",  "_requestAdvertRemind",    (IMP)np_v0);
    np_hook("McsFamilyFileViewController",  "showingAdvertRemind",     (IMP)np_v0);
    np_hook("McsFamilyFileViewController",  "showedAdvertRemind",      (IMP)np_v0);
}

// ---------------------------------------------------------------------------
// 3.5 设备页「场景 + 产品功能图册」卡片
//     日志实测：首页出现 HYHardwareSceneAndBannerView / HYCommonHardwareSenceHalfViewBannerCell，
//     即使 getBannerContentList 已被拦，这张卡仍由本地默认数据渲染 → 直接掐数据入口
// ---------------------------------------------------------------------------
static void np_patch_hardware_banner(void) {
    np_hook("HYHardwareSceneAndBannerView", "reloadBanner:",    (IMP)np_v1);
    np_hook("HYHardwareSceneAndBannerView", "reloadAllBanner:", (IMP)np_v1);
}

// ---------------------------------------------------------------------------
// 4. Banner 运营位（33 处引用的数据源）
//    直接短路 4 个入口 → 不发请求、不出运营位；调用方本来就有“无数据”分支。
// ---------------------------------------------------------------------------
static BOOL np_banner_on(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:@"HeJiaTool_NoAdsBanner"];
    return v ? [v boolValue] : NO;    // 默认关闭：会影响首页/我的页布局，确认无副作用再开
}

static void np_patch_banners(void) {
    const char *cls = "HYGetUserBannerContentListService";
    np_hook(cls, "getUserBannerContentListWithTabId:",                    (IMP)np_v1);
    np_hook(cls, "getUserBannerContentListWithTabId:provCode:",           (IMP)np_v2);
    np_hook(cls, "getUserBannerContentListWithTabId:provCode:extParams:", (IMP)np_v2);
    np_hook(cls, "getUserBannerContentListWithTabId:userSelectedProvCode:userSelectedCityCode:",
            (IMP)np_v2);
}

// ---------------------------------------------------------------------------
// 5. 诊断 A：组件工厂收到的每个 componentId（找剩余广告组件用）
// ---------------------------------------------------------------------------
static IMP np_orig_comp = NULL;

static id np_getComponent(id self, SEL _cmd, id componentId) {
    if (componentId) NP_SCAN("[COMPONENT] %s\n", [[componentId description] UTF8String]);
    typedef id (*fn_t)(id, SEL, id);
    return np_orig_comp ? ((fn_t)np_orig_comp)(self, _cmd, componentId) : nil;
}

static void np_patch_component_trace(void) {
    Class c = objc_getClass("HYComponentManager");
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName("getComponentWithComponentId:"));
    if (!m) return;
    np_orig_comp = method_getImplementation(m);
    method_setImplementation(m, (IMP)np_getComponent);
    NP_LOG(@"[DIAG] HYComponentManager componentId 追踪已开启");
}

// ---------------------------------------------------------------------------
// 6. 诊断 B：页面上出现的广告类视图（类名带 Ad/Banner/Promot/Splash…）
// ---------------------------------------------------------------------------
static IMP np_orig_didMove = NULL;
static Class np_seen[512];
static int np_seen_n = 0;

static BOOL np_adish(const char *n) {
    static const char *k[] = { "Ad", "AD", "Banner", "Promot", "Splash", "Market",
                               "Recommend", "Sale", "Lottery", "Task" };
    for (unsigned i = 0; i < sizeof(k) / sizeof(k[0]); i++)
        if (strstr(n, k[i])) return YES;
    return NO;
}

static void np_didMoveToWindow(id self, SEL _cmd) {
    const char *cn = class_getName(object_getClass(self));
    if (cn && np_adish(cn)) {
        BOOL seen = NO;
        for (int i = 0; i < np_seen_n; i++) if (np_seen[i] == object_getClass(self)) { seen = YES; break; }
        if (!seen && np_seen_n < 512) {
            np_seen[np_seen_n++] = object_getClass(self);
            NP_SCAN("[VIEW] %s\n", cn);
        }
    }
    typedef void (*fn_t)(id, SEL);
    if (np_orig_didMove) ((fn_t)np_orig_didMove)(self, _cmd);
}

static void np_patch_view_trace(void) {
    Class ui = objc_getClass("UIView");
    if (!ui) return;
    Method m = class_getInstanceMethod(ui, sel_registerName("didMoveToWindow"));
    if (!m) return;
    np_orig_didMove = method_getImplementation(m);
    method_setImplementation(m, (IMP)np_didMoveToWindow);
    NP_LOG(@"[DIAG] 广告类视图追踪已开启（命中会写 SCAN 日志）");
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HeJiaNoAdsPlusInit(void) {
    @autoreleasepool {
        if (!np_on()) { NP_LOG(@"已被设置页关闭，跳过"); return; }

        NP_LOG(@"════ NoAdsPlus 加载 ════");

        np_patch_launch_ad();
        np_patch_own_ads();
        np_patch_mcs_popups();
        np_patch_hardware_banner();
        if (np_banner_on()) {
            np_patch_banners();
        } else {
            NP_LOG(@"[SKIP] banner 运营位（默认不拦；需要时在设置里写 HeJiaTool_NoAdsBanner=YES）");
        }

        np_patch_component_trace();
        np_patch_view_trace();

        NP_LOG(@"════ 完成：命中 %d，缺失 %d ════", np_ok, np_miss);
    }
}

} // extern "C"
