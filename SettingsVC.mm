// ============================================================================
//  HeJiaTool 设置面板（工具箱）v2 —— 重新设计
// ----------------------------------------------------------------------------
//  结构：
//    [ 头部卡片 ]  HeJiaTool · 版本 · 当前状态一览
//    增强功能   屏蔽广告 / 隐藏服务 / 隐藏发现 / 隐藏 AI 灵犀 / 屏蔽运营位
//    安全       过签名检测（强制）
//    日志       主日志 / 扫描明细 → 直接预览
//  左上角「退出」= 立即结束进程；右上角「完成」= 关闭面板
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <stdlib.h>
#include <unistd.h>

extern "C" void HTLog(const char *tag, NSString *msg);
extern "C" const char *HTGetLogFilePath(void);
extern "C" const char *HTGetAdScanLogPath(void);
#define SVC_LOG(...) HTLog("HeJiaUI", [NSString stringWithFormat:__VA_ARGS__])

extern "C" {

static NSString *const kNoAdsKey       = @"HeJiaTool_NoAds";
static NSString *const kHideServiceKey = @"HeJiaTool_HideService";
static NSString *const kHideFindKey    = @"HeJiaTool_HideFind";
static NSString *const kHideAIKey      = @"HeJiaTool_HideAI";
static NSString *const kNoOpsKey       = @"HeJiaTool_NoOps";
static NSString *const kInjectedKey    = @"HeJiaTool_Injected";

static void HTPostTabbarChanged(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HeJiaTool_TabbarReload"
                                                        object:nil];
}

extern "C" UIViewController *HTMakeSettingsVC(void);
extern "C" UIViewController *HTMakeLogViewer(NSString *path, NSString *title);

// ===========================================================================
//  自定义行：标题 + 副标题 + 开关
// ===========================================================================
@interface HTSettingCell : UITableViewCell
@property (nonatomic, strong) UILabel *titleLbl;
@property (nonatomic, strong) UILabel *subLbl;
@property (nonatomic, strong) UISwitch *sw;
@end

@implementation HTSettingCell

- (instancetype)initWithStyle:(NSInteger)style reuseIdentifier:(NSString *)reuse {
    self = [super initWithStyle:style reuseIdentifier:reuse];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    _titleLbl = [[UILabel alloc] initWithFrame:CGRectZero];
    _titleLbl.font = [UIFont systemFontOfSize:16 weight:0.3];
    _titleLbl.textColor = [UIColor labelColor];
    [self.contentView addSubview:_titleLbl];

    _subLbl = [[UILabel alloc] initWithFrame:CGRectZero];
    _subLbl.font = [UIFont systemFontOfSize:12 weight:0];
    _subLbl.textColor = [UIColor secondaryLabelColor];
    [self.contentView addSubview:_subLbl];

    _sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    [self.contentView addSubview:_sw];

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;

    CGRect sf = _sw.frame;
    sf.size = CGSizeMake(51, 31);
    sf.origin.x = w - sf.size.width - 16;
    sf.origin.y = (self.contentView.bounds.size.height - sf.size.height) / 2.0;
    _sw.frame = sf;

    CGFloat textW = sf.origin.x - 32;
    _titleLbl.frame = CGRectMake(16, 11, textW, 20);
    _subLbl.frame   = CGRectMake(16, 32, textW, 16);
}

@end

// ===========================================================================
@interface HTSettingsViewController : UITableViewController
@end

@implementation HTSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"工具箱";
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismissSelf)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"退出"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(forceQuitTapped)];

    [self buildHeader];
}

// ---------------------------------------------------------------------------
//  头部卡片
// ---------------------------------------------------------------------------
- (void)buildHeader {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    int on = 0;
    const char *keys[] = { "HeJiaTool_NoAds", "HeJiaTool_HideService", "HeJiaTool_HideFind",
                           "HeJiaTool_HideAI", "HeJiaTool_NoOps" };
    for (int i = 0; i < 5; i++) {
        NSString *k = [NSString stringWithUTF8String:keys[i]];
        if ([ud boolForKey:k]) on++;
    }

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 104)];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(20, 18, 240, 28)];
    name.text = @"HeJiaTool";
    name.font = [UIFont boldSystemFontOfSize:22];
    name.textColor = [UIColor labelColor];
    [header addSubview:name];

    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(20, 46, 240, 18)];
    ver.text = @"移动爱家 · 检测绕过 / 广告接管";
    ver.font = [UIFont systemFontOfSize:12 weight:0];
    ver.textColor = [UIColor secondaryLabelColor];
    [header addSubview:ver];

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, 280, 18)];
    status.text = [NSString stringWithFormat:@"已开启 %d / 5 项增强功能", on];
    status.font = [UIFont systemFontOfSize:12 weight:0.4];
    status.textColor = (on > 0) ? [UIColor systemGreenColor] : [UIColor secondaryLabelColor];
    [header addSubview:status];

    self.tableView.tableHeaderView = header;
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 强制退出

- (void)forceQuitTapped {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"强制退出 App"
                         message:@"立即终止进程（不会做任何保存），确定吗？"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消"
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"退出"
                                          style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *act) {
        (void)act;
        SVC_LOG(@"用户触发强制退出");
        _exit(0);          // 跳过 atexit / stdio 清理，立刻结束
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { (void)tv; return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    (void)tv;
    if (s == 0) return 5;
    if (s == 1) return 1;
    return 2;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    (void)tv; (void)ip;
    return 60;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    (void)tv;
    if (s == 0) return @"增强功能";
    if (s == 1) return @"安全";
    return @"日志与诊断";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    (void)tv;
    if (s == 0) return @"开启后即时生效；日志相关项点击可直接预览。";
    if (s == 1) return @"过签名检测强制开启，否则应用会被判定为已篡改。";
    return @"日志位于 App 沙盒 Library/Caches/HeJiaTool/。";
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"HTSettingCell";
    HTSettingCell *cell = (HTSettingCell *)[tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[HTSettingCell alloc] initWithStyle:0 reuseIdentifier:cid];
    }

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    cell.titleLbl.textColor = [UIColor labelColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.sw.hidden = NO;
    cell.sw.enabled = YES;
    cell.subLbl.hidden = NO;
    cell.sw.tag = 100 + ip.section * 10 + ip.row;

    if (ip.section == 0) {
        NSString *keys[5]   = { kNoAdsKey, kHideServiceKey, kHideFindKey, kHideAIKey, kNoOpsKey };
        NSString *titles[5] = { @"屏蔽广告与推广", @"隐藏「服务」页面", @"隐藏「发现」页面",
                                @"隐藏中间「AI 灵犀」", @"屏蔽运营位推广" };
        NSString *subs[5]   = { @"展示层接管，不拦截网络", @"仅隐藏入口，不改索引",
                                @"仅隐藏入口，不改索引", @"隐藏头像与气泡",
                                @"首页/设备页的推广卡片" };
        [cell.sw addTarget:self action:@selector(switchChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.titleLbl.text = titles[ip.row];
        cell.subLbl.text   = subs[ip.row];
        [cell.sw setOn:[ud boolForKey:keys[ip.row]] animated:NO];
    } else if (ip.section == 1) {
        cell.titleLbl.text = @"过签名检测";
        cell.subLbl.text   = @"强制开启，不可关闭";
        cell.sw.enabled = NO;
        cell.sw.tag = 200;
        [cell.sw setOn:YES animated:NO];
    } else {
        cell.sw.hidden = YES;
        cell.subLbl.hidden = YES;
        cell.titleLbl.text = (ip.row == 0) ? @"主日志  HeJiaTool.log" : @"扫描明细  adscan.log";
        cell.titleLbl.textColor = [UIColor systemBlueColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    (void)tv;
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 2) {
        const char *p = (ip.row == 0) ? HTGetLogFilePath() : HTGetAdScanLogPath();
        NSString *path  = [NSString stringWithUTF8String:(p ? p : "")];
        NSString *title = (ip.row == 0) ? @"主日志" : @"扫描明细";
        UIViewController *vc = HTMakeLogViewer(path, title);
        if (self.navigationController) {
            [self.navigationController pushViewController:vc animated:YES];
        }
        return;
    }
    if (ip.section == 1) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:@"过签名检测"
                             message:@"该项已强制开启，用于绕过应用的篡改检测，不可修改。"
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"知道了"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

#pragma mark - 开关

- (void)switchChanged:(UISwitch *)sw {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSInteger tag = sw.tag;

    if (tag == 100) {
        [ud setBool:sw.isOn forKey:kNoAdsKey];
        SVC_LOG(@"屏蔽广告 = %@", sw.isOn ? @"开" : @"关");
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"HeJiaTool_NoAdsChanged" object:nil];
    } else if (tag == 101) {
        [ud setBool:sw.isOn forKey:kHideServiceKey];
        SVC_LOG(@"隐藏服务页 = %@", sw.isOn ? @"开" : @"关");
        HTPostTabbarChanged();
    } else if (tag == 102) {
        [ud setBool:sw.isOn forKey:kHideFindKey];
        SVC_LOG(@"隐藏发现页 = %@", sw.isOn ? @"开" : @"关");
        HTPostTabbarChanged();
    } else if (tag == 103) {
        [ud setBool:sw.isOn forKey:kHideAIKey];
        SVC_LOG(@"隐藏 AI灵犀 = %@", sw.isOn ? @"开" : @"关");
        HTPostTabbarChanged();
    } else if (tag == 104) {
        [ud setBool:sw.isOn forKey:kNoOpsKey];
        SVC_LOG(@"屏蔽运营位 = %@", sw.isOn ? @"开" : @"关");
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"HeJiaTool_NoAdsChanged" object:nil];
    }
    [self buildHeader];
}

@end

// ===========================================================================
extern "C" UIViewController *HTMakeSettingsVC(void) {
    return [[HTSettingsViewController alloc] init];
}

} // extern "C"
