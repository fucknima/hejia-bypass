// ============================================================================
//  LogViewer.mm —— 日志直接预览
// ----------------------------------------------------------------------------
//  设置页「日志与诊断」两行原来只是把路径复制到剪贴板，还要自己去找文件。
//  这里改成直接 push 一个只读文本视图，展示日志尾部（最多 300 KB），
//  右上角「复制」一键复制全文。
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern "C" void HTLog(const char *tag, NSString *msg);
#define LV_LOG(...) HTLog("HeJiaUI", [NSString stringWithFormat:__VA_ARGS__])

extern "C" {

// ---------------------------------------------------------------------------
@interface HTLogViewController : UIViewController
@property (nonatomic, copy)   NSString *logPath;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation HTLogViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    tv.editable = NO;
    tv.alwaysBounceVertical = YES;
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:0];
    tv.textColor = [UIColor labelColor];
    tv.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:tv];
    self.textView = tv;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"复制"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(copyAll)];

    [self reloadLog];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.textView) self.textView.frame = self.view.bounds;
}

- (void)reloadLog {
    NSString *s = [NSString stringWithContentsOfFile:self.logPath
                                            encoding:NSUTF8StringEncoding
                                               error:NULL];
    if (!s) {
        s = [NSString stringWithFormat:@"（读取失败）\n\n路径：\n%@", self.logPath];
    } else if (s.length == 0) {
        s = @"（文件为空）";
    } else if (s.length > 300000) {
        s = [s substringFromIndex:s.length - 300000];
        s = [@"……（仅显示最后 300 KB）\n\n" stringByAppendingString:s];
    }
    self.textView.text = s;

    if (s.length > 1) {
        [self.textView scrollRangeToVisible:NSMakeRange(s.length - 1, 1)];
    }
}

- (void)copyAll {
    NSString *s = self.textView.text ?: @"";
    [UIPasteboard generalPasteboard].string = s;
    LV_LOG(@"复制日志 %lu 字节", (unsigned long)s.length);
}

@end

// ---------------------------------------------------------------------------
UIViewController *HTMakeLogViewer(NSString *path, NSString *title) {
    HTLogViewController *vc = [[HTLogViewController alloc] init];
    vc.logPath = path;
    vc.title = title;
    return vc;
}

} // extern "C"
