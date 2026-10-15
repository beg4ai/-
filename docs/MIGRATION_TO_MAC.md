# 迁移到 macOS + Xcode

**当前以 Standalone v2 附录 A + `SWIFT_FIRST_PLAN.md` 为准。** 已有四个 Swift Packages 的源码和 27 项未运行 XCTest；迁移先逐包执行 Core、Mocks、Providers、Workflows 的 `swift test`，修复编译/行为问题，然后才创建原生 App。下文早期的“首个核心增量”描述保留历史语境，不表示其他包仍未编写。

当前 `iOS/Packages/DongShaoCore` 已包含首个 Swift 核心增量（契约、有限 Schema 校验、Registry/确认执行器与 XCTest），**尚未编译，也没有 App .xcodeproj**。其他原生 App 模块仍是设计。迁移后的手机直接执行 Swift Native Tools，不需要连接 Windows/Python。复制源码、schemas、config、fixtures、docs；重新建立 Mac 虚拟环境做对照测试，不复制 Windows `.venv` 或个人 `.agent` 数据。

## 0. 记录真实环境

安装与 Mac 系统及 iPhone 实际 OS 匹配的稳定 Xcode，先核对 [Apple 支持表](https://developer.apple.com/xcode/system-requirements)。设计基线 iOS 17.0；最终以本机 SDK 编译可用性为准。

```sh
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
swift --version
```

记录 Mac/Xcode/SDK/Swift/设备 OS 到 `docs/VALIDATION.md`，不能用官网列出的 SDK 代替本机输出。只装 Command Line Tools 不等于已具备 iOS SDK。

## 1. 原生契约和 Mock，先构建

首先运行已有核心包：

```sh
swift test --package-path iOS/Packages/DongShaoCore
```

修复所有编译和测试问题后，再在 Xcode 新建 iOS SwiftUI App，产品内部名 DongShao，Display Name `东少`，选择自己的 Team 与唯一 Bundle ID。把核心作为 Local Swift Package 加入 App 和 ContractTests。现有执行器尚未实现审计、幂等写入、目标缓存和完整工具链，须先补齐这些边界，再连接真实写入或跳转。

Swift 需拒绝未知字段或实现可信 Schema 校验；**仅用 JSONDecoder 解码成功不足以等价于 Python 的 additionalProperties=false**。日期偏移量、IANA 时区、一致性检查、取消无副作用、幂等冲突、未知工具和多候选行为都要保留。Mock 对照固定时钟 `2026-10-15T08:00:00+08:00`；忽略生成的 trace/time/id 差异，断言契约与预期状态。真实 adapter 的数值不与演示样本做相等断言。

创建实际工程后运行，以下 scheme/project 名为建议，需以新建工程为准：

```sh
xcodebuild -list -project iOS/DongShao.xcodeproj
xcodebuild -project iOS/DongShao.xcodeproj -scheme DongShao \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# 查看当前可用模拟器并选择实际 destination，再执行 test。
xcodebuild -showdestinations -project iOS/DongShao.xcodeproj -scheme DongShao
```

通过模拟器构建、契约 XCTest，再部署 iPhone，才继续下一个模块。不得将这里的示例命令记录为已执行的成功构建。

## 2. 系统入口，逐个加 target

1. 实现 `AskAgentIntent` 和 `AppShortcutsProvider`，自然语言入口只进入统一执行器。Siri/Shortcuts 错误反馈应可读；需要选择或确认时转到适合的系统/前台界面，不能默认执行外部动作。
2. 实机验证快捷指令发现、中文 Siri、锁屏/解锁、取消、前后台，记录结果。App Intents 不依赖 Apple Intelligence 才能作为普通 App 动作使用。[AppIntent 官方协议](https://developer.apple.com/documentation/appintents/appintent)
3. 新建 Share Extension target，开启 extension-safe API；配置 App Group 并使用 NSItemProvider 接收用户选中内容。先支持文本/URL，再增量加图片/文件的限额和本地 OCR；不通过不安全技巧调用主 App 的 UIApplication。
4. 扩展内部处理/回显或保存至共享 inbox；受扩展生命周期限制，超时要清楚反馈。不要将“分享扩展必能拉起主 App”作为实现前提。[Share 官方指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
5. 每增加 App Intent / Extension 之后分别构建主 App、扩展和 ContractTests，再做 Siri/Safari 分享真机验证。

## 3. 逐个替换工具

| 顺序 | Mock → Swift adapter | 必须补测 |
|---|---|---|
| A | maps.search → MapKit 或高德 URLSession | 空结果、多候选、真实坐标系统；用户选中目的地 |
| B | maps.navigate → 可信 URI + 原生打开 | `LSApplicationQueriesSchemes` 包含 iosamap；canOpenURL；打开结果失败时 Apple Maps；确认取消不得跳转 |
| C | weather.forecast → WeatherKit 或现有 REST | WeatherKit entitlement/服务/归属，定位授权、无网、过期数据、各温度/风速单位 |
| D | calendar.events / reminders.create → EventKit | iOS 17 full access，首次拒绝/撤销、夏令时与时区、确认后写入、重复不多写 |
| E | health.summary → HealthKit | 类型最小读授权、空数据未知、睡眠统计、workout UUID 对应、同步延迟 |

所有原生 tool 输入和统一错误/确认状态遵守现有契约。真实提醒保存成功设置 `simulated=false`；导航系统打开成功才设置 `opened=true`，不是单纯构造 URI 就标成功。URI 能打开不代表 App 内部已选到正确路线或开始导航，真机仍需核对。

每次只替换一个 adapter，保留可注入 Mock 用于自动化契约测试，构建/测试后再进下一项。远端 LLM 换成 Swift URLSession provider；凭据用 Keychain；核心规则在本机运行。

## 4. 健康同步与四个场景

增加 HKObserverQuery + HKAnchoredObjectQuery、HealthSyncCursor、删除事件、幂等 upsert。更新健康持久数据成功后才推进 anchor，再触发 workout 分析；完成 observer handler 与后台投递配置。未解锁/数据未同步时排队，不把缺失当零。[Anchored Query](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery), [后台 HealthKit 配置](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)

Shortcuts 闹钟停止、离开位置、晚上时间触发 App Intent → 标准事件 → 同一原生 AutomationEngine。用户手动配置触发器；App 不能自行任意创建个人自动化。通知实际提交结果与策略分开记录。BGTask 只能增添尽力刷新，不能承担精确每日时间保证。[Apple 调度约束](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)

健康增量首轮、重传、删除、离线、重新安装后游标恢复，以及 iPhone 强制退出/锁屏情况必须真机记录。只有这些测试通过，才能将当前“CLI 模拟工作流”升级为“已连接系统自动化”。WidgetKit 和更复杂 UI 留在此后。

## 真机最低验收表

- 安装东少后能在 Shortcuts 发现 AskAgent，中文 Siri 执行，失败反馈清楚。
- Safari 分享 URL/文本可在扩展回显；照片输入明确选中内容、无全库偷读。
- 安装/未安装高德分别测试，查看目的地名称和路线；取消无跳转。
- 日历/提醒/健康首次拒绝、部分授权、系统撤销后均不崩溃、不造值。
- 预览明早提醒的本地日期/时区，取消后系统提醒无新条目，确认后仅一条。
- 多个起床闹钟只生成一份；同 workout UUID 重试不重复报告；尚未同步的数据稍后可重试。
- 离家同风险、冷却、安静时段和断网恢复；复盘低信息量只归档。
- 锁屏、重启、用户强制退出、无网均记录实际表现，不填“无限后台/绝对准点”。
