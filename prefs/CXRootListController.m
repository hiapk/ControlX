// 首页：总开关、最近执行、规则列表、调试入口
#import "CXControllers.h"

@implementation CXRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *s = [NSMutableArray array];
        CXSync();

        [s addObject:[self groupNamed:nil footer:@"当 · 如果 · 就 —— 打开 App 时，按条件自动控制系统设置。"]];
        [s addObject:[self switchNamed:@"启用 ControlX" field:@"enabled"]];
        NSString *last = CXGet(CXK_LAST_RUN);
        [s addObject:[self infoNamed:@"最近执行" value:[last isKindOfClass:NSString.class] ? last : @"暂无"]];

        NSArray *rules = CXLoadRules();
        NSUInteger on = 0;
        for (NSDictionary *r in rules) if ([r[@"enabled"] boolValue]) on++;
        [s addObject:[self groupNamed:[NSString stringWithFormat:@"规则（%lu/%lu 已启用）", (unsigned long)on, (unsigned long)rules.count]
                               footer:@"同一个 App 命中多条规则时，按列表顺序执行，后面的覆盖前面的。可在规则页里「上移」调整顺序。"]];
        for (NSDictionary *r in rules) {
            NSString *name = [r[@"enabled"] boolValue] ? r[@"name"] : [NSString stringWithFormat:@"%@（已停用）", r[@"name"]];
            NSString *first = [r[@"apps"] firstObject];
            PSSpecifier *l = [self linkNamed:name subtitle:CXRuleSummary(r) value:nil
                                        icon:first ? CXAppIcon(first) : CXSymbolIcon(@"app.dashed", UIColor.systemGrayColor)
                                      detail:CXRuleController.class props:@{ @"ruleId": r[@"id"] }];
            l.identifier = r[@"id"];
            [s addObject:l];
        }
        [s addObject:[self buttonNamed:@"＋ 新建规则" action:@selector(newRule) tint:nil]];

#if CX_DEBUG_UI
        [s addObject:[self groupNamed:@"调试" footer:@"出问题时，把「运行日志」复制给开发者。「系统接口诊断」只读取本机系统组件的接口清单，用于适配新系统，不会改动任何东西。"]];
        NSArray *log = CXGet(CXK_LOG);
        PSSpecifier *logBtn = [self buttonNamed:@"运行日志" action:@selector(showLog) tint:UIColor.labelColor];
        [logBtn setProperty:@"value" forKey:@"cxStyle"];
        [logBtn setProperty:[NSString stringWithFormat:@"%lu 条", (unsigned long)([log isKindOfClass:NSArray.class] ? log.count : 0)] forKey:@"cxValue"];
        [logBtn setProperty:CXSymbolIcon(@"list.bullet.rectangle", UIColor.systemGrayColor) forKey:@"iconImage"];
        [s addObject:logBtn];
        PSSpecifier *test = [self buttonNamed:@"动作自检" action:@selector(selfTest) tint:UIColor.labelColor];
        [test setProperty:CXSymbolIcon(@"checkmark.seal.fill", UIColor.systemGreenColor) forKey:@"iconImage"];
        [s addObject:test];
        PSSpecifier *diag = [self buttonNamed:@"系统接口诊断" action:@selector(diagnose) tint:UIColor.labelColor];
        [diag setProperty:CXSymbolIcon(@"stethoscope", UIColor.systemBlueColor) forKey:@"iconImage"];
        [s addObject:diag];

#endif
        [s addObject:[self groupNamed:nil footer:@"ControlX · MIT 开源"]];
        _specifiers = s;
    }
    return _specifiers;
}

- (id)cxGet:(PSSpecifier *)spec {
    id v = CXGet(CXK_ENABLED);
    return v ?: @YES;
}

- (void)cxSet:(id)value specifier:(PSSpecifier *)spec {
    CXSet(CXK_ENABLED, value);
    CXPost(CX_NOTIFY_PREFS);
}

- (void)newRule {
    NSMutableArray *rules = CXLoadRules();
    NSString *rid = NSUUID.UUID.UUIDString;
    [rules addObject:[@{ @"id": rid, @"name": [NSString stringWithFormat:@"规则 %lu", (unsigned long)rules.count + 1],
                         @"enabled": @YES, @"apps": @[], @"match": @"all", @"conditions": @[], @"actions": @[],
                         @"reevaluate": @NO } mutableCopy]];
    CXSaveRules(rules);
    [self reloadSpecifiers];
    [self openSpecifierWithID:rid];
}

- (void)showLog {
    CXSync();
    NSArray *log = CXGet(CXK_LOG);
    NSString *text = [log isKindOfClass:NSArray.class] && log.count
        ? [[log reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n\n"] : @"（暂无日志）";
    [self.navigationController pushViewController:[[CXTextController alloc] initWithTitle:@"运行日志" text:text clearable:YES] animated:YES];
}

- (void)diagnose {
    CXSet(CXK_DIAG, nil);
    CXPost(CX_NOTIFY_DIAG);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CXSync();
        NSString *t = CXGet(CXK_DIAG);
        if (![t isKindOfClass:NSString.class]) {
            [self alert:@"没有收到结果" message:@"SpringBoard 里的 ControlX 没有回应。请确认已注销（respring）过。"];
            return;
        }
        [self.navigationController pushViewController:[[CXTextController alloc] initWithTitle:@"系统接口诊断" text:t clearable:NO] animated:YES];
    });
}

- (void)selfTest {
    CXSet(CXK_SELFTEST, nil);
    CXPost(CX_NOTIFY_SELFTEST);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CXSync();
        NSDictionary *r = CXGet(CXK_SELFTEST);
        if (![r isKindOfClass:NSDictionary.class]) {
            [self alert:@"没有收到结果" message:@"SpringBoard 里的 ControlX 没有回应。请确认已注销（respring）过，或把运行日志发给开发者。"];
            return;
        }
        NSMutableString *t = [NSMutableString stringWithFormat:@"%@ · 检测于 %@\n只读取当前状态，不会改动设置。\n\n", r[@"_system"], r[@"_at"]];
        NSUInteger ok = 0;
        for (NSString *type in CXActionTypes()) {
            NSString *v = r[type] ?: @"不可用";
            if ([v hasPrefix:@"可用"]) ok++;
            [t appendFormat:@"%@  %@：%@\n", [v hasPrefix:@"可用"] ? @"✅" : @"❌", CXActionName(type), v];
        }
        [t appendFormat:@"\n共 %lu/%lu 可用", (unsigned long)ok, (unsigned long)CXActionTypes().count];
        [self.navigationController pushViewController:[[CXTextController alloc] initWithTitle:@"动作自检" text:t clearable:NO] animated:YES];
    });
}

@end

#pragma mark - 文本页

@implementation CXTextController {
    NSString *_text;
    BOOL _clearable;
    UITextView *_tv;
}

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text clearable:(BOOL)clearable {
    if ((self = [super init])) { self.title = title; _text = text; _clearable = clearable; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    _tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _tv.editable = NO;
    _tv.backgroundColor = UIColor.clearColor;
    _tv.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _tv.textContainerInset = UIEdgeInsetsMake(16, 12, 32, 12);
    _tv.text = _text;
    [self.view addSubview:_tv];
    NSMutableArray *items = [NSMutableArray arrayWithObject:[[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyText)]];
    if (_clearable) [items addObject:[[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clear)]];
    self.navigationItem.rightBarButtonItems = items;
}

- (void)copyText {
    UIPasteboard.generalPasteboard.string = [NSString stringWithFormat:@"=== ControlX %@ · iOS %@ ===\n%@", self.title, UIDevice.currentDevice.systemVersion, _text];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已复制" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

- (void)clear {
    CXSet(CXK_LOG, @[]);
    _text = @"（暂无日志）";
    _tv.text = _text;
}

@end
