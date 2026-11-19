// 时间段判断单元测试（在 Mac 上运行）：clang -fobjc-arc -framework Foundation tests/time_test.m -o /tmp/cx_time_test && /tmp/cx_time_test
#import "../Shared/CXShared.h"
#define CHK(cond, msg) do { if (!(cond)) { printf("FAIL %s\n", msg); fails++; } else printf("ok   %s\n", msg); } while (0)
int main(void) { @autoreleasepool { int fails = 0;
    // weekday: 1=周日 2=周一 ... 7=周六
    CHK( CXTimeInWindow(1320, 420, @"everyday", 23*60+30, 3), "跨夜 23:30 在内");
    CHK( CXTimeInWindow(1320, 420, @"everyday", 6*60, 3),     "跨夜 06:00 在内");
    CHK(!CXTimeInWindow(1320, 420, @"everyday", 7*60, 3),     "跨夜 07:00 结束");
    CHK(!CXTimeInWindow(1320, 420, @"everyday", 12*60, 3),    "跨夜 12:00 不在");
    CHK( CXTimeInWindow(1320, 420, @"weekdays", 23*60+30, 6), "工作日跨夜 周五23:30 在内");
    CHK( CXTimeInWindow(1320, 420, @"weekdays", 3*60, 7),     "工作日跨夜 周六03:00 属于周五");
    CHK(!CXTimeInWindow(1320, 420, @"weekdays", 23*60+30, 7), "工作日跨夜 周六23:30 不在");
    CHK(!CXTimeInWindow(1320, 420, @"weekdays", 3*60, 2),     "工作日跨夜 周一03:00 属于周日 不在");
    CHK( CXTimeInWindow(720, 780, @"weekend", 12*60+10, 1),   "周末 周日12:10 在内");
    CHK(!CXTimeInWindow(720, 780, @"weekend", 12*60+10, 2),   "周末 周一12:10 不在");
    CHK(!CXTimeInWindow(720, 780, @"weekend", 13*60, 1),      "周末 13:00 结束");
    CHK(!CXTimeInWindow(600, 600, @"everyday", 600, 3),       "开始=结束 不生效");
    CHK(!CXTimeInWindow(-1, 600, @"everyday", 300, 3),        "非法时间 不生效");
    CHK( CXTimeInWindow(0, 1425, nil, 0, 4),                  "days 缺省按每天");
    CHK([CXConditionText(@{@"type":@"time",@"start":@1320,@"end":@420,@"days":@"weekdays"}) isEqualToString:@"22:00–07:00 · 工作日"], "时间段摘要文字");
    CHK([CXConditionText(@{@"type":@"wifi",@"op":@"isNot",@"ssid":@"Home"}) isEqualToString:@"Wi-Fi 不是「Home」"], "Wi-Fi 摘要文字");
    CHK([CXActionValueText(@{@"type":@"volume",@"value":@30}) isEqualToString:@"30%"], "音量文字");
    CHK([CXActionValueText(@{@"type":@"mute",@"value":@NO}) isEqualToString:@"关闭"], "开关文字");
    printf(fails ? "\n%d FAILED\n" : "\nALL PASSED\n", fails); return fails; } }
