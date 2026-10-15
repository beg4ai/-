# 共享契约入口

`tool-manifest.json` 声明附录 A3 的工具元数据。已有 `../schemas/*.json` 继续作为唯一 Schema 来源，避免移动路径破坏 Python 回归与已写的 Swift 资源。

每个工具的 input/output 由 `urn:dongshao:v1:工具名#/$defs/input` 与 `output` 指向对应 schema。manifest 中的 permissions 是项目内部权限标识，不是 Apple entitlement；Native adapter 必须按真实 OS 和授权状态检查。

附录 A 的日历读取能力对应现有 canonical 名称 `calendar.events`，保留既有参数/结果契约，避免另造一个相同行为的实现；后续原生 `calendar.read` 展示/入口名可适配到该工具。`agent.ask`、`agent.run_workflow` 等是后续 App Intent 入口，当前的 Core/Runner 并不表示这些 iOS 入口已经可发现。

新增工具流程：先增加 Schema、manifest 和风险/权限测试，再注册可信 handler；Swift ToolName 是受限字符串值类型，不再需要修改核心枚举。工具未知时拒绝，不能由模型动态注册代码。MCP/API adapter 将来同样经过本地参数校验和确认，不能通过名称或 schema 引用执行任意 URL、文件路径或进程。

`requires_foreground` 与 `requires_network` 描述实际能力要求。Mock 会模拟离线缓存且始终标记为 Mock；这不代表正式工具能离线获取新天气/搜索数据。`timeout` 仅对合作取消的异步调用有效；`idempotency_key` 声明需由 native 写入适配器持久落实的参数。

维护者修改契约后运行资源同步与测试：

```powershell
.\.venv\Scripts\python.exe scripts/generate_contracts.py
.\.venv\Scripts\python.exe scripts/sync_swift_contracts.py
.\scripts\test-contracts.ps1
.\scripts\test-swift.ps1
```

生成器会更新 manifest/Schema 的版本内默认内容，不自动更改现有权限配置。Swift 包的资源是受检查的副本，不在两个目录分别手改。
