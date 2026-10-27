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
    }
}

} // extern "C"
