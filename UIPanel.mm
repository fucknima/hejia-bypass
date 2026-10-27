// ============================================================================
//  HeJiaTool 唤起模块 v6（摇一摇）
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  唯一触发方式：摇一摇手机
//
//  历史（已移除）：
//    - 布局 hook        → 无限递归 0x8BADF00D
//    - addSubview        → UIVisualEffectView 断言 SIGABRT
//    - 三指长按手势      → 被 App 手势吞掉，实测无效
//    - UIWindow.sendEvent → 实测从未被调用
//    - 状态栏双击        → 依附 sendEvent，同样无效
//  motionEnded: 是唯一实测可用的路径，保留单一实现，避免冗余代码。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#include <CoreFoundation/CoreFoundation.h>
#include <unistd.h>

#include <substrate.h>

extern "C" void HTLog(const char *tag, NSString *msg);
extern "C" const char *HTGetLogFilePath(void);
#define UI_LOG(...) HTLog("HeJiaUI", [NSString stringWithFormat:__VA_ARGS__])

extern "C" UIViewController *HTMakeSettingsVC(void);

extern "C" {

// ---------------------------------------------------------------------------
// 状态
// ---------------------------------------------------------------------------
static IMP HTOrig_motionEnded = NULL;

// 目录/文件大小（递归）
static unsigned long long HTDirSize(NSString *path) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    unsigned long long total = 0;
    if (![fm fileExistsAtPath:path isDirectory:&isDir]) return 0;
    if (!isDir) {
        NSDictionary *attr = [fm attributesOfItemAtPath:path error:NULL];
        return attr ? [attr fileSize] : 0;
    }
    NSArray *items = [fm contentsOfDirectoryAtPath:path error:NULL];
    for (NSString *it in items) total += HTDirSize([path stringByAppendingPathComponent:it]);
    return total;
}

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

    [sheet addAction:[UIAlertAction actionWithTitle:@"🧹  清理全部数据"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        (void)a;

        // 放到后台队列：之前在按钮回调里同步删除上万个文件，
        // 主线程被卡住超过 10 秒 → 被 watchdog 以 0x8BADF00D 杀掉。
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            @autoreleasepool {
                NSFileManager *fm = [NSFileManager defaultManager];
                unsigned long long freed = 0;
                int files = 0;

                NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
                NSString *caches = dirs.count ? dirs[0] : nil;

                // 只清 Caches（tmp 里有正在用的 socket/临时文件，删了会崩）
                if (caches.length) {
                    NSArray *items = [fm contentsOfDirectoryAtPath:caches error:NULL];
                    for (NSString *it in items) {
                        @try {
                            NSString *full = [caches stringByAppendingPathComponent:it];
                            freed += HTDirSize(full);
                            if ([fm removeItemAtPath:full error:NULL]) files++;
                        } @catch (NSException *e) { (void)e; }
                    }
                }

                @try { [[NSURLCache sharedURLCache] removeAllCachedResponses]; } @catch (NSException *e) { (void)e; }

                // 图片缓存：必须先 respondsToSelector 再调用，否则 unrecognized selector 崩溃
                for (NSString *cn in @[@"SDImageCache", @"YYImageCache"]) {
                    @try {
                        Class c = objc_getClass([cn UTF8String]);
                        if (!c) continue;
                        id cache = nil;
                        if ([(id)c respondsToSelector:sel_registerName("sharedImageCache")])
                            cache = ((id (*)(id, SEL))objc_msgSend)((id)c, sel_registerName("sharedImageCache"));
                        else if ([(id)c respondsToSelector:sel_registerName("sharedCache")])
                            cache = ((id (*)(id, SEL))objc_msgSend)((id)c, sel_registerName("sharedCache"));
                        if (!cache) continue;
                        if ([cache respondsToSelector:sel_registerName("clearMemory")])
                            ((void (*)(id, SEL))objc_msgSend)(cache, sel_registerName("clearMemory"));
                        if ([cache respondsToSelector:sel_registerName("clearDisk")])
                            ((void (*)(id, SEL))objc_msgSend)(cache, sel_registerName("clearDisk"));
                    } @catch (NSException *e) {
                        UI_LOG(@"图片缓存清理跳过（%@）", e.reason);
                    }
                }

                NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
                for (NSString *k in @[@"TabbarsDictCache", @"TabBarPageDictCacheKey",
                                      @"shouldModifyTabbarInfoDict", @"ModifyTabbarInfoDict",
                                      @"ModifyTabbarsDictForProvice"]) {
                    [ud removeObjectForKey:k];
                }
                [ud synchronize];

                UI_LOG(@"清理完成：%d 项，约 %llu KB", files, freed / 1024);

                NSString *msg = [NSString stringWithFormat:
                    @"已删除 %d 个缓存项，释放约 %llu MB。\n重启 App 后生效。",
                    files, freed / (1024 * 1024)];

                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *ok = [UIAlertController
                        alertControllerWithTitle:@"清理完成"
                                         message:msg
                                  preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"稍后"
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil]];
                    [ok addAction:[UIAlertAction actionWithTitle:@"立即重启"
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction *x) {
                        (void)x;
                        _exit(0);
                    }]];
                    [HTTopMost() presentViewController:ok animated:YES completion:nil];
                });
            }
        });
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
//   优势：完全绕过手势系统，任何手势都抢不走
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// 摇一摇
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
        UI_LOG(@"════ 唤起模块 v6 加载（摇一摇）════");

        Class winCls = objc_getClass("UIWindow");
        if (winCls) {
            // 路线 C
            Method m2 = class_getInstanceMethod(winCls, @selector(motionEnded:withEvent:));
            if (m2) {
                HTOrig_motionEnded = method_getImplementation(m2);
                method_setImplementation(m2, (IMP)HTMotionEnded);
                UI_LOG(@"hook -[UIWindow motionEnded:withEvent:]");
            }
        }

        UI_LOG(@"════ 唤起就绪：摇一摇手机 ════");
    }
}

} // extern "C"
