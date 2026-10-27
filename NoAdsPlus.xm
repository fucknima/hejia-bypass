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
__attribute__((unused)) static void np_patch_own_ads(void) {
    // 这两个涉及 block 回调 / 返回视图，先停用（可能让页面等不到回调而空白）
    // np_hook("McsAdvertsModuleService", "fetchAdvertNewReq:block:", (IMP)np_v2);
    // np_hook("HYOperationPromotedManager", "getOperationPromotedViewWithCallBack:", (IMP)np_v1);
}

// ---------------------------------------------------------------------------
// 3. MCS 弹窗（首页/相册/文件页的“推广”大头）
// ---------------------------------------------------------------------------
__attribute__((unused)) static void np_patch_mcs_popups(void) {
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
// 3.6 设备网格里的广告卡片
//     实测日志：首页出现 HYNewGDRBBannerCollectionViewCell /
//     HYHardwareClassifyBannerDeviceListView_CN.SENSORSDATA，
//     说明广告是混在"设备列表数据"里渲染的。
//     这里只做两件事：把模型类名打进日志（供确认），以及剔除类名里
//     明确带广告/推荐字样的模型 —— 匹配不到就不动，绝不误删设备。
// ---------------------------------------------------------------------------
static BOOL np_initedClsLog = NO;
// 实测（HeJiaTool_10.log）：
//   真设备  type=591630 / 2320794   desc=中兴云电脑… / 智能摄像头-1   rid=CMCC-…
//   广告位  type=77777777 ×3        desc=(null)                    rid=(null)
// 所以广告位的判据就是 type == 77777777（占位模型），不再靠类名猜。
#define kNPAdPlaceholderType 77777777LL

static BOOL np_isAdModel(id m) {
    @try {
        id t = [m valueForKey:@"type"];
        if (t && [t respondsToSelector:@selector(longLongValue)]) {
            if ([t longLongValue] == kNPAdPlaceholderType) {
                // 再确认一次：广告位的 desc 一定为空
                id d = [m valueForKey:@"desc"];
                if (!d || d == [NSNull null]) return YES;
                if ([d isKindOfClass:[NSString class]] && [(NSString *)d length] == 0) return YES;
            }
        }
    } @catch (NSException *e) { (void)e; }
    return NO;
}

static IMP np_orig_cfgDevices = NULL;
static void np_cfgDevices(id self, SEL _cmd, NSArray *arr, long idx) {
    typedef void (*fn_t)(id, SEL, NSArray *, long);
    if (!np_initedClsLog && arr.count) {
        np_initedClsLog = YES;
        NSUInteger n = arr.count > 8 ? 8 : arr.count;
        for (NSUInteger i = 0; i < n; i++) {
            id m = arr[i];
            NSString *info = @"kvc-fail";
            @try {
                info = [NSString stringWithFormat:@"type=%@ cat=%@ desc=%@ rid=%@",
                        [m valueForKey:@"type"], [m valueForKey:@"typeCategory"],
                        [m valueForKey:@"desc"], [m valueForKey:@"id"]];
            } @catch (NSException *e) { (void)e; }
            NP_LOG(@"[dev#%lu] %@ %@", (unsigned long)i,
                   NSStringFromClass([m class]), info);
        }
    }
    NSMutableArray *kept = [NSMutableArray array];
    int dropped = 0;
    for (id m in arr) {
        if (np_isAdModel(m)) { dropped++; continue; }
        [kept addObject:m];
    }
    if (dropped) NP_LOG(@"[dev] 剔除广告模型 %d 个", dropped);
    if (np_orig_cfgDevices) ((fn_t)np_orig_cfgDevices)(self, _cmd, kept, idx);
}

static IMP np_orig_cfgDevices2 = NULL;
static void np_cfgDevices2(id self, SEL _cmd, NSArray *arr) {
    typedef void (*fn_t)(id, SEL, NSArray *);
    NSMutableArray *kept = [NSMutableArray array];
    int dropped = 0;
    for (id m in arr) {
        if (np_isAdModel(m)) { dropped++; continue; }
        [kept addObject:m];
    }
    if (dropped) NP_LOG(@"[dev2] 剔除广告模型 %d 个", dropped);
    if (np_orig_cfgDevices2) ((fn_t)np_orig_cfgDevices2)(self, _cmd, kept);
}

static void np_patch_device_ads(void) {
    Class c = objc_getClass("HYHardwareFamilyDeviceListView");
    if (c) {
        Method m = class_getInstanceMethod(c, sel_registerName("configWithAllDeviceArray:currentRoomIndex:"));
        if (m) {
            np_orig_cfgDevices = method_getImplementation(m);
            method_setImplementation(m, (IMP)np_cfgDevices);
            NP_LOG(@"[OK] HYHardwareFamilyDeviceListView.configWithAllDeviceArray:");
        }
    }
    Class c2 = objc_getClass("HYHardwareClassifyBannerDeviceListView");
    if (c2) {
        Method m = class_getInstanceMethod(c2, sel_registerName("configWithAllDeviceArray:"));
        if (m) {
            np_orig_cfgDevices2 = method_getImplementation(m);
            method_setImplementation(m, (IMP)np_cfgDevices2);
            NP_LOG(@"[OK] HYHardwareClassifyBannerDeviceListView.configWithAllDeviceArray:");
        }
    }
}

// ---------------------------------------------------------------------------
// 3.7 我的页组件过滤（实测类名来自二进制类表）
//     HYMyInfoCoreFunctionsComponent      → 我的钱包（零钱/银行卡/AI豆/号码借）
//     HYMyInfoCircleOfRelativesComponent  → 爱家亲情网
//     HYMyInfoComponentManager 只有一个方法，就是"把组件字典数组变成视图"，
//     在这里剔除即可整块消失，不会留空。
// ---------------------------------------------------------------------------
static BOOL np_myinfoLogged = NO;
static IMP np_orig_myinfo = NULL;

static BOOL np_isBlockedComponent(id d) {
    @try {
        NSString *desc = [d description];
        if (![desc isKindOfClass:[NSString class]]) return NO;
        return [desc containsString:@"HYMyInfoCoreFunctionsComponent"] ||
               [desc containsString:@"HYMyInfoCircleOfRelativesComponent"];
    } @catch (NSException *e) { (void)e; }
    return NO;
}

static id np_myinfoGetView(id self, SEL _cmd, NSArray *dicts, id tabId, id realTabId, id block) {
    typedef id (*fn_t)(id, SEL, NSArray *, id, id, id);
    if (!np_myinfoLogged && dicts.count) {
        np_myinfoLogged = YES;
        @try {
            id first = dicts[0];
            NP_LOG(@"[myinfo] count=%lu keys=%@", (unsigned long)dicts.count,
                   [[first allKeys] description]);
        } @catch (NSException *e) { (void)e; }
    }

    NSMutableArray *kept = [NSMutableArray array];
    int dropped = 0;
    for (id d in dicts) {
        if (np_isBlockedComponent(d)) { dropped++; continue; }
        [kept addObject:d];
    }
    if (kept.count == 0) {          // 保险：绝不能把整个页面清空
        NP_LOG(@"[myinfo] 过滤后为空，回退原数组");
        kept = [NSMutableArray array];
        for (id dd in dicts) [kept addObject:dd];
        dropped = 0;
    }
    if (dropped) NP_LOG(@"[myinfo] 剔除组件 %d 个（钱包/亲情网）", dropped);

    return np_orig_myinfo ? ((fn_t)np_orig_myinfo)(self, _cmd, kept, tabId, realTabId, block) : nil;
}

__attribute__((unused)) static void np_patch_myinfo(void) {
    Class c = objc_getClass("HYMyInfoComponentManager");
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName("getViewWithComponentDictArray:tabId:realTabId:completeBlock:"));
    if (!m) { NP_LOG(@"[myinfo] 方法未找到"); return; }
    np_orig_myinfo = method_getImplementation(m);
    method_setImplementation(m, (IMP)np_myinfoGetView);
    NP_LOG(@"[OK] HYMyInfoComponentManager 组件过滤已启用");
}

// ---------------------------------------------------------------------------
// 3.8 摄像头页广告条
// ---------------------------------------------------------------------------
static IMP np_orig_cncAdMove = NULL;
static void np_cncAdMove(id self, SEL _cmd) {
    typedef void (*fn_t)(id, SEL);
    if (np_orig_cncAdMove) ((fn_t)np_orig_cncAdMove)(self, _cmd);
    if (!((UIView *)self).hidden) {
        ((UIView *)self).hidden = YES;
        NP_LOG(@"[cnc] 隐藏 HYCNCAdBanner");
    }
}

__attribute__((unused)) __attribute__((unused)) static void np_patch_cnc_ad(void) {
    Class c = objc_getClass("HYCNCAdBanner");
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName("didMoveToWindow"));
    if (!m) return;
    np_orig_cncAdMove = method_getImplementation(m);
    method_setImplementation(m, (IMP)np_cncAdMove);
    NP_LOG(@"[OK] HYCNCAdBanner 已接管");
}

// ---------------------------------------------------------------------------
// 3.9 首页/通用页组件日志（只读，不拦截）
//     用来拿到"工具""场景"等板块的组件类名，避免瞎猜
// ---------------------------------------------------------------------------
static BOOL np_compLogged = NO;
static IMP np_orig_compGet = NULL;

static id np_compGetView(id self, SEL _cmd, NSArray *dicts, id tabId, id block) {
    typedef id (*fn_t)(id, SEL, NSArray *, id, id);
    if (!np_compLogged && dicts.count) {
        np_compLogged = YES;
        NSUInteger n = dicts.count > 6 ? 6 : dicts.count;
        for (NSUInteger i = 0; i < n; i++) {
            @try {
                NP_LOG(@"[comp#%lu] %@", (unsigned long)i, [dicts[i] description]);
            } @catch (NSException *e) { (void)e; }
        }
    }
    return np_orig_compGet ? ((fn_t)np_orig_compGet)(self, _cmd, dicts, tabId, block) : nil;
}

__attribute__((unused)) static void np_patch_comp_log(void) {
    Class c = objc_getClass("HYComponentManager");
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName("getViewWithComponentDictArray:tabId:completeBlock:"));
    if (!m) return;
    np_orig_compGet = method_getImplementation(m);
    method_setImplementation(m, (IMP)np_compGetView);
    NP_LOG(@"[OK] HYComponentManager 组件日志已开启");
}

// ---------------------------------------------------------------------------
// 3.95 首页「场景/产品图册」整块
//     反汇编确认：HYHardwareBannerManager -isClose 只读一个字节 ivar，
//     setIsClose: 写它 —— 这是 App 自带的"关闭该模块"开关。
//     让 isClose 恒为 YES，它会按自己的逻辑整块收起，不留空档。
// ---------------------------------------------------------------------------
__attribute__((unused)) static void np_patch_scene_close(void) {
    Class c = objc_getClass("HYHardwareBannerManager");
    if (!c) { NP_LOG(@"[MISS] HYHardwareBannerManager"); return; }
    Method m = class_getInstanceMethod(c, sel_registerName("isClose"));
    if (!m) { NP_LOG(@"[MISS] isClose"); return; }
    method_setImplementation(m, (IMP)np_yes);
    NP_LOG(@"[OK] HYHardwareBannerManager.isClose -> YES（场景/图册整块收起）");
}

// ---------------------------------------------------------------------------
// 3.96 通用组件过滤（首页/工具区这类服务端下发组件）
//     只在组件字典 -> 视图 之前剔除，类名/字段带广告字样的才丢，全程记录
// ---------------------------------------------------------------------------
static BOOL np_isAdComponent(id d) {
    @try {
        NSString *desc = [d description];
        if (![desc isKindOfClass:[NSString class]]) return NO;
        return [desc containsString:@"BigSale"] || [desc containsString:@"Banner"] ||
               [desc containsString:@"Market"] || [desc containsString:@"Promotion"] ||
               [desc containsString:@"Promoted"] || [desc containsString:@"Advert"] ||
               [desc containsString:@"Operation"] || [desc containsString:@"Tool"];
    } @catch (NSException *e) { (void)e; }
    return NO;
}

__attribute__((unused)) static id np_compFilter(id self, SEL _cmd, NSArray *dicts, id tabId, id block) {
    typedef id (*fn_t)(id, SEL, NSArray *, id, id);
    NSMutableArray *kept = [NSMutableArray array];
    int dropped = 0;
    for (id d in dicts) {
        if (np_isAdComponent(d)) {
            dropped++;
            @try { NP_LOG(@"[comp-drop] %@", [d description]); }
            @catch (NSException *e) { (void)e; }
            continue;
        }
        [kept addObject:d];
    }
    if (dropped) NP_LOG(@"[comp] 剔除 %d 个广告/推广组件，剩余 %lu",
                        dropped, (unsigned long)kept.count);
    return np_orig_compGet ? ((fn_t)np_orig_compGet)(self, _cmd, kept, tabId, block) : nil;
}

__attribute__((unused)) static void np_patch_comp_filter(void) {
    Class c = objc_getClass("HYComponentManager");
    if (!c) return;
    Method m = class_getInstanceMethod(c, sel_registerName("getViewWithComponentDictArray:tabId:completeBlock:"));
    if (!m) return;
    np_orig_compGet = method_getImplementation(m);
    method_setImplementation(m, (IMP)np_compFilter);
    NP_LOG(@"[OK] HYComponentManager 组件过滤已启用");
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
        // np_patch_mcs_popups();   // 涉及请求回调，暂停
        np_patch_device_ads();
        // np_patch_myinfo();  // 停用：我的页/第二屏黑屏，先把组件数组还给原样
        // np_patch_cnc_ad();      // 暂停
        // np_patch_scene_close(); // 暂停
        // np_patch_comp_filter();  // 组件过滤（启发式）暂停：它 hook 的是首页组件构建入口，风险最高
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
