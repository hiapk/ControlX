// 动作层：读取 / 设置各个系统开关。只在 SpringBoard 里调用。
// 所有私有接口都先检查是否存在，不存在时返回 nil / NO，不会崩溃。
#pragma once
#import <Foundation/Foundation.h>

// 读取当前值：音量/亮度返回 0~100 的 NSNumber，开关返回 @YES/@NO；不可用返回 nil
NSNumber *CXActionGet(NSString *type);

// 设置；成功返回 YES。how 会写入使用了哪个接口，方便日志排查（可传 NULL）
BOOL CXActionSet(NSString *type, NSNumber *value, NSString **how);

// 这个动作在当前系统上能不能用（读得到状态，或者像音乐那样能发指令）
BOOL CXActionAvailable(NSString *type);

// 自检时附带的说明（比如 VPN 用的是哪个配置），没有返回 nil
NSString *CXActionNote(NSString *type);

// 当前 Wi-Fi 名称，没连时返回 nil
NSString *CXCurrentSSID(void);

// 是否接着电源（充电中或已充满）
BOOL CXIsCharging(void);
