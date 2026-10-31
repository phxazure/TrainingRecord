# trainingrecord-T002 训练记录仓储接口 + 内存实现

状态: approved
分支: task/trainingrecord-T002（基于 task/trainingrecord-T001 @ 4799672，堆叠开发）
执行者: code-local
工作目录: /Users/phx/dev/TrainingRecord-T002（独立 clone，不要用 /Users/phx/dev/TrainingRecord）
范围:
  - Sources/TrainingRecordCore/WorkoutRepository.swift
  - Sources/TrainingRecordCore/InMemoryWorkoutRepository.swift
  - Tests/TrainingRecordCoreTests/InMemoryWorkoutRepositoryTests.swift

负责人: hermes

## 目标

为训练场次提供存取抽象：Core 里定义仓储协议和一个内存实现。界面层以后只依赖协议；本地持久化（SwiftData，放 App target）和云同步以后都作为该协议的另一个实现接入，不改调用方。本单不碰界面、不碰持久化、不改 T001 的模型。

## 验收标准

全部用 `swift test` 机器判定。

**签名必须与下面一致**（方法用 `async throws`，为以后的磁盘/网络实现预留）：

```swift
public protocol WorkoutRepository: Sendable {
    func save(_ session: WorkoutSession) async throws          // 新增或按 id 覆盖
    func session(id: UUID) async throws -> WorkoutSession?    // 不存在返回 nil
    func allSessions() async throws -> [WorkoutSession]       // 排序见下
    func delete(id: UUID) async throws                        // 不存在时静默成功
}

public actor InMemoryWorkoutRepository: WorkoutRepository {
    public init(sessions: [WorkoutSession] = [])
}
```

- [ ] 空仓储：`allSessions()` 返回 `[]`；`session(id: UUID())` 返回 nil
- [ ] `save` 一个新 session 后，`session(id:)` 取回的值 `==` 原值；`allSessions().count == 1`
- [ ] 对同一 `id` 再次 `save` 不同内容：`allSessions().count` 仍为 1，取回的是新内容（覆盖，不是追加）
- [ ] `allSessions()` 按 `date` **降序**（最近的在前）；`date` 相同时按 `id.uuidString` **升序**（结果确定，不依赖插入顺序）。测试须用乱序插入验证
- [ ] `delete(id:)` 已存在的 id 后，`session(id:)` 返回 nil，其余 session 不受影响
- [ ] `delete(id:)` 不存在的 id：不抛错，`allSessions()` 不变
- [ ] `init(sessions:)` 预置数据可被 `allSessions()` 取回；若预置数组里有重复 id，以数组中**靠后**的那个为准
- [ ] 并发：用 `withTaskGroup`（或 `withThrowingTaskGroup`）并发 `save` 100 个不同 id 的 session 后，`allSessions().count == 100`
- [ ] `Sources/TrainingRecordCore/` 不得 `import SwiftUI` / `UIKit` / `SwiftData`
- [ ] T001 的文件（`Models.swift`、`Volume.swift`、`VolumeTests.swift`）与 `SmokeTests.swift` 一字不改；`swift test` 全绿（含 T001 的 9 个测试）
- [ ] 测试不能恒真。review 会做变异：排序改升序、覆盖改追加、`delete` 改成不删、`init` 重复 id 改为保留靠前的 —— 每一种都必须至少让一个测试变红

## 计划

1. 在工作目录确认分支 `task/trainingrecord-T002` 已检出、本任务单存在（hermes 已提交在该分支第一个提交里）
2. 先写 `InMemoryWorkoutRepositoryTests.swift` 覆盖上面每一条 → `swift test` 变红（类型不存在导致编译失败也算红）
3. 写 `WorkoutRepository.swift`（协议）和 `InMemoryWorkoutRepository.swift`（actor 实现）
4. `swift test` 全绿
5. `xcodegen generate` 后 `xcodebuild build -project TrainingRecord.xcodeproj -scheme TrainingRecord -destination 'generic/platform=iOS Simulator' -quiet` 退出 0
6. push `task/trainingrecord-T002`，开 PR，**base 选 `main`**；PR 描述写明「堆叠在 #2（T001）之上，审查请对比 4799672..HEAD」，并逐条自查验收标准

## 实现约束

- 不引入第三方依赖，不改 `Package.swift`、`project.yml`、`App/`、`docs/`
- 内存存储用 `[UUID: WorkoutSession]` 或等价结构；排序在 `allSessions()` 里做
- 测试用固定日期（如 `Date(timeIntervalSince1970: …)`），不用 `Date()`，避免偶发失败
- 不用 `--force` 推送。T001 合并后如需同步 main，用 `git merge origin/main`，不 rebase

## 合并顺序

T001（PR #2）必须先合并，本单后合。若 T001 在合并前被修改，本分支须 `git merge` 新的 T001/main 后重跑全部测试。

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|
| 1 | 通过（1 SHOULD-FIX） | 18 tests、5 种变异全杀、Core 46/46 行；InMemoryWorkoutRepositoryTests.swift:98 并发测试未 waitForAll，吞掉子任务错误 | 2026-10-31 |
| 2 | 通过 | ddd1f0c 补 waitForAll，对照变异证实生效；18 tests、覆盖率 100% 保持 | 2026-10-31 |

## 升级说明

（状态为 escalated 时必填）
