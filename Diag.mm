// ============================================================================
//  Diag.mm —— 定位「点不了」到底卡在哪
// ----------------------------------------------------------------------------
//  只做两件事，都是只读，不改变任何行为：
//    1) 心跳：主线程每 3 秒写一行 alive N
//       —— 日志里 alive 停住 = 主线程真卡死；一直在跳 = 程序活着，是视图吃掉了点击
//    2) hitTest 采样：前 20 次点击，记录「命中谁」
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern "C" void HTLog(const char *tag, NSString *msg);
#define D_LOG(...) HTLog("HeJiaDiag", [NSString stringWithFormat:__VA_ARGS__])

extern "C" {

static IMP gOrigHitTest = NULL;
static int gHitCount = 0;

static id HTDiagHitTest(id self, SEL _cmd, CGPoint point, id event) {
    typedef id (*fn_t)(id, SEL, CGPoint, id);
    id hit = gOrigHitTest ? ((fn_t)gOrigHitTest)(self, _cmd, point, event) : nil;

    if (gHitCount < 20) {
        gHitCount++;
        NSString *extra = @"";
        if (hit) {
            CGRect f = ((UIView *)hit).frame;
            extra = [NSString stringWithFormat:@" frame=(%.0f,%.0f,%.0f,%.0f) super=%@",
                     f.origin.x, f.origin.y, f.size.width, f.size.height,
                     NSStringFromClass([((UIView *)hit).superview class])];
        }
        D_LOG(@"hit#%d on %@ (%.0f,%.0f) -> %@%@",
              gHitCount,
              NSStringFromClass([self class]),
              point.x, point.y,
              hit ? NSStringFromClass([hit class]) : @"nil",
              extra);
    }
    return hit;
}

// ---------------------------------------------------------------------------
// 一次性 dump：窗口列表 + 视图树（类名/坐标/隐藏/可交互）
// ---------------------------------------------------------------------------
static void HTDumpTree(UIView *v, int depth, int *budget) {
    if (!v || depth > 6 || *budget <= 0) return;
    (*budget)--;
    CGRect f = v.frame;
    NSString *pad = @"";
    for (int i = 0; i < depth; i++) pad = [pad stringByAppendingString:@"  "];
    D_LOG(@"%@%@ f=(%.0f,%.0f,%.0f,%.0f) h=%d a=%.2f i=%d",
          pad,
          NSStringFromClass([v class]),
          f.origin.x, f.origin.y, f.size.width, f.size.height,
          (int)v.hidden, (double)v.alpha, (int)v.isUserInteractionEnabled);
    for (UIView *s in v.subviews) HTDumpTree(s, depth + 1, budget);
}

static void HTDumpHierarchy(void) {
    NSArray *wins = [UIApplication sharedApplication].windows;
    D_LOG(@"==== windows=%lu ====", (unsigned long)wins.count);
    int budget = 260;
    for (UIWindow *w in wins) {
        CGRect f = w.frame;
        D_LOG(@"WIN %@ f=(%.0f,%.0f,%.0f,%.0f) h=%d level=%.0f root=%@",
              NSStringFromClass([w class]),
              f.origin.x, f.origin.y, f.size.width, f.size.height,
              (int)w.hidden, (double)w.windowLevel,
              NSStringFromClass([w.rootViewController class]));
    }
    // 每个窗口都在触点 (235,861) 上做一次 hitTest，直接看谁接得住
    CGPoint probe = CGPointMake(235, 861);
    for (UIWindow *w in wins) {
        UIViewController *r = w.rootViewController;
        UIViewController *top = r;
        if ([r isKindOfClass:[UINavigationController class]])
            top = [(UINavigationController *)r topViewController];
        D_LOG(@"WINHIT %@ level=%.0f h=%d root=%@ top=%@ nsub=%lu -> %@",
              NSStringFromClass([w class]), (double)w.windowLevel, (int)w.hidden,
              NSStringFromClass([r class]), NSStringFromClass([top class]),
              (unsigned long)w.subviews.count,
              NSStringFromClass([ [w hitTest:probe withEvent:nil] class ]));
    }

    D_LOG(@"==== keyWindow tree ====");
    for (UIWindow *w in wins) {
        D_LOG(@"---- tree of %@ level=%.0f ----", NSStringFromClass([w class]), (double)w.windowLevel);
        int b = 40;
        HTDumpTree(w, 0, &b);
    }
    D_LOG(@"==== tree end (budget=%d) ====", budget);
}

static void HTDiagHeartbeat(void) {
    static int n = 0;
    if (n >= 25) return;
    n++;
    D_LOG(@"alive %d", n);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ HTDiagHeartbeat(); });
}

__attribute__((constructor))
static void HTDiagInit(void) {
    @autoreleasepool {
        D_LOG(@"════ Diag 加载 ════");

        Class win = objc_getClass("UIWindow");
        if (win) {
            Method m = class_getInstanceMethod(win, sel_registerName("hitTest:withEvent:"));
            if (m) {
                gOrigHitTest = method_getImplementation(m);
                method_setImplementation(m, (IMP)HTDiagHitTest);
                D_LOG(@"hitTest 采样已开启（前 20 次）");
            } else {
                D_LOG(@"没找到 hitTest:withEvent:");
            }
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ HTDiagHeartbeat(); });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try { HTDumpHierarchy(); } @catch (NSException *e) { (void)e; }
        });
    }
}

} // extern "C"
