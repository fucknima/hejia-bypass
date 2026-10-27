// ============================================================================
//  WindowFix.mm —— 修「点不了」的真正元凶：高位空窗口吃掉触摸
// ----------------------------------------------------------------------------
//  实测证据（HeJiaTool_7.log）：
//    WINHIT UIWindow level=0     top=HYCustomTabController nsub=5 -> HYCustomTabBarItem
//    WINHIT UIWindow level=1999  top=UIViewController       nsub=1 -> UIView
//  窗口按 windowLevel 排序，1999 在主窗口(0) 之上；它的 rootVC 是一个普通
//  UIViewController，view 是铺满全屏的 UIView，0 个子视图，但
//  isUserInteractionEnabled = YES —— 于是所有触摸都被这层空窗口接走。
//  摇一摇菜单是系统 alert（level 2000），在它之上，所以只有那个能点。
//
//  处理：周期性扫描"高位的空窗口"，把 root view 的交互关掉（触摸就会穿透到
//  下面主窗口）；一旦它长出子视图（真的要用），再恢复交互。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern "C" void HTLog(const char *tag, NSString *msg);
#define WIN_LOG(...) HTLog("HeJiaWin", [NSString stringWithFormat:__VA_ARGS__])

extern "C" {

static NSMutableArray *gDisabled = nil;   // 被我们关掉交互的 root view

static BOOL HTIsOurDisabled(UIView *v) {
    for (id o in gDisabled) if (o == v) return YES;
    return NO;
}

static void HTScanWindows(void) {
    if (!gDisabled) gDisabled = [NSMutableArray array];

    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        @try {
            CGFloat lv = w.windowLevel;
            if (lv <= 0) continue;          // 主窗口不动
            if (lv >= 2000) continue;       // 系统 alert 层不动
            if (w.hidden) continue;

            UIView *root = w.rootViewController.view;
            if (!root) continue;

            NSUInteger n = root.subviews.count;

            if (n == 0) {
                // 空的全屏高位窗口 → 关掉交互，让触摸穿透
                if (root.isUserInteractionEnabled) {
                    root.userInteractionEnabled = NO;
                    [gDisabled addObject:root];
                    WIN_LOG(@"禁用空窗口交互 level=%.0f root=%@ frame=%.0fx%.0f",
                            (double)lv, NSStringFromClass([root class]),
                            root.frame.size.width, root.frame.size.height);
                }
            } else if (HTIsOurDisabled(root) && !root.isUserInteractionEnabled) {
                // 它开始有内容了 → 还原
                root.userInteractionEnabled = YES;
                [gDisabled removeObject:root];
                WIN_LOG(@"空窗口长出 %lu 个子视图，恢复交互 level=%.0f",
                        (unsigned long)n, (double)lv);
            }
        } @catch (NSException *e) { (void)e; }
    }
}

__attribute__((constructor))
static void HTWindowFixInit(void) {
    @autoreleasepool {
        WIN_LOG(@"════ WindowFix 加载 ════");

        // 前 20 秒密集扫（窗口/页面会反复创建），之后每 5 秒兜底
        for (int i = 1; i <= 10; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)i * 2000 * 1000000LL),
                           dispatch_get_main_queue(), ^{
                @try { HTScanWindows(); } @catch (NSException *e) { (void)e; }
            });
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try { HTScanWindows(); } @catch (NSException *e) { (void)e; }
        });

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(id note) { (void)note; HTScanWindows(); }];
    }
}

} // extern "C"
