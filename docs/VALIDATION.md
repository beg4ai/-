# 本阶段验证记录

当前 v2/Swift-first 阶段的最新结果见 `STANDALONE_VALIDATION.md`：50 项 Python/契约等检查通过；25 项 Swift 测试尚未运行，编译器仍缺失；iOS 真机未验证。下文保留前几次增量的历史记录。

日期：2026-10-15，Asia/Shanghai。环境：用户 Windows 工作目录 `E:\东少`，PowerShell，Python 3.14.7，项目隔离 `.venv`，jsonschema 4.26.0 / tzdata 2026.5。没有 Git 仓库，因此未生成虚构 commit；没有 Xcode/Swift/iOS SDK，因此未运行也未声称 Xcode build。

## 分模块实际运行

| 增量 | 当时执行 | 结果 |
|---|---|---|
| 契约 | `python -m unittest tests.test_contracts -v` | 4 项通过；首轮发现日期 format 缺少严格校验，修正后通过 |
| Mock 与执行器 | `python -m unittest tests.test_contracts tests.test_tools -v` | 13 项通过 |
| HTTP / 公共 adapter | `python -m unittest tests.test_adapters -v` | 5 项通过 |
| 多轮规划和验收 | `python -m unittest tests.test_agent -v` | 8 项通过 |
| 自动化 | `python -m unittest tests.test_automation -v` | 7 项通过 |
| CLI 集成后 | `python -m unittest discover -v` | 38 项通过，含真实子进程调用 CLI |
| 迁移和持久性 | `python -m unittest tests.test_portability -v` | 5 项通过，含 SQLite 关闭重开 |
| 最终集成 | `python -m unittest discover -v` | **45 项通过**；含后补原生结果契约、非法 NaN 审计等检查 |

共享 JSON 向量内含 10 个场景，单工具枚举测试另以 subTest 覆盖六个工具，不将这些子项重复计入总测试数。Schema 使用独立文件，自动检查 Draft 2020-12 合法性。运行时仍会校验所有实际输入/输出。

## CLI 验收实证

实际在 Windows 命令行运行了用户验收句，返回四个工具结果：

`weather.forecast → health.summary → maps.search → maps.navigate`

天气/健康/地点为 Mock，模型为离线规则；导航为 `pending_confirmation`，含 URL 编码后的 `iosamap://path?sourceApplication=...&dlat=...&dlon=...&dev=1&t=2&m=0`，Apple Maps 回退和 `opened=false`。固定时钟的完整输出保存在 `examples/acceptance-output.json`，不是对真实用户跑步状态或真实公园的判断。

实际执行的复现命令：

```powershell
.\.venv\Scripts\python.exe -m agent ask '帮我看看今天适不适合跑步，并且导航到附近的公园。' --store ':memory:' --now '2026-10-15T08:00:00+08:00'
```

CLI 子进程测试还覆盖：多候选不生成动作、高德缺席回退、非交互确认取消、四种标准事件、真实 API 模式缺少位置拒绝、健康权限拒绝返回非零退出码。

## 公共 API 联通

对 Open-Meteo 做了一次真实只读请求，使用公开测试 WGS-84 坐标 `31.23,121.47`、日期 `2026-10-15`，未提供个人定位、健康数据或 API Key。沙箱内网络首先返回结构化 `network_unavailable`；经网络权限允许后重试成功，`source=open_meteo`、`is_mock=false`、`status=ok`，本次白天均温 21.1°C、最大降雨概率 2%、最大风速 10.4 km/h。数据是请求时的预报，不是长期固定测试断言。

高德搜索/转换真实联通：**未执行**，没有用户 Web API Key。已核对官方 endpoint 与参数并通过响应夹具测试；不等于 Key 配额、网络和当前位置搜索已验收。

真实 LLM 推理：**未执行**，用户尚未配置运行模型或远端凭据。已通过 Ollama 请求/响应解析、别名映射、多轮反馈、敏感结果脱敏、非法模型输出拒绝和重复调用预算测试。不会把规则路由演示宣称为模型推理成功。

## 已覆盖的核心失败场景

- 未知工具、非法日期/时区、无时区时间、参数多余字段、NaN、查询窗口反向、输出不符 Schema。
- 权限拒绝、审批取消、模型伪造 approved、policy 试图降低外部动作风险。
- 未先搜索就导航、多个候选、模拟未安装高德、GCJ-02/WGS-84 参数和 Apple Maps 名称回退。
- 无健康记录保持 null；运动 UUID 未同步保留待重试，达到上限不无限执行。
- 闹钟同日去重、workout ID 去重、进程重开仍去重、离家风险不变、冷却、安静时段。
- 断网保留事件与显式 replay、旧事件保持发生日期且不建议过时通知。

## 当前未验收与下一阶段条件

Apple Framework 编译、系统权限弹窗、Siri/App Intent 发现、Share Extension/App Group、通知投递、真实定位事件、高德 App 跳转、EventKit 写入、HealthKit 首轮/增量/删除/后台都未验证。后续已开始编写 Swift 核心包，但没有 App 工程。进入 Mac 原生阶段时按 `MIGRATION_TO_MAC.md` 逐个替换，每一项必须补上实际 Xcode build/test 和 iPhone 14 Pro 手工结果。

原型限制：SQLite 未加密且未自动清理；用户时区固定 Asia/Shanghai；天气为白天聚合，不覆盖空气质量；当前系统待办读取尚未实现；CLI 不常驻、不配置个人自动化、不发送通知；`notification_history` 只记录策略建议，不能当作投递证据。工具的原生侧幂等写入与健康 anchor 恢复仍需真机实现。

## Swift 核心增量（后续同日）

已写入 `iOS/Packages/DongShaoCore/Package.swift`、Foundation 核心源码及 8 项 XCTest 源码。`swift` 不在当前 PATH；只读检查 WSL 只有 docker-desktop，Docker daemon 未运行。因此 **Swift 构建未运行，8 项 XCTest 未运行**，不能记为通过。

实际运行 `scripts/sync_swift_contracts.py --check` 通过；另运行 `python -m unittest tests.test_swift_contract_resources -v`，2 项资源检查通过。它们仅比较所有 canonical Schema/测试向量的资源字节，并检查当前 Schema 关键字集合没有超出 Swift 校验器所声明的词汇。前述 Python 45 项仍是 Python 原型验证，新增这 2 项不构成 Swift 编译或行为验证。
