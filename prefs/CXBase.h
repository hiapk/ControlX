// 设置页公共基础：数据读写、App 信息、图标、通用控件构造。
#pragma once
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import "../Shared/CXShared.h"

@interface PSSpecifier (ControlX)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end

@interface PSListController (ControlX)
- (void)reloadSpecifiers;
- (void)reloadSpecifier:(PSSpecifier *)specifier animated:(BOOL)animated;
@end

#pragma mark - 规则数据

NSMutableArray<NSMutableDictionary *> *CXLoadRules(void);
void CXSaveRules(NSArray *rules);                 // 保存并通知 SpringBoard
NSMutableDictionary *CXFindRule(NSArray *rules, NSString *ruleId);
NSString *CXRuleSummary(NSDictionary *rule);      // 「Telegram · 2 个条件 · 3 个动作」
NSString *CXAppsSummary(NSArray *apps);
void CXPost(const char *name);

#pragma mark - App 信息

NSString *CXAppName(NSString *bundleID);
UIImage *CXAppIcon(NSString *bundleID);
NSArray<NSDictionary *> *CXInstalledApps(void);   // [{id, name, system}]，按名称排序

#pragma mark - 图标

UIImage *CXSymbolIcon(NSString *symbol, UIColor *color);
UIImage *CXActionIcon(NSString *type);
UIImage *CXConditionIcon(NSString *type);

#pragma mark - 自定义单元格：支持副标题 / 右侧值 / 文字颜色 / 勾选

// 通过 specifier 属性控制：
//   cxStyle: @"subtitle" | @"value"     单元格样式
//   cxSubtitle / cxValue: NSString      副标题 / 右侧值
//   cxTint: UIColor                     标题颜色（按钮用）
//   cxChecked: NSNumber                 显示勾号
@interface CXCell : PSTableCell
@end

#pragma mark - 基类

@interface CXBaseController : PSListController
@property (nonatomic, readonly) NSString *ruleId;       // 来自 specifier 属性 ruleId
@property (nonatomic, readonly) NSInteger itemIndex;    // 来自 specifier 属性 index

// 当前规则（可修改，改完调用 saveRule:）
- (NSMutableArray *)rules;
- (NSMutableDictionary *)ruleIn:(NSArray *)rules;
- (void)saveRules:(NSArray *)rules;

// 控件构造：字段型控件统一走 cxGet:/cxSet:specifier:，用属性 field 区分
- (PSSpecifier *)groupNamed:(NSString *)name footer:(NSString *)footer;
- (PSSpecifier *)switchNamed:(NSString *)name field:(NSString *)field;
- (PSSpecifier *)segmentField:(NSString *)field values:(NSArray *)values titles:(NSArray *)titles;
- (PSSpecifier *)textNamed:(NSString *)name field:(NSString *)field placeholder:(NSString *)placeholder;
- (PSSpecifier *)linkNamed:(NSString *)name subtitle:(NSString *)subtitle value:(NSString *)value
                     icon:(UIImage *)icon detail:(Class)detail props:(NSDictionary *)props;
- (PSSpecifier *)buttonNamed:(NSString *)name action:(SEL)action tint:(UIColor *)tint;
- (PSSpecifier *)infoNamed:(NSString *)name value:(NSString *)value;

- (id)cxGet:(PSSpecifier *)spec;
- (void)cxSet:(id)value specifier:(PSSpecifier *)spec;

// 打开某个 specifier 对应的子页面（相当于用户点了它）
- (void)openSpecifierWithID:(NSString *)identifier;

- (void)alert:(NSString *)title message:(NSString *)message;
- (void)chooseFrom:(NSString *)title options:(NSArray<NSString *> *)titles disabled:(NSSet<NSNumber *> *)disabled
           handler:(void (^)(NSInteger index))handler;
- (void)confirm:(NSString *)title action:(NSString *)action handler:(void (^)(void))handler;
@end
