// ============================================================================
//  Tab 隐藏模块 v6 —— 布局路径只做「便宜」的事，AI 扫描交给定时器
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  复盘（v4/v5 实测问题）：
//    · 把「遍历整窗找 AI」放在 layoutSubviews 里 → 主线程被拖住，界面点不动
//    · 而且那一刻 tabBar.window 经常还是 nil，扫描直接空转，所以 AI 一直没掉
//    · 位置调整（center/transform）放在 layoutSubviews 里有回环风险
//
//  v6 的分工：
//    layoutSubviews（高频）: 只做 items 收集 + 按文字 hidden + transform 平移（幂等）
//    定时器（+1.5s / +4s / +8s）: 才遍历窗口找 AI（此时 window 一定存在）
//    任何异常都被 @try 包住，且布局看门狗仍在
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
static BOOL gDumped = NO;

@protocol HTTabBarItems
- (id)itemsAtIndex:(NSUInteger)index;
- (NSUInteger)itemsCount;
- (NSUInteger)specialIndex;
@end

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


static void HTCollectItems(UIView *tabBar, NSMutableArray *out) {
    if ([tabBar respondsToSelector:@selector(itemsAtIndex:)] &&
        [tabBar respondsToSelector:@selector(itemsCount)]) {
        id<HTTabBarItems> bar = (id<HTTabBarItems>)tabBar;
        NSUInteger n = 0;
        @try { n = [bar itemsCount]; } @catch (NSException *e) { (void)e; n = 0; }
        if (n > 64) n = 0;
        for (NSUInteger i = 0; i < n; i++) {
            @try {
                UIView *it = (UIView *)[bar itemsAtIndex:i];
                if (it && [it isKindOfClass:[UIView class]]) [out addObject:it];
            } @catch (NSException *e) { (void)e; }
        }
    }
    if (out.count == 0) {
        Class c1 = objc_getClass("HYTabBarItem");
        Class c2 = objc_getClass("HYBaseTabBarItem");
        for (UIView *v in tabBar.subviews) {
            if ((c1 && [v isKindOfClass:c1]) || (c2 && [v isKindOfClass:c2])) [out addObject:v];
        }
    }
}

// ---------------------------------------------------------------------------
// AI：只在定时器里调用（window 已就绪）
// ---------------------------------------------------------------------------
static int HTHideAI(UIView *tabBar, NSArray *items) {
    int hidden = 0;

    // 1) specialIndex 指向的 item
    if ([tabBar respondsToSelector:@selector(specialIndex)]) {
        NSUInteger idx = 0;
        @try { idx = [(id<HTTabBarItems>)tabBar specialIndex]; } @catch (NSException *e) { (void)e; }
        if (idx < items.count) {
            UIView *it = items[idx];
            if (it && !it.hidden) { it.hidden = YES; hidden++; TAB_LOG(@"AI: specialIndex=%lu", (unsigned long)idx); }
        }
    }

    // 2) customerizeItems
    @try {
        id cust = [tabBar valueForKey:@"customerizeItems"];
        if ([cust isKindOfClass:[NSArray class]]) {
            for (id v in (NSArray *)cust) {
                if ([v isKindOfClass:[UIView class]] && !((UIView *)v).hidden) {
                    ((UIView *)v).hidden = YES; hidden++;
                    TAB_LOG(@"AI: customerizeItem %@", NSStringFromClass([v class]));
                }
            }
        }
    } @catch (NSException *e) { (void)e; }

    // 3) 整窗扫类名 + 最内层「AI灵犀」
    UIWindow *win = tabBar.window;
    if (!win) {
        for (UIWindow *w in [UIApplication sharedApplication].windows) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (!win) { TAB_LOG(@"AI: 拿不到窗口，跳过本轮"); return hidden; }

    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:win];
    int guard = 0;
    NSMutableArray *byText = [NSMutableArray array];
    while (stack.count > 0 && guard++ < 5000) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];

        NSString *cn = NSStringFromClass([v class]);
        if (!v.hidden &&
            ([cn containsString:@"AIBubble"] || [cn containsString:@"AIBannerBubble"] ||
             [cn containsString:@"AIRemind"] || [cn containsString:@"LingXi"])) {
            v.hidden = YES; hidden++;
            TAB_LOG(@"AI: 类名命中 %@", cn);
        }
        if (HTViewHasText(v, @"AI灵犀", 0)) [byText addObject:v];
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    for (UIView *v in byText) {
        if (!v.hidden && v != tabBar && ![v isKindOfClass:[UIWindow class]]) {
            v.hidden = YES; hidden++;
            TAB_LOG(@"AI: 文字命中 %@", NSStringFromClass([v class]));
        }
    }
    return hidden;
}

// ---------------------------------------------------------------------------
// 主逻辑（doAI=NO 时只做便宜的部分）
// ---------------------------------------------------------------------------
static void HTApplyTabBar(UIView *tabBar, BOOL doAI) {
    if (!tabBar) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL hideService = [ud boolForKey:kHideServiceKey];
    BOOL hideFind    = [ud boolForKey:kHideFindKey];
    BOOL hideAI      = [ud boolForKey:kHideAIKey];
    if (!hideService && !hideFind && !hideAI) return;

    NSMutableArray *items = [NSMutableArray array];
    HTCollectItems(tabBar, items);
    if (items.count < 2) return;

    if (!gDumped) {
        gDumped = YES;
        NSString *d = @"";
        for (UIView *v in tabBar.subviews) {
            d = [d stringByAppendingString:
                    [NSString stringWithFormat:@"%@(h%d) ",
                        NSStringFromClass([v class]), (int)v.hidden]];
        }
        TAB_LOG(@"tabBar=%@ items=%lu subs=%@", NSStringFromClass([tabBar class]),
                (unsigned long)items.count, d);
    }

    if (doAI && hideAI) {
        int n = HTHideAI(tabBar, items);
        if (n > 0) TAB_LOG(@"AI 本轮命中 %d", n);
    }

    // 隐藏「服务」「发现」
    NSMutableArray *visible = [NSMutableArray array];
    for (UIView *it in items) {
        if (it.hidden) continue;
        BOOL hide = NO;
        if (hideService && HTViewHasText(it, @"服务", 0)) hide = YES;
        if (!hide && hideFind && HTViewHasText(it, @"发现", 0)) hide = YES;
        if (hide) {
            it.hidden = YES;
            TAB_LOG(@"隐藏 tab item：%@", (hideService && HTViewHasText(it, @"服务", 0)) ? @"服务" : @"发现");
            continue;
        }
        [visible addObject:it];
    }

    // 几何重排只在定时器路径做（doAI），绝不放在 layoutSubviews 里
    if (!doAI) return;
    if (visible.count == 0 || visible.count >= items.count) return;

    NSUInteger vn = visible.count;
    for (NSUInteger i = 1; i < vn; i++) {
        UIView *key = visible[i];
        NSInteger j = (NSInteger)i - 1;
        while (j >= 0 && ((UIView *)visible[(NSUInteger)j]).center.x > key.center.x) {
            visible[(NSUInteger)(j + 1)] = visible[(NSUInteger)j];
            j--;
        }
        visible[(NSUInteger)(j + 1)] = key;
    }

    CGFloat w = tabBar.bounds.size.width;
    if (w <= 1) return;

    for (NSUInteger k = 0; k < vn; k++) {
        UIView *it = visible[k];
        CGFloat dx = w * ((CGFloat)k + 0.5f) / (CGFloat)vn - it.center.x;
        if (fabs(it.transform.tx - dx) > 0.5f) {
            it.transform = CGAffineTransformMakeTranslation(dx, 0);
        }
    }
}

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
    @try { HTApplyTabBar((UIView *)self, NO); } @catch (NSException *e) { TAB_LOG(@"布局异常：%@", e.reason); }
    gInTabLayout = NO;
}

// ---------------------------------------------------------------------------
static void HTScanAllBars(BOOL doAI) {
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
        if ([v isKindOfClass:barCls]) { HTApplyTabBar(v, doAI); found++; }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    if (found == 0) TAB_LOG(@"窗口里没找到 HYTabBar");
}

__attribute__((constructor))
static void HeJiaTabInit(void) {
    @autoreleasepool {
        TAB_LOG(@"════ Tab 模块 v6 加载 ════");

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
                    usingBlock:^(id note) { (void)note; HTScanAllBars(YES); }];

        // 关键：AI 扫描放在窗口就绪之后，而不是 layoutSubviews 里
        const int64_t delays[] = { 1500, 4000, 8000, 15000, 25000 };
        for (int i = 0; i < 5; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delays[i] * 1000000LL),
                           dispatch_get_main_queue(), ^{
                @try { HTScanAllBars(YES); } @catch (NSException *e) { (void)e; }
            });
        }

        TAB_LOG(@"════ Tab 模块 v6 完成 ════");
    }
}

} // extern "C"
