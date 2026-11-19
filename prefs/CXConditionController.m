// 编辑条件：Wi-Fi / 充电 / 时间段
#import "CXControllers.h"

@implementation CXConditionController

- (NSMutableDictionary *)conditionIn:(NSMutableArray *)rules {
    NSArray *conds = [self ruleIn:rules][@"conditions"];
    return self.itemIndex < (NSInteger)conds.count ? conds[self.itemIndex] : nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.title = CXConditionName([self conditionIn:self.rules][@"type"]);
}

- (PSSpecifier *)timeField:(NSString *)field named:(NSString *)name {
    NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array];
    for (NSInteger m = 0; m < 1440; m += 15) { [values addObject:@(m)]; [titles addObject:CXMinutesText(m)]; }
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(cxSet:specifier:) get:@selector(cxGet:)
                                                    detail:NSClassFromString(@"PSListItemsController") cell:PSLinkListCell edit:nil];
    [s setProperty:field forKey:@"field"];
    [s setValues:values titles:titles];
    return s;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *s = [NSMutableArray array];
        NSDictionary *c = [self conditionIn:self.rules];
        NSString *type = c[@"type"];
        if ([type isEqualToString:@"wifi"]) {
            [s addObject:[self groupNamed:nil footer:@"没连 Wi-Fi 时，「连接的是」不满足，「连接的不是」满足。名称区分大小写。"]];
            [s addObject:[self segmentField:@"op" values:@[ @"is", @"isNot" ] titles:@[ @"连接的是", @"连接的不是" ]]];
            [s addObject:[self textNamed:@"Wi-Fi 名称" field:@"ssid" placeholder:@"点下方按钮自动填入"]];
            [s addObject:[self groupNamed:nil footer:nil]];
            CXSync();
            NSString *cur = CXGet(CXK_LAST_SSID);
            [s addObject:[self infoNamed:@"当前连接" value:[cur isKindOfClass:NSString.class] && cur.length ? cur : @"未连接"]];
            [s addObject:[self buttonNamed:@"填入当前连接的 Wi-Fi" action:@selector(fillSSID) tint:nil]];
        } else if ([type isEqualToString:@"charging"]) {
            [s addObject:[self groupNamed:nil footer:@"有线和无线充电都算；充满后仍接着电源也算「正在充电」。"]];
            [s addObject:[self segmentField:@"is" values:@[ @YES, @NO ] titles:@[ @"正在充电", @"没有在充电" ]]];
        } else if ([type isEqualToString:@"time"]) {
            [s addObject:[self groupNamed:nil footer:@"结束早于开始表示跨夜（如 22:00 到次日 07:00），跨夜时段按开始那天算星期。"]];
            [s addObject:[self timeField:@"start" named:@"开始"]];
            [s addObject:[self timeField:@"end" named:@"结束"]];
            [s addObject:[self segmentField:@"days" values:@[ @"everyday", @"weekdays", @"weekend" ] titles:@[ @"每天", @"工作日", @"周末" ]]];
        } else {
            [s addObject:[self groupNamed:nil footer:@"这个条件已被删除。"]];
        }
        if (c) {
            [s addObject:[self groupNamed:nil footer:nil]];
            [s addObject:[self buttonNamed:@"删除条件" action:@selector(deleteCondition) tint:UIColor.systemRedColor]];
        }
        _specifiers = s;
    }
    return _specifiers;
}

- (id)cxGet:(PSSpecifier *)spec {
    return [self conditionIn:self.rules][[spec propertyForKey:@"field"]];
}

- (void)cxSet:(id)value specifier:(PSSpecifier *)spec {
    NSMutableArray *rules = self.rules;
    NSMutableDictionary *c = [self conditionIn:rules];
    if (!c) return;
    NSString *f = [spec propertyForKey:@"field"];
    if ([f isEqualToString:@"ssid"]) value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] ?: @"";
    c[f] = value;
    [self saveRules:rules];
}

- (void)fillSSID {
    [self.view endEditing:YES];
    CXSync();
    NSString *cur = CXGet(CXK_LAST_SSID);
    if (![cur isKindOfClass:NSString.class] || !cur.length) {
        [self alert:@"未连接 Wi-Fi" message:@"请先连上要设置的 Wi-Fi，再回来点这个按钮。"];
        return;
    }
    NSMutableArray *rules = self.rules;
    [self conditionIn:rules][@"ssid"] = cur;
    [self saveRules:rules];
    [self reloadSpecifiers];
}

- (void)deleteCondition {
    NSMutableArray *rules = self.rules;
    NSMutableDictionary *r = [self ruleIn:rules];
    NSMutableArray *conds = [r[@"conditions"] mutableCopy];
    if (self.itemIndex < (NSInteger)conds.count) [conds removeObjectAtIndex:self.itemIndex];
    r[@"conditions"] = conds;
    [self saveRules:rules];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
