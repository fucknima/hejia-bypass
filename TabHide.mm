// ============================================================================
//  Tab 隐藏模块 v5 —— 用 transform 重排（不触发 layout 递归）+ AI 兜底定位
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  v4 的两个问题（用户实测）：
//    1) 改 item.center → setFrame → 再次触发 layoutSubviews → 主线程陷入
//       布局回环，界面点不动（日志里没有异常，就是卡）
//    2) AI灵犀 既不是普通 tab item 也不在 tabBar 的直接子视图里，
//       按文字扫 tabBar.subviews 完全没命中（日志里没有任何「隐藏 AI」）
//
//  v5：
//    · 位移改用 transform（只影响渲染和命中测试，**不会**让父视图重新布局），
//      每帧都从原始 center 重算，幂等，不会累积
//    · AI 三路兜底：
//        a) specialIndex 指向的 item
//        b) 窗口层级里「最内层」含 "AI灵犀" 文字的视图
//        c) 类名含 AIBubble / AIRemind / LingXi 的气泡
//    · 只在值变化时赋值，避免无效布局
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
static CFTimeInterval gLastAIScan = 0;
static BOOL gDumpedTree = NO;
static BOOL gTabDisabled = NO;
static CFTimeInterval gLastLayoutTime = 0;
static int gLayoutBurst = 0;

@protocol HTTabBarItems
- (id)itemsAtIndex:(NSUInteger)index;
- (NSUInteger)itemsCount;
- (NSUInteger)specialIndex;
@end

// ---------------------------------------------------------------------------
// 文字查找
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

// 收集「最内层」含该文字的视图（避免把整个页面隐藏掉）
static void HTCollectLeafMatches(UIView *v, NSString *text, int depth, NSMutableArray *out) {
    if (!v || depth > 14) return;
    if (!HTViewHasText(v, text, 0)) return;

    BOOL hasChildMatch = NO;
    for (UIView *c in v.subviews) {
        if (HTViewHasText(c, text, 0)) {
            hasChildMatch = YES;
            HTCollectLeafMatches(c, text, depth + 1, out);
        }
    }
    if (!hasChildMatch) [out addObject:v];
}

// ---------------------------------------------------------------------------
// 收集 tab item
// ---------------------------------------------------------------------------
static void HTCollectItems(UIView *tabBar, NSMutableArray *out) {
    if ([tabBar respondsToSelector:@selector(itemsAtIndex:)] &&
        [tabBar respondsToSelector:@selector(itemsCount)]) {
        id<HTTabBarItems> bar = (id<HTTabBarItems>)tabBar;
        NSUInteger n = 0;
        @try { n = [bar itemsCount]; } @catch (NSException *e) { (void)e; n = 0; }
        if (n > 64) n = 0;                     // 防御：异常返回值不进入长循环
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
// 隐藏 AI（三路兜底）
// ---------------------------------------------------------------------------
static void HTHideAIViews(UIView *tabBar, NSArray *items) {
    int hidden = 0;

    // a) specialIndex
    if ([tabBar respondsToSelector:@selector(specialIndex)]) {
        NSUInteger idx = 0;
        @try { idx = [(id<HTTabBarItems>)tabBar specialIndex]; } @catch (NSException *e) { (void)e; }
        if (idx < items.count) {
            UIView *it = items[idx];
            if (it && !it.hidden) { it.hidden = YES; hidden++; }
        }
    }

    // a2) customerizeItems（AI 是自定义 item，不在普通 items 里）
    @try {
        id cust = [tabBar valueForKey:@"customerizeItems"];
        if ([cust isKindOfClass:[NSArray class]]) {
            for (id v in (NSArray *)cust) {
                if ([v isKindOfClass:[UIView class]] && !((UIView *)v).hidden) {
                    ((UIView *)v).hidden = YES;
                    hidden++;
                    TAB_LOG(@"隐藏 customerizeItem：%@", NSStringFromClass([v class]));
                }
            }
        }
    } @catch (NSException *e) { (void)e; }

    // a3) item 类名带 AI 的
    for (UIView *it in items) {
        NSString *cn = NSStringFromClass([it class]);
        if ([cn containsString:@"AI"] && !it.hidden) {
            it.hidden = YES;
            hidden++;
            TAB_LOG(@"隐藏 AI item 类：%@", cn);
        }
    }

    // b) 窗口层级里最内层含「AI灵犀」的视图
    for (NSString *t in @[ @"AI灵犀", @"灵犀" ]) {
        NSMutableArray *match = [NSMutableArray array];
        UIWindow *win = tabBar.window;
        if (win) HTCollectLeafMatches(win, t, 0, match);
        for (UIView *v in match) {
            if (v.hidden) continue;
            // 不要动 tabBar 本身或它的祖先
            if (v == tabBar) continue;
            v.hidden = YES;
            hidden++;
            TAB_LOG(@"隐藏 AI 视图：%@ (%@)", NSStringFromClass([v class]), t);
        }
    }

    // c) 气泡
    UIWindow *win = tabBar.window;
    if (win) {
        NSMutableArray *stack = [NSMutableArray array];
        [stack addObject:win];
        int guard = 0;
        while (stack.count > 0 && guard++ < 4000) {
            UIView *v = [stack lastObject];
            [stack removeLastObject];
            if (!v.hidden) {
                NSString *cn = NSStringFromClass([v class]);
                if ([cn containsString:@"AIBubble"] || [cn containsString:@"AIRemind"] ||
                    [cn containsString:@"LingXi"] || [cn containsString:@"AIBannerBubble"]) {
                    v.hidden = YES;
                    hidden++;
                    TAB_LOG(@"隐藏 AI 气泡：%@", cn);
                }
            }
            for (UIView *s in v.subviews) [stack addObject:s];
        }
    }

    if (hidden == 0) TAB_LOG(@"AI 未命中（本轮）");
}

// ---------------------------------------------------------------------------
// 主逻辑：隐藏 + transform 重排
// ---------------------------------------------------------------------------
static void HTApplyTabBar(UIView *tabBar) {
    if (!tabBar) return;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL hideService = [ud boolForKey:kHideServiceKey];
    BOOL hideFind    = [ud boolForKey:kHideFindKey];
    BOOL hideAI      = [ud boolForKey:kHideAIKey];
    if (!hideService && !hideFind && !hideAI) return;

    NSMutableArray *items = [NSMutableArray array];
    HTCollectItems(tabBar, items);
    if (items.count < 2) return;

    if (!gDumpedTree) {
        gDumpedTree = YES;
        TAB_LOG(@"tabBar=%@@(%d) items=%lu", NSStringFromClass([tabBar class]),
                (int)tabBar.subviews.count, (unsigned long)items.count);
        for (UIView *v in tabBar.subviews) {
            TAB_LOG(@"  sub: %@ hidden=%d frame=%@", NSStringFromClass([v class]),
                    (int)v.hidden, NSStringFromCGRect(v.frame));
        }
    }

    // AI 扫描会遍历整棵窗口树，必须节流，否则主线程被拖死
    if (hideAI) {
        CFTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (now - gLastAIScan > 2.0) {
            gLastAIScan = now;
            HTHideAIViews(tabBar, items);
        }
    }

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

    if (visible.count == 0 || visible.count >= items.count) return;

    // 按未变换的 center.x 排序（保持左右顺序）
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
        CGFloat targetX = w * ((CGFloat)k + 0.5f) / (CGFloat)vn;
        CGFloat dx = targetX - it.center.x;          // center 是未变换的布局位置
        CGAffineTransform t = CGAffineTransformMakeTranslation(dx, 0);
        // 只在变化时赋值（幂等，且不会触发父视图 layout）
        if (fabs(it.transform.tx - dx) > 0.5f) {
            it.transform = t;
        }
    }
}

// ---------------------------------------------------------------------------
// hook layoutSubviews
// ---------------------------------------------------------------------------
static void HTTabBarLayout(id self, SEL _cmd) {
    typedef void (*fn_t)(id, SEL);
    if (HTOrig_tabbarLayout) ((fn_t)HTOrig_tabbarLayout)(self, _cmd);

    if (gTabDisabled) return;
    // 看门狗：1 秒内布局超过 60 次视为回环，自动停用，避免整机卡死
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - gLastLayoutTime < 0.05) {
        if (++gLayoutBurst > 60) {
            gTabDisabled = YES;
            TAB_LOG(@"布局过于频繁，已自动停用 Tab 调整（其它功能不受影响）");
            return;
        }
    } else {
        gLayoutBurst = 0;
    }
    gLastLayoutTime = now;

    if (gInTabLayout) return;
    gInTabLayout = YES;
    @try {
        HTApplyTabBar((UIView *)self);
    } @catch (NSException *e) {
        TAB_LOG(@"布局异常：%@", e.reason);
    }
    gInTabLayout = NO;
}

// ---------------------------------------------------------------------------
// 开关变化后重跑
// ---------------------------------------------------------------------------
static void HTRefreshTabBars(void) {
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
    if (!keyWin) return;

    Class barCls = objc_getClass("HYTabBar");
    if (!barCls) return;

    int found = 0;
    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:keyWin];
    int guard = 0;
    while (stack.count > 0 && guard++ < 4000) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if ([v isKindOfClass:barCls]) {
            HTApplyTabBar(v);
            found++;
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    TAB_LOG(@"刷新 tab bar：命中 %d 个", found);
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HeJiaTabInit(void) {
    @autoreleasepool {
        TAB_LOG(@"════ Tab 模块 v5 加载（transform 重排 + 看门狗）════");

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
        if (hooked == 0) TAB_LOG(@"未找到 HYTabBar，隐藏功能不可用");

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"HeJiaTool_TabbarReload"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(id note) { (void)note; HTRefreshTabBars(); }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ HTRefreshTabBars(); });

        TAB_LOG(@"════ Tab 模块 v5 完成 ════");
    }
}

} // extern "C"
