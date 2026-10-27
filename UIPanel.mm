// ============================================================================
//  HeJiaTool 唤起模块 v5 —— 多路并发，确保能打开
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  v4 的三指长按失效原因：
//    手势挂在 rootViewController.view 上，页面切换时该 view 被替换，
//    手势一并丢失；且 App 内部手势可能先消费掉三指事件。
//
//  v5 改为「三路同时生效，任一路成功即可」：
//
//    路线 A：hook -[UIWindow sendEvent:]（最底层，所有触摸必然经过）
//            在这里做触摸计数：检测「3 个手指同时按下并保持 0.5 秒」
//            完全绕过 UIKit 手势系统，不会被任何手势吞掉
//
//    路线 B：状态栏区域双击（顶部 44pt 内，40x40 区域点两下）
//            状态栏无人占用，触摸一定到达 window
//
//    路线 C：摇一摇（UIWindow motionEnded:），完全独立于触摸
//
//  任何一路触发都弹出同一个菜单。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#include <CoreFoundation/CoreFoundation.h>

#include <substrate.h>

extern "C" void HTLog(const char *tag, NSString *msg);
extern "C" const char *HTGetLogFilePath(void);
#define UI_LOG(...) HTLog("HeJiaUI", [NSString stringWithFormat:__VA_ARGS__])

extern "C" UIViewController *HTMakeSettingsVC(void);

extern "C" {

// ---------------------------------------------------------------------------
// 状态
// ---------------------------------------------------------------------------
static CFTimeInterval gFingerDownTime = 0;   // 三指按下的时刻
static int gMaxFingers = 0;                  // 本次触摸最多几指
static CFTimeInterval gLastStatusTap = 0;    // 上次点状态栏的时刻
static IMP HTOrig_sendEvent = NULL;
static IMP HTOrig_motionEnded = NULL;

static const void *kHTMenuShowingKey = &kHTMenuShowingKey;

// ---------------------------------------------------------------------------
// 取最顶层控制器
// ---------------------------------------------------------------------------
static UIViewController *HTTopMost(void) {
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;

    UIViewController *top = keyWin.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

// ---------------------------------------------------------------------------
// 弹出主菜单
// ---------------------------------------------------------------------------
static void HTShowMenu(void) {
    // 防重复弹
    if (objc_getAssociatedObject([UIApplication sharedApplication],
                                 kHTMenuShowingKey)) return;

    UIViewController *top = HTTopMost();
    if (!top) { UI_LOG(@"找不到顶层控制器"); return; }

    UI_LOG(@"菜单触发成功");

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"HeJiaTool 工具箱"
                         message:@"选择要执行的操作"
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"⚙️  打开设置"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        UIViewController *vc = HTMakeSettingsVC();
        if (!vc) return;
        UINavigationController *nav =
            [[UINavigationController alloc] initWithRootViewController:vc];
        [HTTopMost() presentViewController:nav animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📄  复制日志路径"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        const char *p = HTGetLogFilePath();
        NSString *path = [NSString stringWithUTF8String:p ?: ""];
        [UIPasteboard generalPasteboard].string = path;
        UI_LOG(@"已复制日志路径");

        UIAlertController *ok = [UIAlertController
            alertControllerWithTitle:@"日志路径已复制"
                             message:path
                      preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"好"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
        [HTTopMost() presentViewController:ok animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = top.view;
        pop.sourceRect = CGRectMake(top.view.bounds.size.width / 2,
                                    top.view.bounds.size.height / 2, 1, 1);
    }

    objc_setAssociatedObject([UIApplication sharedApplication],
                             kHTMenuShowingKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [top presentViewController:sheet animated:YES completion:^{
        objc_setAssociatedObject([UIApplication sharedApplication],
                                 kHTMenuShowingKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}

// ---------------------------------------------------------------------------
// 路线 A：hook sendEvent，自己数手指
//   优势：完全绕过手势系统，任何手势都抢不走
// ---------------------------------------------------------------------------
static void HTSendEvent(id self, SEL _cmd, UIEvent *event) {
    // 先让系统正常处理
    typedef void (*fn_t)(id, SEL, UIEvent *);
    if (HTOrig_sendEvent) ((fn_t)HTOrig_sendEvent)(self, _cmd, event);

    if (!event) return;

    // UIEvent.type : 4 = touches（直接读 ivar，避免 objc_msgSend 类型问题）
    NSInteger type = 0;
    Ivar typeIvar = class_getInstanceVariable(object_getClass(event), "_type");
    if (typeIvar) {
        type = (NSInteger)(long)*(NSInteger *)((char *)(__bridge void *)event
                                               + ivar_getOffset(typeIvar));
    }
    if (type != 4) return;

    // allTouches：用 NSObject 的 valueForKey 拿（安全，不需要 objc_msgSend）
    NSSet *touches = nil;
    if ([event respondsToSelector:sel_registerName("allTouches")]) {
        id v = [event valueForKey:@"allTouches"];
        if ([v isKindOfClass:[NSSet class]]) touches = (NSSet *)v;
    }
    if (!touches) return;
    NSUInteger tcount = touches.count;
    if (tcount == 0) return;

    // 数一下当前按下（未结束）的手指
    int active = 0;
    BOOL anyBegan = NO;
    BOOL allEnded = YES;
    for (id t in touches) {
        NSInteger phase = 0;
        if ([t respondsToSelector:sel_registerName("phase")]) {
            phase = (NSInteger)(long)[t valueForKey:@"phase"];
            // valueForKey 可能返回 NSNumber
            if (phase == 0) {
                id pv = [t valueForKey:@"phase"];
                if ([pv isKindOfClass:[NSNumber class]]) phase = [pv longValue];
            }
        }
        if (phase == 0) anyBegan = YES;
        if (phase != 3 && phase != 4) { active++; allEnded = NO; }
    }

    CFTimeInterval now = CACurrentMediaTime();

    if (anyBegan) {
        if (active > gMaxFingers) gMaxFingers = active;
        if (gMaxFingers >= 3 && gFingerDownTime == 0) {
            gFingerDownTime = now;
            UI_LOG(@"检测到 %d 指按下，等待保持...", gMaxFingers);
        }
    }

    // 满足条件：3 指以上、保持超过 0.45 秒
    if (gFingerDownTime > 0 && gMaxFingers >= 3) {
        if (now - gFingerDownTime >= 0.45) {
            UI_LOG(@"三指保持 %.2fs，触发", now - gFingerDownTime);
            gFingerDownTime = 0;
            gMaxFingers = 0;
            HTShowMenu();
            return;
        }
    }

    if (allEnded || tcount == 0) {
        gFingerDownTime = 0;
        gMaxFingers = 0;
    }

    // ---- 路线 B：状态栏双击 ----
    if (anyBegan && tcount == 1) {
        for (id t in touches) {
            CGPoint p = CGPointZero;
            id v = [t valueForKey:@"locationInWindow"];
            if ([v isKindOfClass:[NSValue class]]) {
                p = [(NSValue *)v CGPointValue];
            }

            // 状态栏区域：顶部 60pt 内、水平居右 1/3（避开灵动岛/刘海）
            UIWindow *w = (UIWindow *)self;
            CGFloat ww = w ? w.bounds.size.width : 390;
            if (p.y >= 0 && p.y <= 60 && p.x >= ww * 0.45 && p.x <= ww) {
                if (gLastStatusTap > 0 && (now - gLastStatusTap) < 1.2) {
                    UI_LOG(@"状态栏双击触发");
                    gLastStatusTap = 0;
                    HTShowMenu();
                } else {
                    gLastStatusTap = now;
                }
            }
            break;
        }
    }
}

// ---------------------------------------------------------------------------
// 路线 C：摇一摇
// ---------------------------------------------------------------------------
static void HTMotionEnded(id self, SEL _cmd, NSInteger subtype, UIEvent *event) {
    typedef void (*fn_t)(id, SEL, NSInteger, UIEvent *);
    if (HTOrig_motionEnded) ((fn_t)HTOrig_motionEnded)(self, _cmd, subtype, event);

    // UIEventSubtypeMotionShake = 1
    if (subtype == 1) {
        UI_LOG(@"摇一摇触发");
        HTShowMenu();
    }
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HeJiaUIInit(void) {
    @autoreleasepool {
        UI_LOG(@"════ 唤起模块 v5 加载（三路并发）════");

        Class winCls = objc_getClass("UIWindow");
        if (winCls) {
            // 路线 A + B
            Method m = class_getInstanceMethod(winCls, @selector(sendEvent:));
            if (m) {
                HTOrig_sendEvent = method_getImplementation(m);
                method_setImplementation(m, (IMP)HTSendEvent);
                UI_LOG(@"路线A/B已就绪: hook -[UIWindow sendEvent:]");
            }

            // 路线 C
            Method m2 = class_getInstanceMethod(winCls, @selector(motionEnded:withEvent:));
            if (m2) {
                HTOrig_motionEnded = method_getImplementation(m2);
                method_setImplementation(m2, (IMP)HTMotionEnded);
                UI_LOG(@"路线C已就绪: hook -[UIWindow motionEnded:withEvent:]");
            }
        }

        UI_LOG(@"════ 三条触发路线全部就绪 ════");
        UI_LOG(@"  ① 三指同时按住屏幕 0.5 秒");
        UI_LOG(@"  ② 双击屏幕右上角状态栏");
        UI_LOG(@"  ③ 摇一摇手机");
    }
}

} // extern "C"
