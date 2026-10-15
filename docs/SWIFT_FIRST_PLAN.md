# Standalone iPhone First · Swift-first 审查和实施计划

最高优先级：`PersonalAgent_iOS_Codex_Spec_Standalone_v2.md` 附录 A，以及用户明确的 Swift-first + Local-first 补充要求。旧 Python 原型仅保留为协议回归基准；新增核心行为以 Swift 实现。最终 iPhone 进程在获系统执行机会时独立工作，不依赖 Mac、USB、Python、Xcode Runner、Appium、WDA 或 iOS-Tagent。联网不是连接 Mac：天气、搜索、用户配置的模型可使用网络。

已确认的开发安排：**Windows 先完成源码，Swift 编译/XCTest 留到迁移 Mac 后运行。** 不继续安装 Windows 编译依赖或尝试启动 Docker。Windows 契约/资源检查与未来 Mac Swift 测试、iOS 拔线真机验收分别记录。

## 当前审查

已有 DongShaoCore Package：JSONValue、六个工具名、统一结果、有限 Schema 校验、actor Registry/Executor 与首批 XCTest。之前因没有编译器而明确标为未编译。已有 Python 规则/Mock/SQLite 测试，不将其计为 Swift 或 iPhone 验证。

保留上述类型、Schema 与测试，逐项增强。缺口：枚举工具名不利于扩展；风险/权限写在注册闭包中；没有完整 manifest；没有 LocalToolExecutor/PermissionPolicy/WorkflowRunner 的可替换接口；Swift 中尚无生产可用 Mock、LLM 选择闭环、持久工作流。现阶段不重写 Python，不预造 Apple Framework 代码。

## 项目结构与依赖方向

```text
schemas/                         # 既有唯一 JSON Schema 来源，保留路径
contracts/tool-manifest.json      # A3 必备字段；未来工具先登记契约
fixtures/                        # 既有共享行为向量
iOS/Packages/
  DongShaoCore/                   # Foundation 契约、Registry、权限/执行协议
  DongShaoProviders/              # 依赖 Core；本地规则、可替换模型实现
  DongShaoMocks/                  # 依赖 Core；系统能力 Mock 和故障注入
  DongShaoWorkflows/              # 库只依赖 Core；可恢复状态机和 Agent
    Sources/DongShaoCLI/          # 开发可执行目标，可依赖 Providers/Mocks
    Tests/                       # 端到端测试注入 Mock
iOS/DongShao/                     # 后续 SwiftUI/Intents/Share/原生 adapters
scripts/                         # 资源同步、跨平台 Swift 测试入口
docs/                            # 能力矩阵、构建记录、脱机真机验收
agent/                           # 保留的 Python 历史原型，不是正式运行时
experiments/                     # 仅在将来明确开展 UI 自动化实验时使用
```

Core、Providers、Workflows 的库不 import UIKit/HealthKit/AppIntents。iOS composition root 负责把官方框架 adapters 注入 LocalToolExecutor。Mock 仅由测试和开发 CLI 链接；正式 App 不链接开发 CLI，也无需启动电脑上的服务。

## 本次阶段 1

1. 完善能力矩阵：最低版本、entitlement/用途提示、前后台、Siri/Shortcuts、网络、离线降级、真机状态。
2. manifest 独立于实现，声明 name、input/output schema、permissions、foreground/network、confirmation、OS、fallback、timeout、idempotency key；保持现有六个工具 wire name，避免无必要改协议。
3. 沿用 Swift 校验器/Executor，引入可注入 PermissionPolicy、LocalToolExecuting 和模型协议，集中校验所有模型参数。注册器扩展新工具不依赖 UIKit，也不接受任意脚本或 URL。
4. 在独立 Mock Package 提供天气、搜索/导航、健康、日历、提醒，覆盖空值、权限拒绝、歧义、高德缺席、可重试失败。写入确认和幂等由本地执行边界落实。
5. WorkflowRunner 维护完成/失败/待确认/取消/重试状态；以可替换存储保存检查点，不让模型控制审批。Swift 离线规则和 Mock LLM 都能驱动多工具链。
6. 运行 Swift Package 单元与端到端测试；Windows 若使用本地 Linux 编译容器，只记为“Windows 主机上的 Linux Swift 跨平台验证”，绝不记为 Windows 原生 ABI 或 iOS 测试通过。

阶段出口：Swift CLI 中验收句依次产生天气/健康/地点/导航结果，URI 来自可信地点结果，外部动作待用户确认；成功/取消/拒绝/异常模型/失败恢复均有自动化证据。

## 后续阶段

| 阶段 | 内容 | 退出条件 |
|---|---|---|
| 2 Mac 基线 | 真实 Xcode/SDK/Swift 版本、iOS 17 部署基线复核、SwiftUI shell、本地数据库/Keychain | 核心 XCTest + App/扩展构建 + iPhone 安装 |
| 3 系统入口 | App Intents → Share Extension → App Group；Siri/Shortcuts 手工入口 | 关闭 Mac、拔线仍能触发并反馈；锁屏/取消实测 |
| 4 原生工具 | MapKit/高德、WeatherKit、EventKit，逐个替换 Mock | 每工具构建/契约测试/脱机真机验证；离线与授权撤销 |
| 5 健康与后台 | HealthKit 增量/删除、游标和恢复，Core Location、四场景、通知去重/上限 | 系统允许机会内处理，超时保存，重新打开补齐；不承诺准时 |
| 6 增量扩展 | WidgetKit/按版本 Control Widget、可选 MCP/API/其他模型 | 保持同一审批边界；不增加桌面常驻依赖 |

后台/扩展运行预算由系统决定。超时机制只能对合作取消的异步任务生效，不宣称能强制终止任意 native API。网络模型不可用时回到本地规则，不把网络失败包装成实际执行成功。四个系统自动化场景最终须具备缓存有效期、静默/冷却/通知上限、去重和重新启动恢复；本阶段只为其建立可测试的执行与存储接口，尚不宣称连接了系统事件。

## 真机强制验收

Mac 关闭、USB 拔掉：Siri/Shortcuts 运行、分享处理、消歧后路线界面、离线本地规则/缓存/事件留存、权限拒绝与 App 未安装、模型异常、锁屏/执行时间不足、健康后台后补齐、四场景去重与上限、错过复盘后归档不重复推昨天摘要。逐项填写 iPhone 14 Pro 和真实 OS/签名环境的结果；现在这些均为未验证。
