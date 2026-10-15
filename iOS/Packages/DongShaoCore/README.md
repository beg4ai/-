# DongShaoCore · Swift 执行边界

最终 iPhone 应用使用 Swift。这个 Package 是实际 Swift 源码，而不是让 Swift 调用 Python 服务的桥。它只依赖 Foundation，不引入 SwiftUI、App Intents、HealthKit、EventKit 或第三方 Package。

**验证状态：尚未编译。** 2026-10-15 当前机器没有 `swift`，WSL 仅有 Docker 内部发行版，Docker daemon 未运行。没有为此安装大型 Windows 工具链或修改系统。可以在 Mac 的 Xcode 工具链运行，也可按 [Swift 官方 Windows 安装说明](https://www.swift.org/install/windows/) 配置 Windows Swift 和所需开发依赖；Windows 只能验证此类跨平台核心，不能构建 iOS Framework。

## 已写入的边界

- `JSONValue`：可编码的 JSON 值，支持 null，拒绝非有限数。
- 契约类型：可扩展 ToolName 值类型、六个预定义名称、风险、结果状态、错误、统一 ToolResult、可信 ExecutionContext。
- `SchemaValidator`：覆盖当前仓库 Schema 使用的有限关键字集；严格字段、日期/时区格式、范围、枚举、数组、内部引用。不是完整 Draft 2020-12 实现，未知关键字拒绝；不获取远程 Schema。
- `ToolRegistry` / `ToolExecutor`：actor 注册、同调用并发保护、manifest 元数据、固定权限安全下限、先校验参数后执行、可信异步确认、取消无写入、协作超时、成功输出和统一 envelope 再校验。
- `PermissionPolicy`、`LocalToolExecuting`、`ToolAuditSink`、`LLMProvider` 协议；MemoryAuditSink 只保存脱敏执行元数据，正式原生持久化待接入。
- `AutomationRules` 读取与 Python 相同的 JSON 偏好阈值；不复制维护第二套默认配置。
- 10 项 XCTest 源码：共用 JSON 输入、天气/提醒 Mock、必需权限、待确认/取消、确认后执行、伪造审批、非法日期/NaN、未知工具、扩展工具和协作超时。

六个完整 Mock 在 `../DongShaoMocks`，离线/脚本模型在 Providers，WorkflowRunner/存储/Agent/开发 CLI 在 Workflows。Core 不依赖它们或 Apple Framework。Native adapter、正式持久审计、跨进程事务、原生幂等记录、HealthKit anchor 仍待后续实现，不把当前未编译源码接入真实副作用。

## 编译与测试（等待可用 Swift 工具链）

```sh
swift test --package-path iOS/Packages/DongShaoCore
```

Mac 上首先执行这条命令，修复所有编译和 XCTest 问题，再新增原生模块。iOS App 后续把本目录作为 Local Swift Package 加入 Xcode，Display Name 为东少。macOS/Windows 核心测试通过也不能替代 iOS App 构建和真机测试。

## 契约唯一来源

根目录 `schemas/*.json` 和 `fixtures/tool-cases.json` 是唯一来源；SwiftPM 资源仅为逐字复制，以便独立打包使用。修改契约后运行：

```powershell
.\.venv\Scripts\python.exe scripts/sync_swift_contracts.py
.\.venv\Scripts\python.exe scripts/sync_swift_contracts.py --check
.\.venv\Scripts\python.exe -m unittest tests.test_swift_contract_resources -v
```

以上检查**只证明资源没有漂移、Schema 没引入未声明支持的关键字**，不证明 Swift 实现的运行行为。最终以 `swift test` 以及跨语言相同输入/状态测试为准。
