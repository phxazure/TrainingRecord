# trainingrecord-T003 动作维度 + 单动作趋势统计

状态: planned
分支: task/trainingrecord-T003（基于 task/trainingrecord-T002 补修后的提交 ddd1f0c，堆叠开发）
执行者: code-local
工作目录: /Users/phx/dev/TrainingRecord-T003（独立 clone，不要动 TrainingRecord / TrainingRecord-T002）
范围:
  - Sources/TrainingRecordCore/Models.swift（修改）
  - Sources/TrainingRecordCore/Volume.swift（修改）
  - Sources/TrainingRecordCore/ExerciseTrend.swift（新建）
  - Tests/TrainingRecordCoreTests/VolumeTests.swift（修改：仅随模型调整构造方式）
  - Tests/TrainingRecordCoreTests/InMemoryWorkoutRepositoryTests.swift（修改：仅随模型调整构造方式）
  - Tests/TrainingRecordCoreTests/ExerciseTrendTests.swift（新建）

负责人: hermes

## 目标

人类已决定训练记录的结构为「训练 → 动作 → 组」：一次训练包含多个动作，每个动作下有若干组。本单把 T001 的模型改成这个结构，并新增单动作趋势统计（产品范围中的“以单个动作为单位的趋势统计”）。仓储接口与实现（T002）不改。不碰界面、不碰持久化。

## 验收标准

全部用 `swift test` 机器判定。

**模型签名改为**（`SetEntry` 不变）：

```swift
public struct ExerciseEntry: Equatable, Sendable {
    public let name: String          // 已去掉首尾空白
    public let sets: [SetEntry]
    public init?(name: String, sets: [SetEntry])   // name 去掉首尾空白后为空 → nil
}

public struct WorkoutSession: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let exercises: [ExerciseEntry]
    public init(id: UUID = UUID(), date: Date, exercises: [ExerciseEntry])
}

public func volume(of set: SetEntry) -> Double                // 不变
public func volume(of exercise: ExerciseEntry) -> Double      // 该动作所有组容量之和
public func totalVolume(of session: WorkoutSession) -> Double // 所有动作所有组容量之和
```

**趋势签名**：

```swift
public struct ExerciseTrendPoint: Equatable, Sendable {
    public let date: Date        // 该场次日期
    public let bestE1RM: Double  // 该场次该动作的最佳估算 1RM，四舍五入到 0.1
    public let volume: Double    // 该场次该动作的总容量
}

public func trend(for exerciseName: String, in sessions: [WorkoutSession]) -> [ExerciseTrendPoint]
```

模型：
- [ ] `ExerciseEntry(name: "  卧推 ", sets: …)` 非 nil，`name == "卧推"`
- [ ] `ExerciseEntry(name: "   ", sets: …)` 与 `ExerciseEntry(name: "", sets: …)` 返回 nil
- [ ] `volume(of: ExerciseEntry)`：100×5 与 2.5×4 两组 → 510（500 + 10）；空 sets → 0
- [ ] `totalVolume`：一场含两个动作（100×5、2.5×4）+（0×10）→ 510；`exercises: []` → 0
- [ ] T001 原有单组断言（500、10、0、0、负重量/负次数为 nil）的期望值一个都不改，只允许把 `WorkoutSession(..., sets:)` 改写为新构造方式

趋势（以下 e1RM 用 Epley：`reps == 1` 时等于 `weight`；`reps ≥ 2` 时为 `weight × (1 + reps / 30)`；`reps == 0` 的组不参与 e1RM）：
- [ ] 100kg×5 → 116.7；60kg×10 → 80.0；100kg×1 → 100.0
- [ ] 同一场次多组时取 e1RM 最大的那组；`volume` 为该动作该场次所有组容量之和
- [ ] 动作名匹配：两边都去首尾空白后**不区分大小写**相等（`"Bench Press"` 能匹配 `" bench press "`）；不同动作的组不计入
- [ ] 同一场次里同名动作出现多次 → 合并成该场次的**一个**点（组合在一起算）
- [ ] 结果按 `date` **升序**；`date` 相同的不同场次各自一个点，按场次 `id.uuidString` 升序。测试须用乱序输入验证
- [ ] 不含该动作的场次不产生点；该动作在某场次 `sets` 为空也不产生点；没有任何匹配 → `[]`
- [ ] 某场次该动作的组全部 `reps == 0`：产生一个点，`bestE1RM == 0`，`volume == 0`
- [ ] 四舍五入到 1 位小数（`(x * 10).rounded() / 10`）：100kg×7 = 123.333… → 123.3；80kg×8 = 101.333… → 101.3；65kg×6 → 78.0。不用恰好落在 .x5 边界的用例（浮点误差会让结果不确定）

通用：
- [ ] `WorkoutRepository.swift`、`InMemoryWorkoutRepository.swift`、`SmokeTests.swift`、`Package.swift`、`project.yml`、`App/` 不改
- [ ] T002 的测试除构造方式外断言不改；补修后的 `waitForAll` 保留
- [ ] `Sources/TrainingRecordCore/` 不得 `import SwiftUI` / `UIKit` / `SwiftData`
- [ ] `swift test` 全绿；`xcodegen generate` 后 `xcodebuild build … -destination 'generic/platform=iOS Simulator' -quiet` 退出 0
- [ ] 测试不能恒真。review 会做变异：Epley 改成 `reps/40`、取最大改成取第一组、排序改降序、大小写敏感匹配、同场次同名不合并、`reps == 0` 计入 e1RM —— 每一种都必须至少让一个测试变红

## 计划

1. 确认在工作目录、分支 `task/trainingrecord-T003`、本任务单存在
2. 先写 `ExerciseTrendTests.swift` 和改好构造方式的旧测试 → `swift test` 变红
3. 改 `Models.swift`、`Volume.swift`，新建 `ExerciseTrend.swift`
4. `swift test` 全绿，App 构建通过
5. push，开 PR，base 选 `main`；PR 描述写明「堆叠在 #4（T002）之上，审查请对比 ddd1f0c..HEAD」，逐条自查验收

## 实现约束

- 不引入第三方依赖；不改 `docs/`
- 测试用固定日期，不用 `Date()`；浮点比较用精确值（结果已四舍五入）或 `abs(a - b) < 1e-9`
- 不用 `--force`；上游（T001/T002）合并或变化后用 `git merge`，不 rebase

## 合并顺序

#2（T001）→ #3（docs）→ #4（T002）→ 本单。上游任何改动后，本分支须 merge 后重跑全部测试。

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|

## 升级说明

（状态为 escalated 时必填）
