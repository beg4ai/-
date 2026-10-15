# 数据、权限和用户确认

## 当前原型

默认数据为 Mock，`ExecutionContext.permissions` 仅模拟权限授予/撤销，不会弹出或取得任何 Apple 权限。`--deny` 用于测试失败分支。真实公共接口只有显式 `--public-api` 时启用，必须用户配置位置；模型接口只有 `--llm ollama` 时启用。

| 工具 | 风险 | 前置 scope | 确认 |
|---|---|---|---|
| weather.forecast | readOnly | location.share | 无写入确认；真实接口需先显式选择公共 API 模式 |
| maps.search | readOnly | location.share | 搜索不确认；多候选目标由用户选择 |
| maps.navigate | externalAction | 无健康/日历权限 | 必须；Windows 仅提案，确认也不打开应用 |
| health.summary | readOnly，数据私密 | health.read | 模拟类型授权；默认不传给 LLM |
| calendar.events | readOnly，数据私密 | calendar.read | 模拟授权；默认不传给 LLM |
| reminders.create | localWrite | reminders.write | 必须预览标题、时间、时区；当前只演示写入 |

权限策略独立见 `config/permissions.json`，由 `schemas/permission-policy.json` 校验。当前写入与导航的安全下限固定在可信执行器中，不接受模型修改；模型参数不能携带批准。CLI 的 `--confirm` 只启用交互确认，缺省/非 TTY 都不会静默批准。当前尚未实现持久信任白名单或“以后不再询问”。

## 模型与网络

配置模型意味着请求文本、当前时间、配置位置和非敏感工具结果会发送至该 Endpoint。健康、日历、提醒工具结果默认脱敏，`--share-private` 才允许发送这些**聚合/选定窗口**的结果。原始健康样本没有被实现或上传；用户在原始请求中自行输入的信息仍会进入模型上下文。

API Key 仅从 `AMAP_API_KEY` / `AGENT_LLM_API_KEY` 环境读取，不写源码、SQLite 或工具 trace。`.env` 被忽略且当前不自动加载；Shell 历史仍可能保存手工输入，请从系统安全存储注入生产凭据。Windows 环境变量不是 Keychain，也不是加密存储。HTTP 禁止携带凭据跨域重定向；远程必须 HTTPS，明文 HTTP 只允许回环地址。异常仅记通用错误与状态，不输出包含高德 Key 的 URL、请求头或响应体。

模型只规划白名单工具；目的地/分享内容等自然语言不可成为 shell、代码或任意 URL 的执行入口。文本结果仍可能包含不可信内容；任何确认界面都必须根据已验证的结构化参数构建，不能用模型一句“已批准”作为授权。

## 本地留存和限制

默认 `.agent/state.sqlite3` 保存：事件 ID/时间/必要 payload、报告中的聚合结果、演示提醒、工具名/风险/trace/参数 SHA-256/状态/错误码，以及通知策略记录。不会在审计表保存请求文本、健康原始记录、密钥或完整工具参数。SHA-256 用于审计关联，不是匿名化保证，低熵内容仍可能被猜测。

SQLite 当前**未加密**，原型也未实现自动过期清理。默认内容全为 Mock；接入真实私密工具前应补上最小留存策略、导出/清除操作及系统数据保护。仓库忽略 `.agent/`、`.env`、数据库和虚拟环境；不要将运行数据库提交或迁移到共享服务。需要清除时先关闭所有 CLI，再由用户删除 `.agent` 数据目录（本项目不会自动执行删除）。

## 原生阶段必须逐项实现

HealthKit 只申请所需读类型，`NSHealthShareUsageDescription` 写明用途。读授权不能可靠区分“用户拒绝”和“没有样本”，空值保持未知；系统设置撤销后停止采集并处理已有缓存。健康增量数据只在结果落盘后推进 anchor，处理删除与重传。[Apple 健康授权](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)

日历读取使用 iOS 17+ full access 及 `NSCalendarsFullAccessUsageDescription`；提醒使用 full access 及 `NSRemindersFullAccessUsageDescription`，只在写入功能启动时请求。审批取消或系统拒绝时不得保存。[Apple EventKit 授权](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)

主 App/扩展通过同一 App Group 共享最低必要的输入与状态；敏感文件使用 iOS 数据保护，LLM Key 使用 Keychain 可用性策略，不把 API Key 放共享明文偏好。锁屏不可访问的健康数据应排队等解锁，不能降低保护等级来假装后台可靠。[App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [Keychain](https://developer.apple.com/documentation/security/keychain-services)

位置先按需 When In Use；若用户选择原生离家监测，再核对当前 SDK 的 region/后台授权要求。通知单独按需授权。不要启动时一次请求所有敏感权限，也不为了自动化索取通讯录/相册全库权限。
