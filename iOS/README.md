# 东少 Swift 核心与原生 App 设计

主线为 `Packages/` 下 Core、Mocks、Providers、Workflows 四个 Swift Packages；保留已有 Core 并增量补齐 manifest、权限协议、Mock、多轮编排和可恢复状态机。本机没有 Swift 编译器，当前 27 项 Swift XCTest **未编译运行**；50 项 Python/契约/资源/依赖检查不等同于 Swift 验证。详见 `../docs/STANDALONE_VALIDATION.md`。

`DongShao/` 保留 SwiftUI/App Intents/系统 adapter 等模块设计，目前没有 App .xcodeproj。迁移 Mac 后先验证四个包，再创建 SwiftUI App + ContractTests 并按 App Intents→Share→天气/地图/提醒→HealthKit→后台→Widgets 的顺序接入。每一项都必须在拔线、关闭 Mac 后实测。最终显示名为“东少”，Bundle ID/App Group ID 在用户 Team 下创建，维持有效签名。
