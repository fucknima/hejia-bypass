// ============================================================================
//  Tab 隐藏模块 v7 —— 回到实测不卡的做法（v3），AI 只按类名精确摘除
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  复盘：
//    v3（只遍历 tabBar.subviews + hidden）实测**不卡**，只是留空档；
//    v4 起改用 [HYTabBar itemsAtIndex:] 后开始"哪里都点不了" ——
//    这个方法在 layoutSubviews 期间调用会反过来触发布局（懒建 item），回环。
//    v6 的 AI 文字扫描还会把「含 AI灵犀 的祖先视图」一并隐藏，
//    结果整条 tab bar 被它的父容器带走了（截图：低栏全空）。
//
//  v7 原则：
//    1) layoutSubviews 里只做 v3 那套：遍历 subviews、按文字 hidden。不碰 itemsAtIndex:
//    2) 不做任何几何重排（transform/center 全部去掉）——稳定优先
//    3) AI 只在定时器里、只按**类名**摘除（AIBubble / AIBannerBubble / AIRemind / LingXi），
//       绝不做"含文字的祖先视图"这种模糊匹配
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

#include <substrate.h>

extern "C" void HTLog(const char *tag, NSString *msg);
#define TAB_LOG(...) HTLog("HeJiaTab", [NSString stringWithFormat:__VA_ARGS__])

extern "C" {

static NSString *const kHideServiceKey = @"HeJiaTool_HideService";
static NSString *const kHideFindKey    = @"HeJiaTool_HideFind";
static NSString *const kHideAIKey      = @"HeJiaTool_HideAI";

static IMP HTOrig_tabbarLayout = NULL;
static __thread BOOL gInTabLayout = NO;
static BOOL gTabDisabled = NO;
static CFTimeInterval gLastLayoutTime = 0;
static int gLayoutBurst = 0;

// ---------------------------------------------------------------------------
// 递归：视图子树里是否有这个文字
// ---------------------------------------------------------------------------
static BOOL HTViewHasText(id view, NSString *text, int depth) {
    if (!view || depth > 6 || !text) return NO;
    @try {
        if ([view isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)view).text;
            if ([t isKindOfClass:[NSString class]] && [t isEqualToString:text]) return YES;
        }
        if ([view isKindOfClass:[UIButton class]]) {
            NSString *t = [((UIButton *)view) titleForState:UIControlStateNormal];
            if ([t isKindOfClass:[NSString class]] && [t isEqualToString:text]) return YES;
        }
        if ([view isKindOfClass:[UIView class]]) {
            for (UIView *sub in ((UIView *)view).subviews) {
                if (HTViewHasText(sub, text, depth + 1)) return YES;
            }
        }
    } @catch (NSException *e) { (void)e; }
    return NO;
}

// ---------------------------------------------------------------------------
// v3 原版：只遍历 tabBar 的直接子视图
// ---------------------------------------------------------------------------
static void HTHideTabItems(UIView *tabBar) {
    if (!tabBar) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL hideService = [ud boolForKey:kHideServiceKey];
    BOOL hideFind    = [ud boolForKey:kHideFindKey];
    if (!hideService && !hideFind) return;

    NSMutableArray *targets = [NSMutableArray array];
    if (hideService) [targets addObject:@"服务"];
    if (hideFind)    [targets addObject:@"发现"];

    NSArray *subs = tabBar.subviews;
    if (!subs || subs.count == 0) return;

    for (UIView *sub in subs) {
        NSString *cn = NSStringFromClass([sub class]);
        if ([cn containsString:@"ImageView"]) continue;   // 跳过背景图

        for (NSString *t in targets) {
            if (HTViewHasText(sub, t, 0)) {
                if (!sub.hidden) {
                    sub.hidden = YES;
                    TAB_LOG(@"已隐藏 Tab 按钮：%@", t);
                }
                break;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// hook layoutSubviews（只做隐藏，不做任何几何操作）
// ---------------------------------------------------------------------------
static void HTTabBarLayout(id self, SEL _cmd) {
    typedef void (*fn_t)(id, SEL);
    if (HTOrig_tabbarLayout) ((fn_t)HTOrig_tabbarLayout)(self, _cmd);

    if (gTabDisabled) return;

    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - gLastLayoutTime < 0.05) {
        if (++gLayoutBurst > 60) {
            gTabDisabled = YES;
            TAB_LOG(@"布局过于频繁，已自动停用 Tab 调整");
            return;
        }
    } else {
        gLayoutBurst = 0;
    }
    gLastLayoutTime = now;

    if (gInTabLayout) return;
    gInTabLayout = YES;
    @try { HTHideTabItems((UIView *)self); } @catch (NSException *e) { TAB_LOG(@"布局异常：%@", e.reason); }
    gInTabLayout = NO;
}

// ---------------------------------------------------------------------------
// AI：只按类名，定时器里跑（window 已就绪）
// ---------------------------------------------------------------------------
static void HTHideAIByClass(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud boolForKey:kHideAIKey]) return;

    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (!win) return;

    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:win];
    int guard = 0, n = 0;
    while (stack.count > 0 && guard++ < 5000) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];

        if (!v.hidden) {
            NSString *cn = NSStringFromClass([v class]);
            CGSize sz = v.bounds.size;
            BOOL small = (sz.width > 0 && sz.width <= 280 && sz.height <= 280);
            if (small && ([cn containsString:@"AIBubble"] ||
                [cn containsString:@"AIBannerBubble"] ||
                [cn containsString:@"AIRemind"] ||
                [cn containsString:@"LingXi"])) {
                v.hidden = YES;
                n++;
                TAB_LOG(@"AI 隐藏：%@", cn);
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    if (n > 0) TAB_LOG(@"AI 本轮隐藏 %d 个视图", n);
}

// ---------------------------------------------------------------------------
static void HTScanAllBars(void) {
    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (!win) return;

    Class barCls = objc_getClass("HYTabBar");
    if (!barCls) return;

    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:win];
    int guard = 0, found = 0;
    while (stack.count > 0 && guard++ < 5000) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if ([v isKindOfClass:barCls]) { HTHideTabItems(v); found++; }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    if (found == 0) TAB_LOG(@"窗口里没找到 HYTabBar");
}

__attribute__((constructor))
static void HeJiaTabInit(void) {
    @autoreleasepool {
        TAB_LOG(@"════ Tab 模块 v7 加载（稳定版：只隐藏，不重排）════");

        // 一次性迁移：配置版本变化时把三个 Tab 开关复位为关，
        // 保证"装上新版先能正常用"，再让用户按需打开。
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        id ver = [ud objectForKey:@"HeJiaTool_TabVer"];
        if (![ver isKindOfClass:[NSString class]] || ![(NSString *)ver isEqualToString:@"7"]) {
            // 只复位 AI：服务/发现 的隐藏在前几版已实测不卡，保持不变
            [ud setBool:NO forKey:kHideAIKey];
            [ud setObject:@"7" forKey:@"HeJiaTool_TabVer"];
            TAB_LOG(@"配置版本升级：AI 开关已重置为关（需要时到工具箱再打开）");
        }

        int hooked = 0;
        const char *barNames[] = { "HYTabBar", "HYCustomTabBar", NULL };
        for (int i = 0; barNames[i]; i++) {
            Class c = objc_getClass(barNames[i]);
            if (!c) continue;
            Method m = class_getInstanceMethod(c, @selector(layoutSubviews));
            if (!m) continue;
            if (!HTOrig_tabbarLayout) HTOrig_tabbarLayout = method_getImplementation(m);
            method_setImplementation(m, (IMP)HTTabBarLayout);
            TAB_LOG(@"hook -[%s layoutSubviews]", barNames[i]);
            hooked++;
        }
        if (hooked == 0) TAB_LOG(@"未找到 HYTabBar");

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"HeJiaTool_TabbarReload" object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(id note) { (void)note; HTScanAllBars(); HTHideAIByClass(); }];

        const int64_t delays[] = { 1500, 4000, 8000, 15000, 25000 };
        for (int i = 0; i < 5; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delays[i] * 1000000LL),
                           dispatch_get_main_queue(), ^{
                @try { HTScanAllBars(); HTHideAIByClass(); } @catch (NSException *e) { (void)e; }
            });
        }

        TAB_LOG(@"════ Tab 模块 v7 完成 ════");
    }
}

} // extern "C"
