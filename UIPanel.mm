// ============================================================================
//  HeJiaTool 设置中心（UI 层）v3
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  ⚠️ 崩溃历史（务必读）：
//    v1: 在 layoutSubviews 里设 frame → 无限递归 → 0x8BADF00D 看门狗
//    v2: 向 HYMyInfoNaviView 直接 addSubview。该视图内部含有
//        UIVisualEffectView（毛玻璃），UIKit 明确禁止向它 addSubview，
//        触发 NSAssertionHandler → SIGABRT
//        (栈：-[UIVisualEffectView _addSubview:positioned:relativeTo:])
//
//  v3 方案：完全不碰视图层级
//    改用 UIBarButtonItem 走正规通道：
//      寻找承载「我的」页的 UINavigationController，
//      在它的 topViewController.navigationItem 上插入自定义按钮。
//    这样由 UIKit 自己负责布局，不会有任何层级/递归问题。
//
//    若「我的」页没有 NavigationController（自绘导航栏），
//    则改用 window 级别的浮层按钮，点击后再弹设置页，绝不侵入原视图。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#include <substrate.h>

extern "C" void HTWriteLog(const char *tag, NSString *fmt, ...);
#define UI_LOG(fmt, ...) HTWriteLog("HeJiaUI", fmt, ##__VA_ARGS__)

extern "C" {

static NSString *const HTInjectedKey = @"HeJiaTool_Injected";

extern UIViewController *HTMakeSettingsVC(void);

static IMP HTOrig_myinfo_vdl = NULL;

// ===========================================================================
// 图标
// ===========================================================================
static UIImage *HTMakeToolIcon(void) {
    CGFloat size = 24.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);

    if (@available(iOS 13.0, *)) {
        UIImage *sf = [UIImage systemImageNamed:@"wrench.and.screwdriver.fill"];
        if (sf) {
            [[UIColor labelColor] set];
            [sf drawInRect:CGRectMake(1, 1, size - 2, size - 2)];
        }
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// ===========================================================================
// 打开设置页
// ===========================================================================
static void HTOpenSettings(void) {
    UI_LOG(@"打开设置页");
    UIViewController *vc = HTMakeSettingsVC();
    if (!vc) { UI_LOG(@"设置页创建失败"); return; }

    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;

    UIViewController *top = keyWin.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top) { UI_LOG(@"找不到根控制器"); return; }

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [top presentViewController:nav animated:YES completion:nil];
}

// ===========================================================================
// 向「我的」页 navigationItem 插入按钮（正规通道，零侵入）
// ===========================================================================
static void HTInstallBarButton(UIViewController *vc) {
    if (!vc) return;
    if (objc_getAssociatedObject(vc, @selector(HTInstallBarButton))) return;   // 已装过

    UIBarButtonItem *item =
        [[UIBarButtonItem alloc] initWithImage:HTMakeToolIcon()
                                        style:UIBarButtonItemStylePlain
                                       target:vc
                                       action:sel_registerName("HTToolBarItemTapped:")];

    // 给 VC 动态挂点击方法（挂在实例类上，不影响其他类）
    class_addMethod(object_getClass(vc),
                    sel_registerName("HTToolBarItemTapped:"),
                    (IMP)(void (*)(id, SEL, id))HTOpenSettings, "v24@0:8@16");

    NSMutableArray *items = [NSMutableArray array];
    if (vc.navigationItem.rightBarButtonItems) {
        [items addObjectsFromArray:vc.navigationItem.rightBarButtonItems];
    }
    [items insertObject:item atIndex:0];
    vc.navigationItem.rightBarButtonItems = items;

    objc_setAssociatedObject(vc, @selector(HTInstallBarButton), @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UI_LOG(@"已在 %@ 导航栏插入工具按钮", NSStringFromClass([vc class]));
}

// ===========================================================================
// hook「我的」页的 viewDidLoad / viewWillAppear 来装按钮
// ===========================================================================
static void HTMyInfoViewDidLoad(id self, SEL _cmd) {
    typedef void (*fn_t)(id, SEL);
    if (HTOrig_myinfo_vdl) ((fn_t)HTOrig_myinfo_vdl)(self, _cmd);

    // 延迟到下一 runloop，确保 navigationItem 已初始化
    __weak UIViewController *wvc = (UIViewController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = wvc;
        if (!vc) return;
        // 若该 VC 在 UINavigationController 里，优先走 barButtonItem
        if (vc.navigationController) {
            HTInstallBarButton(vc);
        } else {
            UI_LOG(@"%@ 不在导航控制器内，跳过 barButton", NSStringFromClass([vc class]));
        }
    });
}

// ===========================================================================
// 入口
// ===========================================================================
__attribute__((constructor))
static void HeJiaUIInit(void) {
    @autoreleasepool {
        UI_LOG(@"════ UI 模块 v3 加载 ════");

        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:YES forKey:HTInjectedKey];
        [ud synchronize];

        // 只 hook 「我的」页 VC 的生命周期，不碰任何视图层级
        NSArray *clsNames = @[
            @"HYMyInfoViewController",
            @"HYMineViewController",
        ];
        for (NSString *name in clsNames) {
            Class c = objc_getClass(name.UTF8String);
            if (!c) continue;
            Method m = class_getInstanceMethod(c, @selector(viewDidLoad));
            if (m) {
                HTOrig_myinfo_vdl = method_getImplementation(m);
                method_setImplementation(m, (IMP)HTMyInfoViewDidLoad);
                UI_LOG(@"hook -[%@ viewDidLoad]", name);
                break;   // 只挂第一个找到的
            }
        }

        UI_LOG(@"════ UI 初始化完成 ════");
    }
}

} // extern "C"
