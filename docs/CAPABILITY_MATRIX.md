# 能力矩阵与 SDK 预检

**当前最高需求：Standalone v2 附录 A + Swift-first。** 完整运行时在 iPhone，电脑仅用于开发/构建。下表补齐附录 A7 要求；文末原核验记录保留作历史上下文。所有 iPhone 实测当前均未完成，跨平台 Mock 不代表系统授权或后台运行通过。

| 能力 / 最低 API 基线 | entitlement / 用途说明 | 前台与后台边界 | Siri / Shortcuts | 网络 | 离线降级 | 真机状态 |
|---|---|---|---|---|---|---|
| SwiftUI iOS 13；本项目拟 iOS 17 | App 签名；无“通用控制”权限 | 普通 App 生命周期；无常驻 | 由 App Intent 进入 | 本地核心不需 | 本地规则、队列、报告 | 未验证 |
| App Intents/App Shortcuts iOS 16 | 与实际工具对应的能力；不把 SiriKit entitlement 泛化成任意控制权限 | Intent 执行机会有限，锁屏/打开 App 需实测 | 公开本 App 的 agent.ask/run_workflow | 云模型才需 | 本地路由、明确缺失反馈 | 未验证；[App Intents](https://developer.apple.com/documentation/appintents) |
| SiriKit iOS 10 指定领域 | 选用领域按 SDK 配置 Siri 能力 | 只支持特定领域，不能替换 Siri | 有限领域 | 依功能 | 不支持时走本 App Intent/UI | 未实现；[SiriKit](https://developer.apple.com/documentation/sirikit) |
| Shortcuts 个人自动化（各触发器版本实测） | 用户手动配置；不是可编程授予的全局权限 | 时间/闹钟/位置/专注触发有系统限制；不可保证强退后运行 | 调本 App Intent；不任意安装私人自动化 | 本地动作不需 | 保留待执行事件、下次机会恢复 | 未验证；[用户指南](https://support.apple.com/guide/shortcuts/welcome/ios) |
| 分享扩展/App Groups iOS 8 | App Group entitlement；扩展 target | 内存/时间受限；不能任意调用主 App UIApplication | 分享菜单；不是后台偷读 | 在线分析可需 | 处理选中文本/本地 OCR，保存共享 inbox | 未验证；[Share 指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html) |
| HealthKit iOS 8；本阶段仅 Mock | HealthKit entitlement；NSHealthShareUsageDescription；后台投递另启用 background-delivery | 读类型分别授权，读拒绝/无数据不可混淆；锁屏/同步延迟需处理 | Intent 在获准执行时查询 | 本地记录不需 | 本地授权数据或标明过期的聚合；空值不当零 | 未验证；[后台 entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit.background-delivery) |
| EventKit 日历/提醒；本项目用 iOS 17 full-access API | NSCalendarsFullAccessUsageDescription / NSRemindersFullAccessUsageDescription；按需授权 | 写入前预览确认；取消/撤销不写 | 通过本 App Intent | 本地库不需，云同步由系统决定 | 查询已授权本地库；不可假造缺失 | 未验证；[EventKit](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) |
| WeatherKit iOS 16 / 可替换 REST | WeatherKit entitlement/账号服务；地点隐私及归属要求 | 请求/缓存可在获执行机会时完成 | 通过本 App Intent | 新预报需 | 带有效期缓存；过期标注，不误导风险判断 | REST 早期单次验证；原生未验证；[WeatherKit](https://developer.apple.com/weatherkit/) |
| MapKit / 高德 URI；以部署基线和 App 版本为准 | 查询 iosamap scheme 需 LSApplicationQueriesSchemes；定位另申请 | 第三方打开需合适前台、确认目标；不能任意点击或保证开始导航 | Intent 只规划，必要时前台确认 | 新搜索通常需；已知目的地链接生成不需 | 保存已确认候选；高德缺席回退 Apple Maps，仍核对目标 | 未验证；[高德 route](https://lbs.amap.com/api/amap-mobile/guide/ios/route) |
| Core Location region（传统 API，项目基线17） | NSLocationWhenInUseUsageDescription；持续/后台路径按具体 API 核对 Always 用途说明 | 区域事件可能延迟；不能保证强退后继续 | 或用户 Shortcuts 离开触发 | 基础监测不必；天气/搜索另需 | 最少 left_home 事件，定位不准时不下结论 | 未验证；[Core Location](https://developer.apple.com/documentation/corelocation) |
| BackgroundTasks iOS 13 | 任务标识/相应后台模式，非“无限后台” entitlement | 系统调度、不保证指定时间；预算不足保存检查点 | 不替代用户时间自动化 | 依任务 | 下次启动/机会补处理，旧摘要仅归档 | 未验证；[不保证准时](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate) |
| UserNotifications iOS 10 | 单独通知授权，不能绕过关闭/专注模式 | 提交成功不等于已显示；通知与报告分别去重 | Intent 可提出通知请求 | 本地通知不需 | 本地保存；安静时段不主动弹 | 未验证；[UserNotifications](https://developer.apple.com/documentation/usernotifications) |
| WidgetKit iOS 14；Controls iOS 18 | Widget/Control target，按实际版本 availability gate | 时间线和交互受系统策略；不提供常驻悬浮层 | App Intents 支持相应动作 | 依数据源 | 展示缓存和更新时间 | 未实现；[Apple Controls 版本说明](https://developer.apple.com/videos/play/wwdc2024/10157/) |
| Speech iOS 10 / AVFoundation 按功能 | 麦克风/语音识别用途说明，按需授权 | 短时主动输入；不假设后台一直监听 | 独立 App 动作，不替代 Siri | 离线识别依设备/语言 | 不可离线时明确提示，保留用户选择的输入 | 未实现；[Speech](https://developer.apple.com/documentation/speech) |
| focus.context / shortcut_context | 只接收用户快捷指令明确传入字段 | 不通用读改专注设置；不读取其他 App 数据 | 用户手动桥接 | 不需 | 本地上下文缺失保持未知 | 未实现 |
| 其他 App 通知、任意 UI 点击、无限后台 | 不存在本项目所需普通 App 公开权限 | 不实现，不用测试特权冒充 | 不可通过 Siri 获得绕过权限 | — | 明确不支持 | 无实现 |

Windows 可以编译纯 Swift（需 Swift 与平台开发依赖），但没有 Apple SDK。临时 Linux Swift 测试容器只属于开发测试，不是正式 App 后端。Appium/WDA/iOS-Tagent 不在任何产品 Package 的依赖中。Mac/iPhone 阶段必须重新核对 API availability、签名、用途提示和拔线验收；本表不把官网文档核验当作本机 SDK 构建通过。

---

以下为早期官方核验与历史环境记录；当前实施顺序以 `SWIFT_FIRST_PLAN.md` 为准。

核验日期：2026-10-15。结论区分 **官方文档能力**、**Windows 实现/测试** 和 **Mac/iPhone 待验证**。已浏览下列官方页面；这不等于执行过 Apple SDK。当前 Windows 实际 Python 3.14.7，`xcodebuild` / `swift` 不在 PATH，没有可报告的本机 iOS SDK。

拟定原生 Deployment Target **iOS 17.0**，避免维护 EventKit 旧授权分支；目标 iPhone 14 Pro，具体设备系统待迁移时记录。Apple 当前 [Xcode 支持表](https://developer.apple.com/xcode/system-requirements) 列有 Xcode 27、iOS 27 SDK 与 iOS 15–27 Deployment Targets；这支持将 iOS 17 作为设计基线，但不代表用户已安装该版本。迁移时根据 Mac 系统、实际设备 OS 和官方当前稳定发行版选定 Xcode，再记录 `xcodebuild -version` / `-showsdks`，不依赖 beta 特性。

| 能力 | 支持分类 | Windows 当前状态 | iPhone 条件/后续验证 | 官方依据 |
|---|---|---|---|---|
| SwiftUI App | 官方支持 | 仅目录设计，无工程 | Mac 创建、签名、模拟器和 iPhone 构建 | [SwiftUI](https://developer.apple.com/documentation/swiftui) |
| Tool Registry / JSON / 本地规则 | 应用自行实现 | Python 已测试；Swift 核心契约/注册/确认执行器已写入，尚未编译 | 先运行 DongShaoCore 的 swift test，再补 Swift 规则和原生 adapter | [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/) |
| App Intents / Siri / App Shortcuts | 官方支持，需用户入口 | 未实现 Apple API | 定义本 App 动作、发现短语、Siri 语言与锁屏验证；不能替换 Siri | [AppIntent](https://developer.apple.com/documentation/appintents/appintent), [App Intents 入门](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework) |
| 闹钟停止、时间等个人自动化 | 需用户配置 | CLI 注入标准事件 | 用户手动在 Shortcuts 设置；逐项确认当前系统触发及确认选项 | [事件触发器](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios) |
| 轻点背面 | 需用户配置 | 未连接设备 | 系统辅助功能中选择用户快捷指令，真机验证 | [轻点背面](https://support.apple.com/guide/iphone/use-back-tap-iph88ab07cfd/ios) |
| Share Extension | 官方支持，用户主动分享 | 仅模块设计 | 独立扩展 target，读取 NSItemProvider 指定文本/URL/图片；不偷读当前屏幕 | [Share Extension 官方指南](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html) |
| App Groups | 官方支持，需账号配置 | 无共享容器 | 主 App/扩展同组签名，实测容器和并发访问 | [配置 App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) |
| 天气 | 官方/第三方条件支持 | Mock + Open-Meteo；真实只读请求通过 | 优先 WeatherKit：启用服务/Capability，满足展示归属要求；或替换 adapter | [WeatherKit](https://developer.apple.com/weatherkit/), [WeatherKit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.weatherkit), [Open-Meteo](https://open-meteo.com/en/docs) |
| 地点搜索 | 官方/第三方条件支持 | Mock + 高德 Web adapter；协议测试通过，真实 Key 未配置 | MapKit 搜索或高德有效 Web Key；地点歧义必须用户选择 | [MapKit](https://developer.apple.com/documentation/mapkit), [高德 POI 搜索](https://lbs.amap.com/api/webservice/guide/api-advanced/search) |
| 高德路线跳转 | 第三方条件支持 | 已编码 URI 提案；不打开 | 安装高德，声明查询 scheme，确认后调用系统 URL 打开，版本/目的地实测 | [高德 iOS 路线规划](https://lbs.amap.com/api/amap-mobile/guide/ios/route), [canOpenURL](https://developer.apple.com/documentation/uikit/uiapplication/canopenurl(_:)) |
| Apple Maps 回退 | 官方支持，目标需确认 | 已生成回退 URL，未实机打开 | 优先 MapKit 原生打开；按名称回退要核对候选；骑行 URL 回退暂用步行 | [地图链接](https://developer.apple.com/documentation/mapkit/unified-map-urls) |
| HealthKit 授权汇总 | 官方支持，按数据类型授权 | 仅 Mock，不读取 iPhone | HealthKit capability、用途说明、逐类型授权；不能从读授权状态推断可见性 | [健康数据授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [配置 HealthKit](https://developer.apple.com/documentation/xcode/configuring-healthkit-access) |
| 健康增量/后台投递 | 官方条件支持，不保证实时 | workout 事件为模拟，无 anchor 同步 | HKObserverQuery + HKAnchoredObjectQuery、删除对象、持久游标；后台 entitlement，真机记录延迟 | [Observer](https://developer.apple.com/documentation/healthkit/hkobserverquery), [Anchored Query](https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery) |
| 日历读取 | 官方支持，需系统授权 | 仅 Mock | iOS 17+ `requestFullAccessToEvents`，用途说明，取消/撤销处理 | [访问 Event Store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [日历用途键](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription) |
| 提醒事项创建 | 官方支持，需授权与确认 | 本地 Mock 幂等写入 | iOS 17+ `requestFullAccessToReminders`；确认日期/时区后保存 | [提醒授权](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)) |
| 地理围栏/离家 | 官方条件支持或用户配置 | 手动 CLI 事件 | Core Location 对应授权、系统 region 约束；或 Shortcuts 离开触发；可能延迟 | [Core Location](https://developer.apple.com/documentation/corelocation), [定位触发器](https://support.apple.com/guide/shortcuts/travel-triggers-apd8ebfc4e8e/ios) |
| 本地通知 | 官方支持，需授权 | 仅策略建议，不投递 | UserNotifications 授权；提交通知与最终显示不同，专注模式会影响显示 | [UserNotifications](https://developer.apple.com/documentation/usernotifications) |
| 每日精确后台运行 | 不支持保证 | 无守护进程 | Shortcuts 用户触发更合适；BGTask 仅尽力调度 | [earliestBeginDate 不保证指定时间执行](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate) |
| Widget / 活动状态 | 官方条件支持，后续阶段 | 未实现 | WidgetKit / ActivityKit，按系统生命周期运行；不是全局悬浮层 | [WidgetKit](https://developer.apple.com/documentation/widgetkit), [ActivityKit](https://developer.apple.com/documentation/activitykit) |
| LLM API | 外部条件支持/可替换 | Ollama HTTP adapter + 多轮协议测试 | 本地模型或显式配置 HTTPS API；iPhone 可换 URLSession provider，无 Python 依赖 | [Ollama Tool Calling](https://docs.ollama.com/capabilities/tool-calling) |
| Apple Intelligence 本地大模型 | 不作为本项目依赖 | 未使用 | 不依赖特定机型模型资格，iPhone 14 Pro 走规则/用户 API | [Foundation Models](https://developer.apple.com/documentation/foundationmodels) |
| 读取其他 App 通知/私有数据、任意跨 App 点击、替换 Siri、无限常驻 | 不支持本项目所需公开能力 | 无工具、无实现 | 不增加私有 API、越狱或“通用控制”兜底 | 规格书非目标；仅按上列公开 Framework 能力实现 |

## 高德 URI 已核对的具体参数

采用 **路线界面** `iosamap://path`，不是将 URI 生成声称为静默开始导航。官方参数包含 `sourceApplication`、`dlat/dlon`、`dname`、可选 `did`、`dev`、`t`、`m`；起点参数省略时从“我的位置”规划。`t=0/1/2/3` 对应驾车/公交/步行/骑行，`m=0` 提供兼容值但官方注明新版本可能以用户偏好为准；不承诺路线偏好控制。GCJ-02 使用 `dev=0`，WGS-84 使用 `dev=1`，均 URL 编码。[官方路线参数](https://lbs.amap.com/api/amap-mobile/guide/ios/route)

真实搜索使用 `/v3/place/around` 与最多十个候选；WGS-84 源位置先用 `/v3/assistant/coordinate/convert`、`coordsys=gps`，返回高德坐标后再搜索。未授权、Key 不合法、结果为空或结构异常均返回错误，不让模型补坐标。[官方坐标转换](https://lbs.amap.com/api/webservice/guide/api/convert)

## Mac 上必须补的实证

Xcode 和实际 SDK 可用性/Swift Concurrency 编译检查、App Intent 发现和 Siri 执行、Share Extension 生命周期及 App Group、系统权限弹窗、签名 entitlements、高德安装与打开失败回退、健康首轮/增量/删除同步、锁屏/断网/强制退出下的行为。**以上当前均未通过原生验证。**
