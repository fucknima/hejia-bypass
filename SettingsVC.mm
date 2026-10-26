// ============================================================================
//  HeJiaTool 设置页
// ----------------------------------------------------------------------------
//  开关项：
//    - 屏蔽广告（可控）
//    - 隐藏「服务」页面（可控）
//    - 隐藏「发现」页面（可控）
//    - 过签名检测（强制开启，开关置灰，点击提示）
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define SVC_LOG(fmt, ...) NSLog(@"[HeJiaUI] " fmt, ##__VA_ARGS__)

extern "C" {

static NSString *const kNoAdsKey       = @"HeJiaTool_NoAds";
static NSString *const kHideServiceKey = @"HeJiaTool_HideService";
static NSString *const kHideFindKey    = @"HeJiaTool_HideFind";
static NSString *const kInjectedKey    = @"HeJiaTool_Injected";

static void HTPostTabbarChanged(void) {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"HeJiaTool_TabbarReload"
                                                        object:nil];
}

extern UIViewController *HTMakeSettingsVC(void);

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
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(dismissSelf)];
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
}

- (void)dismissSelf {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 数据源

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { (void)tv; return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    (void)tv;
    return s == 0 ? @"增强功能" : @"安全";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    (void)tv;
    if (s == 1) return @"过签名检测默认开启且不可关闭，否则应用将被判定为已篡改。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    (void)tv;
    return s == 0 ? 3 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"HTSettingsCell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:cid];
        UISwitch *sw = [[UISwitch alloc] init];
        [sw addTarget:self action:@selector(switchChanged:)
     forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    UISwitch *sw = (UISwitch *)cell.accessoryView;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    if (ip.section == 0) {
        NSString *keys[3]  = { kNoAdsKey, kHideServiceKey, kHideFindKey };
        NSString *titles[3] = { @"屏蔽广告与推广", @"隐藏「服务」页面", @"隐藏「发现」页面" };

        cell.textLabel.text = titles[ip.row];
        cell.textLabel.textColor = [UIColor labelColor];
        sw.hidden = NO;
        sw.enabled = YES;
        sw.tag = (NSInteger)(100 + ip.row);
        [sw setOn:[ud boolForKey:keys[ip.row]] animated:NO];
    } else {
        cell.textLabel.text = @"过签名检测";
        cell.textLabel.textColor = [UIColor labelColor];
        sw.hidden = NO;
        sw.enabled = NO;          // 不可操作
        sw.tag = 200;
        [sw setOn:YES animated:NO];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    (void)tv;
    [tv deselectRowAtIndexPath:ip animated:YES];
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

    switch (sw.tag) {
        case 100:
            [ud setBool:sw.isOn forKey:kNoAdsKey];
            SVC_LOG(@"屏蔽广告 = %@", sw.isOn ? @"开" : @"关");
            [[NSNotificationCenter defaultCenter]
                postNotificationName:@"HeJiaTool_NoAdsChanged" object:nil];
            break;
        case 101:
            [ud setBool:sw.isOn forKey:kHideServiceKey];
            SVC_LOG(@"隐藏服务页 = %@", sw.isOn ? @"开" : @"关");
            HTPostTabbarChanged();
            break;
        case 102:
            [ud setBool:sw.isOn forKey:kHideFindKey];
            SVC_LOG(@"隐藏发现页 = %@", sw.isOn ? @"开" : @"关");
            HTPostTabbarChanged();
            break;
        default:
            break;
    }
    [ud synchronize];
}

@end

// ===========================================================================
UIViewController *HTMakeSettingsVC(void) {
    return [[HTSettingsViewController alloc] init];
}

} // extern "C"
