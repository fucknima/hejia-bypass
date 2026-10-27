// ============================================================================
//  HeJiaTool 手势唤起模块 v4
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  ⚠️ 崩溃历史：
//    v1: layoutSubviews 里设 frame → 无限递归 → 0x8BADF00D
//    v2: 向 HYMyInfoNaviView addSubview → 它是 UIVisualEffectView 内部
//        结构 → NSAssertionHandler 断言 → SIGABRT
//
//  v4 方案：三指长按唤起，完全不碰任何视图
//    - 在 UIWindow 上挂一个 UILongPressGestureRecognizer（numberOfTouchesRequired=3）
//    - 手势识别后弹出 UIAlertController 菜单
//    - 只有用户主动触发才会创建 UI，平时零开销、零副作用
//
//  为什么安全：
//    - 不 hook 任何 layoutSubviews
//    - 不 addSubview 到 App 的视图树
//    - 不修改 navigationItem
//    - 手势识别器挂在 window 上，UIKit 原生支持，不会断言
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#include <substrate.h>

extern "C" void HTWriteLog(const char *tag, NSString *fmt, ...);
extern "C" const char *HTGetLogFilePath(void);
#define UI_LOG(fmt, ...) HTWriteLog("HeJiaUI", fmt, ##__VA_ARGS__)

extern "C" {

// 关闭状态（临时开关，不影响设置页的持久化配置）
static const void *kHTGestureKey = &kHTGestureKey;

extern UIViewController *HTMakeSettingsVC(void);

// ---------------------------------------------------------------------------
// 取当前最顶层控制器
// ---------------------------------------------------------------------------
static UIViewController *HTTopMostViewController(void) {
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;

    UIViewController *top = keyWin.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;

    if ([top isKindOfClass:[UINavigationController class]]) {
        UIViewController *v = ((UINavigationController *)top).topViewController;
        if (v) top = v;
    }
    return top;
}

// ---------------------------------------------------------------------------
// 手势回调：弹出菜单
// ---------------------------------------------------------------------------
static void HTGestureFired(UILongPressGestureRecognizer *g) {
    // 只在开始时触发一次，忽略变化/结束态
    if (g.state != UIGestureRecognizerStateBegan) return;

    UI_LOG(@"三指长按触发");

    UIViewController *top = HTTopMostViewController();
    if (!top) { UI_LOG(@"找不到顶层控制器"); return; }

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:@"HeJiaTool 工具箱"
                         message:@"选择要执行的操作"
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"⚙️ 打开设置"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        UIViewController *vc = HTMakeSettingsVC();
        if (!vc) { UI_LOG(@"设置页创建失败"); return; }
        UINavigationController *nav =
            [[UINavigationController alloc] initWithRootViewController:vc];
        [HTTopMostViewController() presentViewController:nav animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"📄 复制日志路径"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) {
        (void)a;
        const char *p = HTGetLogFilePath();
        NSString *path = [NSString stringWithUTF8String:p ?: ""];
        [UIPasteboard generalPasteboard].string = path;
        UI_LOG(@"已复制日志路径: %@", path);

        UIAlertController *ok = [UIAlertController
            alertControllerWithTitle:@"日志路径已复制"
                             message:path
                      preferredStyle:UIAlertControllerStyleAlert];
        [ok addAction:[UIAlertAction actionWithTitle:@"好"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
        [HTTopMostViewController() presentViewController:ok animated:YES completion:nil];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    // iPad 需要设置 popover 锚点，否则崩溃
    // 为 iPad 设置锚点（iPhone 上无 popover，if 内不会执行）
    UIPopoverPresentationController *pop = sheet.popoverPresentationController;
    if (pop) {
        pop.sourceView = top.view;
        pop.sourceRect = CGRectMake(top.view.bounds.size.width / 2,
                                    top.view.bounds.size.height / 2, 1, 1);
    }

    [top presentViewController:sheet animated:YES completion:nil];
}

// ---------------------------------------------------------------------------
// 给 window 挂手势
// ---------------------------------------------------------------------------
static void HTInstallGesture(UIWindow *window) {
    if (!window) return;
    if (objc_getAssociatedObject(window, kHTGestureKey)) return;

    // 给 window 动态挂手势回调方法（只需一次）
    static BOOL methodAdded = NO;
    if (!methodAdded) {
        class_addMethod(object_getClass(window),
                        sel_registerName("HTGestureFired:"),
                        (IMP)HTGestureFired, "v24@0:8@16");
        methodAdded = YES;
    }

    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc]
         initWithTarget:window action:sel_registerName("HTGestureFired:")];
    g.numberOfTouchesRequired = 3;
    g.minimumPressDuration = 0.6;
    g.cancelsTouchesInView = NO;
    g.delaysTouchesBegan = NO;
    g.delaysTouchesEnded = NO;

    [window addGestureRecognizer:g];
    objc_setAssociatedObject(window, kHTGestureKey, g,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UI_LOG(@"已给 window 挂载三指长按手势");
}

// ---------------------------------------------------------------------------
// 监听 window 出现：hook UIWindow 的 didBecomeKeyWindow（最轻量）
// ---------------------------------------------------------------------------
static IMP HTOrig_becomeKey = NULL;

static void HTWindowBecomeKey(id self, SEL _cmd) {
    typedef void (*fn_t)(id, SEL);
    if (HTOrig_becomeKey) ((fn_t)HTOrig_becomeKey)(self, _cmd);

    // 延迟到下一 runloop，确保 window 已完成初始化
    __weak UIWindow *weakWin = (UIWindow *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = weakWin;
        if (w && w.isKeyWindow) HTInstallGesture(w);
    });
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HeJiaUIInit(void) {
    @autoreleasepool {
        UI_LOG(@"════ 手势模块 v4 加载 ════");

        Class winCls = objc_getClass("UIWindow");
        if (winCls) {
            Method m = class_getInstanceMethod(winCls, @selector(didBecomeKeyWindow));
            if (!m) m = class_getInstanceMethod(winCls,
                        sel_registerName("becomeKeyWindow"));
            if (m) {
                HTOrig_becomeKey = method_getImplementation(m);
                method_setImplementation(m, (IMP)HTWindowBecomeKey);
                UI_LOG(@"hook -[UIWindow didBecomeKeyWindow]");
            }
        }

        // 兜底：若 window 早已是 key（dylib 注入晚于启动），延时后主动挂一次
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIWindow *keyWin = nil;
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                if (w.isKeyWindow) { keyWin = w; break; }
            }
            if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
            HTInstallGesture(keyWin);
        });

        UI_LOG(@"════ 手势模块初始化完成 ════");
    }
}

} // extern "C"
