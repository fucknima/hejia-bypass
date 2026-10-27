// ============================================================================
//  Tab 隐藏模块 v4 —— 隐藏后重排，消除空白；支持隐藏中间「AI灵犀」
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  v3 的问题（用户实测截图）：
//    只把按钮 hidden=YES，HYTabBar 的 frame 是 layoutSubviews 按**原始数量**
//    算好的，所以「服务」「发现」的位置留下两个空档，两边挤、中间空，很别扭。
//
//  v4：
//    1) 仍然**不动 viewControllers / 不改索引**（v2 的错位 bug 不会回来）
//    2) 隐藏后，把剩下的 item 均匀重排：center.x = width*(i+0.5)/n
//       —— 只改 center，不改 size，不会触发 cell 级重排
//    3) 新增「AI灵犀」（中间那个凸起圆头像）开关 HeJiaTool_HideAI
//       同时隐藏它头顶的气泡 HYCustomTabBarAIBubble*
//    4) 递归保护不变
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import <objc/runtime.h>

#include <substrate.h>

extern "C" void HTLog(const char *tag, NSString *msg);
#define TAB_LOG(...) HTLog("HeJiaTab", [NSString stringWithFormat:__VA_ARGS__])

extern "C" {

static NSString *const kHideServiceKey = @"HeJiaTool_HideService";
static NSString *const kHideFindKey    = @"HeJiaTool_HideFind";
static NSString *const kHideAIKey      = @"HeJiaTool_HideAI";

static IMP HTOrig_tabbarLayout = NULL;
static __thread BOOL gInTabLayout = NO;

// HYTabBar 暴露的两个查询方法
@protocol HTTabBarItems
- (id)itemsAtIndex:(NSUInteger)index;
- (NSUInteger)itemsCount;
@end

// ---------------------------------------------------------------------------
// 递归查找：视图里是否含指定文字
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
// 收集 tab bar 的 item
// ---------------------------------------------------------------------------
static void HTCollectItems(UIView *tabBar, NSMutableArray *out) {
    if ([tabBar respondsToSelector:@selector(itemsAtIndex:)] &&
        [tabBar respondsToSelector:@selector(itemsCount)]) {
        id<HTTabBarItems> bar = (id<HTTabBarItems>)tabBar;
        NSUInteger n = [bar itemsCount];
        for (NSUInteger i = 0; i < n; i++) {
            @try {
                UIView *it = (UIView *)[bar itemsAtIndex:i];
                if (it && [it isKindOfClass:[UIView class]]) [out addObject:it];
            } @catch (NSException *e) { (void)e; }
        }
    }
    if (out.count == 0) {
        // 兜底：按类名找
        Class c1 = objc_getClass("HYTabBarItem");
        Class c2 = objc_getClass("HYBaseTabBarItem");
        for (UIView *v in tabBar.subviews) {
            if ((c1 && [v isKindOfClass:c1]) || (c2 && [v isKindOfClass:c2])) {
                [out addObject:v];
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 主逻辑：隐藏 + 重排
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

    // ---- 1. 按文字决定谁隐藏 ----
    NSMutableArray *visible = [NSMutableArray array];
    for (UIView *it in items) {
        BOOL shouldHide = NO;
        if (hideService && HTViewHasText(it, @"服务", 0)) shouldHide = YES;
        if (!shouldHide && hideFind && HTViewHasText(it, @"发现", 0)) shouldHide = YES;
        if (!shouldHide && hideAI &&
            (HTViewHasText(it, @"AI灵犀", 0) || HTViewHasText(it, @"灵犀", 0))) shouldHide = YES;

        if (shouldHide) {
            if (!it.hidden) {
                it.hidden = YES;
                TAB_LOG(@"隐藏 tab item：%@", HTViewHasText(it, @"服务", 0) ? @"服务" :
                                               (HTViewHasText(it, @"发现", 0) ? @"发现" : @"AI灵犀"));
            }
        } else {
            [visible addObject:it];
        }
    }

    // ---- 2. 隐藏 AI 气泡（挂在 tab bar 或它的父视图上）----
    if (hideAI) {
        NSMutableArray *scan = [NSMutableArray array];
        [scan addObject:tabBar];
        if (tabBar.superview) [scan addObject:tabBar.superview];
        for (UIView *host in scan) {
            for (UIView *v in host.subviews) {
                if (v.hidden) continue;
                NSString *cn = NSStringFromClass([v class]);
                if ([cn containsString:@"AIBubble"] || [cn containsString:@"AIRemind"] ||
                    [cn containsString:@"AIBannerBubble"]) {
                    v.hidden = YES;
                    TAB_LOG(@"隐藏 AI 气泡：%@", cn);
                }
            }
        }
        // tab bar 内部若有独立的「AI灵犀」子视图（不在 items 里）
        for (UIView *v in tabBar.subviews) {
            if (v.hidden) continue;
            if (HTViewHasText(v, @"AI灵犀", 0)) {
                v.hidden = YES;
                TAB_LOG(@"隐藏 AI 独立子视图：%@", NSStringFromClass([v class]));
            }
        }
    }

    // ---- 3. 剩下的一起均匀重排 ----
    if (visible.count >= 1 && visible.count < items.count) {
        // 按当前 x 排序，保持原有左右顺序
        // 简单插入排序（按当前 x 从左到右）
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
        NSUInteger n = visible.count;
        for (NSUInteger k = 0; k < n; k++) {
            UIView *it = visible[k];
            CGPoint c = it.center;
            c.x = w * ((CGFloat)k + 0.5f) / (CGFloat)n;
            if (fabs(c.x - it.center.x) > 0.5f) {
                it.center = c;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// hook layoutSubviews
// ---------------------------------------------------------------------------
static void HTTabBarLayout(id self, SEL _cmd) {
    typedef void (*fn_t)(id, SEL);
    if (HTOrig_tabbarLayout) ((fn_t)HTOrig_tabbarLayout)(self, _cmd);

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
    if (keyWin) [stack addObject:keyWin];
    while (stack.count > 0) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];
        if ([v isKindOfClass:barCls]) {
            HTApplyTabBar(v);
            [v setNeedsLayout];
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
        TAB_LOG(@"════ Tab 模块 v4 加载（隐藏后重排 + AI 开关）════");

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

        TAB_LOG(@"════ Tab 模块 v4 完成 ════");
    }
}

} // extern "C"
