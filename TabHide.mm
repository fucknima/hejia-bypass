// ============================================================================
//  Tab 隐藏模块 v8 —— 不碰 layoutSubviews，全部由定时器完成
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
// AI：HYCustomTabBar 有 AIIndex 属性；拿不到就用几何特征（居中 + 抬高）
// ---------------------------------------------------------------------------
__attribute__((unused))
static void HTHideAI(UIView *tabBar) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud boolForKey:kHideAIKey]) return;

    int hidden = 0;

    // 1) 气泡（类名精确匹配 + 尺寸护栏）
    UIWindow *win = tabBar.window;
    if (win) {
        NSMutableArray *stack = [NSMutableArray array];
        [stack addObject:win];
        int guard = 0;
        while (stack.count > 0 && guard++ < 5000) {
            UIView *v = [stack lastObject];
            [stack removeLastObject];
            if (!v.hidden) {
                NSString *cn = NSStringFromClass([v class]);
                CGSize sz = v.bounds.size;
                if (sz.width > 0 && sz.width <= 280 && sz.height <= 280 &&
                    ([cn containsString:@"AIBubble"] || [cn containsString:@"AIBannerBubble"] ||
                     [cn containsString:@"AIRemind"] || [cn containsString:@"LingXi"])) {
                    v.hidden = YES; hidden++;
                    TAB_LOG(@"AI 气泡隐藏：%@", cn);
                }
            }
            for (UIView *sub in v.subviews) [stack addObject:sub];
        }
    }

    // 2) AIIndex 指向的 item
    NSInteger aiIdx = -1;
    @try {
        id v = [tabBar valueForKey:@"AIIndex"];
        if ([v respondsToSelector:@selector(integerValue)]) aiIdx = [v integerValue];
    } @catch (NSException *e) { (void)e; }

    NSMutableArray *items = [NSMutableArray array];
    for (UIView *v in tabBar.subviews) {
        if ([v isKindOfClass:objc_getClass("HYCustomTabBarItem")]) [items addObject:v];
    }
    if (aiIdx >= 0 && aiIdx < (NSInteger)items.count) {
        UIView *it = items[(NSUInteger)aiIdx];
        if (!it.hidden) { it.hidden = YES; hidden++; TAB_LOG(@"AI: AIIndex=%ld 命中", (long)aiIdx); }
    } else if (items.count >= 3) {
        // 几何特征：居中 + 比其它 item 更靠上（凸起）
        CGFloat w = tabBar.bounds.size.width;
        CGFloat mid = w / 2.0;
        UIView *best = nil;
        CGFloat bestDy = 0;
        for (UIView *it in items) {
            if (it.hidden) continue;
            if (fabs(it.center.x - mid) > w * 0.12) continue;      // 必须居中
            CGFloat dy = 0;
            for (UIView *other in items) {
                if (other == it || other.hidden) continue;
                dy += (other.center.y - it.center.y);
            }
            if (dy > 0 && dy > bestDy) { bestDy = dy; best = it; }  // 平均更高
        }
        if (best && bestDy > 1.0) {
            best.hidden = YES; hidden++;
            TAB_LOG(@"AI: 几何命中 %@ dy=%.1f", NSStringFromClass([best class]), bestDy);
        }
    }

    if (hidden > 0) TAB_LOG(@"AI 本轮隐藏 %d", hidden);
}

// ---------------------------------------------------------------------------
// 均匀重排：把某一层里可见的按钮按 width*(i+0.5)/n 摆开
//   App 的底栏是两层叠在一起：
//     UITabBar
//       ├ UITabBarButton ×5        ← 系统层（真正显示图标文字）
//       └ HYCustomTabBar          ← 自定义层（AI 凸起/气泡在这里）
//   只动自定义层的话，看起来完全没变化，所以两层都要排。
// ---------------------------------------------------------------------------
static void HTRepositionGroup(UIView *container, NSMutableArray *items) {
    if (!container || items.count == 0) return;

    NSMutableArray *vis = [NSMutableArray array];
    for (UIView *v in items) {
        if (v.hidden || v.alpha < 0.01) continue;
        [vis addObject:v];
    }
    if (vis.count == 0 || vis.count > 6) return;

    NSUInteger n = vis.count;
    for (NSUInteger i = 1; i < n; i++) {
        UIView *key = vis[i];
        NSInteger k = (NSInteger)i - 1;
        while (k >= 0 && ((UIView *)vis[(NSUInteger)k]).center.x > key.center.x) {
            vis[(NSUInteger)(k + 1)] = vis[(NSUInteger)k];
            k--;
        }
        vis[(NSUInteger)(k + 1)] = key;
    }

    CGFloat w = container.bounds.size.width;
    if (w <= 1) return;

    int moved = 0;
    for (NSUInteger i = 0; i < n; i++) {
        UIView *it = vis[i];
        CGFloat dx = w * ((CGFloat)i + 0.5f) / (CGFloat)n - it.center.x;
        if (fabs(it.transform.tx - dx) > 0.5f) {
            it.transform = CGAffineTransformMakeTranslation(dx, 0);
            moved++;
        }
    }
    if (moved) TAB_LOG(@"重排 %@：n=%lu 移动 %d 个",
                       NSStringFromClass([container class]), (unsigned long)n, moved);
}

static void HTRepositionItems(UIView *tabBar) {
    if (!tabBar) return;

    // 1) 自定义层
    Class itemCls = objc_getClass("HYCustomTabBarItem");
    if (itemCls) {
        NSMutableArray *a = [NSMutableArray array];
        for (UIView *v in tabBar.subviews)
            if ([v isKindOfClass:itemCls]) [a addObject:v];
        HTRepositionGroup(tabBar, a);
    }

    // 2) 系统层（父视图是 UITabBar）
    UIView *parent = tabBar.superview;
    Class btnCls = objc_getClass("UITabBarButton");
    if (parent && btnCls) {
        NSMutableArray *a = [NSMutableArray array];
        for (UIView *v in parent.subviews)
            if ([v isKindOfClass:btnCls]) [a addObject:v];
        HTRepositionGroup(parent, a);
    }
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
        if ([v isKindOfClass:barCls]) {
            HTHideTabItems(v);
            if (doAI) HTHideAI(v);
            HTRepositionItems(v);
            found++;
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    if (found == 0) TAB_LOG(@"窗口里没找到 HYTabBar");
}

__attribute__((constructor))
static void HeJiaTabInit(void) {
    @autoreleasepool {
        TAB_LOG(@"════ Tab 模块 v8 加载（纯定时器隐藏，不 hook 布局）════");

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        id ver = [ud objectForKey:@"HeJiaTool_TabVer"];
        if (![ver isKindOfClass:[NSString class]] || ![(NSString *)ver isEqualToString:@"9"]) {
            [ud setObject:@"9" forKey:@"HeJiaTool_TabVer"];
            TAB_LOG(@"配置版本 v9（开关保持用户设置，不再复位）");
        }

        // ⚠️ 不再 hook layoutSubviews：
        //    v3~v7 里 HYTabBar / HYCustomTabBar 共用一个 original IMP，
        //    第二个类被替换成"调用 HYTabBar 的实现"，HYCustomTabBar 自己的布局从未执行过，
        //    这会让 tab bar 的命中区域失效（点了没反应）。
        //    现在改为纯定时器隐藏，完全不碰布局。
        if (!objc_getClass("HYTabBar")) TAB_LOG(@"未找到 HYTabBar");

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"HeJiaTool_TabbarReload" object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(id note) { (void)note; HTScanAllBars(YES); }];

        const int64_t delays[] = { 1000, 2500, 5000, 9000, 15000, 25000 };
        for (int i = 0; i < 6; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delays[i] * 1000000LL),
                           dispatch_get_main_queue(), ^{
                @try { HTScanAllBars(YES); } @catch (NSException *e) { (void)e; }
            });
        }
        TAB_LOG(@"AI 隐藏：AIIndex / 几何特征 / 气泡类名，三者取一");

        TAB_LOG(@"════ Tab 模块 v8 完成 ════");
    }
}

} // extern "C"
