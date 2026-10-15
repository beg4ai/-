# DongShaoWorkflows

库目标只依赖 Core。开发 `dongshao` CLI 和 XCTest 才依赖 Mocks/Providers；正式 iOS App 只链接库并在 composition root 注入 native tools 和所选 provider。

WorkflowRunner 协议与 LocalWorkflowRunner 保存检查点，具有运行、待确认、待前台、待重试、失败、取消和完成状态。已完成步骤不重放；同 ID 不能替换计划前缀。故障恢复前可从受校验的历史结果恢复最小上下文。中断写入若结果未知，拒绝自动重放，等待 native 幂等记录核对。

LocalWorkflowStore 可用内存或原子 JSON 文件。它仅适用于单进程原型，不提供 App Group 跨进程事务、加密、自动清理或 native 数据保护。正式 App/扩展阶段须换成具备事务与数据保护的存储 adapter。工作流记录保留步骤参数与本地聚合，不能当作已脱敏的公开日志。

AgentCoordinator 实现 Swift provider → 整轮 Schema 校验 → Runner → Executor → 结果反馈循环，限制轮次/调用数并拦截重复。默认不向非本地 provider 提供健康/日历/提醒结果；可替换模型不可用时可注入离线规则 fallback。显式从同一 run ID 恢复时重新评估当前权限、前台、网络与提醒日期。

ScenarioPlans 提供晨间、离家、运动、复盘的标准事件到工具计划映射与基础 ID 去重。**还没有连接系统触发、原生通知策略、完整 workout 增量/删除或四场景通知上限**，这些按计划在 Mac 阶段补齐，不能以本包 Mock 成功替代脱机真机验收。

工具链就绪后：

```powershell
swift test --package-path iOS/Packages/DongShaoWorkflows
swift run --package-path iOS/Packages/DongShaoWorkflows dongshao '帮我看看今天适不适合跑步，并且导航到附近的公园。'
```

CLI 默认保存 `.agent/swift-workflows.json`，输出含 trace/run ID。用相同 `--run-id` 和 `--store` 重试或恢复确认；`--confirm` 逐项询问，缺省不审批。当前只是 Mock 工具，即使确认也不打开地图、不写系统提醒。其他 flags 见 `--help`。Swift CLI/测试目前因缺少编译器尚未运行。
