// ============================================================================
//  HeJiaTool 设置中心（UI 层）
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  入口：在「我的」页面右上角，紧贴原生设置图标左侧新增一个工具图标按钮。
//
//  ⚠️ 关键修复（v2）：
//      v1 在 layoutSubviews 里每次都给按钮设 frame，setFrame: 会让父视图
//      重新布局 → 再次进入 layoutSubviews → 无限递归 → 主线程卡死 →
//      0x8BADF00D watchdog 闪退（已在 .ips 崩溃栈确认为本函数）。
//      修复：
//        1) 递归保护标志，重入直接返回
//        2) 只在 frame 真正变化时才 setFrame
//        3) 用 dispatch_async 延后到下一 runloop，脱离当前布局周期
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

#include <substrate.h>

#define UI_LOG(fmt, ...) NSLog(@"[HeJiaUI] " fmt, ##__VA_ARGS__)

extern "C" {

static NSString *const HTInjectedKey = @"HeJiaTool_Injected";   // 过签名：强制开

extern UIViewController *HTMakeSettingsVC(void);                 // 见 SettingsVC.mm

static IMP HTOrig_layout = NULL;

// 递归保护：正在布局时不再嵌套布局
static __thread BOOL gInLayout = NO;

// ===========================================================================
// 图标：复用原生设置图标 + 右下角小蓝点
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
// 点击
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
    [top presentViewController:nav animated:YES completion:nil];
}

// ===========================================================================
// 布局（带递归保护）
// ===========================================================================
static const void *kHTToolButtonKey = &kHTToolButtonKey;

static void HTApplyToolButtonLayout(UIView *navi, UIButton *settingBtn, UIButton *myBtn) {
    // 递归保护
    if (gInLayout) return;
    gInLayout = YES;

    CGRect target;
    if (settingBtn && settingBtn.superview) {
        CGRect f = settingBtn.frame;
        CGFloat w = (f.size.width > 0) ? f.size.width : 28.0;
        CGFloat h = (f.size.height > 0) ? f.size.height : 28.0;
        CGFloat gap = 6.0;
        target = CGRectMake(f.origin.x - w - gap, f.origin.y, w, h);
        if (target.origin.x < 0) {   // 越界就退回默认位置
            target = CGRectMake(navi.bounds.size.width - 89,
                                (navi.bounds.size.height - h) / 2, w, h);
        }
    } else {
        CGFloat h = navi.bounds.size.height;
        target = CGRectMake(navi.bounds.size.width - 89, (h - 28) / 2, 28, 28);
    }

    // 只在真正变化时才 setFrame（这是防递归的关键）
    CGRect cur = myBtn.frame;
    if (fabs(cur.origin.x - target.origin.x) > 0.5 ||
        fabs(cur.origin.y - target.origin.y) > 0.5 ||
        fabs(cur.size.width - target.size.width) > 0.5 ||
        fabs(cur.size.height - target.size.height) > 0.5) {
        myBtn.frame = target;
    }

    gInLayout = NO;
}

static void HTLayoutNaviView(id self, SEL _cmd) {
    if (gInLayout) return;   // 直接挡掉嵌套调用

    typedef void (*fn_t)(id, SEL);
    if (HTOrig_layout) ((fn_t)HTOrig_layout)(self, _cmd);

    UIView *navi = (UIView *)self;

    UIButton *myBtn = objc_getAssociatedObject(navi, kHTToolButtonKey);
    if (!myBtn) {
        // 只在第一次创建，避免重复添加
        myBtn = [UIButton buttonWithType:UIButtonTypeCustom];

        class_addMethod(object_getClass(navi),
                        sel_registerName("HTToolButtonClicked:"),
                        (IMP)HTToolButtonClicked, "v24@0:8@16");
        [myBtn addTarget:navi
                  action:sel_registerName("HTToolButtonClicked:")
        forControlEvents:UIControlEventTouchUpInside];

        UIButton *settingBtn = nil;
        SEL btnSel = sel_registerName("settingBtn");
        if ([navi respondsToSelector:btnSel]) {
            settingBtn = ((id (*)(id, SEL))objc_msgSend)(navi, btnSel);
        }
        UIImage *base = nil;
        if (settingBtn) {
            base = [settingBtn imageForState:UIControlStateNormal];
            if (!base) base = settingBtn.imageView.image;
        }
        // 图标绘制放到后台，避免阻塞首屏
        __weak UIButton *weakBtn = myBtn;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            __block UIImage *icon = HTMakeToolIcon(base);
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakBtn setImage:icon forState:UIControlStateNormal];
            });
        });
        // 先用原生图标占位，避免闪烁
        if (base) [myBtn setImage:base forState:UIControlStateNormal];

        [navi addSubview:myBtn];
        objc_setAssociatedObject(navi, kHTToolButtonKey, myBtn,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UI_LOG(@"已添加工具按钮");
    }

    UIButton *settingBtn = nil;
    SEL btnSel = sel_registerName("settingBtn");
    if ([navi respondsToSelector:btnSel]) {
        settingBtn = ((id (*)(id, SEL))objc_msgSend)(navi, btnSel);
    }

    // 关键：延后到下一 runloop 再设 frame，彻底跳出当前布局周期
    __weak UIView *weakNavi = navi;
    __weak UIButton *weakSetting = settingBtn;
    __weak UIButton *weakMy = myBtn;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *n = weakNavi;
        UIButton *s = weakSetting;
        UIButton *m = weakMy;
        if (n && m) HTApplyToolButtonLayout(n, s, m);
    });
}

// ===========================================================================
// 入口
// ===========================================================================
__attribute__((constructor))
static void HeJiaUIInit(void) {
    @autoreleasepool {
        UI_LOG(@"════ UI 模块加载 ════");

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
