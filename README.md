# ControlX

**当 · 如果 · 就** —— 一个开源的 iOS 越狱插件：打开某个 App 时，按条件自动控制系统设置，离开时自动恢复。

> When · If · Then — an open-source jailbreak tweak that changes system settings when you open an app, only if your conditions are met, and restores them when you leave.

```
规则：Telegram 夜间模式
├─ 当：打开 Telegram
├─ 如果：Wi-Fi 不是「Home-5G」，并且时间在 22:00–07:00
└─ 就：亮度 30% ↩︎ · 音量 0 ↩︎        （↩︎ = 离开时恢复）
```

## 功能

| | 支持 |
|---|---|
| **当** | 打开所选 App（可多选） |
| **如果** | Wi-Fi 是 / 不是某个网络 · 是否在充电 · 时间段（支持跨夜、工作日 / 周末）；全部满足 / 任一满足 |
| **就** | 音量 · 亮度 · 自动亮度 · Wi-Fi · 蜂窝数据 · 蓝牙 · 飞行模式 · VPN · 定位服务 · 勿扰模式 · 低电量模式 · 深色模式 · 夜览 · 降低白点值 · 智能反转颜色 · 方向锁定 · 静音 · 音乐播放/暂停；每个动作可单独设「离开时恢复」（音乐除外） |
| **使用期间** | 隐藏手势横条 · 禁用控制中心 · 禁用通知中心 · 隐藏通知横幅 · 隐藏低电量弹窗 · 禁用便捷访问 · 禁用 Home 手势（防误触，2 秒内连续上划两次可退出）；只在该 App 里生效，离开自动解除，不改系统设置 |
| **一次性** | 清理后台 App（保留当前 App 和正在播放音乐的 App） |
| 其他 | 条件变化时重新判断（可选）· 试运行 · 立即试一下 · 运行日志 · 动作自检 · 系统接口诊断 |

## 安装

到 [Releases](https://github.com/hiapk/ControlX/releases) 下载对应的 `.deb`：

- roothide：`iphoneos-arm64e`
- rootless：`iphoneos-arm64`

用 Sileo / Zebra 打开安装，注销（respring）后在「设置 → ControlX」里配置。

## 兼容性与测试状态

在 **iOS 16.5 · roothide** 上开发和测试：

| 状态 | 功能 |
|---|---|
| ✅ 真机实测通过 | VPN · 音量 · 亮度 · 隐藏手势横条 |
| 🟡 接口已检测到，待更多实测 | 其余动作（「动作自检」共 24/25 项可用） |
| ❌ 暂不可用 | 深色模式（iOS 16.5 上切换接口待适配） |

- 理论支持 iOS 15 及以上的 rootless / roothide。所有私有接口都会先检测，不存在就跳过，不会崩溃。
- 正式版不显示调试工具。调试版（Releases 里带 `-debug` 的包，或 `./build.sh debug` 自己编译）在设置页多一个「调试」区：运行日志、动作自检（本机哪些动作可用）、系统接口诊断（相关系统组件的实际接口，方便适配其他版本）。
- 锁屏时不会拦截任何系统界面；拦截通知中心 / 控制中心只拦「打开」，已打开的照常能收起。

## 构建

需要 [roothide Theos](https://github.com/roothide/theos) 和 iOS SDK（`$THEOS/sdks/iPhoneOS16.5.sdk`）。

```sh
./build.sh                  # roothide 正式版
./build.sh rootless         # rootless 正式版
./build.sh debug            # 调试版（设置页带「调试」区），可与 rootless 组合
```

产物在 `packages/`。时间段判断等纯逻辑有单元测试，可在 Mac 上直接跑：

```sh
clang -fobjc-arc -framework Foundation tests/time_test.m -o /tmp/cx_time_test && /tmp/cx_time_test
```

## 目录结构

```
Shared/CXShared.h      规则数据结构、设置项名称、时间段判断（插件与设置页共用）
Tweak/Tweak.x          规则引擎：前台 App 变化 → 判断条件 → 执行 / 恢复动作
Tweak/CXActions.m      动作层：各系统开关的读取与设置（私有接口集中在这里）
Tweak/CXBlocks.m       拦截类动作（控制中心、通知中心、横幅等）与系统接口诊断
prefs/                 设置页（规则列表、规则编辑、选择 App、条件、动作）
design/                可点击的设置页设计稿（浏览器打开）
tests/                 单元测试
```

## 反馈问题 / 参与贡献

- 遇到问题：装调试版，在「设置 → ControlX → 调试」里复制「运行日志」和「动作自检」结果，一起提交 [Issue](https://github.com/hiapk/ControlX/issues)，并注明 iOS 版本和越狱类型。
- 适配其他 iOS 版本：附上「系统接口诊断」的结果会很有帮助。
- 适配新系统：开关类私有接口集中在 `Tweak/CXActions.m`，拦截类钩子集中在 `Tweak/CXBlocks.m`，每个动作一组 `Get` / `Set` 函数，按现有写法加新的兼容分支即可。
- 新增条件或动作：在 `Shared/CXShared.h` 登记类型和名称，在引擎和设置页各加一处处理。

## 许可

[MIT](LICENSE)
