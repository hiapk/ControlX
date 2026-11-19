#import "CXBase.h"
#import <notify.h>

@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *applicationType;
@property (nonatomic, readonly) NSArray *appTags;
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray<LSApplicationProxy *> *)allInstalledApplications;
@end

@interface UIImage (Private)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

#pragma mark - 规则数据

static id CXDeepMutable(id obj) {
    return CFBridgingRelease(CFPropertyListCreateDeepCopy(kCFAllocatorDefault, (__bridge CFPropertyListRef)obj, kCFPropertyListMutableContainersAndLeaves));
}

NSMutableArray<NSMutableDictionary *> *CXLoadRules(void) {
    CXSync();
    id rules = CXGet(CXK_RULES);
    return [rules isKindOfClass:NSArray.class] ? CXDeepMutable(rules) : [NSMutableArray array];
}

void CXPost(const char *name) { notify_post(name); }

void CXSaveRules(NSArray *rules) {
    CXSet(CXK_RULES, rules);
    CXPost(CX_NOTIFY_PREFS);
}

NSMutableDictionary *CXFindRule(NSArray *rules, NSString *ruleId) {
    for (NSMutableDictionary *r in rules) if ([r[@"id"] isEqual:ruleId]) return r;
    return nil;
}

NSString *CXAppsSummary(NSArray *apps) {
    if (!apps.count) return @"未选择 App";
    if (apps.count == 1) return CXAppName(apps[0]);
    return [NSString stringWithFormat:@"%@ 等 %lu 个", CXAppName(apps[0]), (unsigned long)apps.count];
}

NSString *CXRuleSummary(NSDictionary *rule) {
    NSUInteger c = [rule[@"conditions"] count], a = [rule[@"actions"] count];
    return [NSString stringWithFormat:@"%@ · %@ · %lu 个动作", CXAppsSummary(rule[@"apps"]),
            c ? [NSString stringWithFormat:@"%lu 个条件", (unsigned long)c] : @"无条件", (unsigned long)a];
}

#pragma mark - App 信息

NSString *CXAppName(NSString *bundleID) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[bundleID]) return cache[bundleID];
    Class cls = NSClassFromString(@"LSApplicationProxy");
    NSString *name = nil;
    if ([cls respondsToSelector:@selector(applicationProxyForIdentifier:)])
        name = [[cls applicationProxyForIdentifier:bundleID] localizedName];
    name = name.length ? name : bundleID;
    cache[bundleID] = name;
    return name;
}

UIImage *CXAppIcon(NSString *bundleID) {
    if (![UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) return nil;
    return [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:UIScreen.mainScreen.scale];
}

NSArray<NSDictionary *> *CXInstalledApps(void) {
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    if (![ws respondsToSelector:@selector(defaultWorkspace)]) return @[];
    LSApplicationWorkspace *w = [ws defaultWorkspace];
    if (![w respondsToSelector:@selector(allInstalledApplications)]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (LSApplicationProxy *p in [w allInstalledApplications]) {
        NSString *bid = p.applicationIdentifier;
        if (!bid.length) continue;
        if ([p respondsToSelector:@selector(appTags)] && [p.appTags containsObject:@"hidden"]) continue;
        NSString *name = p.localizedName.length ? p.localizedName : bid;
        BOOL system = [p.applicationType isEqualToString:@"System"];
        [out addObject:@{ @"id": bid, @"name": name, @"system": @(system) }];
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
    return out;
}

#pragma mark - 图标

UIImage *CXSymbolIcon(NSString *symbol, UIColor *color) {
    CGFloat s = 29;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s, s) cornerRadius:7] fill];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        UIImage *img = [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithTintColor:UIColor.whiteColor
                                                                                   renderingMode:UIImageRenderingModeAlwaysOriginal];
        if (img) [img drawInRect:CGRectMake((s - img.size.width) / 2, (s - img.size.height) / 2, img.size.width, img.size.height)];
    }];
}

UIImage *CXActionIcon(NSString *type) {
    NSDictionary *m = @{
        @"volume": @[ @"speaker.wave.2.fill", UIColor.systemPinkColor ],
        @"brightness": @[ @"sun.max.fill", UIColor.systemBlueColor ],
        @"wifi": @[ @"wifi", UIColor.systemBlueColor ],
        @"bluetooth": @[ @"antenna.radiowaves.left.and.right", UIColor.systemBlueColor ],
        @"lowPower": @[ @"battery.25", UIColor.systemYellowColor ],
        @"darkMode": @[ @"circle.lefthalf.filled", UIColor.systemGrayColor ],
        @"rotationLock": @[ @"lock.rotation", UIColor.systemRedColor ],
        @"mute": @[ @"bell.slash.fill", UIColor.systemRedColor ],
        @"autoBrightness": @[ @"sun.max.circle.fill", UIColor.systemBlueColor ],
        @"cellular": @[ @"antenna.radiowaves.left.and.right", UIColor.systemGreenColor ],
        @"airplane": @[ @"airplane", UIColor.systemOrangeColor ],
        @"vpn": @[ @"lock.shield.fill", UIColor.systemBlueColor ],
        @"location": @[ @"location.fill", UIColor.systemBlueColor ],
        @"dnd": @[ @"moon.fill", UIColor.systemIndigoColor ],
        @"nightShift": @[ @"sun.haze.fill", UIColor.systemOrangeColor ],
        @"reduceWhitePoint": @[ @"circle.dotted", UIColor.systemGrayColor ],
        @"invertColors": @[ @"circle.righthalf.filled", UIColor.darkGrayColor ],
        @"music": @[ @"playpause.fill", UIColor.systemPinkColor ],
        @"hideHomeBar": @[ @"minus", UIColor.systemTealColor ],
        @"noControlCenter": @[ @"switch.2", UIColor.systemTealColor ],
        @"noNotificationCenter": @[ @"rectangle.topthird.inset.filled", UIColor.systemTealColor ],
        @"noBanners": @[ @"bell.badge.slash.fill", UIColor.systemRedColor ],
        @"noLowPowerAlert": @[ @"battery.0", UIColor.systemOrangeColor ],
        @"noReachability": @[ @"arrow.down.to.line", UIColor.systemTealColor ],
        @"noHomeGesture": @[ @"hand.raised.slash.fill", UIColor.systemRedColor ],
        @"killApps": @[ @"xmark.circle.fill", UIColor.systemRedColor ],
    };
    NSArray *v = m[type] ?: @[ @"questionmark", UIColor.systemGrayColor ];
    return CXSymbolIcon(v[0], v[1]);
}

UIImage *CXConditionIcon(NSString *type) {
    NSDictionary *m = @{
        @"wifi": @[ @"wifi", UIColor.systemBlueColor ],
        @"charging": @[ @"bolt.fill", UIColor.systemGreenColor ],
        @"time": @[ @"clock.fill", UIColor.systemIndigoColor ],
    };
    NSArray *v = m[type] ?: @[ @"questionmark", UIColor.systemGrayColor ];
    return CXSymbolIcon(v[0], v[1]);
}

#pragma mark - 单元格

@implementation CXCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier specifier:(PSSpecifier *)specifier {
    NSString *s = [specifier propertyForKey:@"cxStyle"];
    UITableViewCellStyle st = [s isEqualToString:@"subtitle"] ? UITableViewCellStyleSubtitle
                            : [s isEqualToString:@"value"] ? UITableViewCellStyleValue1 : style;
    return [super initWithStyle:st reuseIdentifier:reuseIdentifier specifier:specifier];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    NSString *sub = [specifier propertyForKey:@"cxSubtitle"] ?: [specifier propertyForKey:@"cxValue"];
    if (sub) {
        self.detailTextLabel.text = sub;
        self.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }
    UIColor *tint = [specifier propertyForKey:@"cxTint"];
    if (tint) self.textLabel.textColor = tint;
    NSNumber *checked = [specifier propertyForKey:@"cxChecked"];
    if (checked) self.accessoryType = checked.boolValue ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
}

@end

#pragma mark - 基类

@implementation CXBaseController

- (NSString *)ruleId { return [self.specifier propertyForKey:@"ruleId"]; }
- (NSInteger)itemIndex { return [[self.specifier propertyForKey:@"index"] integerValue]; }

- (NSMutableArray *)rules { return CXLoadRules(); }
- (NSMutableDictionary *)ruleIn:(NSArray *)rules { return CXFindRule(rules, self.ruleId); }
- (void)saveRules:(NSArray *)rules { CXSaveRules(rules); }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers]; // 子页面改过数据，返回时刷新摘要
}

- (PSSpecifier *)groupNamed:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *g = name ? [PSSpecifier groupSpecifierWithName:name] : [PSSpecifier emptyGroupSpecifier];
    if (footer) [g setProperty:footer forKey:@"footerText"];
    return g;
}

- (PSSpecifier *)fieldSpec:(NSString *)name field:(NSString *)field cell:(PSCellType)cell {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(cxSet:specifier:)
                                                       get:@selector(cxGet:) detail:nil cell:cell edit:nil];
    [s setProperty:field forKey:@"field"];
    s.identifier = field;
    return s;
}

- (PSSpecifier *)switchNamed:(NSString *)name field:(NSString *)field {
    return [self fieldSpec:name field:field cell:PSSwitchCell];
}

- (PSSpecifier *)segmentField:(NSString *)field values:(NSArray *)values titles:(NSArray *)titles {
    PSSpecifier *s = [self fieldSpec:@"" field:field cell:PSSegmentCell];
    [s setValues:values titles:titles];
    return s;
}

- (PSSpecifier *)textNamed:(NSString *)name field:(NSString *)field placeholder:(NSString *)placeholder {
    PSSpecifier *s = [self fieldSpec:name field:field cell:PSEditTextCell];
    if (placeholder) [s setProperty:placeholder forKey:@"placeholder"];
    [s setProperty:@YES forKey:@"noAutoCorrect"];
    return s;
}

- (PSSpecifier *)linkNamed:(NSString *)name subtitle:(NSString *)subtitle value:(NSString *)value
                      icon:(UIImage *)icon detail:(Class)detail props:(NSDictionary *)props {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:detail cell:PSLinkCell edit:nil];
    [s setProperty:CXCell.class forKey:@"cellClass"];
    if (subtitle) { [s setProperty:@"subtitle" forKey:@"cxStyle"]; [s setProperty:subtitle forKey:@"cxSubtitle"]; }
    else if (value) { [s setProperty:@"value" forKey:@"cxStyle"]; [s setProperty:value forKey:@"cxValue"]; }
    if (icon) [s setProperty:icon forKey:@"iconImage"];
    [props enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { [s setProperty:v forKey:k]; }];
    return s;
}

- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action tint:(UIColor *)tint {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    s.buttonAction = action;
    [s setProperty:CXCell.class forKey:@"cellClass"];
    if (tint) [s setProperty:tint forKey:@"cxTint"];
    return s;
}

- (PSSpecifier *)infoNamed:(NSString *)name value:(NSString *)value {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [s setProperty:CXCell.class forKey:@"cellClass"];
    [s setProperty:@"value" forKey:@"cxStyle"];
    [s setProperty:value ?: @"" forKey:@"cxValue"];
    return s;
}

- (id)cxGet:(PSSpecifier *)spec { return nil; }
- (void)cxSet:(id)value specifier:(PSSpecifier *)spec {}

- (void)openSpecifierWithID:(NSString *)identifier {
    PSSpecifier *s = [self specifierForID:identifier];
    NSIndexPath *ip = s ? [self indexPathForSpecifier:s] : nil;
    if (!ip) return;
    UITableView *tv = [self respondsToSelector:@selector(table)] ? self.table : nil;
    if (!tv && [self respondsToSelector:@selector(tableView)]) tv = self.tableView;
    if (tv) [self tableView:tv didSelectRowAtIndexPath:ip];
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseFrom:(NSString *)title options:(NSArray<NSString *> *)titles disabled:(NSSet<NSNumber *> *)disabled
           handler:(void (^)(NSInteger))handler {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        UIAlertAction *act = [UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { handler(i); }];
        act.enabled = ![disabled containsObject:@(i)];
        [a addAction:act];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 40, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)confirm:(NSString *)title action:(NSString *)action handler:(void (^)(void))handler {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:action style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { handler(); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 40, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

@end
