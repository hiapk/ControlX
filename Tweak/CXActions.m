#import "CXActions.h"
#import "CXBlocks.h"
#import "../Shared/CXShared.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

#pragma mark - 私有接口声明（只用于让编译器知道参数类型，调用前都会检查 respondsToSelector）

@interface SBWiFiManager : NSObject
+ (instancetype)sharedInstance;
- (NSString *)currentNetworkName;
- (BOOL)wiFiEnabled;
- (void)setWiFiEnabled:(BOOL)enabled;
@end

@interface SBVolumeControl : NSObject
+ (instancetype)sharedInstance;
- (float)_effectiveVolume;
- (void)setActiveCategoryVolume:(float)volume;
@end

@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (BOOL)getActiveCategoryVolume:(float *)volume andName:(NSString **)name;
- (BOOL)setActiveCategoryVolumeTo:(float)volume;
@end

@interface BluetoothManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)powered;
- (BOOL)enabled;
- (BOOL)setPowered:(BOOL)powered;
- (BOOL)setEnabled:(BOOL)enabled;
@end

@interface _CDBatterySaver : NSObject
+ (instancetype)batterySaver;
- (BOOL)setPowerMode:(long long)mode error:(NSError **)error;
- (long long)setMode:(long long)mode;
@end

@interface UISUserInterfaceStyleArbiter : NSObject
+ (instancetype)sharedInstance;
- (long long)currentStyle;
- (void)toggleCurrentStyle;
@end

@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUserLocked;
- (void)lock;
- (void)unlock;
@end

@interface SBRingerControl : NSObject
- (BOOL)isRingerMuted;
- (void)setRingerMuted:(BOOL)muted;
@end

@interface SpringBoard : UIApplication
- (SBRingerControl *)ringerControl;
@end

#pragma mark - 工具

static void CXLoadFramework(NSString *path) {
    static NSMutableSet *loaded;
    if (!loaded) loaded = [NSMutableSet set];
    if ([loaded containsObject:path]) return;
    [loaded addObject:path];
    dlopen(path.fileSystemRepresentation, RTLD_LAZY);
}

static id CXShared(NSString *className, SEL sel) {
    Class cls = NSClassFromString(className);
    if (![cls respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, sel);
}

static void CXHow(NSString **how, NSString *s) { if (how) *how = s; }

#pragma mark - Wi-Fi / 充电（条件也会用到）

NSString *CXCurrentSSID(void) {
    SBWiFiManager *m = CXShared(@"SBWiFiManager", @selector(sharedInstance));
    if (![m respondsToSelector:@selector(currentNetworkName)]) return nil;
    NSString *name = [m currentNetworkName];
    return name.length ? name : nil;
}

BOOL CXIsCharging(void) {
    UIDevice *d = UIDevice.currentDevice;
    if (!d.batteryMonitoringEnabled) d.batteryMonitoringEnabled = YES;
    return d.batteryState == UIDeviceBatteryStateCharging || d.batteryState == UIDeviceBatteryStateFull;
}

#pragma mark - 各动作

static NSNumber *VolumeGet(void) {
    CXLoadFramework(@"/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience");
    CXLoadFramework(@"/System/Library/PrivateFrameworks/Celestial.framework/Celestial");
    AVSystemController *av = CXShared(@"AVSystemController", @selector(sharedAVSystemController));
    if ([av respondsToSelector:@selector(getActiveCategoryVolume:andName:)]) {
        float v = 0; NSString *name = nil;
        if ([av getActiveCategoryVolume:&v andName:&name]) return @(lroundf(v * 100));
    }
    SBVolumeControl *vc = CXShared(@"SBVolumeControl", @selector(sharedInstance));
    if ([vc respondsToSelector:@selector(_effectiveVolume)]) return @(lroundf([vc _effectiveVolume] * 100));
    return nil;
}

static BOOL VolumeSet(NSInteger level, NSString **how) {
    float v = MAX(0, MIN(100, level)) / 100.0f;
    SBVolumeControl *vc = CXShared(@"SBVolumeControl", @selector(sharedInstance));
    if ([vc respondsToSelector:@selector(setActiveCategoryVolume:)]) {
        [vc setActiveCategoryVolume:v];
        CXHow(how, @"SBVolumeControl");
        return YES;
    }
    VolumeGet(); // 确保框架已加载
    AVSystemController *av = CXShared(@"AVSystemController", @selector(sharedAVSystemController));
    if ([av respondsToSelector:@selector(setActiveCategoryVolumeTo:)]) {
        CXHow(how, @"AVSystemController");
        return [av setActiveCategoryVolumeTo:v];
    }
    return NO;
}

static NSNumber *BrightnessGet(void) {
    return @(lround(UIScreen.mainScreen.brightness * 100));
}

@interface SBBrightnessController : NSObject
+ (instancetype)sharedBrightnessController;
- (void)setBrightnessLevel:(float)level;
@end

// 直接 BKSDisplayBrightnessSet 只是「临时亮度」，系统随后会拉回原值；
// 要么走 SpringBoard 自己的亮度控制器（和控制中心滑块同一路径），
// 要么包在 BKS 亮度事务里提交，才会被当成用户设置保存下来。
static BOOL BrightnessSet(NSInteger level, NSString **how) {
    float v = MAX(0, MIN(100, level)) / 100.0f;
    Class sb = NSClassFromString(@"SBBrightnessController");
    if ([sb respondsToSelector:@selector(sharedBrightnessController)]) {
        SBBrightnessController *c = [sb sharedBrightnessController];
        if ([c respondsToSelector:@selector(setBrightnessLevel:)]) {
            [c setBrightnessLevel:v];
            CXHow(how, @"SBBrightnessController");
            return YES;
        }
    }
    CXLoadFramework(@"/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices");
    void (*set)(float, int) = (void (*)(float, int))dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessSet");
    CFTypeRef (*begin)(CFAllocatorRef) = (CFTypeRef (*)(CFAllocatorRef))dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessTransactionCreate");
    if (set) {
        CFTypeRef t = begin ? begin(kCFAllocatorDefault) : NULL;
        set(v, 1);
        if (t) CFRelease(t);
        CXHow(how, t ? @"BKSDisplayBrightness 事务" : @"BKSDisplayBrightnessSet（可能被拉回）");
        return YES;
    }
    UIScreen.mainScreen.brightness = v;
    CXHow(how, @"UIScreen");
    return YES;
}

static NSNumber *WiFiGet(void) {
    SBWiFiManager *m = CXShared(@"SBWiFiManager", @selector(sharedInstance));
    return [m respondsToSelector:@selector(wiFiEnabled)] ? @([m wiFiEnabled]) : nil;
}

static BOOL WiFiSet(BOOL on, NSString **how) {
    SBWiFiManager *m = CXShared(@"SBWiFiManager", @selector(sharedInstance));
    if (![m respondsToSelector:@selector(setWiFiEnabled:)]) return NO;
    [m setWiFiEnabled:on];
    CXHow(how, @"SBWiFiManager");
    return YES;
}

static BluetoothManager *BT(void) {
    CXLoadFramework(@"/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager");
    return CXShared(@"BluetoothManager", @selector(sharedInstance));
}

static NSNumber *BluetoothGet(void) {
    BluetoothManager *bt = BT();
    if ([bt respondsToSelector:@selector(enabled)]) return @([bt enabled]);
    if ([bt respondsToSelector:@selector(powered)]) return @([bt powered]);
    return nil;
}

static BOOL BluetoothSet(BOOL on, NSString **how) {
    BluetoothManager *bt = BT();
    if (![bt respondsToSelector:@selector(setEnabled:)] && ![bt respondsToSelector:@selector(setPowered:)]) return NO;
    if ([bt respondsToSelector:@selector(setEnabled:)]) [bt setEnabled:on];
    if ([bt respondsToSelector:@selector(setPowered:)]) [bt setPowered:on];
    CXHow(how, @"BluetoothManager");
    return YES;
}

static NSNumber *LowPowerGet(void) {
    return @(NSProcessInfo.processInfo.isLowPowerModeEnabled);
}

static BOOL LowPowerSet(BOOL on, NSString **how) {
    CXLoadFramework(@"/System/Library/PrivateFrameworks/CoreDuet.framework/CoreDuet");
    _CDBatterySaver *saver = CXShared(@"_CDBatterySaver", @selector(batterySaver));
    if ([saver respondsToSelector:@selector(setPowerMode:error:)]) {
        CXHow(how, @"_CDBatterySaver.setPowerMode");
        return [saver setPowerMode:on ? 1 : 0 error:NULL];
    }
    if ([saver respondsToSelector:@selector(setMode:)]) {
        [saver setMode:on ? 1 : 0];
        CXHow(how, @"_CDBatterySaver.setMode");
        return YES;
    }
    return NO;
}

static UISUserInterfaceStyleArbiter *Arbiter(void) {
    CXLoadFramework(@"/System/Library/PrivateFrameworks/UIKitServices.framework/UIKitServices");
    return CXShared(@"UISUserInterfaceStyleArbiter", @selector(sharedInstance));
}

static NSNumber *DarkModeGet(void) {
    UISUserInterfaceStyleArbiter *a = Arbiter();
    if ([a respondsToSelector:@selector(currentStyle)]) return @([a currentStyle] == 2);
    // 读取的兜底：系统当前外观（只用于读，设置仍需要上面的接口）
    return @(UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
}

static BOOL DarkModeSet(BOOL on, NSString **how) {
    UISUserInterfaceStyleArbiter *a = Arbiter();
    if (!a) { CXHow(how, @"找不到 UISUserInterfaceStyleArbiter"); return NO; }
    BOOL dark = [a respondsToSelector:@selector(currentStyle)] ? [a currentStyle] == 2
                                                               : UIScreen.mainScreen.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    if (dark == on) { CXHow(how, @"已经是目标状态"); return YES; }
    if ([a respondsToSelector:@selector(toggleCurrentStyle)]) { [a toggleCurrentStyle]; CXHow(how, @"UISUserInterfaceStyleArbiter toggle"); return YES; }
    SEL setSel = NSSelectorFromString(@"setCurrentStyle:");
    if ([a respondsToSelector:setSel]) {
        ((void (*)(id, SEL, long long))objc_msgSend)(a, setSel, on ? 2 : 1);
        CXHow(how, @"UISUserInterfaceStyleArbiter setCurrentStyle");
        return YES;
    }
    CXHow(how, @"UISUserInterfaceStyleArbiter 没有可用的方法");
    return NO;
}

static NSNumber *RotationLockGet(void) {
    SBOrientationLockManager *m = CXShared(@"SBOrientationLockManager", @selector(sharedInstance));
    return [m respondsToSelector:@selector(isUserLocked)] ? @([m isUserLocked]) : nil;
}

static BOOL RotationLockSet(BOOL on, NSString **how) {
    SBOrientationLockManager *m = CXShared(@"SBOrientationLockManager", @selector(sharedInstance));
    if (![m respondsToSelector:@selector(lock)] || ![m respondsToSelector:@selector(unlock)]) return NO;
    if (on) [m lock]; else [m unlock];
    CXHow(how, @"SBOrientationLockManager");
    return YES;
}

static SBRingerControl *Ringer(void) {
    SpringBoard *sb = (SpringBoard *)UIApplication.sharedApplication;
    return [sb respondsToSelector:@selector(ringerControl)] ? [sb ringerControl] : nil;
}

static NSNumber *MuteGet(void) {
    SBRingerControl *r = Ringer();
    return [r respondsToSelector:@selector(isRingerMuted)] ? @([r isRingerMuted]) : nil;
}

static BOOL MuteSet(BOOL on, NSString **how) {
    SBRingerControl *r = Ringer();
    if (![r respondsToSelector:@selector(setRingerMuted:)]) return NO;
    [r setRingerMuted:on];
    CXHow(how, @"SBRingerControl");
    return YES;
}

#pragma mark - 飞行模式

@interface SBAirplaneModeController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isInAirplaneMode;
- (void)setInAirplaneMode:(BOOL)on;
@end

@interface RadiosPreferences : NSObject
- (BOOL)airplaneMode;
- (void)setAirplaneMode:(BOOL)on;
- (void)synchronize;
@end

static NSNumber *AirplaneGet(void) {
    SBAirplaneModeController *c = CXShared(@"SBAirplaneModeController", @selector(sharedInstance));
    if ([c respondsToSelector:@selector(isInAirplaneMode)]) return @([c isInAirplaneMode]);
    CXLoadFramework(@"/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport");
    RadiosPreferences *r = [NSClassFromString(@"RadiosPreferences") new];
    return [r respondsToSelector:@selector(airplaneMode)] ? @([r airplaneMode]) : nil;
}

static BOOL AirplaneSet(BOOL on, NSString **how) {
    SBAirplaneModeController *c = CXShared(@"SBAirplaneModeController", @selector(sharedInstance));
    if ([c respondsToSelector:@selector(setInAirplaneMode:)]) {
        [c setInAirplaneMode:on];
        CXHow(how, @"SBAirplaneModeController");
        return YES;
    }
    CXLoadFramework(@"/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport");
    RadiosPreferences *r = [NSClassFromString(@"RadiosPreferences") new];
    if (![r respondsToSelector:@selector(setAirplaneMode:)]) return NO;
    [r setAirplaneMode:on];
    if ([r respondsToSelector:@selector(synchronize)]) [r synchronize];
    CXHow(how, @"RadiosPreferences");
    return YES;
}

#pragma mark - 蜂窝数据

static void *CXSym(NSString *lib, const char *name) {
    if (lib) CXLoadFramework(lib);
    return dlsym(RTLD_DEFAULT, name);
}

#define CT_LIB @"/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony"

static NSNumber *CellularGet(void) {
    Boolean (*get)(void) = (Boolean (*)(void))CXSym(CT_LIB, "CTCellularDataPlanGetIsEnabled");
    return get ? @((BOOL)get()) : nil;
}

static BOOL CellularSet(BOOL on, NSString **how) {
    void (*set)(Boolean) = (void (*)(Boolean))CXSym(CT_LIB, "CTCellularDataPlanSetIsEnabled");
    if (!set) return NO;
    set(on);
    CXHow(how, @"CTCellularDataPlanSetIsEnabled");
    return YES;
}

#pragma mark - 定位服务

@interface CXLocationManager : NSObject   // 实际是 CLLocationManager，只借用方法声明
+ (BOOL)locationServicesEnabled;
+ (void)setLocationServicesEnabled:(BOOL)on;
@end

static Class CLM(void) {
    CXLoadFramework(@"/System/Library/Frameworks/CoreLocation.framework/CoreLocation");
    return NSClassFromString(@"CLLocationManager");
}

static NSNumber *LocationGet(void) {
    Class c = CLM();
    return [c respondsToSelector:@selector(locationServicesEnabled)] ? @([c locationServicesEnabled]) : nil;
}

static BOOL LocationSet(BOOL on, NSString **how) {
    Class c = CLM();
    if (![c respondsToSelector:@selector(setLocationServicesEnabled:)]) return NO;
    [c setLocationServicesEnabled:on];
    CXHow(how, @"CLLocationManager");
    return YES;
}

#pragma mark - 勿扰模式（iOS 15+ 专注框架，用和控制中心相同的客户端身份）

@interface DNDModeAssertionDetails : NSObject
+ (instancetype)userRequestedAssertionDetailsWithIdentifier:(NSString *)ident modeIdentifier:(NSString *)mode lifetime:(id)lifetime;
@end

@interface DNDModeAssertionService : NSObject
+ (instancetype)serviceForClientIdentifier:(NSString *)ident;
- (id)takeModeAssertionWithDetails:(id)details error:(NSError **)error;
- (BOOL)invalidateAllActiveModeAssertionsWithError:(NSError **)error;
@end

@interface DNDState : NSObject
- (BOOL)isActive;
@end

@interface DNDStateService : NSObject
+ (instancetype)serviceForClientIdentifier:(NSString *)ident;
- (DNDState *)queryCurrentStateWithError:(NSError **)error;
@end

#define DND_CLIENT @"com.apple.donotdisturb.control-center.module"

static NSNumber *DNDGet(void) {
    CXLoadFramework(@"/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb");
    Class c = NSClassFromString(@"DNDStateService");
    if (![c respondsToSelector:@selector(serviceForClientIdentifier:)]) return nil;
    DNDStateService *svc = [c serviceForClientIdentifier:DND_CLIENT];
    if (![svc respondsToSelector:@selector(queryCurrentStateWithError:)]) return nil;
    DNDState *st = [svc queryCurrentStateWithError:NULL];
    return [st respondsToSelector:@selector(isActive)] ? @([st isActive]) : nil;
}

static BOOL DNDSet(BOOL on, NSString **how) {
    CXLoadFramework(@"/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb");
    Class svcCls = NSClassFromString(@"DNDModeAssertionService");
    if (![svcCls respondsToSelector:@selector(serviceForClientIdentifier:)]) return NO;
    DNDModeAssertionService *svc = [svcCls serviceForClientIdentifier:DND_CLIENT];
    NSError *err = nil;
    if (on) {
        Class d = NSClassFromString(@"DNDModeAssertionDetails");
        if (![d respondsToSelector:@selector(userRequestedAssertionDetailsWithIdentifier:modeIdentifier:lifetime:)]) return NO;
        id details = [d userRequestedAssertionDetailsWithIdentifier:@"com.apple.control-center.manual-toggle"
                                                     modeIdentifier:@"com.apple.donotdisturb.mode.default" lifetime:nil];
        id a = [svc takeModeAssertionWithDetails:details error:&err];
        CXHow(how, err ? [NSString stringWithFormat:@"DNDModeAssertionService %@", err.localizedDescription] : @"DNDModeAssertionService");
        return a != nil;
    }
    BOOL ok = [svc invalidateAllActiveModeAssertionsWithError:&err];
    CXHow(how, err ? [NSString stringWithFormat:@"DNDModeAssertionService %@", err.localizedDescription] : @"DNDModeAssertionService");
    return ok;
}

#pragma mark - 夜览 / 自动亮度（CoreBrightness）

@interface CBBlueLightClient : NSObject
- (BOOL)getBlueLightStatus:(void *)status;
- (BOOL)setEnabled:(BOOL)on;
@end

@interface BrightnessSystemClient : NSObject
- (id)copyPropertyForKey:(NSString *)key;
- (BOOL)setProperty:(id)value forKey:(NSString *)key;
@end

#define CB_LIB @"/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

static CBBlueLightClient *BlueLight(void) {
    static CBBlueLightClient *c;
    if (!c) { CXLoadFramework(CB_LIB); c = [NSClassFromString(@"CBBlueLightClient") new]; }
    return c;
}

static NSNumber *NightShiftGet(void) {
    CBBlueLightClient *c = BlueLight();
    if (![c respondsToSelector:@selector(getBlueLightStatus:)]) return nil;
    // CBBlueLightStatus 开头两个字段：BOOL active; BOOL enabled; 后面还有日程等，留足空间
    unsigned char buf[128] = { 0 };
    if (![c getBlueLightStatus:buf]) return nil;
    return @(buf[1] != 0);
}

static BOOL NightShiftSet(BOOL on, NSString **how) {
    CBBlueLightClient *c = BlueLight();
    if (![c respondsToSelector:@selector(setEnabled:)]) return NO;
    CXHow(how, @"CBBlueLightClient");
    return [c setEnabled:on];
}

static BrightnessSystemClient *BrightnessClient(void) {
    static BrightnessSystemClient *c;
    if (!c) { CXLoadFramework(CB_LIB); c = [NSClassFromString(@"BrightnessSystemClient") new]; }
    return c;
}

static NSNumber *AutoBrightnessGet(void) {
    BrightnessSystemClient *c = BrightnessClient();
    if ([c respondsToSelector:@selector(copyPropertyForKey:)]) {
        id v = [c copyPropertyForKey:@"DisplayBrightnessAuto"];
        if ([v isKindOfClass:NSNumber.class]) return @([v boolValue]);
    }
    Boolean (*get)(void) = (Boolean (*)(void))CXSym(@"/usr/lib/libAccessibility.dylib", "_AXSAutoBrightnessEnabled");
    return get ? @((BOOL)get()) : nil;
}

static BOOL AutoBrightnessSet(BOOL on, NSString **how) {
    BrightnessSystemClient *c = BrightnessClient();
    if (![c respondsToSelector:@selector(setProperty:forKey:)]) return NO;
    CXHow(how, @"BrightnessSystemClient");
    return [c setProperty:@(on) forKey:@"DisplayBrightnessAuto"];
}

#pragma mark - 辅助功能：降低白点值 / 智能反转

#define AX_LIB @"/usr/lib/libAccessibility.dylib"

static NSNumber *AXGet(const char *getter) {
    Boolean (*get)(void) = (Boolean (*)(void))CXSym(AX_LIB, getter);
    return get ? @((BOOL)get()) : nil;
}

static BOOL AXSet(const char *setter, BOOL on, NSString **how) {
    void (*set)(Boolean) = (void (*)(Boolean))CXSym(AX_LIB, setter);
    if (!set) return NO;
    set(on);
    CXHow(how, [NSString stringWithUTF8String:setter]);
    return YES;
}

#pragma mark - 音乐（只能发指令，读不到状态）

#define MR_LIB @"/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"

static BOOL MusicAvailable(void) { return CXSym(MR_LIB, "MRMediaRemoteSendCommand") != NULL; }

static BOOL MusicSet(BOOL play, NSString **how) {
    Boolean (*send)(uint32_t, NSDictionary *) = (Boolean (*)(uint32_t, NSDictionary *))CXSym(MR_LIB, "MRMediaRemoteSendCommand");
    if (!send) return NO;
    CXHow(how, @"MRMediaRemoteSendCommand");
    return send(play ? 0 : 1, nil); // 0 = 播放，1 = 暂停
}

#pragma mark - VPN
//
// 操作的是「设置 → VPN」里当前选中的那个配置（Shadowrocket、Quantumult 等装的都算）。
// 1. 先读出所有 VPN 配置：优先 NEConfigurationManager，读不到再直接解析系统的配置文件
// 2. 用 ne_session 按配置的 UUID 连接 / 断开 / 查询状态

typedef void *ne_session_t;
typedef void (^ne_status_block)(int status);

@interface NEConfigurationManager : NSObject
+ (instancetype)sharedManager;
- (void)loadConfigurationsWithCompletionQueue:(dispatch_queue_t)queue handler:(void (^)(NSArray *configs, NSError *error))handler;
@end

static NSString *gVPNNote;          // 自检时显示：用的哪个配置、通过什么方式读到
static NSString *gVPNSource;        // 「通过 xx 读到 n 个网络配置」
static NSArray *gVPNConfigs;
static NSDate *gVPNConfigsAt;

static dispatch_queue_t VPNQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("controlx.vpn", DISPATCH_QUEUE_SERIAL); });
    return q;
}

static void CollectConfigs(id obj, NSMutableArray *out, int depth) {
    if (!obj || depth > 4) return;
    Class cfg = NSClassFromString(@"NEConfiguration");
    if (cfg && [obj isKindOfClass:cfg]) { [out addObject:obj]; return; }
    if ([obj isKindOfClass:NSDictionary.class]) for (id v in [obj allValues]) CollectConfigs(v, out, depth + 1);
    else if ([obj isKindOfClass:NSArray.class]) for (id v in obj) CollectConfigs(v, out, depth + 1);
}

static NSArray *VPNLoadConfigs(NSString **source) {
    CXLoadFramework(@"/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension");
    // 方式 1：NEConfigurationManager（异步，最多等 1 秒）
    NEConfigurationManager *m = CXShared(@"NEConfigurationManager", @selector(sharedManager));
    if ([m respondsToSelector:@selector(loadConfigurationsWithCompletionQueue:handler:)]) {
        __block NSArray *result = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [m loadConfigurationsWithCompletionQueue:VPNQueue() handler:^(NSArray *configs, NSError *error) {
            result = configs;
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)));
        if (result.count) { if (source) *source = @"NEConfigurationManager"; return result; }
    }
    // 方式 2：直接读系统保存的配置文件
    NSData *data = [NSData dataWithContentsOfFile:@"/var/preferences/com.apple.networkextension.plist"];
    if (data) {
        id root = nil;
        @try {
            NSKeyedUnarchiver *u = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:NULL];
            u.requiresSecureCoding = NO;
            root = [u decodeObjectForKey:NSKeyedArchiveRootObjectKey];
            [u finishDecoding];
        } @catch (NSException *e) {}
        NSMutableArray *out = [NSMutableArray array];
        CollectConfigs(root, out, 0);
        if (out.count) { if (source) *source = @"配置文件"; return out; }
    }
    return nil;
}

static id KVC(id obj, NSString *key) {
    @try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; }
}

// 找出「设置 → VPN」里选中的那个配置
static id VPNSelectedConfig(void) {
    if (!gVPNConfigs || -[gVPNConfigsAt timeIntervalSinceNow] > 30) {
        NSString *src = nil;
        NSArray *configs = VPNLoadConfigs(&src);
        if (configs) { gVPNConfigs = configs; gVPNConfigsAt = NSDate.date; }
        if (!configs) { gVPNNote = @"读不到 VPN 配置"; return nil; }
        gVPNSource = [NSString stringWithFormat:@"通过 %@ 读到 %lu 个网络配置", src, (unsigned long)configs.count];
    }
    gVPNNote = gVPNSource;
    id selected = nil, onlyOne = nil;
    NSUInteger vpnCount = 0;
    for (id c in gVPNConfigs) {
        id vpn = KVC(c, @"VPN");
        if (!vpn) continue;
        vpnCount++;
        onlyOne = c;
        if ([KVC(vpn, @"enabled") boolValue]) { selected = c; break; }
    }
    if (!selected && vpnCount == 1) selected = onlyOne;
    if (!selected) gVPNNote = vpnCount ? @"有 VPN 配置，但没有选中的（请到 设置 → VPN 选一个）" : @"没有找到 VPN 配置";
    return selected;
}

static ne_session_t VPNSession(id config) {
    static NSMutableDictionary *sessions;
    if (!sessions) sessions = [NSMutableDictionary dictionary];
    NSUUID *uuid = KVC(config, @"identifier");
    if (![uuid isKindOfClass:NSUUID.class]) return NULL;
    NSValue *cached = sessions[uuid.UUIDString];
    if (cached) return cached.pointerValue;
    ne_session_t (*create)(const unsigned char *, int) = (ne_session_t (*)(const unsigned char *, int))dlsym(RTLD_DEFAULT, "ne_session_create");
    if (!create) return NULL;
    uuid_t bytes;
    [uuid getUUIDBytes:bytes];
    ne_session_t s = create(bytes, 1); // 1 = VPN 类型
    if (s) sessions[uuid.UUIDString] = [NSValue valueWithPointer:s];
    return s;
}

// 返回 ne_session 状态：1 已断开 2 连接中 3 已连接 4 重连中 5 断开中；查不到返回 -1
static int VPNStatus(ne_session_t s) {
    void (*getStatus)(ne_session_t, dispatch_queue_t, ne_status_block) =
        (void (*)(ne_session_t, dispatch_queue_t, ne_status_block))dlsym(RTLD_DEFAULT, "ne_session_get_status");
    if (!s || !getStatus) return -1;
    __block int status = -1;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    getStatus(s, VPNQueue(), ^(int st) { status = st; dispatch_semaphore_signal(sem); });
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)));
    return status;
}

static NSNumber *VPNGet(void) {
    id config = VPNSelectedConfig();
    if (!config) return nil;
    int st = VPNStatus(VPNSession(config));
    gVPNNote = [NSString stringWithFormat:@"%@；当前配置「%@」，状态码 %d", gVPNSource ?: @"", KVC(config, @"name") ?: @"?", st];
    if (st < 0) return nil;
    return @(st == 2 || st == 3 || st == 4);
}

static BOOL VPNSet(BOOL on, NSString **how) {
    id config = VPNSelectedConfig();
    if (!config) { CXHow(how, gVPNNote); return NO; }
    ne_session_t s = VPNSession(config);
    void (*fn)(ne_session_t) = (void (*)(ne_session_t))dlsym(RTLD_DEFAULT, on ? "ne_session_start" : "ne_session_stop");
    if (!s || !fn) { CXHow(how, @"ne_session 不可用"); return NO; }
    fn(s);
    CXHow(how, [NSString stringWithFormat:@"ne_session · %@", KVC(config, @"name") ?: @"?"]);
    return YES;
}

#pragma mark - 对外接口

NSNumber *CXActionGet(NSString *type) {
    if (CXActionIsWhileInApp(type)) return CXBlockGet(type);
    if ([type isEqualToString:@"volume"]) return VolumeGet();
    if ([type isEqualToString:@"brightness"]) return BrightnessGet();
    if ([type isEqualToString:@"wifi"]) return WiFiGet();
    if ([type isEqualToString:@"bluetooth"]) return BluetoothGet();
    if ([type isEqualToString:@"lowPower"]) return LowPowerGet();
    if ([type isEqualToString:@"darkMode"]) return DarkModeGet();
    if ([type isEqualToString:@"rotationLock"]) return RotationLockGet();
    if ([type isEqualToString:@"mute"]) return MuteGet();
    if ([type isEqualToString:@"airplane"]) return AirplaneGet();
    if ([type isEqualToString:@"cellular"]) return CellularGet();
    if ([type isEqualToString:@"location"]) return LocationGet();
    if ([type isEqualToString:@"dnd"]) return DNDGet();
    if ([type isEqualToString:@"nightShift"]) return NightShiftGet();
    if ([type isEqualToString:@"autoBrightness"]) return AutoBrightnessGet();
    if ([type isEqualToString:@"reduceWhitePoint"]) return AXGet("_AXSReduceWhitePointEnabled");
    if ([type isEqualToString:@"invertColors"]) return AXGet("_AXSInvertColorsEnabled");
    if ([type isEqualToString:@"vpn"]) return VPNGet();
    return nil;
}

BOOL CXActionAvailable(NSString *type) {
    if ([type isEqualToString:@"killApps"]) return CXKillAppsAvailable();
    if ([type isEqualToString:@"music"]) return MusicAvailable();
    @try { return CXActionGet(type) != nil; } @catch (NSException *e) { return NO; }
}

NSString *CXActionNote(NSString *type) {
    if ([type isEqualToString:@"vpn"]) return gVPNNote;
    if (CXActionIsWhileInApp(type)) return CXBlockNote(type);
    if ([type isEqualToString:@"killApps"]) return @"保留前台 App 和正在播放音乐的 App";
    if ([type isEqualToString:@"music"]) return @"只能发送播放/暂停指令，读不到当前状态";
    return nil;
}

BOOL CXActionSet(NSString *type, NSNumber *value, NSString **how) {
    if (!value) return NO;
    @try {
        if (CXActionIsWhileInApp(type)) return CXBlockSet(type, value.boolValue, how);
        if ([type isEqualToString:@"killApps"]) return CXKillApps(how);
        if ([type isEqualToString:@"volume"]) return VolumeSet(value.integerValue, how);
        if ([type isEqualToString:@"brightness"]) return BrightnessSet(value.integerValue, how);
        if ([type isEqualToString:@"wifi"]) return WiFiSet(value.boolValue, how);
        if ([type isEqualToString:@"bluetooth"]) return BluetoothSet(value.boolValue, how);
        if ([type isEqualToString:@"lowPower"]) return LowPowerSet(value.boolValue, how);
        if ([type isEqualToString:@"darkMode"]) return DarkModeSet(value.boolValue, how);
        if ([type isEqualToString:@"rotationLock"]) return RotationLockSet(value.boolValue, how);
        if ([type isEqualToString:@"mute"]) return MuteSet(value.boolValue, how);
        if ([type isEqualToString:@"airplane"]) return AirplaneSet(value.boolValue, how);
        if ([type isEqualToString:@"cellular"]) return CellularSet(value.boolValue, how);
        if ([type isEqualToString:@"location"]) return LocationSet(value.boolValue, how);
        if ([type isEqualToString:@"dnd"]) return DNDSet(value.boolValue, how);
        if ([type isEqualToString:@"nightShift"]) return NightShiftSet(value.boolValue, how);
        if ([type isEqualToString:@"autoBrightness"]) return AutoBrightnessSet(value.boolValue, how);
        if ([type isEqualToString:@"reduceWhitePoint"]) return AXSet("_AXSSetReduceWhitePointEnabled", value.boolValue, how);
        if ([type isEqualToString:@"invertColors"]) return AXSet("_AXSInvertColorsSetEnabled", value.boolValue, how);
        if ([type isEqualToString:@"vpn"]) return VPNSet(value.boolValue, how);
        if ([type isEqualToString:@"music"]) return MusicSet(value.boolValue, how);
    } @catch (NSException *e) {
        CXHow(how, [NSString stringWithFormat:@"异常 %@", e.reason]);
    }
    return NO;
}
