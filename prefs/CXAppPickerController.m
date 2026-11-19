// 选择 App：多选、搜索、已选置顶
#import "CXControllers.h"

@implementation CXAppPickerController {
    NSArray<NSDictionary *> *_apps;
    NSString *_query;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择 App";
    UISearchController *sc = [[UISearchController alloc] initWithSearchResultsController:nil];
    sc.searchResultsUpdater = self;
    sc.obscuresBackgroundDuringPresentation = NO;
    sc.searchBar.placeholder = @"搜索 App";
    self.navigationItem.searchController = sc;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    _query = sc.searchBar.text;
    [self reloadSpecifiers];
}

- (BOOL)matches:(NSDictionary *)app {
    if (!_query.length) return YES;
    return [app[@"name"] localizedCaseInsensitiveContainsString:_query] || [app[@"id"] localizedCaseInsensitiveContainsString:_query];
}

- (PSSpecifier *)rowFor:(NSDictionary *)app checked:(BOOL)checked {
    PSSpecifier *s = [self buttonNamed:app[@"name"] action:@selector(toggleApp:) tint:UIColor.labelColor];
    [s setProperty:@"subtitle" forKey:@"cxStyle"];
    [s setProperty:app[@"id"] forKey:@"cxSubtitle"];
    [s setProperty:@(checked) forKey:@"cxChecked"];
    [s setProperty:app[@"id"] forKey:@"bundleID"];
    UIImage *icon = CXAppIcon(app[@"id"]);
    if (icon) [s setProperty:icon forKey:@"iconImage"];
    return s;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        if (!_apps) _apps = CXInstalledApps();
        NSArray *selected = [self ruleIn:self.rules][@"apps"] ?: @[];
        NSMutableArray *s = [NSMutableArray array];
        if (!_apps.count) {
            [s addObject:[self groupNamed:nil footer:@"读取不到已安装的 App 列表。"]];
            _specifiers = s;
            return s;
        }
        NSMutableArray *sel = [NSMutableArray array], *user = [NSMutableArray array], *sys = [NSMutableArray array];
        for (NSDictionary *a in _apps) {
            if (![self matches:a]) continue;
            if ([selected containsObject:a[@"id"]]) [sel addObject:[self rowFor:a checked:YES]];
            else if ([a[@"system"] boolValue]) [sys addObject:[self rowFor:a checked:NO]];
            else [user addObject:[self rowFor:a checked:NO]];
        }
        if (sel.count) { [s addObject:[self groupNamed:[NSString stringWithFormat:@"已选择 %lu 个", (unsigned long)sel.count] footer:nil]]; [s addObjectsFromArray:sel]; }
        if (user.count) { [s addObject:[self groupNamed:@"用户 App" footer:nil]]; [s addObjectsFromArray:user]; }
        if (sys.count) { [s addObject:[self groupNamed:@"系统 App" footer:nil]]; [s addObjectsFromArray:sys]; }
        if (!sel.count && !user.count && !sys.count) [s addObject:[self groupNamed:nil footer:@"没有匹配的 App"]];
        _specifiers = s;
    }
    return _specifiers;
}

- (void)toggleApp:(PSSpecifier *)spec {
    NSString *bid = [spec propertyForKey:@"bundleID"];
    NSMutableArray *rules = self.rules;
    NSMutableDictionary *r = [self ruleIn:rules];
    NSMutableArray *apps = [r[@"apps"] mutableCopy] ?: [NSMutableArray array];
    if ([apps containsObject:bid]) [apps removeObject:bid]; else [apps addObject:bid];
    r[@"apps"] = apps;
    // 新规则还叫默认名时，用第一个 App 自动命名
    if (apps.count == 1 && [r[@"name"] hasPrefix:@"规则 "]) r[@"name"] = CXAppName(apps[0]);
    [self saveRules:rules];
    [self reloadSpecifiers];
}

@end
