# Personal Agent — iOS Native AI Gateway 开发规格书（交给 Codex）

> 目标设备：iPhone 14 或更早机型（以 iOS 实际支持的版本为准）；开发环境：Mac、Xcode、付费 Apple Developer 账号。单用户、自用、非越狱。优先 Local-first，复杂推理可调用用户配置的 LLM API；不要求 App Store 发布。**请先验证当前 Xcode SDK、iOS Deployment Target 与所引用的官方文档，再进行编码，切勿猜测 API 能力。**

## 1. 产品目标和非目标

做一个以“系统入口 + 工具调用 + 事件自动化”为核心的个人 AI 助手，而非新的聊天 App。用户从 Siri、快捷指令、轻点背面、分享菜单、小组件、系统事件触发 Agent；Agent 根据上下文选择已注册的 iOS Native Tools、公开 API 或第三方应用动作，并在权限允许、执行条件满足时完成操作或提出确认。

第一阶段场景：
1. **晨间简报**：停止起床闹钟后获取天气、已授权睡眠数据、当日日程，生成简报，尽量少打扰。
2. **外出助手**：离开家或设定地点后结合天气、日程、出行方式决定是否提醒雨具/天气风险。
3. **运动分析**：HealthKit 有新完成运动数据且同步完成后，生成运动概览与非诊断性健康建议。
4. **每日复盘**：晚上按快捷指令指定时间触发，或系统允许时在后台生成摘要，整合活动、运动、日程、待办。
5. **自然语言工具调用**：例如“用高德导航到虹桥火车站”“明天早上九点提醒我开会”“今天适合跑步吗”。
6. **分享内容给 AI**：Safari/照片/文件等分享文本、URL、用户选中图像或文件，执行总结、提取待办、问答。

非目标：读取别的 App 的通知/私有数据、读取任意当前屏幕、后台任意点击第三方 App、完全替代 Siri、保证 iOS 后台常驻/精确定时、银行 Push 采集或自动记账（暂缓）。

## 2. 设计原则

- 本地优先：HealthKit 数据原始记录留在手机，优先本地计算趋势和摘要；上传到第三方模型时按最小必要原则筛选，并征得用户同意。
- 确定性执行：LLM 仅生成工具调用计划和参数；由 Swift 工具执行器做 schema 校验、授权和确认。
- AI 可替换：云端模型通过 `LLMProvider` 协议隔离，不绑死供应商；第一版可使用符合 function/tool calling 的远端 API。不要在客户端内硬编码服务端的机密 API Key；单人自用也应使用 Keychain、短期 token 或自建代理。
- 事件去重、队列持久化、权限可撤销、失败可重试、日志脱敏。
- 独立应用可以通过 App Intents **向** Siri/Shortcuts 提供动作，但不能随意控制所有其他 App 或程序化创建任意用户个人自动化。
- 要兼容 iPhone 14 及更早机型；不要依赖 Apple Intelligence、Dynamic Island 或仅在新设备可用的本地大模型 API。

## 3. 目标架构

```
Siri / Shortcuts / Back Tap / Share Extension / Widget
       └──> App Intents / App UI
                   └──> PersonalAgentCoordinator
                          ├─ Intent Parser / LLMProvider
                          ├─ Tool Registry + Permission Policy
                          ├─ Context Engine (local state & data freshness)
                          ├─ Automation Engine (dedupe/cooldown/quiet hours)
                          ├─ Native Tools (HealthKit, EventKit, Location, Notifications, Maps...)
                          ├─ Third-party tools (Amap URI, weather, optional Home Assistant...)
                          └─ Persistence (SwiftData or SQLite, Keychain, persistent event queue)
```

第一版不部署手机上的常驻 FastAPI/Docker/PostgreSQL 服务。后期需要跨设备、24/7 任务时再增加可选后端。可离线执行简单规则；联网仅用于天气/地图搜索/模型 API 等必要场景。

## 4. iOS 主要模块和官方文档

| 模块 | 用途 | 官方文档 |
|---|---|---|
| App Intents | Siri/Shortcuts 触发个人工具 | https://developer.apple.com/documentation/appintents |
| App Shortcuts | 暴露可发现的短语与动作 | https://developer.apple.com/documentation/appintents/app-shortcuts |
| Shortcuts 用户指南 | 闹钟、打开 App、位置等个人自动化触发器；具体可用性按当前系统验证 | https://support.apple.com/guide/shortcuts/welcome/ios |
| SiriKit（仅支持的特定领域） | 了解 Siri 集成约束，不当作“替换 Siri” | https://developer.apple.com/documentation/sirikit |
| Share Extensions | 分享菜单接收文本、链接、图片、文件 | https://developer.apple.com/documentation/uikit/app-extensions |
| App Groups | 扩展与主 App 在授权组内共享数据 | https://developer.apple.com/documentation/xcode/configuring-app-groups |
| HealthKit | 步数、睡眠、运动、心率等授权读取 | https://developer.apple.com/documentation/healthkit |
| HKAnchoredObjectQuery | 增量数据、删除记录 | https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery |
| HKObserverQuery | 观察指定健康数据更新 | https://developer.apple.com/documentation/healthkit/hkobserverquery |
| Core Location | 授权定位、地理围栏等 | https://developer.apple.com/documentation/corelocation |
| EventKit | 日历、提醒事项的授权与操作 | https://developer.apple.com/documentation/eventkit |
| WeatherKit | 天气服务与可用性/配额 | https://developer.apple.com/documentation/weatherkit |
| MapKit | 地图、地点/路线能力 | https://developer.apple.com/documentation/mapkit |
| UserNotifications | 本地通知、权限管理 | https://developer.apple.com/documentation/usernotifications |
| WidgetKit | 桌面/锁屏小组件入口 | https://developer.apple.com/documentation/widgetkit |
| ActivityKit（可选） | 长任务状态；不等于常驻 Overlay | https://developer.apple.com/documentation/activitykit |
| BackgroundTasks | 系统调度后台任务；**不保证准点** | https://developer.apple.com/documentation/backgroundtasks |
| Speech | 语音转写（设备/地区/授权限制） | https://developer.apple.com/documentation/speech |
| AVFoundation | 语音合成/音频输入输出 | https://developer.apple.com/documentation/avfoundation |
| PhotosUI | 用户挑选图像内容 | https://developer.apple.com/documentation/photosui |
| Vision | 本地 OCR/图像处理 | https://developer.apple.com/documentation/vision |
| Contacts | 经过授权访问联系人 | https://developer.apple.com/documentation/contacts |
| Core Bluetooth（可选） | 连接受支持 BLE 设备 | https://developer.apple.com/documentation/corebluetooth |
| Core NFC（可选） | 支持的 NFC 标签交互 | https://developer.apple.com/documentation/corenfc |
| HomeKit（可选） | 授权智能家居控制 | https://developer.apple.com/documentation/homekit |
| MusicKit（可选） | Apple Music 支持范围内的媒体操作 | https://developer.apple.com/musickit/ |
| SwiftData | 本地数据存储，可结合加密/数据保护策略 | https://developer.apple.com/documentation/swiftdata |
| Security / Keychain | 本地保存凭据 | https://developer.apple.com/documentation/security/keychain-services |

**特别提醒**：HealthKit 读授权对 App 来说不代表可读所有指标；用户可按类型拒绝，不能把“无结果”解释为“健康数据为零”。EventKit 日历与提醒授权类型和 iOS 版本差异需要用当前 SDK 核对。快捷指令自动化触发不等于 App 能自行配置用户的自动化；应提供引导用户一次性配置的说明。

## 5. 第三方应用/API 接入与官方入口

| 对接 | 方式 | 官方入口 | 约束 |
|---|---|---|---|
| 高德地图地点搜索/路线 | Web Service API | https://lbs.amap.com/ | 申请 key、核对配额与使用条款；不要由 LLM 猜坐标 |
| 高德地图 App 跳转 | URI API / URL Scheme | https://lbs.amap.com/ | 去官方“URI API”文档核对 iOS Scheme、参数、URL 编码与自动起导航是否受限；无保障时退化为打开目的地/路线界面 |
| Open-Meteo | REST 天气（备选） | https://open-meteo.com/en/docs | 查清商业/非商业条件、请求配额及地点隐私 |
| Home Assistant（可选） | REST/WebSocket | https://developers.home-assistant.io/docs/api/rest/ | 需要用户自己的实例与 token；控制设备要确认 |
| Apple Maps | MapKit / 系统地图链接 | https://developer.apple.com/documentation/mapkit | 提供高德不可用时的回退路径 |
| GitHub（可选） | REST API | https://docs.github.com/en/rest | 需要合适的 token 和权限范围 |
| Notion（可选） | REST API | https://developers.notion.com/ | OAuth/Integration 权限 |
| Spotify（可选） | Web API | https://developer.spotify.com/documentation/web-api | 账户订阅、设备及 API 权限限制 |
| OpenAI（LLM 可选） | Responses / tool calling | https://platform.openai.com/docs | 与 ChatGPT 订阅分开计费；API Key 不硬编码在 App |

第三方链接是官方文档**入口**，不是对 2026 年最新接口版本/参数的实时核验。编码前请通过现行官方文档确认具体页面、配置、授权和 SDK 要求；无法核实就实现可替换 adapter、写清 TODO，而不要编造 endpoint。

## 6. Tool Registry 设计

接口模型（建议，具体由 Codex 按 Swift Concurrency 实现）：

```swift
protocol AgentTool {
    var name: String { get }
    var risk: ToolRisk { get }
    func execute(arguments: [String: CodableValue]) async throws -> ToolResult
}

enum ToolRisk { case readOnly, localWrite, externalAction, sensitive }
```

`CodableValue`、`ToolResult`、工具调用 schema、权限/确认错误类型需实际实现，以上非独立可编译代码。

首批工具：
- `weather.get_forecast`: 授权/配置地点，拉取小时天气与降雨。
- `health.get_summary`: 查询授权健康数据的必要聚合指标（睡眠、步数、运动）；注意数据新鲜度。
- `calendar.list_events`: 读取授权时间窗口内日程。
- `reminders.create`: 创建提醒事项，展示用户确认、校验时间与时区。
- `maps.search_place`: 由 MapKit/高德 API 返回结构化候选地点与坐标。
- `maps.navigate`: 用户确认地点后经高德已核对 URI 或 Apple Maps 打开路线规划。
- `notifications.schedule_local`: 在授权范围创建本地通知。
- `agent.summarize_shared`: 对 Share Extension 输入文本/URL/图片做总结或提问。

第二批工具（按权限逐步添加）：`contacts.lookup`、`speech.transcribe`、`photos.pick`、`home.get_state`、`home.control`、`files.import`、`notes.save_local`、`shortcuts` 中明确可调用的动作。**不要定义一个声称能够“任意运行所有快捷指令/点击所有 App”的工具。**

默认权限策略：只读自动；本地写入通常显示确认（允许用户按工具单独设置信任策略）；外部动作及敏感操作必须确认。每条工具执行都有 trace ID、参数审计摘要、执行结果和错误分类。不要让 LLM 直接运行任意 Swift、shell 或 URL。

## 7. 四大自动化场景的触发、数据、去打扰策略

| 场景 | iOS 触发 | 工具链 | 通知/可靠性策略 |
|---|---|---|---|
| 晨间简报 | 用户在 Shortcuts 配置“闹钟停止”→ App Intent | HealthKit 睡眠（若有）+ WeatherKit + EventKit → 摘要 | 每天同一早晨仅一份；睡眠尚未写入则标明缺失；不要因多个闹钟连推 |
| 外出助手 | Shortcuts“离开地点”或 App 获得权限后注册 Core Location 地理围栏 | 本地离家事件 → 天气/日程/交通偏好 → 判断 | 冷却期（如 90 分钟），只提醒新风险；地理围栏可能延迟 |
| 运动分析 | HealthKit `HKObserverQuery` → `HKAnchoredObjectQuery` | 新完成 `HKWorkout` + 授权运动样本 → 本地统计/AI 建议 | 按 workout UUID 去重；更新记录可重算但不连续推送；HealthKit 不保证实时后台投递 |
| 每日复盘 | Shortcuts 时间自动化（追求固定时刻）或 BackgroundTasks（尽力执行） | 当天日历/待办/健康统计/本地事件 → 总结 | 低信息量仅保存报告；免打扰时不主动弹；BGTask 不承诺准点 |

App 不应在启动/打开每个第三方 App 时无意义推送通知。Shortcuts 可以在某些“打开 App”事件触发自动化，但无法因此读取那个 App 的屏幕/私有内容。

## 8. 本地持久化建议

最小实体：
- `EventRecord(id, type, occurredAt, receivedAt, payloadSummary, processedAt, status, dedupeKey)`
- `AgentRun(id, triggerEventID, inputSummary, outputSummary, status, startedAt, finishedAt)`
- `ToolExecution(id, runID, toolName, risk, approved, status, errorCode)`
- `HealthSyncCursor(sampleType, serializedAnchor, lastSuccessAt)`
- `HealthMetricSnapshot(kind, timeStart, timeEnd, value, unit, source, collectedAt)`
- `PersonalPreference(key, value, updatedAt)`
- `NotificationHistory(dedupeKey, severity, issuedAt, deliveryRequested, result)`
- `Report(id, kind, periodStart, periodEnd, text, dataFreshness, createdAt)`

HealthKit 增量数据要处理删除对象、样本重传和多来源重复；锚点仅在已持久化结果后推进。处理模型输出时保存来源与生成时间。为本地缓存和敏感数据采用合理的数据保护级别、最小留存策略。

## 9. 代码组织建议

```
PersonalAgent/
├── iOS/PersonalAgentApp/
│   ├── App/                       # SwiftUI 和权限配置
│   ├── Intents/                   # AskAgent, MorningBrief, Review...
│   ├── Extensions/ShareExtension/ # 分享界面
│   ├── Tools/                     # 各 Native/ThirdParty adapter
│   ├── Orchestration/             # LLMProvider, AgentCoordinator
│   ├── Context/                   # 统计、事件、规则、偏好
│   ├── Automation/                # 触发接入与去重/冷却
│   ├── Storage/                   # SwiftData / Keychain
│   ├── UI/                        # 今日概览、历史报告、设置
│   └── Tests/
├── docs/
│   ├── CAPABILITY_MATRIX.md
│   ├── PRIVACY_AND_PERMISSIONS.md
│   └── MANUAL_SHORTCUTS_SETUP.md
└── README.md
```

## 10. 交给 Codex 的开发顺序（请分阶段提交）

**阶段 0：能力预检**
1. 确定 Deployment Target、Xcode/Swift SDK，验证必要 entitlements 和用户授权说明。
2. 输出 `CAPABILITY_MATRIX.md`：官方支持 / 需用户配置 / 第三方条件支持 / 不支持。验证高德 URI 入口，保留 Apple Maps fallback。
3. 建立 SwiftUI 工程、Signing & Capabilities、App Group、权限提示。不要默认全部申请敏感权限，按需授权。

**阶段 1：真正能用的系统入口**
1. `AskAgentIntent` 接收文本、触发本地 tool routing；配置 App Shortcuts phrases。
2. Share Extension 接收文本/URL/图片，在主 App / Extension 正确共享必要数据。
3. Shortcuts 用户手册：Siri、轻点背面、闹钟停止、时间触发、离家触发的逐步配置与实机验证。
4. `ToolRegistry`、`PermissionPolicy`、`ToolExecutor`、可替换 `LLMProvider`、本地记录与错误反馈。

**阶段 2：可用的工具链**
1. WeatherKit 或可替换天气 API、MapKit 地点搜索。
2. EventKit 日历读取、提醒事项创建（含确认）。
3. 高德 URI adapter 和 Apple Maps fallback；地点歧义时列出候选，绝不自行猜测。
4. 用自然语言完成“今晚适合跑步吗”“导航到某地”“明早提醒我 XXX”。

**阶段 3：HealthKit + 四个自动化场景**
1. 健康读授权，历史/增量读取，observer 查询与后台投递；实现持久游标、去重、删除事件、离线重试。
2. 晨间简报、外出助手、运动后分析、每日复盘；加入 `ContextEngine` 和 `NotificationPolicy`。
3. 后台机制应分别记录可测的行为，不能宣传“绝对准时”。

**阶段 4：健壮性与可扩展性**
1. WidgetKit 快捷入口、记录查询、用户可配置规则、可撤销授权。
2. 若需要远程 Agent，再增加可选后端 adapter 与 MCP/tool 代理，但不要让远程模型绕过本地审批。

## 11. 验收标准

- `AskAgentIntent` 出现在快捷指令中，可从 Siri 运行，失败也有清晰反馈。
- 分享 Safari URL/一段文本到扩展，无需手动打开聊天 App，即可处理并回显摘要。
- “导航到高德某地”在装有高德的设备上打开可用的地点/路线界面；高德不可用时退回 Apple Maps。不要将“打开路线”伪称为“已静默开始导航”。
- 读取天气/日历/健康数据在未授权时表现为权限提示或不可用，不崩溃，不假造数据。
- 创建提醒事项前可查看日期/时区，确认后才写入；取消不执行。
- 同一闹钟停止事件或 workout 重试不会出现重复报告/通知。
- 离开地点事件通知遵守冷却和安静时段规则。
- HealthKit sync 能处理首轮、增量、重试、删除和重新安装后状态（按可行范围设计）。
- iPhone 断网时能保存可本地处理的事件；联网后恢复同步；不需要 24/7 常驻进程。
- 测试包括工具 schema 校验、权限被拒、取消确认、第三方 App 未安装、地点歧义、模型输出异常、无健康数据、重复事件。

## 12. 交给 Codex 的直接执行提示词

请把本文作为工程需求，不要停留在讨论。先扫描仓库并输出实际的 iOS 能力可行性矩阵、当前 SDK 的兼容性清单及实施计划，然后**分阶段创建代码并运行可运行的测试**。优先做阶段 0 和阶段 1，确保 Xcode 工程可构建，Siri/Shortcuts/Share Extension 能实际调用统一工具执行器。之后按阶段 2、3、4 增量实现。任何第三方 API、URL Scheme、entitlement 或后台特性的当前支持情况必须查官方文档；无法证实时标记为待验证并实现安全降级，**不得编造苹果权限、系统级悬浮层、通知读取 API、任意跨 App 点击能力或后台常驻能力**。每阶段输出变更清单、构建/测试结果、必要的真机手工操作步骤和下一阶段阻塞项。仅在得到明确确认时执行有副作用的外部操作。

---

# 附录 A：脱离 Mac 独立运行（Standalone iPhone）增强规范 · 2026-10-15

> 本附录是强制需求，优先于本文中任何默认需要持续连接 Mac、Xcode、USB、WebDriverAgent 或 Python 服务的设计。Windows 可以提前开发协议与 Mock，Mac 仅用于首次构建、签名、安装和调试；**验收时拔掉 USB、关闭 Mac，iPhone 仍可日常使用**。支持 iPhone 14 及更早设备，不依赖 Apple Intelligence。此处的“完全独立”指运行时不需要 Mac；天气、在线地图搜索及云端 LLM 可能仍需要网络。

## A1. 执行模式与严格边界

1. **On-device Runtime（主通道）**：SwiftUI + App Intents + native ToolExecutor + 本地数据库 + Keychain。Siri、Share Extension、快捷指令或 Widgets 通过受支持的入口唤起，按 iOS 授予的执行时间运行。
2. **System Automation Bridge（辅助通道）**：用户手工在 Shortcuts 创建时间、停止闹钟、App 打开/关闭、专注模式等触发器，调用应用公开的 App Intent。不能编程批量安装/修改用户私人自动化，也不能假设可调用任意快捷指令动作。
3. **Native Background Events（辅助通道）**：Core Location 区域监测、HealthKit observer/background delivery、BGTaskScheduler。均受授权、后台调度和系统策略约束；不能保证实时、准点或用户强制退出后继续。
4. **Remote Model（可选）**：云端 LLM 只产生结构化工具调用意图；iPhone 在获得执行机会时决定、校验和执行本地动作。网络/模型不可用时继续运行本地规则、提醒与缓存。
5. **Test-only UI Automation（独立实验）**：Appium、WDA、iOS-Tagent 仅用于连接测试设备时的测试/评估；不作为个人主力手机脱机运行的功能依赖；不得把 XCUITest 特权描述为普通 App 权限。

官方参考：
- App Intents：https://developer.apple.com/documentation/appintents
- App Shortcuts：https://developer.apple.com/documentation/appintents/app-shortcuts
- Shortcuts User Guide：https://support.apple.com/guide/shortcuts/welcome/ios
- BackgroundTasks：https://developer.apple.com/documentation/backgroundtasks
- Core Location：https://developer.apple.com/documentation/corelocation
- HealthKit：https://developer.apple.com/documentation/healthkit
- UserNotifications：https://developer.apple.com/documentation/usernotifications

## A2. 新增工具与交互能力（逐项能力探测；不承诺跨版本普适）

| Tool / 入口 | 实现方式 | 用户体验 | 限制/验收要求 |
|---|---|---|---|
| `agent.ask` | App Intent + App Shortcuts | Siri 口述提问并得到简短回复 | Siri 交互不是通用多轮 Agent UI；网络/锁屏行为实测 |
| `agent.run_workflow` | 参数化 App Intent | Siri/Shortcuts 触发预定义 workflow | 不允许任意执行模型生成的 Swift/系统指令 |
| `agent.analyze_shared` | Share Extension / App Group | Safari/照片/文件分享并分析 | 仅可读取用户主动分享的数据；扩展有内存和生命周期限制 |
| `agent.analyze_webpage` | 用户分享 Safari URL / 可选 Safari Web Extension | 在网页场景处理正文/摘要 | URL 不一定意味着有全文；登录页面需显式权限且谨慎处理 |
| `agent.voice_note` | Speech/AVFoundation（获得权限） | 语音转文字→摘要→创建待办 | 后台监听麦克风不可假设；离线能力按语言/设备验证 |
| `maps.navigate` | MapKit/高德公开 URI / URL Scheme | 语音指定地点，打开路线 | 地点歧义时确认，不能保证静默开始导航 |
| `calendar.read` / `reminders.create` | EventKit | 查询日程、创建提醒 | 按版本申请授权；写入需要预览或可撤销策略 |
| `health.summary` | HealthKit + 本地统计 | 基于授权数据生成趋势 | 无数据与未授权不能混淆；原始敏感数据最少外传 |
| `weather.forecast` | WeatherKit 或已核准 API | 离家/起床天气助手 | 网络及配额限制，本地缓存与过期标识 |
| `focus.context` | Shortcuts 专注模式触发、应用自有状态 | 切换工作/休息场景 | 不得宣称可以通用读取/修改任意系统专注设置 |
| `device.shortcut_context` | 快捷指令明确传入设备信息 | 电量/网络/剪贴板等上下文 | 只接受系统动作实际可导出的字段，不得读取他 App 私有数据 |
| `notification.schedule` | UNUserNotificationCenter | 本地提醒和报告通知 | 不可绕过用户关闭通知、专注模式或系统调度 |
| `app.open` | 官方 URL/Universal Link、UIApplication.open | 打开第三方 App 对应页面 | 仅支持公开链接且需要适当 UI 前台上下文，不可跨 App 任意点击 |
| `file.process` | Share Extension / document picker | 对用户选择的 PDF、文件分类摘要 | 安全范围书签与权限生命周期要正确处理 |

附加官方参考：
- App Extensions：https://developer.apple.com/documentation/uikit/app-extensions
- Safari Web Extensions：https://developer.apple.com/documentation/safariservices/safari-web-extensions
- WidgetKit：https://developer.apple.com/documentation/widgetkit
- App Groups：https://developer.apple.com/documentation/xcode/configuring-app-groups
- Speech：https://developer.apple.com/documentation/speech
- EventKit：https://developer.apple.com/documentation/eventkit
- MapKit：https://developer.apple.com/documentation/mapkit
- Control Center：先查当前 SDK 中 WidgetKit Control Widget / App Intents 的可用版本与适配设备，不能假设所有旧系统均支持。https://developer.apple.com/documentation/widgetkit
- Live Activities：https://developer.apple.com/documentation/activitykit

## A3. 必须新增的内部架构模块

```
iOS/PersonalAgentApp/
  Intents/                 # Ask, RunWorkflow, Summarize, MorningBrief
  Extensions/Share/       # UI extension + App Group bridge
  Widgets/                # WidgetKit / availability-gated Control Widget
  ToolRuntime/
    ToolRegistry.swift
    LocalToolExecutor.swift
    ParameterValidator.swift
    ConfirmationPolicy.swift
    ResultEnvelope.swift
  Automation/
    EventInbox.swift       # 持久化、去重、来源追踪
    WorkflowRunner.swift   # 状态机；暂停、恢复、失败、确认
    RulesEngine.swift      # 简单场景不用调用 LLM
    NotificationPolicy.swift
  Health/                  # 查询、后台投递、增量/删除、游标
  Location/                # 区域监测与事件去重
  Speech/                  # 按需短时语音输入
  Storage/                 # SQLite/SwiftData + Keychain + 文件保护
  Providers/               # OnlineLLM / OfflineRules / API adapters
  Diagnostics/             # 权限、同步状态、事件日志、可观测性
contracts/                 # 共享 JSON Schema 与 tool manifest
mocks/                     # Windows 开发的事件与系统响应
```

Tool manifest 至少应声明：`name`, `input_schema`, `output_schema`, `permissions`, `requires_foreground`, `requires_network`, `requires_confirmation`, `supported_os`, `fallback`, `timeout`, `idempotency_key`。执行器必须校验模型生成的所有参数，不可以让 LLM 指定任意 URL scheme、进程指令或文件路径直接执行。

## A4. 场景执行的离机策略

- **晨间简报**：用户创建“停止闹钟”个人自动化→调用 App Intent。设备离线时本地读取最近健康统计、日程缓存并注明天气过期；运行超时要保存事件并在下次执行机会恢复。
- **外出助手**：首选 Core Location 区域监测或用户配置的 Shortcuts 位置触发；只传递 `left_home` 等最少事件；天气不足/定位不准时不发误导性提示。
- **运动分析**：HealthKit observer + anchored query + 本地队列；完成的 workout UUID 去重；更新/删除能修正报告；无法保证运动完成后立刻执行。
- **每日复盘**：用户配置 Shortcuts 指定时间启动；BGTaskScheduler 仅作为尽力补充；若错过时间，下一次启动补生成，不应声明“精确 21:30 后台必达”。

通知决策：风险/新颖度/数据有效期/安静时段/每日上限；默认仅价值足够高时通知；事件落库与通知发送结果分别去重。用户随时可关闭某项规则。

## A5. Windows → Mac 迁移要求

Windows 阶段：编写 JSON Schema、纯业务规则、测试事件、Mock iOS 工具、LLM 工具选择契约；可用 Python CLI 验证，但 Python 后端**不得成为 iPhone 独立运行的必选组件**。不得标记 Swift 原生集成为已通过测试。

Mac 阶段：Xcode 构建签名、授权能力、真机安装；替换 Mock 为 Swift 实现并与 `contracts/` 做契约测试。特别验证 iPhone 14 与目标 iOS 版本的部署要求。升级系统前保留兼容性记录。

## A6. 强制验收用例：拔线、关 Mac 后验证

1. 关闭 Mac/断开 USB，iPhone 可从 Siri 和 Shortcuts 运行 `agent.ask`，得到结果或可恢复的离线提示。
2. 在 Safari 分享 URL/选中文字，可直接调用 AI 处理，而不必主动进入独立 AI 聊天 App。
3. 用 Siri 说“导航到某地点”，经明确消歧后打开高德或 Apple Maps 的对应界面；不伪称自动开始导航。
4. 无网络下依然可以读已缓存/已授权的本地健康摘要、查询本地规则，并记录待同步事件；缓存过期有标识。
5. 每个工具在权限拒绝、App 未安装、模型响应异常、锁屏、后台时长不足、网络断开时均返回明确状态而不编造结果。
6. 运动数据更新时，在系统允许的后台机会内生成摘要；不要求秒级实时；强制退出后重新打开可补齐。
7. 四个自动化场景各自拥有去重、冷却和通知上限；提供事件与结果记录。
8. “每日复盘”在错过计划时间后能补生成，不会在次日重复推送昨天的摘要。
9. 完整运行功能不需要 Mac 常驻、USB、WDA、Appium、iOS-Tagent 或 Windows Python 进程。
10. 审查全部 URL Scheme 和三方 API 的当前官方文档；未经核验的参数/可用性标为待真机验证。

## A7. Codex 执行补充指令

请遵循**Standalone iPhone First**：优先让应用在脱离 Mac 的 iPhone 上实现可观察的独立功能。先维护一个 `CAPABILITY_MATRIX.md`，列出每项能力的最低 iOS 版本、所需 entitlement、权限提示、前台/后台限制、是否可通过 Siri/快捷指令触发、是否必须联网、离线降级方案和实机测试状态。请把 UI 自动化测试工具放入 `experiments/`，不得作为主运行依赖。Windows 阶段先完成 contracts、mock、规则与测试；Mac 阶段按单模块顺序实现 App Intents→Share Extension→ToolRegistry→天气/地图/提醒→HealthKit→后台自动化→WidgetKit。每实现一个工具都在 Mac 断开后真机验收，并把已验证/未验证状态写清楚。
