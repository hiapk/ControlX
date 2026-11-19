// ControlX 规则引擎（运行在 SpringBoard）
//
// 流程：前台 App 变化
//   → 离开旧 App：把本次改过、且设了「离开时恢复」的动作还原
//   → 打开新 App：找出包含它的规则 → 判断条件 → 执行动作（执行前先记下原值）
// 规则按列表顺序执行，后面的覆盖前面的。

#import <UIKit/UIKit.h>
#import <notify.h>
#import "../Shared/CXShared.h"
#import "CXActions.h"
#import "CXBlocks.h"

@interface SBApplication : NSObject
- (NSString *)bundleIdentifier;
@end

#pragma mark - 状态

static NSString *gFront;                    // 当前前台 App
NSString *CXFrontApp(void) { return gFront; }
static NSMutableDictionary *gSnapshot;      // type -> 打开 App 前的原值（只记需要恢复的）
static NSArray<NSString *> *gAppliedRules;  // 本次已执行的规则 id
static NSString *gLastSSID;
static BOOL gLastCharging;

#pragma mark - 日志

static void CXLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void CXLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    static NSDateFormatter *df;
    if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"MM-dd HH:mm:ss"; }
    CXSync();
    id old = CXGet(CXK_LOG);
    NSMutableArray *log = [old isKindOfClass:NSArray.class] ? [old mutableCopy] : [NSMutableArray array];
    [log addObject:[NSString stringWithFormat:@"%@ %@", [df stringFromDate:NSDate.date], msg]];
    while (log.count > CX_LOG_MAX) [log removeObjectAtIndex:0];
    CXSet(CXK_LOG, log);
}

static NSString *CXNow(void) {
    static NSDateFormatter *df;
    if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"HH:mm"; }
    return [df stringFromDate:NSDate.date];
}

#pragma mark - 读取规则

static BOOL CXEnabled(void) {
    id v = CXGet(CXK_ENABLED);
    return v ? [v boolValue] : YES;
}

static NSArray<NSDictionary *> *CXRulesFor(NSString *bundleID) {
    id rules = CXGet(CXK_RULES);
    if (![rules isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *r in rules) {
        if (![r isKindOfClass:NSDictionary.class] || ![r[@"enabled"] boolValue]) continue;
        id apps = r[@"apps"];
        if ([apps isKindOfClass:NSArray.class] && [apps containsObject:bundleID]) [out addObject:r];
    }
    return out;
}

#pragma mark - 条件

// 返回是否满足；detail 写入判断时的实际值，给日志用
static BOOL CXConditionMet(NSDictionary *c, NSString **detail) {
    NSString *type = c[@"type"];
    if ([type isEqualToString:@"wifi"]) {
        NSString *cur = CXCurrentSSID();
        BOOL same = cur && [cur isEqualToString:c[@"ssid"] ?: @""];
        *detail = [NSString stringWithFormat:@"当前：%@", cur ?: @"未连接"];
        return [c[@"op"] isEqualToString:@"isNot"] ? !same : same;
    }
    if ([type isEqualToString:@"charging"]) {
        BOOL charging = CXIsCharging();
        *detail = charging ? @"当前：充电中" : @"当前：未充电";
        return charging == [c[@"is"] boolValue];
    }
    if ([type isEqualToString:@"time"]) {
        NSDateComponents *n = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitWeekday fromDate:NSDate.date];
        *detail = [NSString stringWithFormat:@"当前：%@", CXNow()];
        return CXTimeInWindow([c[@"start"] integerValue], [c[@"end"] integerValue], c[@"days"], n.hour * 60 + n.minute, n.weekday);
    }
    *detail = @"未知条件类型";
    return NO;
}

// 判断一条规则；lines 收集每个条件的判断结果
static BOOL CXRuleMatches(NSDictionary *rule, NSMutableArray<NSString *> *lines) {
    NSArray *conds = [rule[@"conditions"] isKindOfClass:NSArray.class] ? rule[@"conditions"] : @[];
    if (!conds.count) { [lines addObject:@"    （无条件）"]; return YES; }
    BOOL any = [rule[@"match"] isEqualToString:@"any"];
    BOOL result = !any;
    for (NSDictionary *c in conds) {
        NSString *detail = @"";
        BOOL ok = CXConditionMet(c, &detail);
        [lines addObject:[NSString stringWithFormat:@"    %@ %@（%@）", ok ? @"✓" : @"✗", CXConditionText(c), detail]];
        result = any ? (result || ok) : (result && ok);
    }
    return result;
}

#pragma mark - 执行与恢复

static void CXRestore(NSString *reason) {
    if (!gSnapshot.count) { gAppliedRules = nil; return; }
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *type in CXActionTypes()) {          // 固定顺序，日志更好读
        NSNumber *orig = gSnapshot[type];
        if (!orig) continue;
        NSString *how = nil;
        BOOL ok = CXActionSet(type, orig, &how);
        [parts addObject:[NSString stringWithFormat:@"%@ → %@%@", CXActionName(type),
                          CXActionValueText(@{ @"type": type, @"value": orig }), ok ? @"" : @"（失败）"]];
    }
    CXLog(@"↩︎ %@，恢复：%@", reason, [parts componentsJoinedByString:@" · "]);
    [gSnapshot removeAllObjects];
    gAppliedRules = nil;
}

static void CXApply(NSString *bundleID, NSString *reason) {
    if (!bundleID || !CXEnabled()) return;
    NSArray *rules = CXRulesFor(bundleID);
    if (!rules.count) return;

    NSMutableArray *applied = [NSMutableArray array];
    NSMutableArray *summary = [NSMutableArray array];
    NSUInteger actionCount = 0;
    for (NSDictionary *rule in rules) {
        NSMutableArray *lines = [NSMutableArray array];
        BOOL ok = CXRuleMatches(rule, lines);
        NSMutableString *entry = [NSMutableString stringWithFormat:@"%@ %@\n  规则「%@」\n%@", reason, bundleID, rule[@"name"],
                                  [lines componentsJoinedByString:@"\n"]];
        if (!ok) {
            [entry appendString:@"\n  → 条件不满足，跳过"];
            CXLog(@"%@", entry);
            continue;
        }
        NSMutableArray *done = [NSMutableArray array];
        for (NSDictionary *a in rule[@"actions"]) {
            NSString *type = a[@"type"];
            NSNumber *value = a[@"value"];
            if (!type || !value) continue;
            if (CXActionWillRestore(a) && !gSnapshot[type]) {
                NSNumber *orig = CXActionGet(type);
                if (orig) gSnapshot[type] = orig;
            }
            NSString *how = nil;
            BOOL set = CXActionSet(type, value, &how);
            [done addObject:[NSString stringWithFormat:@"%@ %@%@", CXActionName(type), CXActionValueText(a),
                             set ? @"" : [NSString stringWithFormat:@"（失败%@）", how ? [@" " stringByAppendingString:how] : @""]]];
            if (set) actionCount++;
        }
        [entry appendFormat:@"\n  → 执行：%@", done.count ? [done componentsJoinedByString:@" · "] : @"（没有动作）"];
        CXLog(@"%@", entry);
        [applied addObject:rule[@"id"] ?: @""];
        [summary addObject:rule[@"name"] ?: @""];
    }
    gAppliedRules = applied;
    if (summary.count)
        CXSet(CXK_LAST_RUN, [NSString stringWithFormat:@"%@ · %@ · 执行 %lu 个动作", [summary componentsJoinedByString:@"、"], CXNow(), (unsigned long)actionCount]);
}

static void CXFrontChanged(NSString *bundleID) {
    if ((bundleID == gFront) || [bundleID isEqualToString:gFront]) return;
    CXSync();
    if (gFront) CXRestore([NSString stringWithFormat:@"离开 %@", gFront]);
    gFront = bundleID;
    if (bundleID) CXApply(bundleID, @"打开");
}

#pragma mark - 环境变化：重新判断

// 只有当前 App 有规则开启了「条件变化时重新判断」时才处理
static void CXReevaluate(NSString *why) {
    if (!gFront || !CXEnabled()) return;
    CXSync();
    NSArray *rules = CXRulesFor(gFront);
    BOOL wants = NO;
    for (NSDictionary *r in rules) if ([r[@"reevaluate"] boolValue]) { wants = YES; break; }
    if (!wants) return;

    NSMutableArray *nowMatching = [NSMutableArray array];
    for (NSDictionary *r in rules) {
        NSMutableArray *ignored = [NSMutableArray array];
        if (CXRuleMatches(r, ignored)) [nowMatching addObject:r[@"id"] ?: @""];
    }
    if ([nowMatching isEqualToArray:gAppliedRules ?: @[]]) return;
    CXLog(@"%@，重新判断 %@", why, gFront);
    CXRestore(@"条件变化");
    CXApply(gFront, @"重新判断");
}

static void CXCheckEnvironment(void) {
    NSString *ssid = CXCurrentSSID();
    BOOL charging = CXIsCharging();
    BOOL wifiChanged = !((ssid == gLastSSID) || [ssid isEqualToString:gLastSSID]);
    BOOL chargeChanged = charging != gLastCharging;
    if (wifiChanged) {
        CXLog(@"网络变化：%@ → %@", gLastSSID ?: @"未连接", ssid ?: @"未连接");
        CXSet(CXK_LAST_SSID, ssid ?: @"");
    }
    if (chargeChanged) CXLog(@"%@", charging ? @"开始充电" : @"停止充电");
    gLastSSID = ssid;
    gLastCharging = charging;
    if (wifiChanged || chargeChanged) CXReevaluate(wifiChanged ? @"网络变化" : @"充电状态变化");
}

#pragma mark - 设置页发来的请求

static void CXHandlePrefsChanged(void) {
    CXSync();
    // 关掉总开关：立即恢复正在生效的动作
    if (!CXEnabled() && gSnapshot.count) CXRestore(@"ControlX 已停用");
}

static void CXHandleSelfTest(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *type in CXActionTypes()) {
        NSString *line;
        @try {
            NSNumber *v = CXActionGet(type);
            if (v && (CXActionIsWhileInApp(type) || CXActionIsOneShot(type))) line = @"可用";
            else if (v) line = [NSString stringWithFormat:@"可用 · 当前 %@", CXActionValueText(@{ @"type": type, @"value": v })];
            else line = CXActionAvailable(type) ? @"可用" : @"不可用";
        } @catch (NSException *e) {
            line = [NSString stringWithFormat:@"不可用（异常 %@）", e.reason];
        }
        NSString *note = CXActionNote(type);
        out[type] = note.length ? [NSString stringWithFormat:@"%@\n      %@", line, note] : line;
    }
    out[@"_at"] = CXNow();
    out[@"_system"] = [NSString stringWithFormat:@"iOS %@", UIDevice.currentDevice.systemVersion];
    CXSet(CXK_SELFTEST, out);
    CXLog(@"动作自检完成");
    notify_post(CX_NOTIFY_RESULT);
}

static void CXHandleDryRun(void) {
    CXSync();
    NSString *rid = CXGet(CXK_DRYRUN_RULE);
    NSDictionary *rule = nil;
    for (NSDictionary *r in CXGet(CXK_RULES)) if ([r[@"id"] isEqual:rid]) { rule = r; break; }
    NSString *result;
    if (!rule) {
        result = @"找不到这条规则";
    } else {
        NSMutableArray *lines = [NSMutableArray array];
        BOOL ok = CXRuleMatches(rule, lines);
        NSMutableArray *acts = [NSMutableArray array];
        for (NSDictionary *a in rule[@"actions"]) [acts addObject:[NSString stringWithFormat:@"%@ %@", CXActionName(a[@"type"]), CXActionValueText(a)]];
        result = [NSString stringWithFormat:@"%@\n\n%@", [lines componentsJoinedByString:@"\n"],
                  ok ? [NSString stringWithFormat:@"→ 现在打开会执行：%@", acts.count ? [acts componentsJoinedByString:@" · "] : @"（没有动作）"]
                     : @"→ 现在打开不会执行"];
        result = [result stringByReplacingOccurrencesOfString:@"    " withString:@""];
    }
    CXSet(CXK_DRYRUN_OUT, result);
    notify_post(CX_NOTIFY_RESULT);
}

static void CXHandleDiagnose(void) {
    CXSet(CXK_DIAG, CXDiagnose());
    CXLog(@"系统接口诊断完成");
    notify_post(CX_NOTIFY_RESULT);
}

static void CXHandlePreview(void) {
    CXSync();
    NSDictionary *a = CXGet(CXK_PREVIEW);
    if (![a isKindOfClass:NSDictionary.class]) return;
    NSString *how = nil;
    BOOL ok = CXActionSet(a[@"type"], a[@"value"], &how);
    CXLog(@"试一下：%@ %@%@（%@）", CXActionName(a[@"type"]), CXActionValueText(a), ok ? @"" : @" 失败", how ?: @"无可用接口");
}

static void CXDarwin(CFNotificationCenterRef c, void *o, CFStringRef name, const void *obj, CFDictionaryRef info) {
    NSString *n = (__bridge NSString *)name;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([n isEqualToString:@CX_NOTIFY_PREFS]) CXHandlePrefsChanged();
        else if ([n isEqualToString:@CX_NOTIFY_SELFTEST]) CXHandleSelfTest();
        else if ([n isEqualToString:@CX_NOTIFY_DRYRUN]) CXHandleDryRun();
        else if ([n isEqualToString:@CX_NOTIFY_PREVIEW]) CXHandlePreview();
        else if ([n isEqualToString:@CX_NOTIFY_DIAG]) CXHandleDiagnose();
        else {
            // 网络变化：Wi-Fi 名称可能稍晚才更新，3 秒后再查一次
            CXCheckEnvironment();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ CXCheckEnvironment(); });
        }
    });
}

#pragma mark - 迁移

// 0.4.0 之前的测试版用的是占位包名，把那时保存的规则搬过来（只搬一次，旧数据不删）
static void CXMigrateOldDomain(void) {
    CFStringRef old = CFSTR("com.example.controlx");
    if (CXGet(CXK_RULES)) return;
    NSArray *keys = CFBridgingRelease(CFPreferencesCopyKeyList(old, kCFPreferencesCurrentUser, kCFPreferencesAnyHost));
    if (!keys.count) return;
    for (NSString *k in keys) {
        id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)k, old));
        if (v) CXSet(k, v);
    }
    CXLog(@"已从旧版本迁移 %lu 项设置", (unsigned long)keys.count);
}

#pragma mark - 钩子

static NSTimer *gTimer;

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)app {
    %orig;
    CXMigrateOldDomain();
    CXBlocksInstall();
    gSnapshot = [NSMutableDictionary dictionary];
    CFNotificationCenterRef d = CFNotificationCenterGetDarwinNotifyCenter();
    for (NSString *n in @[ @CX_NOTIFY_PREFS, @CX_NOTIFY_SELFTEST, @CX_NOTIFY_DRYRUN, @CX_NOTIFY_PREVIEW, @CX_NOTIFY_DIAG,
                           @"com.apple.system.config.network_change" ])
        CFNotificationCenterAddObserver(d, NULL, CXDarwin, (__bridge CFStringRef)n, NULL, CFNotificationSuspensionBehaviorCoalesce);

    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *n) { CXCheckEnvironment(); }];
    // 时间段条件、以及漏掉的通知：每 60 秒兜底检查一次
    gTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *t) {
        CXCheckEnvironment();
        CXReevaluate(@"定时检查");
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        gLastSSID = CXCurrentSSID();
        gLastCharging = CXIsCharging();
        CXSet(CXK_LAST_SSID, gLastSSID ?: @"");
        CXLog(@"ControlX 已启动（iOS %@）", UIDevice.currentDevice.systemVersion);
    });
}

// 前台 App 变化：display 为 nil 表示回到主屏幕
- (void)frontDisplayDidChange:(id)display {
    %orig;
    NSString *bid = [display respondsToSelector:@selector(bundleIdentifier)] ? [display bundleIdentifier] : nil;
    CXFrontChanged(bid);
}

%end
