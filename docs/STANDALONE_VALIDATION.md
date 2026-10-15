# Standalone v2 · 第一阶段验证与未完成出口

**用户已确认：先完成源码，迁移 Mac 后编译。** Windows 阶段不再安装 Swift/Visual Studio 依赖或继续尝试 Docker 编译环境。当前四包源码、Mock、27 项 XCTest 与测试入口已准备；Swift 编译和行为验证按此决定延后，不计为通过。

日期：2026-10-15，Windows 11 / PowerShell，工作目录 E:\东少。已完整阅读 v2 正文及附录 A1–A7。本阶段先输出 `SWIFT_FIRST_PLAN.md` 和补齐 `CAPABILITY_MATRIX.md`，再增量扩展既有 Swift Core，未重新生成一个重复项目。

## 已落地源码

- 四个独立 Swift Packages，Core 复用 JSONValue、校验器和 Registry/Executor；工具名改为可扩展安全字符串值类型。
- 独立 manifest 包含附录 A3 的全部字段；参数/结果、权限、规则、事件 Schema 保留原有唯一来源并同步 Swift 资源。
- LocalToolExecuting（LocalToolExecutor actor 实现）、PermissionPolicy、WorkflowRunner、WorkflowStore、LLMProvider 等跨平台接口。
- 六个工具 Mock、可拒绝策略、写入幂等、可信确认、协作超时、失败注入、前台暂停、缓存过期与地点消歧。
- Agent provider → 多轮工具计划 → 整轮验证 → 可恢复 Runner → Executor → 反馈的 Swift 源码；云模型 Mock 默认看不到私密聚合。
- 四个标准事件的基础工具计划及日/运动 ID 去重映射；完整系统触发/健康同步/通知规则属于后续原生阶段。

## 实际执行结果

| 检查 | 结果 | 证据/边界 |
|---|---|---|
| `scripts/test-contracts.ps1` | **50 项通过** | Python 历史行为、JSON Schema、manifest、资源一致性及静态依赖边界；不是 Swift 行为测试 |
| 资源同步后 `tests.test_swift_contract_resources` | 2 项通过 | canonical schemas/manifest/规则与 Swift 资源字节一致；词汇集合未漂移 |
| `scripts/test-swift.ps1` | **阻塞** | 实际报告 `Swift compiler was not found. No Swift build or XCTest has run.` |
| 本地 Docker 编译尝试 | 未形成可用环境 | 已安装 Docker Desktop 启动尝试后仍无 engine pipe；没有运行 Swift 容器，没有安装或启动后端服务 |
| Swift XCTest | **27 项源码已写，0 项已运行** | Core 10、Mocks 3、Providers 3、Workflows 11；不得标为通过 |
| Swift CLI 验收句 | **未运行** | 等待 Swift 编译器；先前 Python CLI 成功不能替代 Swift 验收 |
| iOS/Xcode/真机 | **全部未验证** | 没有 Apple SDK、签名 App、系统权限/入口或拔线实测 |

## Swift 测试覆盖意图（待运行）

六工具 Schema 与 Mock；同一自然语言句的天气→健康→地点→导航；确认与取消；权限安全下限；前后台恢复；过期天气不作跑步结论；空健康数据未知；高德缺席和多候选；故障后恢复且不重放已完成天气；JSON 检查点跨 store/executor 恢复候选；整轮模型异常拒绝且没有任何工具执行；云端结果脱敏；模型不可用本地 fallback；扩展工具注册；超时；四个场景计划重复执行不重复调用工具。

这些目前是测试设计和源码，不是已证明的运行行为。阶段 1 的完整出口仍包含真实 Swift 编译与上述测试通过；因此本次不能将阶段 1 标为完整验收。

## 编译准备与复现

按用户确认的安排，迁移 Mac 后先记录实际 `xcodebuild -version`、`xcodebuild -showsdks` 和 `swift --version`，然后依次执行：

```sh
swift test --package-path iOS/Packages/DongShaoCore
swift test --package-path iOS/Packages/DongShaoMocks
swift test --package-path iOS/Packages/DongShaoProviders
swift test --package-path iOS/Packages/DongShaoWorkflows
swift run --package-path iOS/Packages/DongShaoWorkflows dongshao '帮我看看今天适不适合跑步，并且导航到附近的公园。'
```

先修复所有编译与测试问题，再接入 Apple Framework。以下 Windows 安装说明仅保留为替代方案，当前不执行。

当前没有 Windows Swift/Visual Studio C++ 工具链。按 [Swift 官方 Windows 指南](https://www.swift.org/install/windows/) 配置 Swift 及 Windows SDK/C++ 开发依赖后：

```powershell
.\scripts\test-swift.ps1
# 或指定现有编译器
.\scripts\test-swift.ps1 -SwiftPath 'swift.exe 的完整路径'
swift run --package-path iOS/Packages/DongShaoWorkflows dongshao '帮我看看今天适不适合跑步，并且导航到附近的公园。'
```

也可在 Mac 逐个 `swift test --package-path iOS/Packages/包名`。即使跨平台 Swift 测试全部通过，仍要另做 Xcode iOS 构建、签名和附录 A6 的拔线/关 Mac 验收。开发容器若未来可用，只作为测试手段，不写入正式产品依赖。

## 仍待原生阶段解决

App Intents/Siri/Share/Shortcuts 入口，真实天气/地图/日历/提醒/健康 adapter；iOS 权限和锁屏状态复核；App Group 事务/文件保护/Keychain；持久审计、写入结果未知时的原生幂等核对；健康 anchor/删除处理；缓存生命周期、事件/通知分别去重、静默/冷却/每日上限与补生成；Widgets。LocalWorkflowStore 当前 JSON 文件只适合单进程原型，未加密、未跨进程锁定、未自动清理，不能直接当作正式 App Group 存储。

本阶段没有加入 Appium、WDA、iOS-Tagent、PythonKit、任意 URL/进程/文件执行工具，也没有公开 Framework 不支持的权限或后台保证。
