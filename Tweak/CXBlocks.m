#import "CXBlocks.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <dlfcn.h>

#pragma mark - 标记与钩子登记

static NSMutableSet<NSString *> *gActive;                         // 正在拦截的类型
static NSMutableDictionary<NSString *, NSMutableArray *> *gHooked; // 类型 -> 已装上的钩子

static BOOL Blocked(NSString *type) { return [gActive containsObject:type]; }

static BOOL CXHook(NSString *type, NSString *cls, NSString *sel, IMP imp, IMP *orig) {
    Class c = NSClassFromString(cls);
    SEL s = NSSelectorFromString(sel);
    if (!c || !class_getInstanceMethod(c, s)) return NO;
    MSHookMessageEx(c, s, imp, orig);
    if (!gHooked[type]) gHooked[type] = [NSMutableArray array];
    [gHooked[type] addObject:[NSString stringWithFormat:@"%@ %@", cls, sel]];
    return YES;
}

static id CXCall(id obj, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    return [obj respondsToSelector:s] ? ((id (*)(id, SEL))objc_msgSend)(obj, s) : nil;
}

static BOOL CXCallBool(id obj, NSString *sel, BOOL fallback) {
    SEL s = NSSelectorFromString(sel);
    return [obj respondsToSelector:s] ? ((BOOL (*)(id, SEL))objc_msgSend)(obj, s) : fallback;
}

static id CXSharedOf(NSString *cls) {
    Class c = NSClassFromString(cls);
    for (NSString *sel in @[ @"sharedInstance", @"sharedInstanceIfExists", @"sharedService" ]) {
        id o = CXCall(c, sel);
        if (o) return o;
    }
    return nil;
}

// 锁屏时一律不拦截，避免影响解锁、锁屏通知
static BOOL CXDeviceLocked(void) {
    id m = CXSharedOf(@"SBLockScreenManager");
    return CXCallBool(m, @"isUILocked", YES); // 读不到时按「已锁」处理，宁可不拦
}

#pragma mark - 禁用控制中心

static BOOL (*orig_ccShouldAllow)(id, SEL);
static BOOL hook_ccShouldAllow(id self, SEL _cmd) {
    if (Blocked(@"noControlCenter") && !CXDeviceLocked()) return NO;
    return orig_ccShouldAllow(self, _cmd);
}

static void (*orig_ccPresent)(id, SEL, BOOL);
static void hook_ccPresent(id self, SEL _cmd, BOOL animated) {
    if (Blocked(@"noControlCenter") && !CXDeviceLocked()) return;
    orig_ccPresent(self, _cmd, animated);
}

static void (*orig_ccPresentC)(id, SEL, BOOL, id);
static void hook_ccPresentC(id self, SEL _cmd, BOOL animated, id completion) {
    if (Blocked(@"noControlCenter") && !CXDeviceLocked()) return;
    orig_ccPresentC(self, _cmd, animated, completion);
}

// 下面几个只在控制中心「没打开」时拦，已打开时不拦，保证能收回去
static BOOL CXCCBlockNow(id cc) {
    return Blocked(@"noControlCenter") && !CXDeviceLocked() && !CXCallBool(cc, @"isPresentedOrDismissing", YES);
}

static BOOL (*orig_ccGestureBegin)(id, SEL, id);
static BOOL hook_ccGestureBegin(id self, SEL _cmd, id recognizer) {
    if (CXCCBlockNow(self)) return NO;
    return orig_ccGestureBegin(self, _cmd, recognizer);
}

static BOOL (*orig_ccTongueEnabled)(id, SEL, id, id);
static BOOL hook_ccTongueEnabled(id self, SEL _cmd, id tongue, id recognizer) {
    if (CXCCBlockNow(self)) return NO;
    return orig_ccTongueEnabled(self, _cmd, tongue, recognizer);
}

static void (*orig_ccStatusBarPull)(id, SEL, id);
static void hook_ccStatusBarPull(id self, SEL _cmd, id recognizer) {
    if (CXCCBlockNow(self)) return;
    orig_ccStatusBarPull(self, _cmd, recognizer);
}

#pragma mark - 禁用通知中心（只拦「下拉打开」的手势；已经打开时不拦，保证能收回去）

static BOOL CXCoverSheetShown(void) {
    id m = CXSharedOf(@"SBCoverSheetPresentationManager");
    for (NSString *sel in @[ @"isPresented", @"isVisible" ])
        if ([m respondsToSelector:NSSelectorFromString(sel)]) return CXCallBool(m, sel, YES);
    return YES; // 判断不了就当作已打开，不拦
}

static BOOL CXNCBlockNow(void) {
    return Blocked(@"noNotificationCenter") && !CXDeviceLocked() && !CXCoverSheetShown();
}

// 只有「打开」用的手势才拦，收起 / 解锁用的手势完全不碰
static BOOL (*orig_csShouldBegin)(id, SEL, id);
static BOOL hook_csShouldBegin(id self, SEL _cmd, id recognizer) {
    if (CXNCBlockNow() && recognizer &&
        (recognizer == CXCall(self, @"presentGestureRecognizer") || recognizer == CXCall(self, @"indirectPresentGestureRecognizer")))
        return NO;
    return orig_csShouldBegin(self, _cmd, recognizer);
}

static BOOL (*orig_csCanPresent)(id, SEL);
static BOOL hook_csCanPresent(id self, SEL _cmd) {
    if (CXNCBlockNow()) return NO;
    return orig_csCanPresent(self, _cmd);
}

static BOOL (*orig_csPresentAllowed)(id, SEL);
static BOOL hook_csPresentAllowed(id self, SEL _cmd) {
    if (CXNCBlockNow()) return NO;
    return orig_csPresentAllowed(self, _cmd);
}

#pragma mark - 隐藏通知横幅（通知仍会进通知中心）

static BOOL (*orig_bannerCanReceive)(id, SEL, id);
static BOOL hook_bannerCanReceive(id self, SEL _cmd, id request) {
    if (Blocked(@"noBanners") && !CXDeviceLocked()) return NO;
    return orig_bannerCanReceive(self, _cmd, request);
}

static void (*orig_bannerPost)(id, SEL, id);
static void hook_bannerPost(id self, SEL _cmd, id request) {
    if (Blocked(@"noBanners") && !CXDeviceLocked()) return;
    orig_bannerPost(self, _cmd, request);
}

#pragma mark - 隐藏低电量弹窗

static BOOL CXIsLowPowerAlert(id item) {
    Class c = NSClassFromString(@"SBLowPowerAlertItem");
    return c && [item isKindOfClass:c];
}

static void (*orig_alertActivate)(id, SEL, id);
static void hook_alertActivate(id self, SEL _cmd, id item) {
    if (Blocked(@"noLowPowerAlert") && CXIsLowPowerAlert(item)) return;
    orig_alertActivate(self, _cmd, item);
}

static void (*orig_alertActivateA)(id, SEL, id, BOOL);
static void hook_alertActivateA(id self, SEL _cmd, id item, BOOL animated) {
    if (Blocked(@"noLowPowerAlert") && CXIsLowPowerAlert(item)) return;
    orig_alertActivateA(self, _cmd, item, animated);
}

#pragma mark - 禁用便捷访问

static void (*orig_reachToggle)(id, SEL);
static void hook_reachToggle(id self, SEL _cmd) {
    if (Blocked(@"noReachability")) return;
    orig_reachToggle(self, _cmd);
}

static void (*orig_reachToggleObs)(id, SEL, id);
static void hook_reachToggleObs(id self, SEL _cmd, id observer) {
    if (Blocked(@"noReachability")) return;
    orig_reachToggleObs(self, _cmd, observer);
}

static void (*orig_reachToggleMode)(id, SEL);
static void hook_reachToggleMode(id self, SEL _cmd) {
    if (Blocked(@"noReachability") && !CXCallBool(self, @"reachabilityModeActive", NO)) return;
    orig_reachToggleMode(self, _cmd);
}

static void (*orig_reachActivate)(id, SEL, id);
static void hook_reachActivate(id self, SEL _cmd, id arg) {
    if (Blocked(@"noReachability")) return;
    orig_reachActivate(self, _cmd, arg);
}

static BOOL (*orig_reachCan)(id, SEL);
static BOOL hook_reachCan(id self, SEL _cmd) {
    if (Blocked(@"noReachability")) return NO;
    return orig_reachCan(self, _cmd);
}

static void CXReachabilityApply(BOOL disable) {
    id m = CXSharedOf(@"SBReachabilityManager");
    SEL s = NSSelectorFromString(@"setReachabilityTemporarilyDisabled:forReason:");
    if ([m respondsToSelector:s]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(m, s, disable, @"ControlX");
}

#pragma mark - 隐藏手势横条

static NSHashTable *gPills;
static const void *kCXHidPill = &kCXHidPill;

static void CXPillApply(UIView *pill) {
    BOOL hide = Blocked(@"hideHomeBar");
    BOOL hidByUs = [objc_getAssociatedObject(pill, kCXHidPill) boolValue];
    if (hide && !hidByUs) {
        objc_setAssociatedObject(pill, kCXHidPill, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        pill.alpha = 0;
    } else if (hide) {
        if (pill.alpha != 0) pill.alpha = 0; // 系统动画可能把它改回来
    } else if (hidByUs) {
        objc_setAssociatedObject(pill, kCXHidPill, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        pill.alpha = 1;
    }
}

static void (*orig_pillLayout)(id, SEL);
static void hook_pillLayout(UIView *self, SEL _cmd) {
    orig_pillLayout(self, _cmd);
    [gPills addObject:self];
    CXPillApply(self);
}

static void (*orig_pillMove)(id, SEL);
static void hook_pillMove(UIView *self, SEL _cmd) {
    orig_pillMove(self, _cmd);
    [gPills addObject:self];
    CXPillApply(self);
}

#pragma mark - 禁用 Home 手势
//
// 逃生口：被拦下一次后，2 秒内再上划一次（新的一次触摸）就放行。
// 另外：锁屏、通知中心或控制中心打开时一律不拦。

static NSUInteger gTouchSeq;          // 每次新的触摸序列 +1
static NSUInteger gBlockedSeq;        // 上次被拦的触摸序列
static NSUInteger gAllowedSeq;        // 被放行的触摸序列（同一次滑动里后续询问都放行）
static CFAbsoluteTime gBlockedAt;     // 上次被拦的时间
static CFAbsoluteTime gLastTouchAt;   // 上次触摸开始的时间

static BOOL CXHomeGestureBlockNow(void) {
    if (!Blocked(@"noHomeGesture") || CXDeviceLocked() || CXCoverSheetShown()) return NO;
    if (CXCallBool(CXSharedOf(@"SBControlCenterController"), @"isPresentedOrDismissing", YES)) return NO;
    if (gTouchSeq == gAllowedSeq) return NO;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (gBlockedSeq && gTouchSeq != gBlockedSeq && now - gBlockedAt < 2.0) {
        gAllowedSeq = gTouchSeq; // 第二次上划：放行
        gBlockedSeq = 0;
        return NO;
    }
    gBlockedSeq = gTouchSeq;
    gBlockedAt = now;
    return YES;
}

// 可能有多个手势识别器同时收到同一次触摸，0.25 秒内的算同一次
static void (*orig_homeTouchesBegan)(id, SEL, id, id);
static void hook_homeTouchesBegan(id self, SEL _cmd, NSSet *touches, id event) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (now - gLastTouchAt > 0.25) gTouchSeq++;
    gLastTouchAt = now;
    orig_homeTouchesBegan(self, _cmd, touches, event);
}

static BOOL (*orig_homeShouldBegin)(id, SEL);
static BOOL hook_homeShouldBegin(id self, SEL _cmd) {
    BOOL ok = orig_homeShouldBegin(self, _cmd);
    if (ok && CXHomeGestureBlockNow()) return NO;
    return ok;
}

#pragma mark - 安装

void CXBlocksInstall(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    gActive = [NSMutableSet set];
    gHooked = [NSMutableDictionary dictionary];
    gPills = [NSHashTable weakObjectsHashTable];

    CXHook(@"noControlCenter", @"SBControlCenterController", @"_shouldAllowControlCenterGesture", (IMP)hook_ccShouldAllow, (IMP *)&orig_ccShouldAllow);
    CXHook(@"noControlCenter", @"SBControlCenterController", @"presentAnimated:", (IMP)hook_ccPresent, (IMP *)&orig_ccPresent);
    CXHook(@"noControlCenter", @"SBControlCenterController", @"presentAnimated:completion:", (IMP)hook_ccPresentC, (IMP *)&orig_ccPresentC);

    CXHook(@"noControlCenter", @"SBControlCenterController", @"gestureRecognizerShouldBegin:", (IMP)hook_ccGestureBegin, (IMP *)&orig_ccGestureBegin);
    CXHook(@"noControlCenter", @"SBControlCenterController", @"grabberTongueOrPullEnabled:forGestureRecognizer:", (IMP)hook_ccTongueEnabled, (IMP *)&orig_ccTongueEnabled);
    CXHook(@"noControlCenter", @"SBControlCenterController", @"_handleStatusBarPullDownGesture:", (IMP)hook_ccStatusBarPull, (IMP *)&orig_ccStatusBarPull);

    CXHook(@"noNotificationCenter", @"SBCoverSheetSystemGesturesDelegate", @"gestureRecognizerShouldBegin:", (IMP)hook_csShouldBegin, (IMP *)&orig_csShouldBegin);
    CXHook(@"noNotificationCenter", @"SBCoverSheetSystemGesturesDelegate", @"_canPresentGestureBegin", (IMP)hook_csCanPresent, (IMP *)&orig_csCanPresent);
    CXHook(@"noNotificationCenter", @"SBCoverSheetSystemGesturesDelegate", @"isPresentGestureAllowedToBegin", (IMP)hook_csPresentAllowed, (IMP *)&orig_csPresentAllowed);

    CXHook(@"noBanners", @"SBNotificationBannerDestination", @"canReceiveNotificationRequest:", (IMP)hook_bannerCanReceive, (IMP *)&orig_bannerCanReceive);
    CXHook(@"noBanners", @"SBNotificationBannerDestination", @"postNotificationRequest:", (IMP)hook_bannerPost, (IMP *)&orig_bannerPost);

    CXHook(@"noLowPowerAlert", @"SBAlertItemsController", @"activateAlertItem:", (IMP)hook_alertActivate, (IMP *)&orig_alertActivate);
    CXHook(@"noLowPowerAlert", @"SBAlertItemsController", @"activateAlertItem:animated:", (IMP)hook_alertActivateA, (IMP *)&orig_alertActivateA);

    CXHook(@"noReachability", @"SBReachabilityManager", @"toggleReachability", (IMP)hook_reachToggle, (IMP *)&orig_reachToggle);
    CXHook(@"noReachability", @"SBReachabilityManager", @"_toggleReachabilityModeWithRequestingObserver:", (IMP)hook_reachToggleObs, (IMP *)&orig_reachToggleObs);
    CXHook(@"noReachability", @"SBReachabilityManager", @"_toggleReachabilityMode", (IMP)hook_reachToggleMode, (IMP *)&orig_reachToggleMode);
    CXHook(@"noReachability", @"SBReachabilityManager", @"_activateReachability:", (IMP)hook_reachActivate, (IMP *)&orig_reachActivate);
    CXHook(@"noReachability", @"SBReachabilityManager", @"canActivateReachability", (IMP)hook_reachCan, (IMP *)&orig_reachCan);
    if ([NSClassFromString(@"SBReachabilityManager") instancesRespondToSelector:NSSelectorFromString(@"setReachabilityTemporarilyDisabled:forReason:")]) {
        if (!gHooked[@"noReachability"]) gHooked[@"noReachability"] = [NSMutableArray array];
        [gHooked[@"noReachability"] addObject:@"SBReachabilityManager setReachabilityTemporarilyDisabled:forReason:（调用）"];
    }

    CXHook(@"hideHomeBar", @"MTLumaDodgePillView", @"layoutSubviews", (IMP)hook_pillLayout, (IMP *)&orig_pillLayout);
    CXHook(@"hideHomeBar", @"MTLumaDodgePillView", @"didMoveToWindow", (IMP)hook_pillMove, (IMP *)&orig_pillMove);

    // Home 手势：两个都装上才算可用（逃生口依赖 touchesBegan 计数）
    Class hg = NSClassFromString(@"SBHomeGesturePanGestureRecognizer");
    if (hg && class_getInstanceMethod(hg, NSSelectorFromString(@"_shouldBegin")) &&
        class_getInstanceMethod(hg, @selector(touchesBegan:withEvent:))) {
        CXHook(@"noHomeGesture", @"SBHomeGesturePanGestureRecognizer", @"touchesBegan:withEvent:", (IMP)hook_homeTouchesBegan, (IMP *)&orig_homeTouchesBegan);
        CXHook(@"noHomeGesture", @"SBHomeGesturePanGestureRecognizer", @"_shouldBegin", (IMP)hook_homeShouldBegin, (IMP *)&orig_homeShouldBegin);
    }
}

#pragma mark - 对外：标记

NSNumber *CXBlockGet(NSString *type) {
    if (!gHooked[type].count) return nil;
    return @(Blocked(type));
}

BOOL CXBlockSet(NSString *type, BOOL on, NSString **how) {
    if (!gHooked[type].count) { if (how) *how = @"本机上没有找到可用的接口"; return NO; }
    if (on) [gActive addObject:type]; else [gActive removeObject:type];
    if ([type isEqualToString:@"noReachability"]) CXReachabilityApply(on);
    if ([type isEqualToString:@"hideHomeBar"]) for (UIView *p in gPills.allObjects) CXPillApply(p);
    if (how) *how = [NSString stringWithFormat:@"拦截标记（%lu 个钩子）", (unsigned long)gHooked[type].count];
    return YES;
}

NSString *CXBlockNote(NSString *type) {
    NSArray *h = gHooked[type];
    return h.count ? [@"已挂上：" stringByAppendingString:[h componentsJoinedByString:@"；"]] : @"没有找到可用的系统接口";
}

#pragma mark - 清理后台 App

@interface CXFBSSystemService : NSObject
- (void)terminateApplication:(NSString *)bundleID forReason:(long long)reason andReport:(BOOL)report withDescription:(NSString *)desc;
@end

BOOL CXKillAppsAvailable(void) {
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
    id svc = CXCall(NSClassFromString(@"FBSSystemService"), @"sharedService");
    id apps = CXSharedOf(@"SBApplicationController");
    return [svc respondsToSelector:@selector(terminateApplication:forReason:andReport:withDescription:)] &&
           [apps respondsToSelector:NSSelectorFromString(@"runningApplications")];
}

BOOL CXKillApps(NSString **how) {
    if (!CXKillAppsAvailable()) { if (how) *how = @"本机上没有找到可用的接口"; return NO; }
    CXFBSSystemService *svc = CXCall(NSClassFromString(@"FBSSystemService"), @"sharedService");
    NSArray *running = CXCall(CXSharedOf(@"SBApplicationController"), @"runningApplications");

    NSMutableSet *keep = [NSMutableSet setWithObjects:@"com.apple.springboard", @"com.apple.InCallService", nil];
    if (CXFrontApp()) [keep addObject:CXFrontApp()];
    NSString *playing = CXCall(CXCall(CXSharedOf(@"SBMediaController"), @"nowPlayingApplication"), @"bundleIdentifier");
    if (playing) [keep addObject:playing];

    NSMutableArray *killed = [NSMutableArray array];
    for (id app in running) {
        NSString *bid = CXCall(app, @"bundleIdentifier");
        if (!bid || [keep containsObject:bid]) continue;
        [svc terminateApplication:bid forReason:1 andReport:NO withDescription:@"ControlX"];
        [killed addObject:bid];
    }
    // 多任务界面里的卡片也一起删掉
    id coord = CXSharedOf(@"SBMainSwitcherControllerCoordinator");
    SEL del = NSSelectorFromString(@"_deleteAppLayoutsMatchingBundleIdentifier:");
    BOOL cards = [coord respondsToSelector:del];
    if (cards) for (NSString *bid in killed) {
        @try { ((void (*)(id, SEL, id))objc_msgSend)(coord, del, bid); } @catch (NSException *e) { cards = NO; }
    }
    [keep removeObject:@"com.apple.springboard"];
    [keep removeObject:@"com.apple.InCallService"];
    if (how) *how = [NSString stringWithFormat:@"结束了 %lu 个%@，保留 %@", (unsigned long)killed.count, cards ? @"并删除卡片" : @"",
                     keep.count ? [keep.allObjects componentsJoinedByString:@"、"] : @"无"];
    return YES;
}

#pragma mark - 系统接口诊断

static NSArray *CXMethods(Class c, BOOL meta, NSArray *keywords) {
    NSMutableArray *out = [NSMutableArray array];
    unsigned int n = 0;
    Method *list = class_copyMethodList(meta ? object_getClass(c) : c, &n);
    for (unsigned int i = 0; i < n; i++) {
        NSString *name = NSStringFromSelector(method_getName(list[i]));
        BOOL hit = !keywords.count;
        for (NSString *k in keywords) if ([name rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) { hit = YES; break; }
        if (hit) [out addObject:[NSString stringWithFormat:@"%@ %@  %s", meta ? @"+" : @"-", name, method_getTypeEncoding(list[i]) ?: ""]];
    }
    free(list);
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

NSString *CXDiagnose(void) {
    NSArray *common = @[ @"shared", @"gesture", @"present", @"dismiss", @"allow", @"should", @"enable", @"disable", @"active", @"visible", @"locked" ];
    // 类名 -> 关键字（空数组 = 全部列出）
    NSArray *targets = @[
        @[ @"SBControlCenterController", common ],
        @[ @"SBControlCenterSystemAgent", common ],
        @[ @"SBCoverSheetPresentationManager", common ],
        @[ @"SBCoverSheetSystemGesturesDelegate", @[] ],
        @[ @"SBSystemGestureManager", @[ @"shared", @"allow", @"gesture", @"disable" ] ],
        @[ @"SBNotificationBannerDestination", @[ @"request", @"post", @"receive", @"present", @"suppress" ] ],
        @[ @"SBAlertItemsController", @[ @"shared", @"activate", @"alert" ] ],
        @[ @"SBReachabilityManager", @[] ],
        @[ @"MTLumaDodgePillView", @[] ],
        @[ @"SBHomeGrabberView", @[ @"hidden", @"hide", @"pill", @"visib", @"autoHide", @"layout" ] ],
        @[ @"SBHomeGestureSettings", @[] ],
        @[ @"SBHomeGesturePanGestureRecognizer", @[ @"init", @"should", @"begin", @"enable", @"touch" ] ],
        @[ @"SBMainSwitcherControllerCoordinator", @[ @"shared", @"remove", @"quit", @"kill", @"appLayout", @"switcher" ] ],
        @[ @"SBFluidSwitcherViewController", @[ @"remove", @"quit", @"kill", @"appLayouts" ] ],
        @[ @"SBApplicationController", @[ @"shared", @"running", @"application" ] ],
        @[ @"SBLockScreenManager", @[ @"shared", @"locked" ] ],
        @[ @"SBMediaController", @[ @"shared", @"nowPlaying", @"playing" ] ],
        @[ @"FBSSystemService", @[ @"shared", @"terminate" ] ],
        @[ @"UISUserInterfaceStyleArbiter", @[] ],
        @[ @"SBBrightnessController", @[] ],
    ];
    NSMutableString *s = [NSMutableString stringWithFormat:@"iOS %@ · %@\n", UIDevice.currentDevice.systemVersion, NSDate.date];
    [s appendString:@"\n【已挂上的钩子】\n"];
    for (NSString *t in [gHooked.allKeys sortedArrayUsingSelector:@selector(compare:)])
        [s appendFormat:@"%@：%@\n", t, [gHooked[t] componentsJoinedByString:@"；"]];
    for (NSArray *t in targets) {
        Class c = NSClassFromString(t[0]);
        if (!c) { [s appendFormat:@"\n【%@】不存在\n", t[0]]; continue; }
        Dl_info info = { 0 };
        dladdr((__bridge void *)c, &info);
        NSString *image = info.dli_fname ? [@(info.dli_fname) lastPathComponent] : @"?";
        [s appendFormat:@"\n【%@】%@ · 父类 %@\n", t[0], image, NSStringFromClass(class_getSuperclass(c))];
        NSArray *ms = [CXMethods(c, YES, t[1]) arrayByAddingObjectsFromArray:CXMethods(c, NO, t[1])];
        NSUInteger cap = 80;
        for (NSUInteger i = 0; i < MIN(ms.count, cap); i++) [s appendFormat:@"%@\n", ms[i]];
        if (ms.count > cap) [s appendFormat:@"…还有 %lu 个\n", (unsigned long)(ms.count - cap)];
    }
    return s;
}
