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

extern "C" void HTLog(const char *tag, NSString *msg);
#define TAB_LOG(...) HTLog("HeJiaTab", [NSString stringWithFormat:__VA_ARGS__])

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

    // 诊断：把每个 tab 的真实信息打出来（只在开关打开时）
    if (hideService || hideFind) {
        TAB_LOG(@"检查 tab: class=%@ title=%@", clsName, title);
    }

    // VC 上若有 tabbarId 属性，优先读取（KVC，避免 objc_msgSend 类型问题）
    @try {
        id v = [vc valueForKey:@"tabbarId"];
        if ([v isKindOfClass:[NSString class]]) tabId = (NSString *)v;
    } @catch (NSException *e) { (void)e; }

    const char *cn = clsName.UTF8String;
    const char *tt = title.UTF8String;

    // 大小写不敏感匹配
    NSString *cnLower = [clsName lowercaseString];
    NSString *tiLower = tabId ? [tabId lowercaseString] : nil;
    const char *cnl = cnLower.UTF8String;
    const char *til = tiLower.UTF8String;

    if (hideFind) {
        if ((til && strstr(til, "find")) ||
            (cnl && strstr(cnl, "find")) ||
            (cnl && strstr(cnl, "discover")) ||
            (tt && (strcmp(tt, "发现") == 0))) {
            TAB_LOG(@"隐藏 tab: %s (%s)", cn ?: "?", tt ?: "?");
            return YES;
        }
    }

    if (hideService) {
        if ((til && (strstr(til, "life") || strstr(til, "service"))) ||
            (cnl && (strstr(cnl, "life") || strstr(cnl, "service"))) ||
            (tt && (strcmp(tt, "服务") == 0))) {
            TAB_LOG(@"隐藏 tab: %s (%s)", cn ?: "?", tt ?: "?");
            return YES;
        }
    }
    return NO;
}

static void HTReapplyTabFilter(UITabBarController *tabC);

// hook getter：读出来的时候就把被隐藏的 tab 剔掉
static IMP HTOrig_getViewControllers = NULL;

static NSArray *HTGetViewControllers(UITabBarController *self, SEL _cmd) {
    typedef NSArray *(*fn_t)(id, SEL);
    NSArray *orig = HTOrig_getViewControllers
                  ? ((fn_t)HTOrig_getViewControllers)(self, _cmd) : nil;
    if (!orig || orig.count == 0) return orig;

    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:orig.count];
    BOOL changed = NO;
    for (UIViewController *vc in orig) {
        if (HTShouldHideTab(vc)) { changed = YES; continue; }
        [kept addObject:vc];
    }
    if (!changed || kept.count == 0) return orig;
    return kept;
}

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
        TAB_LOG(@"setViewControllers: %lu -> %lu",
                (unsigned long)vcs.count, (unsigned long)kept.count);
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

static void HTForceReloadTabs(void) {
    // 遍历所有 tabbar，强制重新 set 一次
    UIWindow *keyWin = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { keyWin = w; break; }
    }
    if (!keyWin) keyWin = [UIApplication sharedApplication].keyWindow;
    if (!keyWin) return;

    NSMutableArray *stack = [NSMutableArray array];
    if (keyWin.rootViewController) [stack addObject:keyWin.rootViewController];

    while (stack.count > 0) {
        UIViewController *vc = [stack lastObject];
        [stack removeLastObject];
        if ([vc isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tb = (UITabBarController *)vc;
            NSArray *cur = tb.viewControllers;
            if (cur && cur.count > 0) {
                // 用 setter 重新设置，触发我们的过滤
                typedef void (*fn_t)(id, SEL, NSArray *);
                if (HTOrig_setViewControllers) {
                    ((fn_t)HTOrig_setViewControllers)(tb,
                        sel_registerName("setViewControllers:"), cur);
                }
                TAB_LOG(@"强制重载 tab，当前 %lu 个",
                        (unsigned long)cur.count);
            }
        }
        for (UIViewController *c in vc.childViewControllers) [stack addObject:c];
    }
}

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
            Method g = class_getInstanceMethod(tabCls, @selector(viewControllers));
            if (g) {
                HTOrig_getViewControllers = method_getImplementation(g);
                method_setImplementation(g, (IMP)HTGetViewControllers);
                TAB_LOG(@"hook -[UITabBarController viewControllers] (getter)");
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
            HTForceReloadTabs();
        }];
        (void)token;

        TAB_LOG(@"════ Tab 模块完成 ════");
    }
}

} // extern "C"
