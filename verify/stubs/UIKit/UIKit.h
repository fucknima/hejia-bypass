#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct CGContext *CGContextRef;

CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h);
CGSize CGSizeMake(CGFloat w, CGFloat h);

void UIGraphicsBeginImageContextWithOptions(CGSize size, BOOL opaque, CGFloat scale);
void UIGraphicsEndImageContext(void);
CGContextRef UIGraphicsGetCurrentContext(void);
id UIGraphicsGetImageFromCurrentImageContext(void);
void CGContextFillEllipseInRect(CGContextRef c, CGRect r);
void CGContextStrokeEllipseInRect(CGContextRef c, CGRect r);
void CGContextSetLineWidth(CGContextRef c, CGFloat w);

/* ---------------- 基础 ---------------- */
@interface NSObject (UIBase)
+ (id)alloc;
+ (id)new;
- (id)init;
@end

@interface UIColor : NSObject
+ (UIColor *)labelColor;
+ (UIColor *)systemBlueColor;
+ (UIColor *)whiteColor;
+ (UIColor *)systemGroupedBackgroundColor;
+ (UIColor *)separatorColor;
- (void)set;
- (void)setFill;
- (void)setStroke;
@end

@interface UIImage : NSObject
+ (UIImage *)systemImageNamed:(NSString *)n;
- (void)drawInRect:(CGRect)r;
- (UIImage *)imageWithRenderingMode:(NSInteger)m;
@end
enum { UIImageRenderingModeAlwaysOriginal = 1, UIImageRenderingModeAlwaysTemplate = 2 };

@interface UIView : NSObject
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic, readonly) UIView *superview;
@property (nonatomic) BOOL hidden;
- (void)addSubview:(UIView *)v;
- (void)removeFromSuperview;
- (void)layoutSubviews;
@end

@interface UIImageView : UIView
@property (nonatomic, strong) UIImage *image;
@end

@interface UIButton : UIView
+ (instancetype)buttonWithType:(NSInteger)t;
- (void)setImage:(UIImage *)i forState:(NSUInteger)s;
- (UIImage *)imageForState:(NSUInteger)s;
- (void)addTarget:(id)t action:(SEL)a forControlEvents:(NSUInteger)e;
@property (nonatomic, readonly) UIImageView *imageView;
@end
enum { UIControlEventTouchUpInside = 64, UIControlEventValueChanged = 4096,
       UIControlStateNormal = 0, UIButtonTypeCustom = 0 };

@interface UISwitch : UIView
@property (nonatomic, getter=isOn) BOOL on;
@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic) NSInteger tag;
- (void)setOn:(BOOL)on animated:(BOOL)animated;
- (void)addTarget:(id)t action:(SEL)a forControlEvents:(NSUInteger)e;
@end

@interface UILabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *textColor;
@end

@interface UITableViewCell : UIView
- (instancetype)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)rid;
@property (nonatomic, readonly) UILabel *textLabel;
@property (nonatomic, strong) UIView *accessoryView;
@property (nonatomic) NSInteger selectionStyle;
@end
enum { UITableViewCellStyleDefault = 0,
       UITableViewCellSelectionStyleNone = 0,
       UITableViewCellSelectionStyleDefault = 1 };

@interface NSIndexPath : NSObject
@property (nonatomic, readonly) NSInteger section;
@property (nonatomic, readonly) NSInteger row;
@end
@interface UITableView : UIView
- (instancetype)initWithFrame:(CGRect)f style:(NSInteger)s;
- (id)dequeueReusableCellWithIdentifier:(NSString *)cid;
- (void)deselectRowAtIndexPath:(id)ip animated:(BOOL)a;
@property (nonatomic, strong) UIColor *backgroundColor;
@end
enum { UITableViewStyleInsetGrouped = 2 };

@interface UIBarButtonItem : NSObject
- (instancetype)initWithBarButtonSystemItem:(NSInteger)i target:(id)t action:(SEL)a;
- (instancetype)initWithImage:(UIImage *)img style:(NSInteger)s target:(id)t action:(SEL)a;
@end
enum { UIBarButtonSystemItemDone = 0, UIBarButtonItemStylePlain = 0 };

@interface UINavigationItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIBarButtonItem *rightBarButtonItem;
@property (nonatomic, copy) NSArray<UIBarButtonItem *> *rightBarButtonItems;
@end

@interface UIViewController : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, readonly) UINavigationItem *navigationItem;
@property (nonatomic, readonly) UIView *view;
@property (nonatomic, strong) UIViewController *presentedViewController;
@property (nonatomic) NSInteger modalPresentationStyle;
@property (nonatomic, readonly) id navigationController;
- (void)viewDidLoad;
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)a completion:(void (^)(void))c;
- (void)dismissViewControllerAnimated:(BOOL)a completion:(void (^)(void))c;
@property (nonatomic, readonly) NSArray *childViewControllers;
@end
enum { UIModalPresentationFormSheet = 2 };

@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)t style:(NSInteger)s handler:(void (^)(UIAlertAction *))h;
@end
enum { UIAlertActionStyleDefault = 0 };

@interface UIAlertController : UIViewController
+ (instancetype)alertControllerWithTitle:(NSString *)t message:(NSString *)m preferredStyle:(NSInteger)s;
- (void)addAction:(UIAlertAction *)a;
@end
enum { UIAlertControllerStyleAlert = 1 };

@interface UITableViewController : UIViewController
- (instancetype)initWithStyle:(NSInteger)s;
@property (nonatomic, readonly) UITableView *tableView;
@end

@interface UINavigationController : UIViewController
@property (nonatomic, readonly) NSArray *viewControllers;
- (instancetype)initWithRootViewController:(UIViewController *)vc;@end
@interface UINavigationControllerX : UIViewController
- (instancetype)initWithRootViewController:(UIViewController *)vc;
@end

@interface UITabBarController : UIViewController
@property (nonatomic, copy) NSArray *viewControllers;
@property (nonatomic) NSInteger selectedIndex;
@end
@interface UIWindow : UIView
@property (nonatomic, readonly, getter=isKeyWindow) BOOL keyWindow;
@property (nonatomic, strong) UIViewController *rootViewController;
@end

@interface UIPasteboard : NSObject
+ (instancetype)generalPasteboard;
@property (nonatomic, copy) NSString *string;
@end
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@property (nonatomic, readonly) NSArray<UIWindow *> *windows;
@property (nonatomic, readonly) UIWindow *keyWindow;
@end

#ifdef __cplusplus
}
#endif
