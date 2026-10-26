// ============================================================================
//  HeJiaTool 设置中心（UI 层）
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  入口：在「我的」页面右上角标题栏，紧贴原生设置图标左侧新增一个图标按钮。
//  实现：hook HYMyInfoNaviView 的 layoutSubviews，读取原生 settingBtn 的真实
//        frame 后把新按钮放在它左边，间距与原生保持一致（不硬编码坐标）。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#include <substrate.h>

#define UI_LOG(fmt, ...) NSLog(@"[HeJiaUI] " fmt, ##__VA_ARGS__)

extern "C" {

// 配置键（与 NoAds / SettingsVC 共用）
static NSString *const HTNoAdsKey       = @"HeJiaTool_NoAds";
static NSString *const HTHideServiceKey = @"HeJiaTool_HideService";
static NSString *const HTHideFindKey    = @"HeJiaTool_HideFind";
static NSString *const HTInjectedKey    = @"HeJiaTool_Injected";   // 过签名：强制开

extern UIViewController *HTMakeSettingsVC(void);   // 定义在 SettingsVC.mm

static IMP HTOrig_layout = NULL;

// ===========================================================================
// 图标：复用原生设置图标 + 右下角小蓝点作为区分
// ===========================================================================
static UIImage *HTMakeToolIcon(UIImage *baseImage) {
    CGFloat size = 24.0;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);

    if (baseImage) {
        [baseImage drawInRect:CGRectMake(0, 0, size, size)];
    } else if (@available(iOS 13.0, *)) {
        UIImage *sf = [UIImage systemImageNamed:@"wrench.and.screwdriver.fill"];
        if (sf) {
            [[UIColor labelColor] set];
            [sf drawInRect:CGRectMake(1, 1, size - 2, size - 2)];
        }
    }

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (ctx) {
        [[UIColor systemBlueColor] setFill];
        CGContextFillEllipseInRect(ctx, CGRectMake(size - 7.5, size - 7.5, 7, 7));
        [[UIColor whiteColor] setStroke];
        CGContextSetLineWidth(ctx, 1.2);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(size - 7.5, size - 7.5, 7, 7));
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

// ===========================================================================
// 点击：打开设置页
// ===========================================================================
static void HTToolButtonClicked(id self, SEL _cmd, id sender) {
    (void)sender;
    UI_LOG(@"工具按钮点击");

    UIViewController *vc = HTMakeSettingsVC();
    if (!vc) { UI_LOG(@"设置页创建失败"); return; }

    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;

    UIViewController *top = keyWin.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [top presentViewController:nav animated:YES completion:nil];
}

// ===========================================================================
// 布局
// ===========================================================================
static const void *kHTToolButtonKey = &kHTToolButtonKey;

static void HTLayoutNaviView(id self, SEL _cmd) {
    typedef void (*fn_t)(id, SEL);
    if (HTOrig_layout) ((fn_t)HTOrig_layout)(self, _cmd);

    UIView *navi = (UIView *)self;

    // 取原生设置按钮
    UIButton *settingBtn = nil;
    SEL btnSel = sel_registerName("settingBtn");
    if ([navi respondsToSelector:btnSel]) {
        settingBtn = ((id (*)(id, SEL))objc_msgSend)(navi, btnSel);
    }

    UIButton *myBtn = objc_getAssociatedObject(navi, kHTToolButtonKey);
    if (!myBtn) {
        myBtn = [UIButton buttonWithType:UIButtonTypeCustom];

        // 首次创建时给 navi 动态挂点击方法
        class_addMethod(object_getClass(navi),
                        sel_registerName("HTToolButtonClicked:"),
                        (IMP)HTToolButtonClicked, "v24@0:8@16");
        [myBtn addTarget:navi
                  action:sel_registerName("HTToolButtonClicked:")
        forControlEvents:UIControlEventTouchUpInside];

        UIImage *base = nil;
        if (settingBtn) {
            base = [settingBtn imageForState:UIControlStateNormal];
            if (!base) base = settingBtn.imageView.image;
        }
        [myBtn setImage:HTMakeToolIcon(base) forState:UIControlStateNormal];

        [navi addSubview:myBtn];
        objc_setAssociatedObject(navi, kHTToolButtonKey, myBtn,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UI_LOG(@"已添加工具按钮");
    }

    if (settingBtn && settingBtn.superview) {
        CGRect f = settingBtn.frame;
        CGFloat size = (f.size.width > 0) ? f.size.width : 28.0;
        CGFloat gap  = (f.size.width > 0) ? 6.0 : 0.0;
        myBtn.frame = CGRectMake(f.origin.x - size - gap, f.origin.y, size, f.size.height);
    } else {
        CGFloat h = navi.bounds.size.height;
        myBtn.frame = CGRectMake(navi.bounds.size.width - 89, (h - 28) / 2, 28, 28);
    }
}

// ===========================================================================
// 入口
// ===========================================================================
__attribute__((constructor))
static void HeJiaUIInit(void) {
    @autoreleasepool {
        UI_LOG(@"════ UI 模块加载 ════");

        // 过签名默认强制开启（设置页里只读显示）
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:YES forKey:HTInjectedKey];
        [ud synchronize];

        Class naviCls = objc_getClass("HYMyInfoNaviView");
        if (naviCls) {
            Method m = class_getInstanceMethod(naviCls, @selector(layoutSubviews));
            if (m) {
                HTOrig_layout = method_getImplementation(m);
                method_setImplementation(m, (IMP)HTLayoutNaviView);
                UI_LOG(@"hook -[HYMyInfoNaviView layoutSubviews]");
            }
        } else {
            UI_LOG(@"未找到 HYMyInfoNaviView");
        }

        UI_LOG(@"════ UI 初始化完成 ════");
    }
}

} // extern "C"
