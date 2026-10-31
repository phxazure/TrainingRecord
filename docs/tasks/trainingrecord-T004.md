# trainingrecord-T004 训练录入：ViewModel + 录入界面

状态: planned
分支: task/trainingrecord-T004（基于 main @ 94408b9）
执行者: code
里程碑: m2-app（T004 录入 → T005 历史与趋势 → T006 本地持久化，三单完成后由 hermes 开一个 PR 到 main）
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - Sources/TrainingRecordCore/WorkoutDraft.swift（新建：录入草稿值类型 + 输入解析）
  - Sources/TrainingRecordCore/RecordViewModel.swift（新建）
  - Tests/TrainingRecordCoreTests/RecordViewModelTests.swift（新建）
  - App/TrainingRecordApp.swift（修改：创建仓储并注入）
  - App/ContentView.swift（修改：作为根视图）
  - App/Record/（新建目录，录入功能的 SwiftUI 视图，文件数不限）
  - docs/screenshots/trainingrecord-T004-*.png（新建：模拟器截图）

负责人: hermes

## 目标

让用户在 App 里记录一次训练：选日期、添加动作、给每个动作添加若干组（重量、次数）、删改、保存。保存走 `WorkoutRepository` 协议，本单用 `InMemoryWorkoutRepository`；T006 会换成本地持久化，调用方不改。

所有业务逻辑（输入解析、校验、增删、能否保存、保存后状态）放在 Core 的 `RecordViewModel`，可被 `swift test` 测试；SwiftUI 视图只做展示和绑定。T005（code-local）会在本单基础上做历史与趋势，所以下面列出的公共 API 必须存在且语义一致；在此之外可以自行增加。

## 验收标准

全部用 `swift test` 机器判定（界面是否好看不在验收标准里，见「UI 契约」，由人类判断）。

**必须提供的公共 API**（名字和语义按此；参数标签可微调，但要在交付消息里列出最终签名）：

```swift
// Core，import Foundation + Observation，不得 import SwiftUI/UIKit/SwiftData
public enum SetInputError: Error, Equatable { case invalidWeight, invalidReps }

@MainActor @Observable
public final class RecordViewModel {
    public init(repository: any WorkoutRepository, now: @escaping @Sendable () -> Date = { Date() })
    public var date: Date                                  // 初始为 now()
    public private(set) var exercises: [ExerciseDraft]     // ExerciseDraft: Identifiable, 含 name 与已添加的组
    @discardableResult public func addExercise(name: String) -> Bool
    public func removeExercise(id: ExerciseDraft.ID)
    @discardableResult public func addSet(toExercise id: ExerciseDraft.ID, weightText: String, repsText: String) -> SetInputError?
    public func removeSet(exerciseID: ExerciseDraft.ID, setID: /* 组的 id 类型 */)
    public var canSave: Bool { get }
    public func save() async throws -> WorkoutSession
}
```

动作：
- [ ] `addExercise(name: "  卧推 ")` 返回 true，动作名为 `卧推`
- [ ] 空名或全空白返回 false，不新增
- [ ] 与已有动作重名（去首尾空白后不区分大小写）返回 false，不新增
- [ ] `removeExercise` 删除指定动作，其余动作和它们的组不变

组输入解析（`addSet`）：
- [ ] 重量接受 `"60"`、`"60.5"`、`"60,5"`（逗号视作小数点）、首尾空白；均按 Double 存入
- [ ] 重量 `0` 允许（自重动作）；负数、空串、非数字、大于 1000 → 返回 `.invalidWeight`，不新增
- [ ] 次数必须是 1…1000 的整数；`"0"`、`"-1"`、`"5.5"`、空串、非数字 → 返回 `.invalidReps`，不新增
- [ ] 重量和次数都非法时返回 `.invalidWeight`（先校验重量）
- [ ] 成功时返回 nil，组追加到该动作末尾（保持录入顺序）
- [ ] 对不存在的动作 id 调用：不新增、不崩溃；返回值由你决定（不得为此新增 `SetInputError` 以外的抛错路径），并写测试固定下来
- [ ] `removeSet` 只删除指定组

保存：
- [ ] `canSave` 为 true 当且仅当至少有一个动作含 ≥1 组
- [ ] `save()` 写入仓储的 session：`date` 等于当前 `date`；只包含 ≥1 组的动作（空动作丢弃）；动作与组的顺序与录入一致；数值与输入一致
- [ ] `save()` 成功后：`exercises` 清空，`date` 重置为 `now()`；返回值等于仓储中存入的那条
- [ ] `canSave == false` 时调用 `save()` 抛错，仓储不写入
- [ ] 仓储 `save` 抛错时：`save()` 把错误抛出，草稿（`exercises`、`date`）保持不变。用一个测试内的假仓储验证
- [ ] 测试用注入的固定 `now`，不依赖真实时间

通用：
- [ ] Core 不得 `import SwiftUI` / `UIKit` / `SwiftData`（`Observation` 允许）
- [ ] T001–T003 的源码与测试不改；`swift test` 全绿
- [ ] `xcodegen generate` 后 `xcodebuild build -project TrainingRecord.xcodeproj -scheme TrainingRecord -destination 'generic/platform=iOS Simulator' -quiet` 退出 0
- [ ] 录入界面的关键控件带 `accessibilityIdentifier`（至少：添加动作、动作名输入、重量输入、次数输入、添加组、保存），后续 UI 测试会用
- [ ] 测试不能恒真。review 会做变异：逗号不当小数点、次数允许 0、重名不拦截、保存不丢空动作、保存后不清空、仓储失败时清空草稿——每一种至少让一个测试变红
- [ ] CI 兼容：CI 用 Xcode 26.6 / Swift 6.3，比本机旧。不要用局部变量名遮蔽它调用的函数名等依赖新编译器的写法；不要用 iOS 18+ / macOS 15+ 才有的 API（部署目标 iOS 17 / macOS 14）

## UI 契约（由人类判断，review 不判视觉）

目前没有 `ui/DESIGN.md`，按协议由 code 自定界面风格，交付时附截图留证。人类要求：**参考 Apple 自家 App 的风格**（如「健身」「健康」「备忘录」）：

- 使用系统组件：`NavigationStack`、`Form`/`List` 的 inset grouped 样式、系统字体与 Dynamic Type、SF Symbols、系统语义色（`.primary`/`.secondary`/`.tint`），不写死颜色与字号
- 深色模式跟随系统，两种模式都可读
- 中文界面；单位 kg
- 输入：重量用小数键盘、次数用数字键盘；非法输入时就地提示（`SetInputError` 对应的中文提示），不弹系统级警告框
- 保存按钮在 `canSave == false` 时禁用；保存成功有轻量反馈（如短暂提示或触感），不跳转
- 根视图用 `TabView`，本单只有「记录」一个标签；T005 会加「历史」标签
- 截图至少 2 张：空状态、已录入 2 个动作（每个 ≥2 组）的状态；浅色模式即可。可以用仅在 DEBUG 下生效的启动参数预填样例数据来截图，Release 构建不得包含样例数据

## 计划

1. `git checkout -b task/trainingrecord-T004` 已由 hermes 建好并提交本任务单；确认在该分支
2. 先写 `RecordViewModelTests.swift` → `swift test` 变红
3. 写 `WorkoutDraft.swift`、`RecordViewModel.swift` → 全绿
4. 写 SwiftUI 视图并接入；`xcodegen generate` + `xcodebuild build` 通过
5. 在模拟器（iPhone 17，iOS 27.2）上运行截图，存到 `docs/screenshots/`
6. commit、正常 push（不 force）。**里程碑模式：不开 PR。** 用 `message_agent` 通知 review：任务单路径、分支名、审查对比基线 `94408b9`、最终公共 API 签名、截图路径，并回报 hermes

## 实现约束

- 不引入第三方依赖；不改 `Package.swift`、`project.yml`、`.github/`
- 不用 `--force`

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|

## 升级说明

（状态为 escalated 时必填）
