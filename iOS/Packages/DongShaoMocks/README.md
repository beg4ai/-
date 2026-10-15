# DongShaoMocks

开发/测试专用，依赖 Core；不链接到正式 iPhone App 的库目标。

`MockToolExecutor.make` 注入六个工具，使用真实 Core Schema、PermissionPolicy 与确认执行边界。包含演示天气、健康缺失、空日历、搜索/导航、提醒幂等、一次性错误注入、协作延迟、地点歧义和模拟未安装高德。任何导航都 `opened=false`，提醒 `simulated=true`。

MockPermissionPolicy 可模拟拒绝，但不能削弱 Core 的必需权限与确认安全下限。跨执行器恢复时，只从已校验的工作流搜索结果重建候选，过期结果拒绝使用。离线天气明确标记 stale。

Windows 尚无编译器：当前 Swift 测试源码未运行。具备工具链后：`swift test --package-path iOS/Packages/DongShaoMocks`。
