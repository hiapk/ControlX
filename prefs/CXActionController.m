// 编辑动作：数值（滑块）或开关 + 离开时恢复
#import "CXControllers.h"

@implementation CXActionController

- (NSMutableDictionary *)actionIn:(NSMutableArray *)rules {
    NSArray *acts = [self ruleIn:rules][@"actions"];
    return self.itemIndex < (NSInteger)acts.count ? acts[self.itemIndex] : nil;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.title = CXActionName([self actionIn:self.rules][@"type"]);
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *s = [NSMutableArray array];
        NSDictionary *a = [self actionIn:self.rules];
        if (!a) { _specifiers = @[ [self groupNamed:nil footer:@"这个动作已被删除。"] ].mutableCopy; return _specifiers; }
        NSString *type = a[@"type"];

        if (CXActionIsWhileInApp(type)) {
            NSDictionary *notes = @{
                @"hideHomeBar": @"在这个 App 里时，屏幕底部的手势横条会隐藏，手势照常可用。",
                @"noControlCenter": @"在这个 App 里时，从右上角下拉不会打开控制中心。锁屏时不受影响。",
                @"noNotificationCenter": @"在这个 App 里时，从顶部下拉不会打开通知中心。锁屏时不受影响。",
                @"noBanners": @"在这个 App 里时，新通知不弹顶部横幅，但仍会进入通知中心。",
                @"noLowPowerAlert": @"在这个 App 里时，不弹「电量不足」提示框。",
                @"noReachability": @"在这个 App 里时，下滑手势横条不会触发便捷访问（屏幕下移）。",
                @"noHomeGesture": @"在这个 App 里时，上划不会回到主屏幕，适合游戏防误触。\n\n要退出：上划一次被挡住后，2 秒内再上划一次即可。锁屏、通知中心或控制中心打开时不拦截。",
            };
            [s addObject:[self groupNamed:@"使用期间生效" footer:[NSString stringWithFormat:@"%@\n\n离开 App 时自动解除，不需要设置恢复。", notes[type] ?: @""]]];
            [s addObject:[self groupNamed:nil footer:nil]];
            [s addObject:[self buttonNamed:@"删除动作" action:@selector(deleteAction) tint:UIColor.systemRedColor]];
            _specifiers = s;
            return _specifiers;
        }
        if (CXActionIsOneShot(type)) {
            [s addObject:[self groupNamed:@"打开 App 时执行一次" footer:@"结束所有后台 App 的进程，保留当前打开的 App 和正在播放音乐的 App。多任务界面里的卡片可能仍会显示，点开会重新启动。"]];
            [s addObject:[self groupNamed:nil footer:@"注意：在这里点会立即清理，「设置」以外的后台 App 都会被结束。"]];
            [s addObject:[self buttonNamed:@"立即试一下" action:@selector(preview) tint:nil]];
            [s addObject:[self groupNamed:nil footer:nil]];
            [s addObject:[self buttonNamed:@"删除动作" action:@selector(deleteAction) tint:UIColor.systemRedColor]];
            _specifiers = s;
            return _specifiers;
        }

        if (CXActionIsLevel(type)) {
            [s addObject:[self groupNamed:[NSString stringWithFormat:@"打开 App 时 · %@", CXActionValueText(a)] footer:nil]];
            PSSpecifier *slider = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:@selector(cxSet:specifier:) get:@selector(cxGet:)
                                                                 detail:nil cell:PSSliderCell edit:nil];
            [slider setProperty:@"value" forKey:@"field"];
            [slider setProperty:@0 forKey:@"min"];
            [slider setProperty:@100 forKey:@"max"];
            [slider setProperty:@YES forKey:@"showValue"];
            slider.identifier = @"slider";
            [s addObject:slider];
        } else {
            [s addObject:[self groupNamed:@"打开 App 时" footer:nil]];
            BOOL music = [type isEqualToString:@"music"];
            [s addObject:[self segmentField:@"value" values:@[ @YES, @NO ] titles:music ? @[ @"播放", @"暂停" ] : @[ @"打开", @"关闭" ]]];
        }

        if (CXActionCanRestore(type)) {
            [s addObject:[self groupNamed:@"离开 App 时" footer:[a[@"restore"] boolValue] ? @"离开时还原成打开 App 之前的值。" : @"离开后保持这个设置，不还原。"]];
            [s addObject:[self switchNamed:@"恢复原来的状态" field:@"restore"]];
        } else {
            [s addObject:[self groupNamed:nil footer:@"读不到播放状态，所以没法「离开时恢复」。需要的话，可以再建一条规则在别的 App 里暂停。"]];
        }
        if ([type isEqualToString:@"vpn"])
            [s addObject:[self groupNamed:nil footer:@"控制的是「设置 → VPN」里当前选中的那个 VPN。打开 VPN 时会拉起对应的 App 扩展，可能要一两秒才连上。"]];

        [s addObject:[self groupNamed:nil footer:@"立即执行一次这个动作，方便调到满意的值。不会自动还原。"]];
        [s addObject:[self buttonNamed:@"立即试一下" action:@selector(preview) tint:nil]];

        [s addObject:[self groupNamed:nil footer:nil]];
        [s addObject:[self buttonNamed:@"删除动作" action:@selector(deleteAction) tint:UIColor.systemRedColor]];
        _specifiers = s;
    }
    return _specifiers;
}

- (id)cxGet:(PSSpecifier *)spec {
    return [self actionIn:self.rules][[spec propertyForKey:@"field"]];
}

- (void)cxSet:(id)value specifier:(PSSpecifier *)spec {
    NSMutableArray *rules = self.rules;
    NSMutableDictionary *a = [self actionIn:rules];
    if (!a) return;
    NSString *f = [spec propertyForKey:@"field"];
    if ([f isEqualToString:@"value"] && CXActionIsLevel(a[@"type"])) value = @(lround([value doubleValue]));
    a[f] = value;
    [self saveRules:rules];
    // 只刷新标题/说明文字，不重建滑块（否则拖动会中断）
    if ([f isEqualToString:@"restore"]) [self reloadSpecifiers];
}

- (void)preview {
    NSDictionary *a = [self actionIn:self.rules];
    if (!a) return;
    CXSet(CXK_PREVIEW, @{ @"type": a[@"type"], @"value": a[@"value"] });
    CXPost(CX_NOTIFY_PREVIEW);
}

- (void)deleteAction {
    NSMutableArray *rules = self.rules;
    NSMutableDictionary *r = [self ruleIn:rules];
    NSMutableArray *acts = [r[@"actions"] mutableCopy];
    if (self.itemIndex < (NSInteger)acts.count) [acts removeObjectAtIndex:self.itemIndex];
    r[@"actions"] = acts;
    [self saveRules:rules];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
