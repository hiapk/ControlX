// 拦截类动作：在某个 App 里时，屏蔽控制中心 / 通知中心 / 横幅 / 手势横条等。
// 原理：只维护一组「当前要拦截什么」的标记；系统界面要出现时，钩子先查标记。
// 不改任何系统设置，离开 App 时清掉标记就自动恢复。
#pragma once
#import <Foundation/Foundation.h>

// 安装钩子（SpringBoard 启动时调用一次）。找不到的接口会跳过并记录
void CXBlocksInstall(void);

// 拦截标记：没有任何钩子装上时返回 nil（= 不可用）
NSNumber *CXBlockGet(NSString *type);
BOOL CXBlockSet(NSString *type, BOOL on, NSString **how);
NSString *CXBlockNote(NSString *type);

// 清理后台 App：保留前台 App 和正在播放音乐的 App
BOOL CXKillAppsAvailable(void);
BOOL CXKillApps(NSString **how);

// 系统接口诊断：列出相关系统组件在本机上的实际接口，供适配用
NSString *CXDiagnose(void);

// 由规则引擎提供：当前前台 App
NSString *CXFrontApp(void);
