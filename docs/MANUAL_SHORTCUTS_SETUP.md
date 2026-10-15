# 后续 iPhone 14 Pro 系统入口手册

**当前尚无可安装的 iOS App 或 App Intent，这些步骤是 Mac 原生阶段的验证手册，不是已经可用的入口。** 先按迁移文档创建并签名构建东少，确认 AskAgent 和四个场景动作已经在 Shortcuts 中出现，再逐项配置。各 iOS 版本的菜单文字、立即运行/运行前询问能力可能不同，以真机所见和 [Apple 用户指南](https://support.apple.com/guide/shortcuts/welcome/ios) 为准。

## Siri 和普通快捷指令

1. 在“快捷指令”新建“问东少”，添加东少的 AskAgent 动作。
2. 把文本参数设为“每次询问”或快捷指令提供的输入；先手动输入验收句。
3. 读取天气/健康等结果，遇到地点歧义应列候选，需要外部动作应给确认。
4. 用 Siri 说“运行问东少”，验证中文识别、参数询问、失败和取消；也测系统是否要求解锁。
5. 若 Siri 未识别，先回到 Shortcuts 确认动作可手动运行和命名无冲突，不声称绕过 Siri 限制。

## 轻点背面

在“设置 → 辅助功能 → 触控 → 轻点背面”中选择双击或三击，并选择“问东少”。分别在解锁和锁屏测试是否触发、是否需要前台确认。这是用户设置的快捷入口，不是后台读取当前屏幕。[Apple 轻点背面说明](https://support.apple.com/guide/iphone/use-back-tap-iph88ab07cfd/ios)

## 晨间简报

1. Shortcuts 的“自动化”中新建“闹钟”相关自动化，选择停止闹钟事件和目标起床闹钟。
2. 添加东少的晨间简报 App Intent；由 Intent 生成 `alarm.stopped` 标准事件。
3. 按当前系统提供的选项选择立即运行或确认；不要假设所有版本都可静默。
4. 停止两个闹钟验证同一天只一份；睡眠未同步时报告必须标明缺失。

闹钟是 [Apple 事件触发器](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios) 提供的用户自动化入口，App 不读取系统闹钟私有数据库。

## 离家提醒

在自动化中新建离开指定地点的触发，明确选择家的位置和范围，添加东少外出助手动作。按系统要求确认定位和自动化运行选项。实际离开范围后记录触发延迟；没有事件时不能宣称原生定位监听已经替代系统行为。同风险重试、新风险 90 分钟内和安静时段分别验证。[Apple 定位触发器](https://support.apple.com/guide/shortcuts/travel-triggers-apd8ebfc4e8e/ios)

若后续改用 Core Location region，另行按系统授权与后台行为测试，不把这两条触发路径同时开启却漏去重。

## 每日复盘与运动

在自动化中选择“时间”触发，例如每天 21:30，添加每日复盘动作；确认用户设备的运行提示选项。BGTask 不用来承诺 21:30 准点。晚间信息少或进入安静时段时只归档。[Apple 时间触发器](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios)

运动完成优先由完成原生集成后的 HealthKit observer/anchored sync 产生 workout UUID 事件，不猜测当前所有“运动”快捷指令触发器都能读取已同步的完整健康数据。停止运动与 HealthKit 记录可读可能存在间隔，需真机测量和延迟重试。

## 分享入口

Safari 分享菜单中选择东少扩展，先分享文本和 URL，确认扩展只接收用户主动提供的内容。照片/文件支持加入后另测体积上限、取消和超时。URL 本身不等于网页正文；摘要若未抓取正文必须明确只基于链接/选中文本。不能通过通用 URL 抓取自动打开登录内容或冒充能读取第三方 App 的私有页面。
