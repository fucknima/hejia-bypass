#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef double CGFloat;
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { NSUInteger location, length; } NSRange;
NSRange NSMakeRange(NSUInteger l, NSUInteger n);
extern const CGRect CGRectZero;
typedef struct CGContext *CGContextRef;
extern const CGPoint CGPointZero;

CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h);
typedef struct { CGFloat a, b, c, d; CGFloat tx, ty; } CGAffineTransform;
CGAffineTransform CGAffineTransformMakeTranslation(CGFloat tx, CGFloat ty);
@class NSString;
NSString *NSStringFromCGRect(CGRect r);
NSString *NSStringFromClass(Class c);
CGSize CGSizeMake(CGFloat w, CGFloat h);
CGPoint CGPointMake(CGFloat x, CGFloat y);

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

@interface UIEvent : NSObject
@end
@interface NSValue : NSObject
+ (NSValue *)valueWithRect:(CGRect)r;
- (CGPoint)CGPointValue;
- (CGRect)CGRectValue;
@end
@interface UIColor : NSObject
+ (UIColor *)labelColor;
+ (UIColor *)systemBackgroundColor;
+ (UIColor *)systemBlueColor;
+ (UIColor *)whiteColor;
+ (UIColor *)systemGroupedBackgroundColor;
+ (UIColor *)separatorColor;
- (void)set;
- (void)setFill;
- (void)setStroke;

+ (UIColor *)secondaryLabelColor;
+ (UIColor *)secondarySystemGroupedBackgroundColor;
+ (UIColor *)systemGreenColor;
+ (UIColor *)systemRedColor;
@end

@interface UIImage : NSObject
+ (UIImage *)systemImageNamed:(NSString *)n;
- (void)drawInRect:(CGRect)r;
- (UIImage *)imageWithRenderingMode:(NSInteger)m;
@end
enum { UIImageRenderingModeAlwaysOriginal = 1, UIImageRenderingModeAlwaysTemplate = 2 };

@interface UIPopoverPresentationController : NSObject
@property (nonatomic, strong) id sourceView;
@property (nonatomic) CGRect sourceRect;
@end
@interface UIView : NSObject
@property (nonatomic, readonly) NSArray<UIView *> *subviews;
@property (nonatomic) CGRect frame;
@property (nonatomic) CGRect bounds;
@property (nonatomic) CGPoint center;
@property (nonatomic) CGAffineTransform transform;
@property (nonatomic, readonly) UIView *superview;
@property (nonatomic, readonly) id window;
@property (nonatomic) BOOL hidden;
@property (nonatomic, strong) UIColor *backgroundColor;
@property (nonatomic) CGFloat alpha;
@property (nonatomic) NSInteger tag;
@property (nonatomic) BOOL userInteractionEnabled;
@property (nonatomic, readonly) BOOL isUserInteractionEnabled;
- (void)addSubview:(UIView *)v;
- (void)removeFromSuperview;
- (instancetype)initWithFrame:(CGRect)f;
- (void)layoutSubviews;
- (UIView *)hitTest:(CGPoint)p withEvent:(id)e;
- (void)setNeedsLayout;
- (void)sendEvent:(UIEvent *)e;
- (void)motionEnded:(NSInteger)subtype withEvent:(UIEvent *)e;
- (void)addGestureRecognizer:(id)g;
- (void)removeGestureRecognizer:(id)g;
@end

@interface UIImageView : UIView
@property (nonatomic, strong) UIImage *image;
@end

@interface UIButton : UIView
+ (instancetype)buttonWithType:(NSInteger)t;
- (void)setImage:(UIImage *)i forState:(NSUInteger)s;
- (UIImage *)imageForState:(NSUInteger)s;
- (NSString *)titleForState:(NSUInteger)s;
- (void)setTitle:(NSString *)t forState:(NSUInteger)s;
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

@interface UIFont : NSObject
+ (UIFont *)monospacedSystemFontOfSize:(CGFloat)sz weight:(CGFloat)w;

+ (UIFont *)systemFontOfSize:(CGFloat)sz;
+ (UIFont *)systemFontOfSize:(CGFloat)sz weight:(CGFloat)w;
+ (UIFont *)boldSystemFontOfSize:(CGFloat)sz weight:(CGFloat)w;
@end
@interface UITextView : UIView
- (instancetype)initWithFrame:(CGRect)f;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic) BOOL editable;
@property (nonatomic) BOOL alwaysBounceVertical;
- (void)scrollRangeToVisible:(NSRange)r;
@end
@interface UILabel : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *textColor;

@property (nonatomic, strong) UIFont *font;
@property (nonatomic) NSInteger numberOfLines;
@end

@interface UITableViewCell : UIView
- (instancetype)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)rid;
@property (nonatomic, readonly) UILabel *textLabel;
@property (nonatomic, strong) UIView *accessoryView;
@property (nonatomic) NSInteger selectionStyle;

@property (nonatomic, readonly) UIView *contentView;

@property (nonatomic, strong) UIView *tableHeaderView;
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
@property (nonatomic, strong) UIView *tableHeaderView;
@end
enum { UITableViewStyleInsetGrouped = 2 };

@interface UIBarButtonItem : NSObject
- (instancetype)initWithBarButtonSystemItem:(NSInteger)i target:(id)t action:(SEL)a;
- (instancetype)initWithImage:(UIImage *)img style:(NSInteger)s target:(id)t action:(SEL)a;
- (instancetype)initWithTitle:(NSString *)t style:(NSInteger)s target:(id)tg action:(SEL)a;
@end
enum { UIBarButtonSystemItemDone = 0, UIBarButtonItemStylePlain = 0 };

@interface UINavigationItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) UIBarButtonItem *rightBarButtonItem;
@property (nonatomic, strong) UIBarButtonItem *leftBarButtonItem;
@property (nonatomic, copy) NSArray<UIBarButtonItem *> *rightBarButtonItems;
@end

@interface UIViewController : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, readonly) UINavigationItem *navigationItem;
@property (nonatomic, readonly) UIView *view;
@property (nonatomic, strong) UIViewController *presentedViewController;
@property (nonatomic) NSInteger modalPresentationStyle;
@property (nonatomic, readonly) id navigationController;
@property (nonatomic, readonly) UIPopoverPresentationController *popoverPresentationController;
- (void)viewDidLoad;
- (void)viewDidLayoutSubviews;
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)a completion:(void (^)(void))c;
- (void)dismissViewControllerAnimated:(BOOL)a completion:(void (^)(void))c;
@property (nonatomic, readonly) NSArray *childViewControllers;
@end
enum { UIModalPresentationFormSheet = 2 };

@interface UIAlertAction : NSObject
+ (instancetype)actionWithTitle:(NSString *)t style:(NSInteger)s handler:(void (^)(UIAlertAction *))h;
@end
enum { UIAlertActionStyleDefault = 0, UIAlertActionStyleCancel = 1, UIAlertActionStyleDestructive = 2 };

@interface UIAlertController : UIViewController
+ (instancetype)alertControllerWithTitle:(NSString *)t message:(NSString *)m preferredStyle:(NSInteger)s;
- (void)addAction:(UIAlertAction *)a;
@end
enum { UIAlertControllerStyleActionSheet = 0, UIAlertControllerStyleAlert = 1 };

@interface UITableViewController : UIViewController
- (instancetype)initWithStyle:(NSInteger)s;
@property (nonatomic, readonly) UITableView *tableView;
@end

@interface UINavigationController : UIViewController
@property (nonatomic, readonly) UIViewController *topViewController;
@property (nonatomic, readonly) NSArray *viewControllers;
- (instancetype)initWithRootViewController:(UIViewController *)vc;
- (void)pushViewController:(UIViewController *)vc animated:(BOOL)a;@end
@interface UINavigationControllerX : UIViewController
- (instancetype)initWithRootViewController:(UIViewController *)vc;
@end

@interface UITabBarController : UIViewController
@property (nonatomic, copy) NSArray *viewControllers;
@property (nonatomic) NSInteger selectedIndex;
@end
@interface UIWindow : UIView
@property (nonatomic, readonly, getter=isKeyWindow) BOOL keyWindow;
@property (nonatomic) CGFloat windowLevel;
@property (nonatomic, strong) UIViewController *rootViewController;
@end

@interface UIPasteboard : NSObject
+ (instancetype)generalPasteboard;
@property (nonatomic, copy) NSString *string;
@end
extern NSString *UIApplicationDidBecomeActiveNotification;
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
@property (nonatomic, readonly) NSArray<UIWindow *> *windows;
@property (nonatomic, readonly) UIWindow *keyWindow;
@end


@protocol UIGestureRecognizerDelegate
@optional
- (BOOL)gestureRecognizer:(id)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(id)o;
@end
@interface UIGestureRecognizer : NSObject
- (instancetype)initWithTarget:(id)t action:(SEL)a;
@property (nonatomic, readonly) NSInteger state;
@property (nonatomic, weak) id delegate;
@property (nonatomic) BOOL cancelsTouchesInView;
@property (nonatomic) BOOL delaysTouchesBegan;
@property (nonatomic) BOOL delaysTouchesEnded;
@end
enum {
    UIGestureRecognizerStateBegan = 1,
    UIGestureRecognizerStateChanged = 2,
    UIGestureRecognizerStateEnded = 3,
    UIGestureRecognizerStateCancelled = 4,
};
@interface UILongPressGestureRecognizer : UIGestureRecognizer
@property (nonatomic) NSInteger numberOfTouchesRequired;
@property (nonatomic) double minimumPressDuration;
@property (nonatomic) double allowableMovement;
@end

#ifdef __cplusplus
}
#endif
