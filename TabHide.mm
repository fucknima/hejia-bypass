// ============================================================================
//  Tab 隐藏模块：隐藏「服务」「发现」页面
//  Bundle: com.cmcc.zhihuiguanjia
// ----------------------------------------------------------------------------
//  已确认（主二进制）：
//    tabbarId 取值： default / find / hardware / life / familyCloud /
//                   gateway / scene / ai_chat
//    「发现」= find
//    「服务」= life（"服务" tab 走 life 频道）
//    TabBar 控制器： HYTabBarController / HYCustomTabBar / MainTabViewController
//
//  实现：hook UITabBarController 的 setViewControllers:，在设值前把
//        被隐藏 tab 的 VC 剔除，并同步调整 selectedIndex。
//        用 UITabBarController 这个系统类做拦截点，覆盖所有子类。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <string.h>

#include <substrate.h>

extern "C" void HTWriteLog(const char *tag, NSString *fmt, ...);
#define TAB_LOG(fmt, ...) HTWriteLog("HeJiaTab", fmt, ##__VA_ARGS__)

extern "C" {

static NSString *const kHideServiceKey = @"HeJiaTool_HideService";
static NSString *const kHideFindKey    = @"HeJiaTool_HideFind";

// 判断某个 tab 的 VC 是否应该被隐藏
static BOOL HTShouldHideTab(UIViewController *vc) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    BOOL hideService = [ud boolForKey:kHideServiceKey];
    BOOL hideFind    = [ud boolForKey:kHideFindKey];
    if (!hideService && !hideFind) return NO;

    if (![vc isKindOfClass:[UIViewController class]]) return NO;

    NSString *clsName = NSStringFromClass([vc class]);
    NSString *title   = vc.title;
    NSString *tabId   = nil;

    // VC 上若有 tabbarId 属性，优先读取
    SEL idSel = sel_registerName("tabbarId");
    if ([vc respondsToSelector:idSel]) {
        id v = ((id (*)(id, SEL))objc_msgSend)(vc, idSel);
        if ([v isKindOfClass:[NSString class]]) tabId = v;
    }

    const char *cn = clsName.UTF8String;
    const char *tt = title.UTF8String;
    const char *ti = tabId.UTF8String;

    if (hideFind) {
        if ((ti && strstr(ti, "find")) ||
            (cn && strstr(cn, "Find")) ||
            (tt && strcmp(tt, "发现") == 0)) {
            TAB_LOG(@"隐藏 tab: %s (%s)", cn ?: "?", tt ?: "?");
            return YES;
        }
    }

    if (hideService) {
        if ((ti && (strstr(ti, "life") || strstr(ti, "service"))) ||
            (tt && strcmp(tt, "服务") == 0)) {
            TAB_LOG(@"隐藏 tab: %s (%s)", cn ?: "?", tt ?: "?");
            return YES;
        }
    }
    return NO;
}

static void HTReapplyTabFilter(UITabBarController *tabC);

// ---------------------------------------------------------------------------
// hook: setViewControllers:
// ---------------------------------------------------------------------------
static IMP HTOrig_setViewControllers = NULL;

static void HTSetViewControllers(UITabBarController *self, SEL _cmd, NSArray *vcs) {
    NSArray *filtered = vcs;
    NSMutableArray *kept = nil;

    for (UIViewController *vc in vcs) {
        if (HTShouldHideTab(vc)) {
            if (!kept) {
                kept = [NSMutableArray arrayWithCapacity:vcs.count];
                for (UIViewController *v in vcs) {
                    if (v == vc) break;
                    [kept addObject:v];
                }
            }
        } else if (kept) {
            [kept addObject:vc];
        }
    }

    if (kept && kept.count > 0 && kept.count < vcs.count) {
        filtered = kept;
        TAB_LOG(@"setViewControllers: %lu -> %lu", (unsigned long)vcs.count,
                (unsigned long)kept.count);
    } else {
        filtered = vcs;
    }

    typedef void (*fn_t)(id, SEL, NSArray *);
    if (HTOrig_setViewControllers) {
        ((fn_t)HTOrig_setViewControllers)(self, _cmd, filtered);
    }
}

// 已有 tab 时（比如设置页改完开关），就地重新过滤一次
static void HTReapplyTabFilter(UITabBarController *tabC) {
    if (!tabC) return;
    NSArray *vcs = tabC.viewControllers;
    if (!vcs || vcs.count == 0) return;

    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:vcs.count];
    BOOL changed = NO;
    for (UIViewController *vc in vcs) {
        if (HTShouldHideTab(vc)) { changed = YES; continue; }
        [kept addObject:vc];
    }
    if (!changed || kept.count == 0) return;

    NSUInteger oldIdx = tabC.selectedIndex;
    UIViewController *selected = (oldIdx < vcs.count) ? vcs[oldIdx] : nil;

    typedef void (*fn_t)(id, SEL, NSArray *);
    if (HTOrig_setViewControllers) {
        ((fn_t)HTOrig_setViewControllers)(tabC, sel_registerName("setViewControllers:"), kept);
    }

    // 恢复原来的选中项
    if (selected) {
        NSUInteger newIdx = [kept indexOfObject:selected];
        if (newIdx != (NSUInteger)-1 && newIdx < kept.count) {
            tabC.selectedIndex = (NSInteger)newIdx;
        }
    }
    TAB_LOG(@"已重新过滤 tab，剩余 %lu 个", (unsigned long)kept.count);
}

// ---------------------------------------------------------------------------
// 设置页改动后立即生效
// ---------------------------------------------------------------------------

static void HTOnTabbarReloadImpl(id note) {
    (void)note;
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;

    UIViewController *root = keyWin.rootViewController;
    UINavigationController *nav = [root isKindOfClass:[UINavigationController class]]
                                    ? (UINavigationController *)root : nil;

    // 深度遍历找 tabbar
    NSMutableArray *stack = [NSMutableArray array];
    UIViewController *start = nav ? nav : root;
    if (start) [stack addObject:start];

    while (stack.count > 0) {
        UIViewController *vc = [stack lastObject];
        [stack removeLastObject];
        if ([vc isKindOfClass:[UITabBarController class]]) {
            HTReapplyTabFilter((UITabBarController *)vc);
        }
        if ([vc isKindOfClass:[UINavigationController class]]) {
            for (UIViewController *c in ((UINavigationController *)vc).viewControllers) [stack addObject:c];
        }
        for (UIViewController *c in vc.childViewControllers) [stack addObject:c];
    }
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
__attribute__((constructor))
static void HeJiaTabInit(void) {
    @autoreleasepool {
        TAB_LOG(@"════ Tab 模块加载 ════");

        Class tabCls = objc_getClass("UITabBarController");
        if (tabCls) {
            Method m = class_getInstanceMethod(tabCls, @selector(setViewControllers:));
            if (m) {
                HTOrig_setViewControllers = method_getImplementation(m);
                method_setImplementation(m, (IMP)HTSetViewControllers);
                TAB_LOG(@"hook -[UITabBarController setViewControllers:]");
            }
        }

        // block 形式注册，避免 selector 认知问题
        NSOperationQueue *mainQ = [NSOperationQueue mainQueue];
        id token = [[NSNotificationCenter defaultCenter]
            addObserverForName:@"HeJiaTool_TabbarReload"
                        object:nil
                         queue:mainQ
                    usingBlock:^(id note) {
            HTOnTabbarReloadImpl(note);
        }];
        (void)token;

        TAB_LOG(@"════ Tab 模块完成 ════");
    }
}

} // extern "C"
