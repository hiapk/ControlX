// ControlX 共享定义：SpringBoard 插件和设置页共用。
//
// 规则模型（存在偏好设置 CX_DOMAIN 的 "rules" 键里，数组）：
// {
//   id: "UUID", name: "Telegram 夜间模式", enabled: true,
//   apps: ["ph.telegra.Telegraph"],                     // 当：打开这些 App 时
//   match: "all" | "any",                                // 如果：条件组合方式
//   conditions: [
//     { type: "wifi", op: "is" | "isNot", ssid: "Home-5G" },
//     { type: "charging", is: true },
//     { type: "time", start: 1320, end: 420, days: "everyday" | "weekdays" | "weekend" }  // 分钟
//   ],
//   actions: [                                           // 就：执行这些动作
//     { type: "volume" | "brightness", value: 0...100, restore: true },
//     { type: "wifi" | "bluetooth" | "lowPower" | "darkMode" | "rotationLock" | "mute", value: true, restore: true }
//   ],
//   reevaluate: false                                    // App 还开着时条件变化，是否重新判断
// }
#pragma once
#import <Foundation/Foundation.h>

#define CX_DOMAIN            @"com.hiapk.controlx"

// 设置页 -> SpringBoard
#define CX_NOTIFY_PREFS      "com.hiapk.controlx/prefs"     // 规则或总开关变化
#define CX_NOTIFY_SELFTEST   "com.hiapk.controlx/selftest"  // 动作自检（只读）
#define CX_NOTIFY_DRYRUN     "com.hiapk.controlx/dryrun"    // 规则试运行：只判断条件，不执行
#define CX_NOTIFY_PREVIEW    "com.hiapk.controlx/preview"   // 立即执行一个动作
// SpringBoard -> 设置页
#define CX_NOTIFY_DIAG       "com.hiapk.controlx/diagnose"  // 系统接口诊断（只读）
#define CX_NOTIFY_RESULT     "com.hiapk.controlx/result"    // 自检 / 试运行结果已写入

// 偏好设置里的键
#define CXK_ENABLED      @"enabled"        // BOOL 总开关
#define CXK_RULES        @"rules"          // NSArray 规则
#define CXK_LOG          @"log"            // NSArray<NSString> 运行日志（最新在后）
#define CXK_LAST_RUN     @"lastRun"        // NSString 最近一次执行摘要
#define CXK_LAST_SSID    @"lastSSID"       // NSString 当前 Wi-Fi，给设置页「填入当前 Wi-Fi」用
#define CXK_SELFTEST     @"selfTest"       // NSDictionary type -> 结果字符串
#define CXK_DRYRUN_RULE  @"dryRunRule"     // NSString 要试运行的规则 id
#define CXK_DRYRUN_OUT   @"dryRunResult"   // NSString 试运行结果
#define CXK_PREVIEW      @"previewAction"  // NSDictionary 要立即执行的动作
#define CXK_DIAG         @"diagnose"       // NSString 系统接口诊断结果

#define CX_LOG_MAX 120

static inline id CXGet(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)CX_DOMAIN));
}

static inline void CXSet(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)CX_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)CX_DOMAIN);
}

static inline void CXSync(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)CX_DOMAIN);
}

#pragma mark - 动作与条件的元数据

static inline NSArray<NSString *> *CXActionTypes(void) {
    return @[ @"volume", @"brightness", @"autoBrightness",
              @"wifi", @"cellular", @"bluetooth", @"airplane", @"vpn", @"location",
              @"dnd", @"lowPower", @"darkMode", @"nightShift", @"reduceWhitePoint", @"invertColors",
              @"rotationLock", @"mute", @"music",
              @"hideHomeBar", @"noControlCenter", @"noNotificationCenter", @"noBanners", @"noLowPowerAlert", @"noReachability", @"noHomeGesture",
              @"killApps" ];
}

static inline BOOL CXActionIsLevel(NSString *type) {
    return [type isEqualToString:@"volume"] || [type isEqualToString:@"brightness"];
}

static inline NSString *CXActionName(NSString *type) {
    NSDictionary *names = @{ @"volume": @"音量", @"brightness": @"亮度", @"autoBrightness": @"自动亮度",
                             @"wifi": @"Wi-Fi", @"cellular": @"蜂窝数据", @"bluetooth": @"蓝牙", @"airplane": @"飞行模式",
                             @"vpn": @"VPN", @"location": @"定位服务", @"dnd": @"勿扰模式",
                             @"lowPower": @"低电量模式", @"darkMode": @"深色模式", @"nightShift": @"夜览",
                             @"reduceWhitePoint": @"降低白点值", @"invertColors": @"智能反转颜色",
                             @"rotationLock": @"方向锁定", @"mute": @"静音", @"music": @"音乐播放",
                             @"hideHomeBar": @"隐藏手势横条", @"noControlCenter": @"禁用控制中心", @"noNotificationCenter": @"禁用通知中心",
                             @"noBanners": @"隐藏通知横幅", @"noLowPowerAlert": @"隐藏低电量弹窗", @"noReachability": @"禁用便捷访问", @"noHomeGesture": @"禁用 Home 手势",
                             @"killApps": @"清理后台 App" };
    return names[type] ?: type;
}

// 「使用期间」类动作：只在这个 App 里生效，离开时一定解除（拦截控制中心、隐藏横条等）
static inline BOOL CXActionIsWhileInApp(NSString *type) {
    return [@[ @"hideHomeBar", @"noControlCenter", @"noNotificationCenter", @"noBanners", @"noLowPowerAlert", @"noReachability", @"noHomeGesture" ] containsObject:type];
}

// 一次性动作：没有开关值，打开 App 时执行一次
static inline BOOL CXActionIsOneShot(NSString *type) {
    return [type isEqualToString:@"killApps"];
}

// 能读取当前状态的动作才能「离开时恢复」；音乐只能发播放/暂停指令
static inline BOOL CXActionCanRestore(NSString *type) {
    return ![type isEqualToString:@"music"] && !CXActionIsOneShot(type);
}

// 离开 App 时是否会还原
static inline BOOL CXActionWillRestore(NSDictionary *action) {
    NSString *t = action[@"type"];
    return CXActionIsWhileInApp(t) || ([action[@"restore"] boolValue] && CXActionCanRestore(t));
}

static inline NSArray<NSString *> *CXConditionTypes(void) {
    return @[ @"wifi", @"charging", @"time" ];
}

static inline NSString *CXConditionName(NSString *type) {
    NSDictionary *names = @{ @"wifi": @"Wi-Fi", @"charging": @"充电", @"time": @"时间段" };
    return names[type] ?: type;
}

static inline NSString *CXActionValueText(NSDictionary *action) {
    id v = action[@"value"];
    if (CXActionIsLevel(action[@"type"])) return [NSString stringWithFormat:@"%ld%%", (long)[v integerValue]];
    if ([action[@"type"] isEqualToString:@"music"]) return [v boolValue] ? @"播放" : @"暂停";
    if (CXActionIsWhileInApp(action[@"type"])) return [v boolValue] ? @"使用期间" : @"不拦截";
    if (CXActionIsOneShot(action[@"type"])) return @"执行一次";
    return [v boolValue] ? @"打开" : @"关闭";
}

static inline NSString *CXMinutesText(NSInteger m) {
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(m / 60), (long)(m % 60)];
}

static inline NSString *CXDaysText(NSString *days) {
    if ([days isEqualToString:@"weekdays"]) return @"工作日";
    if ([days isEqualToString:@"weekend"]) return @"周末";
    return @"每天";
}

static inline NSString *CXConditionText(NSDictionary *c) {
    NSString *type = c[@"type"];
    if ([type isEqualToString:@"wifi"]) {
        NSString *ssid = [c[@"ssid"] length] ? c[@"ssid"] : @"未填写";
        return [NSString stringWithFormat:@"Wi-Fi %@「%@」", [c[@"op"] isEqualToString:@"isNot"] ? @"不是" : @"是", ssid];
    }
    if ([type isEqualToString:@"charging"]) return [c[@"is"] boolValue] ? @"正在充电" : @"没有在充电";
    if ([type isEqualToString:@"time"])
        return [NSString stringWithFormat:@"%@–%@ · %@", CXMinutesText([c[@"start"] integerValue]),
                CXMinutesText([c[@"end"] integerValue]), CXDaysText(c[@"days"])];
    return type;
}

#pragma mark - 时间段判断（插件与单元测试共用）

// days: everyday / weekdays（周一至周五）/ weekend；weekday: 1=周日 ... 7=周六
static inline BOOL CXDayMatches(NSString *days, NSInteger weekday) {
    if ([days isEqualToString:@"weekdays"]) return weekday >= 2 && weekday <= 6;
    if ([days isEqualToString:@"weekend"]) return weekday == 1 || weekday == 7;
    return YES;
}

// 结束早于开始表示跨夜，跨夜时段归属于开始的那一天
static inline BOOL CXTimeInWindow(NSInteger start, NSInteger end, NSString *days, NSInteger nowMin, NSInteger today) {
    if (start < 0 || end < 0 || start >= 1440 || end >= 1440 || start == end) return NO;
    NSInteger yesterday = today == 1 ? 7 : today - 1;
    if (start < end) return CXDayMatches(days, today) && nowMin >= start && nowMin < end;
    if (nowMin >= start) return CXDayMatches(days, today);
    if (nowMin < end) return CXDayMatches(days, yesterday);
    return NO;
}
