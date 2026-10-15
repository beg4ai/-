# 东少 · Personal Agent

**Standalone iPhone First · Swift-first · Local-first。** 以 `PersonalAgent_iOS_Codex_Spec_Standalone_v2.md` 附录 A 为最高需求。最终 Swift 应用在拔掉 USB、关闭 Mac 后独立运行；Python、Docker、Xcode Runner、Appium、WDA、iOS-Tagent 均不是手机运行依赖。在线天气/搜索/可选模型仍可能需要网络。

当前是 **Swift 第一阶段源码与测试准备**，不是已经构建的 iPhone App。保留此前 Python 原型和现有 Swift 核心，渐进扩展，不重写已验证的旧模块。显示名称为 **东少**。结构、审查、分阶段出口见 [SWIFT_FIRST_PLAN.md](docs/SWIFT_FIRST_PLAN.md)，能力/权限/后台边界见 [CAPABILITY_MATRIX.md](docs/CAPABILITY_MATRIX.md)。

## Swift 主线

| Package | 职责 |
|---|---|
| [DongShaoCore](iOS/Packages/DongShaoCore/README.md) | JSON 契约、可扩展工具名、manifest/Registry、PermissionPolicy、LocalToolExecuting/Executor、审计接口 |
| [DongShaoMocks](iOS/Packages/DongShaoMocks/README.md) | 六个工具 Mock、拒绝/错误/歧义/缓存/高德缺席、提醒幂等 |
| [DongShaoProviders](iOS/Packages/DongShaoProviders/README.md) | LLMProvider 协议实现：离线规则与脚本化模型；不依赖 Python |
| [DongShaoWorkflows](iOS/Packages/DongShaoWorkflows/README.md) | WorkflowRunner、检查点/恢复、Agent 多轮编排、四场景事件映射；开发 CLI 单独目标 |

库只依赖 Foundation 和 Core，不 import UIKit、HealthKit、App Intents。正式 iOS App 后续注入 native adapters，开发 CLI/Mocks 不链接进生产库。独立工具 manifest 在 [contracts/](contracts/README.md)，现有 `schemas/` 保持唯一 Schema 来源。敏感读结果默认不交给非本地模型；本地写入和导航必须可信确认。

当前验证：**50 项 Python/契约/资源/静态依赖检查通过；27 项 Swift XCTest 已写但未运行。** `test-swift.ps1` 实际报告编译器缺失；Docker 启动尝试也没有得到可用引擎。没有把静态检查计作 Swift 或 iPhone 验证。详情见 [STANDALONE_VALIDATION.md](docs/STANDALONE_VALIDATION.md)。

**已按用户决定采用“先完成源码，迁移 Mac 后编译”。** Windows 阶段不再配置编译环境；Mac 的四包测试与 CLI 验收命令已列在上述验证记录中。以下 Windows 工具链命令仅作为备选。

Windows 配好 [官方 Swift 工具链及平台依赖](https://www.swift.org/install/windows/) 后执行：

```powershell
.\scripts\test-swift.ps1
# 已有编译器不在 PATH 时：
.\scripts\test-swift.ps1 -SwiftPath '你的 swift.exe 完整路径'
swift run --package-path iOS/Packages/DongShaoWorkflows dongshao '帮我看看今天适不适合跑步，并且导航到附近的公园。'
```

Swift CLI 默认演示数据、离线规则，不启动服务；待确认动作不会执行。`--confirm` 逐项预览询问，确认也仅模拟；用相同 `--run-id` 与 `--store` 恢复。`--help` 查看拒绝权限、断网、后台、歧义和一次性故障等测试 flags。当前真实 Apple API、Swift 在线模型 provider、完整通知策略均留在后续阶段，不宣称已实现。

现有 Windows 契约/历史回归检查：`.\scripts\test-contracts.ps1`。Swift 编译测试必须单独通过，之后才允许接入实际副作用。

## 历史 Python 原型运行参考（非正式运行时）

需要 Python 3.11+；本次实际使用 Windows Python 3.14.7。

```powershell
cd E:\东少
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m agent ask '帮我看看今天适不适合跑步，并且导航到附近的公园。'
```

省略请求文本可进入单次交互输入：`python -m agent ask`（先激活虚拟环境，或继续使用上述完整 Python 路径）。默认不联网，不需要 API Key，不部署后台服务。

默认依次选择 `weather.forecast → health.summary → maps.search → maps.navigate`，返回 JSON：

```json
{
  "planner": "offline_rules",
  "status": "pending_confirmation",
  "contains_mock_data": true,
  "actions": [{
    "type": "open_navigation",
    "provider": "amap",
    "requires_confirmation": true,
    "opened": false,
    "execution": "proposal"
  }]
}
```

实际 JSON 包含天气/健康结果、来源、工具 trace、评估理由，以及完整高德 URI 和 Apple Maps 回退链接。**所有默认天气、健康、日历、地点均为演示数据，不是你的真实状态或真实公园。** 坐标是明确标注的上海测试位置。离线路由是受限规则解析器，不能冒充通用模型；当前支持今天白天跑步评估、导航到某地、`明天早上9点提醒我开会`。复杂表达会要求补充信息或配置模型，不猜测。

## 已实现的模块

| 模块 | 本次内容 |
|---|---|
| 契约 | 独立 Draft 2020-12 Schema：六个工具 input/output、调用、结果、事件、权限、规则、Agent 返回、工作流报告 |
| Tool Registry | 已注册工具白名单、LocalToolExecutor / RemoteToolExecutor、集中校验和审计 |
| 权限 | 按 scope 拒绝、写入逐项确认、外部动作不可降低为只读；模型无审批权 |
| 工具 | 六个工具均有 Mock；天气有 Open-Meteo adapter，地点有高德 Web API adapter |
| LLM | LLMProvider 协议；Ollama HTTP 多轮 Tool Calling，Endpoint/模型/Key 可配置 |
| 自动化 | 晨间简报、离家提醒、运动分析、每日复盘；显式 CLI 事件、SQLite 去重/队列/重试、JSON 规则 |
| Swift 首个增量 | DongShaoCore Package：契约值类型、有限 Schema 校验、actor Registry/执行器与 XCTest 源码；当前未编译 |
| 迁移准备 | 共享契约测试向量、Mac 构建和 iPhone 14 Pro 验证步骤 |

架构与边界：[ARCHITECTURE.md](docs/ARCHITECTURE.md)。官方支持与当前实现状态：[CAPABILITY_MATRIX.md](docs/CAPABILITY_MATRIX.md)。

## 参数、权限与确认

以下命令均以虚拟环境内的 `python` 为例。未经确认的动作只返回参数预览。`--confirm` 会逐项询问 `y/N`，并不自动批准；非交互输入按取消处理。Windows 即使确认导航也只返回 `approved_not_opened`。提醒仅写入本地演示数据库，带 `simulated: true`。

```powershell
python -m agent ask '明天早上9点提醒我开会' --confirm
python -m agent ask '今天适合跑步吗' --deny health.read
python -m agent ask '导航到公园' --mock-ambiguous
python -m agent ask '导航到公园' --mock-ambiguous --place-id mock-park-2
python -m agent ask '导航到公园' --mock-no-amap
python -m agent ask '今天适合跑步吗' --mock-empty-health --mock-rain 80
python -m agent schemas
python -m agent tool reminders.create --args '@examples/reminder.json' --now '2026-10-15T08:00:00+08:00'
```

地点多候选不会自动取最近项。`--place-id` 必须匹配本轮搜索候选；真实搜索重试时 ID 可能变化，需要重新核对。

## 可选模型 API

实现遵循 [Ollama 官方 Tool Calling 协议](https://docs.ollama.com/capabilities/tool-calling)。可配置本地 Ollama 或提供相同协议的 HTTPS Endpoint。模型必须实际支持工具调用，本项目不自动下载模型、不安装模型服务。

```powershell
$env:AGENT_LLM_URL = 'http://127.0.0.1:11434/api/chat'
$env:AGENT_LLM_MODEL = '填写你已安装且支持工具调用的模型名'
# 远端有鉴权时，设置 AGENT_LLM_API_KEY；不要写进源码。
python -m agent ask '帮我看看今天适不适合跑步，并且导航到附近的公园。' --llm ollama
```

这条命令会将请求文本、当前时间、配置位置和非敏感工具结果发给所配置模型。健康聚合、日程与提醒结果默认留在本地，模型仅看到 `redacted`；最终跑步评估仍由本地规则生成。用户明确同意后可加 `--share-private` 传递这些工具结果。模型从用户原始文本中已获得的个人信息无法通过结果脱敏收回。其他供应商需实现 `LLMProvider`，不是将任意 API URL 填进 Ollama 协议即可兼容。

每轮参数通过 Schema 后才执行；工具调用有轮次和数量限制、重复调用拦截，模型不能执行 shell、Swift 或任意 URL。模型文字不作为成功执行的证据，请看 `tool_results` 与 `actions.opened`。

## 可选真实公共 API

`--public-api` 显式启用真实天气和高德搜索；**健康、日历、提醒仍为 Mock**。必须手动提供 WGS-84 位置，不会读取 Windows 或 iPhone 定位。此模式会将坐标发送给天气服务和高德。高德使用环境变量 `AMAP_API_KEY`，需为 Web 服务 Key。绝不将 Key 交给模型或写进日志。

```powershell
$env:AMAP_API_KEY = '从安全存储注入你的 Web 服务 Key'
python -m agent ask '今天适不适合跑步，并且导航到附近的公园' --public-api --latitude 31.23 --longitude 121.47
```

上面是公开测试坐标，请替换为你选择的位置。高德返回多个候选时，查看 ID 后加 `--place-id` 重新核对。WGS-84 先经高德官方坐标转换接口再搜索；不使用手写近似转换。高德搜索返回 GCJ-02，导航 `dev=0`；Mock WGS-84 导航 `dev=1`。GCJ-02 目的地的 Apple Maps 链接按名称重新查找，不混用坐标，实际目的地仍需确认。

当前天气是指定日期白天逐小时聚合：均温、最大降雨概率与最大风速，不是某一时刻的跑步保证；不含空气质量/地面情况。Open-Meteo 的非商业免费额度与署名条件见 [官方价格页](https://open-meteo.com/en/pricing) 和 [文档](https://open-meteo.com/en/docs)。离线错误保留为可重试状态，不静默替换为 Mock 成功。

## 四个工作流

```powershell
python -m agent event --type alarm.stopped --id wake-1
python -m agent event --type location.left_home --id away-1 --mock-rain 80
python -m agent event --type health.workout_completed --workout-id mock-workout-1
python -m agent event --type schedule.evening --id evening-1
python -m agent replay
python -m agent reports --limit 10
```

`event` 可从 `--file examples/morning-event.json` 导入标准事件；测试时配合 `--now`。当前无后台进程，CLI 不会自行感知闹钟、离家或运动，也不发送系统通知。报告中的 `notification.should_notify` 是策略建议，`delivered` 始终为 false。离家同一天同一风险仅建议一次，新风险受 90 分钟冷却限制；22:00–07:00 安静，延迟 6 小时以上的旧事件仅归档。运动事件未找到对应 UUID 时保留队列，默认总共尝试三次；不会把日汇总当成该次运动。每日复盘读取日程、健康与本地演示提醒记录数；系统待办清单读取留到 Mac 后续扩展。

编辑 `config/automations.json` 可调整降雨、风速、睡眠阈值、安静时间、冷却和重试次数；也可 `--rules 路径` 指定独立文件。当前用户时区固定 Asia/Shanghai。阈值为可解释的个人偏好规则，不能作为医疗标准。

## 测试与迁移

```powershell
.\.venv\Scripts\python.exe -m unittest discover -v
```

本次测试与真实 API 验证见 [VALIDATION.md](docs/VALIDATION.md)。原生实现逐个替换顺序见 [MIGRATION_TO_MAC.md](docs/MIGRATION_TO_MAC.md)，系统入口手工配置见 [MANUAL_SHORTCUTS_SETUP.md](docs/MANUAL_SHORTCUTS_SETUP.md)，数据处理见 [PRIVACY_AND_PERMISSIONS.md](docs/PRIVACY_AND_PERMISSIONS.md)。

Swift 当前主线为上文四个 Packages，含编排/恢复源码、六类 Mock 和模型协议；27 项 XCTest 尚待编译器运行。以下核心包命令只是其中一项，不能替代四包测试：

具备工具链后先运行：

```powershell
swift test --package-path iOS/Packages/DongShaoCore
```

`iOS/DongShao/` 仍为 App 模块设计目录，不含 Xcode App 工程。Mac 阶段先构建通过核心包，再创建 SwiftUI 工程与系统入口，最后逐个接入 Apple Framework、构建与真机测试。
