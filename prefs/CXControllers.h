#pragma once
#import "CXBase.h"

@interface CXRootListController : CXBaseController
@end

@interface CXRuleController : CXBaseController
@end

@interface CXAppPickerController : CXBaseController <UISearchResultsUpdating>
@end

@interface CXConditionController : CXBaseController
@end

@interface CXActionController : CXBaseController
@end

// 纯文本页面：运行日志、自检结果
@interface CXTextController : UIViewController
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text clearable:(BOOL)clearable;
@end
