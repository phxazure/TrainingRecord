# trainingrecord-T001 训练记录数据模型 + 容量计算

状态: planned
分支: task/trainingrecord-T001
执行者: code-local
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - Sources/TrainingRecordCore/Models.swift
  - Sources/TrainingRecordCore/Volume.swift
  - Tests/TrainingRecordCoreTests/VolumeTests.swift

负责人: hermes

## 目标

`TrainingRecordCore` 目前只有一个版本号占位。需要提供训练记录的基础数据模型（单组、训练场次）与容量计算，让界面层和后续统计模块有可依赖的纯 Swift 类型。这一单只做「模型 + 计算 + 测试」，不碰界面、不碰持久化。

## 验收标准

全部可机器判定，用 `swift test` 验证。

**类型签名必须与下面一致**（后面的验收项都依赖它）：

```swift
public struct SetEntry: Equatable, Sendable {
    public let weight: Double
    public let reps: Int
    public init?(weight: Double, reps: Int)   // weight < 0 或 reps < 0 时返回 nil
}

public struct WorkoutSession: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let sets: [SetEntry]
    public init(id: UUID = UUID(), date: Date, sets: [SetEntry])
}

public func volume(of set: SetEntry) -> Double
public func totalVolume(of session: WorkoutSession) -> Double
```

- [ ] `SetEntry(weight: 100, reps: 5)` 非 nil；`volume(of:)` 返回 500
- [ ] `SetEntry(weight: 2.5, reps: 4)` 非 nil；`volume(of:)` 返回 10（支持小数重量，不做取整）
- [ ] `SetEntry(weight: 0, reps: 10)` 非 nil；`volume(of:)` 返回 0
- [ ] `SetEntry(weight: 100, reps: 0)` 非 nil；`volume(of:)` 返回 0
- [ ] `SetEntry(weight: -100, reps: 5)` 返回 nil
- [ ] `SetEntry(weight: 100, reps: -5)` 返回 nil
- [ ] `totalVolume` 对含 3 个 set 的 session 返回三者之和（例：100×5 + 2.5×4 + 0×10 = 510）
- [ ] `totalVolume` 对 `sets: []` 的 session 返回 0
- [ ] `swift test` 全绿（含原有的 `versionIsNotEmpty` smoke 测试）
- [ ] `Sources/TrainingRecordCore/` 下的文件**不得** `import SwiftUI`、`import UIKit`、`import SwiftData`（core 必须能在 macOS 上 `swift test`，一旦引入这些就测不了）
- [ ] 每一条验收断言都有对应测试用例；测试不能写成恒真断言（review 会做变异测试：把 `weight * reps` 改成 `+`、把 0 返回改成 1，测试必须变红）

## 计划

1. 先写 `Tests/TrainingRecordCoreTests/VolumeTests.swift`，覆盖上面每条断言 → `swift test` 必须变红（编译失败也算红，因为类型还不存在）
2. 再写 `Sources/TrainingRecordCore/Models.swift`（两个 struct）与 `Volume.swift`（两个函数）
3. `swift test` 全绿
4. `xcodebuild build -project TrainingRecord.xcodeproj -scheme TrainingRecord -destination 'generic/platform=iOS Simulator' -quiet` 通过（确认 App target 仍能编译；改了源文件后若报缺文件，跑 `xcodegen generate` 再试）
5. push `task/trainingrecord-T001`，开 PR，PR 描述里逐条自查验收标准

## 实现约束（review 会查）

- `id` 用 `UUID`，默认值 `UUID()`；不要引入第三方依赖
- `volume` / `totalVolume` 用 `public func`（自由函数），不要写成类型方法
- 不要新增文件，不要改 `Package.swift`、`project.yml`、`App/`
- 中文注释可以，但不要写中文标识符

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|

## 升级说明

（状态为 escalated 时必填）
