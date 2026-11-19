// 编辑规则：当 / 如果 / 就
#import "CXControllers.h"

@implementation CXRuleController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSDictionary *r = [self ruleIn:self.rules];
    self.title = r[@"name"] ?: @"规则";
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *s = [NSMutableArray array];
        NSDictionary *r = [self ruleIn:self.rules];
        if (!r) { _specifiers = @[ [self groupNamed:nil footer:@"这条规则已被删除。"] ].mutableCopy; return _specifiers; }
        NSDictionary *ids = @{ @"ruleId": self.ruleId };

        [s addObject:[self groupNamed:nil footer:nil]];
        [s addObject:[self textNamed:@"名称" field:@"name" placeholder:@"给规则起个名字"]];
        [s addObject:[self switchNamed:@"启用这条规则" field:@"enabled"]];

        // 当
        [s addObject:[self groupNamed:@"当 · 打开这些 App 时" footer:nil]];
        NSArray *apps = r[@"apps"];
        PSSpecifier *pick = [self linkNamed:@"选择 App" subtitle:CXAppsSummary(apps) value:nil
                                       icon:apps.count ? CXAppIcon(apps[0]) : CXSymbolIcon(@"app.dashed", UIColor.systemGrayColor)
                                     detail:CXAppPickerController.class props:ids];
        pick.identifier = @"apps";
        [s addObject:pick];

        // 如果
        NSArray *conds = r[@"conditions"];
        [s addObject:[self groupNamed:conds.count ? @"如果 · 满足以下条件" : @"如果 · 没有条件，总是执行"
                               footer:conds.count > 1 ? @"「全部满足」：每个条件都要满足；「任一满足」：满足一个就执行。" : nil]];
        if (conds.count > 1) [s addObject:[self segmentField:@"match" values:@[ @"all", @"any" ] titles:@[ @"全部满足", @"任一满足" ]]];
        [conds enumerateObjectsUsingBlock:^(NSDictionary *c, NSUInteger i, BOOL *stop) {
            PSSpecifier *l = [self linkNamed:CXConditionName(c[@"type"]) subtitle:CXConditionText(c) value:nil icon:CXConditionIcon(c[@"type"])
                                      detail:CXConditionController.class props:@{ @"ruleId": self.ruleId, @"index": @(i) }];
            l.identifier = [NSString stringWithFormat:@"cond%lu", (unsigned long)i];
            [s addObject:l];
        }];
        [s addObject:[self buttonNamed:@"＋ 添加条件" action:@selector(addCondition) tint:nil]];

        // 就
        NSArray *acts = r[@"actions"];
        [s addObject:[self groupNamed:@"就 · 执行这些动作" footer:@"标有「↩︎」的动作，离开 App 时会还原成打开前的状态。条件不满足、没执行的动作不会被还原。"]];
        [acts enumerateObjectsUsingBlock:^(NSDictionary *a, NSUInteger i, BOOL *stop) {
            BOOL back = CXActionWillRestore(a);
            NSString *v = [NSString stringWithFormat:@"%@%@", CXActionValueText(a), back ? @"  ↩︎" : @""];
            PSSpecifier *l = [self linkNamed:CXActionName(a[@"type"]) subtitle:nil value:v icon:CXActionIcon(a[@"type"])
                                      detail:CXActionController.class props:@{ @"ruleId": self.ruleId, @"index": @(i) }];
            l.identifier = [NSString stringWithFormat:@"act%lu", (unsigned long)i];
            [s addObject:l];
        }];
        [s addObject:[self buttonNamed:@"＋ 添加动作" action:@selector(addAction) tint:nil]];

        // 高级
        [s addObject:[self groupNamed:@"高级" footer:@"打开后：App 还开着时如果条件变了（比如连上了家里的 Wi-Fi、插上了充电器），会立即执行或撤销动作。关闭：只在打开 App 的那一刻判断一次。"]];
        [s addObject:[self switchNamed:@"条件变化时重新判断" field:@"reevaluate"]];

        [s addObject:[self groupNamed:nil footer:@"只判断条件、告诉你现在打开 App 会不会执行，不会真的执行动作。"]];
        [s addObject:[self buttonNamed:@"试运行（现在打开会怎样）" action:@selector(dryRun) tint:nil]];

        [s addObject:[self groupNamed:nil footer:nil]];
        [s addObject:[self buttonNamed:@"上移一位" action:@selector(moveUp) tint:nil]];
        [s addObject:[self buttonNamed:@"删除规则" action:@selector(deleteRule) tint:UIColor.systemRedColor]];
        _specifiers = s;
    }
    return _specifiers;
}

- (id)cxGet:(PSSpecifier *)spec {
    NSString *f = [spec propertyForKey:@"field"];
    id v = [self ruleIn:self.rules][f];
    if ([f isEqualToString:@"match"]) return v ?: @"all";
    return v;
}

- (void)cxSet:(id)value specifier:(PSSpecifier *)spec {
    NSString *f = [spec propertyForKey:@"field"];
    NSMutableArray *rules = self.rules;
    NSMutableDictionary *r = [self ruleIn:rules];
    if (!r) return;
    if ([f isEqualToString:@"name"]) {
        NSString *n = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        value = n.length ? n : r[@"name"];
        self.title = value;
    }
    r[f] = value;
    [self saveRules:rules];
}

- (void)addCondition {
    NSArray *types = CXConditionTypes();
    NSMutableArray *titles = [NSMutableArray array];
    for (NSString *t in types) [titles addObject:CXConditionName(t)];
    [self chooseFrom:@"添加条件" options:titles disabled:nil handler:^(NSInteger i) {
        NSString *type = types[i];
        NSMutableArray *rules = self.rules;
        NSMutableDictionary *r = [self ruleIn:rules];
        NSDictionary *c = [type isEqualToString:@"wifi"] ? @{ @"type": type, @"op": @"is", @"ssid": @"" }
                        : [type isEqualToString:@"charging"] ? @{ @"type": type, @"is": @YES }
                        : @{ @"type": type, @"start": @(22 * 60), @"end": @(7 * 60), @"days": @"everyday" };
        NSMutableArray *conds = [r[@"conditions"] mutableCopy] ?: [NSMutableArray array];
        [conds addObject:c.mutableCopy];
        r[@"conditions"] = conds;
        [self saveRules:rules];
        [self reloadSpecifiers];
        [self openSpecifierWithID:[NSString stringWithFormat:@"cond%lu", (unsigned long)conds.count - 1]];
    }];
}

- (void)addAction {
    NSArray *types = CXActionTypes();
    NSDictionary *r = [self ruleIn:self.rules];
    NSMutableSet *used = [NSMutableSet set];
    NSMutableArray *titles = [NSMutableArray array];
    [types enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        [titles addObject:CXActionName(t)];
        for (NSDictionary *a in r[@"actions"]) if ([a[@"type"] isEqualToString:t]) [used addObject:@(i)];
    }];
    [self chooseFrom:@"添加动作" options:titles disabled:used handler:^(NSInteger i) {
        NSString *type = types[i];
        NSMutableArray *rules = self.rules;
        NSMutableDictionary *rr = [self ruleIn:rules];
        NSMutableArray *acts = [rr[@"actions"] mutableCopy] ?: [NSMutableArray array];
        [acts addObject:[@{ @"type": type, @"value": CXActionIsLevel(type) ? @50 : @YES, @"restore": @(CXActionCanRestore(type) || CXActionIsWhileInApp(type)) } mutableCopy]];
        rr[@"actions"] = acts;
        [self saveRules:rules];
        [self reloadSpecifiers];
        [self openSpecifierWithID:[NSString stringWithFormat:@"act%lu", (unsigned long)acts.count - 1]];
    }];
}

- (void)dryRun {
    CXSet(CXK_DRYRUN_OUT, nil);
    CXSet(CXK_DRYRUN_RULE, self.ruleId);
    CXPost(CX_NOTIFY_DRYRUN);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CXSync();
        NSString *out = CXGet(CXK_DRYRUN_OUT);
        if (![out isKindOfClass:NSString.class])
            [self alert:@"没有收到结果" message:@"SpringBoard 里的 ControlX 没有回应。请确认已注销（respring）过。"];
        else
            [self alert:@"试运行" message:out];
    });
}

- (void)moveUp {
    NSMutableArray *rules = self.rules;
    NSMutableDictionary *r = [self ruleIn:rules];
    NSUInteger i = [rules indexOfObject:r];
    if (i == NSNotFound || i == 0) { [self alert:@"已经在最前面了" message:nil]; return; }
    [rules exchangeObjectAtIndex:i withObjectAtIndex:i - 1];
    [self saveRules:rules];
    [self alert:@"已上移" message:[NSString stringWithFormat:@"现在排第 %lu 位。", (unsigned long)i]];
}

- (void)deleteRule {
    NSString *name = [self ruleIn:self.rules][@"name"];
    [self confirm:[NSString stringWithFormat:@"删除「%@」？", name] action:@"删除规则" handler:^{
        NSMutableArray *rules = self.rules;
        NSMutableDictionary *r = [self ruleIn:rules];
        if (r) [rules removeObject:r];
        [self saveRules:rules];
        [self.navigationController popViewControllerAnimated:YES];
    }];
}

@end
