// ============================================================================
//  OpsHide.mm —— 运营位/推广卡片开关（默认关闭）
// ----------------------------------------------------------------------------
//  只做「隐藏」，不改任何布局、不碰 tab bar、不 hook 任何 UIKit 方法。
//  依据实测日志：首页那张「移动爱家产品功能 操作使用图册」是
//      HYHardwareSceneAndBannerView / HYCommonHardwareSenceHalfViewBannerCell
//      / HYNewGDRBBannerCollectionViewCell / HYBannerCollectionViewCell
//  这几个类渲染的。
//
//  注意：隐藏 cell 会在原位置留空，属于"看得见的取舍"，所以默认关闭，
//        由设置页「屏蔽运营位推广」开关控制。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>

extern "C" void HTLog(const char *tag, NSString *msg);
#define OPS_LOG(...) HTLog("HeJiaOps", [NSString stringWithFormat:__VA_ARGS__])

extern "C" {

static NSString *const kNoOpsKey = @"HeJiaTool_NoOps";

static const char *kOpsClasses[] = {
    "HYCommonHardwareSenceHalfViewBannerCell",
    "HYNewGDRBBannerCollectionViewCell",
    "HYBannerCollectionViewCell",
    NULL
};

static BOOL HTOpsOn(void) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:kNoOpsKey];
    return v ? [v boolValue] : NO;      // 默认关闭
}

static void HTHideOpsOnce(void) {
    if (!HTOpsOn()) return;

    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].keyWindow;
    if (!win) return;

    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:win];
    int guard = 0, n = 0;

    while (stack.count > 0 && guard++ < 6000) {
        UIView *v = [stack lastObject];
        [stack removeLastObject];

        if (!v.hidden) {
            const char *cn = class_getName(object_getClass(v));
            for (int i = 0; kOpsClasses[i]; i++) {
                if (cn && strcmp(cn, kOpsClasses[i]) == 0) {
                    v.hidden = YES;
                    n++;
                    OPS_LOG(@"隐藏运营位：%s", cn);
                    break;
                }
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    if (n > 0) OPS_LOG(@"本轮隐藏 %d 个运营位视图", n);
}

__attribute__((constructor))
static void HTOpsInit(void) {
    @autoreleasepool {
        OPS_LOG(@"════ OpsHide 加载（默认关闭）════");

        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"HeJiaTool_NoAdsChanged" object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(id note) { (void)note; HTHideOpsOnce(); }];

        const int64_t delays[] = { 3000, 6000, 10000, 16000, 24000 };
        for (int i = 0; i < 5; i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delays[i] * 1000000LL),
                           dispatch_get_main_queue(), ^{
                @try { HTHideOpsOnce(); } @catch (NSException *e) { (void)e; }
            });
        }
    }
}

} // extern "C"
