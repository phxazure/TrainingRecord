# trainingrecord-T005 训练历史 + 单动作趋势图

状态: planned
分支: task/trainingrecord-T005（基于 task/trainingrecord-T004 审查通过的 6c036b2，堆叠开发）
执行者: code-local
里程碑: m2-app（T004 → T005 → T006，三单完成后由 hermes 开一个 PR 到 main）
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - Sources/TrainingRecordCore/HistoryViewModel.swift（新建）
  - Tests/TrainingRecordCoreTests/HistoryViewModelTests.swift（新建）
  - App/ContentView.swift（修改：TabView 增加「历史」标签）
  - App/Record/RecordView.swift（修改：仅限修复底部标签栏遮挡，见 UI 契约最后一条）
  - App/History/（新建目录，历史与趋势的 SwiftUI 视图，文件数不限）
  - docs/screenshots/trainingrecord-T005-*.png（新建：模拟器截图）

负责人: hermes

## 目标

在 App 里新增「历史」标签：按时间倒序列出已保存的训练；点进去看某次训练的明细；选一个动作看它的趋势图（最佳估算 1RM / 容量）。数据来自 `WorkoutRepository`，趋势计算直接用 T003 的 `trend(for:in:)`。逻辑放在 Core 的 `HistoryViewModel`，可被 `swift test` 测试；视图只做展示和绑定。

## 验收标准

全部用 `swift test` 机器判定（界面是否好看不在验收标准里，见「UI 契约」，由人类判断）。

**签名按此**（参数标签可微调，交付消息里列出最终签名）：

```swift
// Core：import Foundation + Observation，不得 import SwiftUI/UIKit/SwiftData/Charts
public struct HistoryRow: Identifiable, Equatable, Sendable {
    public let id: UUID                 // == session.id
    public let date: Date
    public let exerciseNames: [String]  // 该场次动作名，按录入顺序
    public let setCount: Int            // 所有动作的组数之和
    public let totalVolume: Double      // == totalVolume(of: session)
}

@MainActor @Observable
public final class HistoryViewModel {
    public init(repository: any WorkoutRepository)
    public private(set) var sessions: [WorkoutSession]   // 与仓储 allSessions() 顺序一致（日期降序）
    public var rows: [HistoryRow] { get }               // 与 sessions 一一对应、同序
    public var exerciseNames: [String] { get }          // 见下
    public private(set) var errorMessage: String?       // 最近一次加载/删除失败时非 nil，成功后置 nil
    public func reload() async
    public func delete(id: UUID) async
    public func trend(for exerciseName: String) -> [ExerciseTrendPoint]
}
```

- [ ] 初始 `sessions == []`；空仓储 `reload()` 后仍为 `[]`，`errorMessage == nil`
- [ ] 有数据时 `reload()` 后 `sessions` 与仓储 `allSessions()` 完全相同（含顺序）
- [ ] `rows` 每一项的 `id/date/exerciseNames/setCount/totalVolume` 与对应 session 一致；用一个含 2 个动作（共 5 组）的 session 验证具体数值
- [ ] `exerciseNames`：所有场次出现过的动作名去重（去首尾空白后不区分大小写视为同一个），按「最近一次出现的场次日期」降序；同一场次内按录入顺序；显示用最近一次出现时的写法。用乱序、大小写混用的数据验证
- [ ] `trend(for:)` 的结果等于 `trend(for:in: sessions)`（直接复用 T003，不另写算法）；含一条具体数值断言
- [ ] `delete(id:)` 成功：仓储里该 id 不存在，`sessions` 里也去掉，其余不变
- [ ] 仓储 `allSessions()` 抛错：`reload()` 不崩溃，`sessions` 保持上一次成功的值，`errorMessage` 非 nil；之后成功的 `reload()` 把 `errorMessage` 置 nil
- [ ] 仓储 `delete` 抛错：`sessions` 不变，`errorMessage` 非 nil
- [ ] 失败场景用测试内的假仓储验证
- [ ] Core 不得 `import SwiftUI` / `UIKit` / `SwiftData` / `Charts`
- [ ] T001–T004 的源码与测试不改（`App/Record/RecordView.swift` 的遮挡修复除外，只允许布局改动）；`swift test` 全绿
- [ ] `xcodegen generate` 后 `xcodebuild build -project TrainingRecord.xcodeproj -scheme TrainingRecord -destination 'generic/platform=iOS Simulator' -quiet` 退出 0
- [ ] 历史界面关键控件带 `accessibilityIdentifier`（至少：历史列表、每行、动作选择器、趋势图、删除操作）
- [ ] 测试不能恒真。review 会做变异：`exerciseNames` 不去重/大小写敏感/改成字母序、`rows` 的组数少算一个动作、`delete` 失败时仍从 `sessions` 移除、`reload` 失败时清空 `sessions` —— 每一种至少让一个测试变红
- [ ] CI 兼容：CI 用 Xcode 26.6 / Swift 6.3，比本机旧。不要用局部变量名遮蔽它调用的函数名；不用 iOS 18+ / macOS 15+ 才有的 API（部署目标 iOS 17 / macOS 14）

## UI 契约（由人类判断，review 不判视觉）

延续 T004 的风格（参考 Apple 自家 App，如「健身」「健康」）：

- 「历史」标签用 SF Symbol（如 `clock.arrow.circlepath`），放在「记录」之后
- 历史列表：`List` inset grouped，按日期倒序，每行显示日期、动作名摘要、组数与总容量（kg）；左滑删除；无数据时用 `ContentUnavailableView`
- 点行进入明细：按动作分组列出每组重量 × 次数
- 趋势：选择动作（`Picker` 或列表），用 Swift Charts 画折线 + 点，横轴日期，纵轴可在「最佳 1RM」与「容量」间切换（分段控件），单位 kg；无数据时显示空状态
- 每次切到「历史」标签都重新 `reload()`，保证刚在「记录」保存的训练能看到
- 系统字体与语义色，深色模式跟随系统；中文界面
- **修复 T004 遗留问题**：「记录」页滚动到底部时，最后一个输入区（新增动作的名称框和按钮）不能被底部悬浮标签栏遮挡。用系统方式处理（如 `safeAreaPadding` / `contentMargins` / 列表底部留白），不写死像素值；不改录入逻辑
- 截图至少 4 张：历史列表、某次训练明细、某个动作的趋势图（≥4 个数据点）、「记录」页滚动到底部（证明遮挡已修复）。可以用仅在 DEBUG 下生效的启动参数往仓储里预填样例训练数据；Release 构建不得包含样例数据

## 计划

1. 确认在 `/Users/phx/dev/TrainingRecord`、分支 `task/trainingrecord-T005`（hermes 已建好并提交本任务单）
2. 先写 `HistoryViewModelTests.swift` → `swift test` 变红
3. 写 `HistoryViewModel.swift` → 全绿
4. 写 `App/History/` 视图，接入 `ContentView`；构建通过
5. 模拟器截图存到 `docs/screenshots/`
6. commit、正常 push（不 force）。**里程碑模式：不开 PR。** 用 `message_agent` 通知 review：任务单路径、分支名、审查对比基线 `6c036b2`、最终签名、截图路径，并回报 hermes

## 实现约束

- 不引入第三方依赖（Swift Charts 是系统框架，可用）；不改 `Package.swift`、`project.yml`、`.github/`
- 不用 `--force`

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|

## 升级说明

（状态为 escalated 时必填）
