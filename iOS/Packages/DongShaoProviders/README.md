# DongShaoProviders

纯 Swift，依赖 Core 的 LLMProvider 协议。当前提供：

- OfflineRulesProvider：受限中文离线路由，支持今天白天跑步评估、导航、明早提醒；不冒充模型理解能力。
- MockLLMProvider：脚本化模型轮次和不可用错误，用于测试参数校验、多工具反馈、脱敏、预算与本地 fallback。

本阶段没有 Swift 在线模型/公共 HTTP 实现，没有 API Key、Python 或桌面服务依赖。后续把用户配置的 HTTPS 模型 adapter 注入同一协议，使用 iPhone URLSession/Keychain；不得让远端计划批准本地写入。在线/本地 provider 元数据是应用配置，不采信模型自行声明的授权。

Windows 尚无编译器：当前 Swift 测试源码未运行。具备工具链后：`swift test --package-path iOS/Packages/DongShaoProviders`。
