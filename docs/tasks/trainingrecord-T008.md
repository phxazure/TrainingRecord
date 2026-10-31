# trainingrecord-T008 动作库：数据层 + 改名同步 + 上次成绩/最近动作/复制上次训练

状态: planned
分支: task/trainingrecord-T008（基于 task/trainingrecord-T007 @ 83c1bbc（含 main 合入），堆叠开发）
执行者: code
里程碑: m3-library（T008 数据层 → T009 界面，两单都通过后由 hermes 开一个 PR 到 main）
工作目录: /Users/phx/dev/TrainingRecord
范围:
  - Sources/TrainingRecordCore/（新增文件不限；可修改 Models.swift、RecordViewModel.swift；R1 后追加：可修改 WorkoutRepository.swift、InMemoryWorkoutRepository.swift，仅限下方「R1 追加：原子重写」所需）
  - Tests/TrainingRecordCoreTests/（只新增文件；已有测试文件不改）
  - Sources/TrainingRecordPersistence/（新增、修改不限）
  - Tests/TrainingRecordPersistenceTests/（只新增文件和测试资源；已有测试文件不改）
  - Package.swift（仅限给测试 target 加 resources，用于旧版存储样本）
  - App/TrainingRecordApp.swift（仅限：创建动作库仓储、启动时调用回填）
  - App/ 其他文件：只允许为保持编译通过而做的最小改动，不做界面改动（界面在 T009）

负责人: hermes

## 背景（人类已确认的需求，2026-11-01）

- 动作库**不预置任何动作**，全部由用户自己添加；每个动作可设：名字、训练部位、照片
- 动作库按部位分组；动作支持修改（改名等），**改名要同步到历史和趋势**
- 一起做设计稿 §9 的三项：P1 上次成绩、P2 最近动作、P3 复制上次训练
- 人类已同意数据迁移：已有历史里的动作自动关联到动作库，部位为「未分类」，不删除任何数据

本单只做数据层和逻辑（全部可用 `swift test` 测）；界面（第 4 个标签「动作库」、选动作、拍照/选照片）在 T009。

## 设计决定（hermes）

1. `ExerciseEntry` 增加可选 `exerciseID: UUID?`，指向动作库条目；`name` 继续保存，作为显示名和兼容旧逻辑的快照。
2. 改名 = 改动作库 **并** 重写所有引用该 id 的历史条目的 `name`。这样 T003 的 `trend(for: name)`、T005 的历史行等按名字工作的逻辑无需改动即保持正确。
3. 动作库内名字唯一：去首尾空白后不区分大小写。
4. 照片在 Core 里只存文件名（`photoFileName: String?`），文件的读写、缩放由 App（T009）负责。
5. 动作库与训练记录存在**同一个** SwiftData 存储文件里。

## 验收标准

**签名按此**（可微调，交付消息里列出最终签名）：

```swift
// Core
public struct ExerciseDefinition: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String          // 去首尾空白，非空
    public let bodyPart: String      // 去首尾空白；空 → "未分类"
    public let photoFileName: String?
    public init?(id: UUID = UUID(), name: String, bodyPart: String, photoFileName: String? = nil)
}
public protocol ExerciseLibraryRepository: Sendable {
    func allExercises() async throws -> [ExerciseDefinition]   // 按 bodyPart、再按 name（localizedStandardCompare）升序
    func exercise(id: UUID) async throws -> ExerciseDefinition?
    func save(_ exercise: ExerciseDefinition) async throws     // 同 id 覆盖
    func delete(id: UUID) async throws                         // 不存在时静默成功
}
public actor InMemoryExerciseLibraryRepository: ExerciseLibraryRepository { ... }

public enum ExerciseLibraryError: Error, Equatable, Sendable {
    case invalidName, duplicateName, notFound, inUse(sessionCount: Int)
}

/// 动作库的业务操作（协调动作库仓储与训练仓储）
public actor ExerciseLibraryService {
    public init(library: any ExerciseLibraryRepository, workouts: any WorkoutRepository)
    public func add(name: String, bodyPart: String, photoFileName: String?) async throws -> ExerciseDefinition
    public func update(id: UUID, name: String, bodyPart: String, photoFileName: String?) async throws -> ExerciseDefinition
    public func delete(id: UUID) async throws
    public func merge(sourceID: UUID, into targetID: UUID) async throws
    public func backfill() async throws -> Int                       // 返回新建的动作库条目数
    public func grouped() async throws -> [(bodyPart: String, exercises: [ExerciseDefinition])]
    public func lastPerformance(exerciseID: UUID, before: Date?) async throws -> LastPerformance?
    public func recentExercises(limit: Int) async throws -> [ExerciseDefinition]
    public func lastSessionTemplate() async throws -> SessionTemplate?
}
public struct LastPerformance: Equatable, Sendable { public let date: Date; public let bestSet: SetEntry }
public struct SessionTemplate: Equatable, Sendable { public let date: Date; public let exercises: [ExerciseDefinition] }

// RecordViewModel 新增（原有 API 与行为不变）
@discardableResult public func addExercise(_ definition: ExerciseDefinition) -> Bool
public func apply(_ template: SessionTemplate) -> Bool

// Persistence
public actor SwiftDataExerciseLibraryRepository: ExerciseLibraryRepository { ... }
// 与 SwiftDataWorkoutRepository 共用同一个容器/存储文件的创建方式，例如：
public enum TrainingRecordStore {
    public static func inMemory() throws -> (workouts: SwiftDataWorkoutRepository, library: SwiftDataExerciseLibraryRepository)
    public static func onDisk(url: URL) throws -> (workouts: SwiftDataWorkoutRepository, library: SwiftDataExerciseLibraryRepository)
}
```

模型：
- [ ] `ExerciseEntry(name:sets:)` 原有调用全部照常编译、行为不变；新增 `exerciseID` 默认 nil
- [ ] `ExerciseDefinition`：名字 trim、空名返回 nil；部位 trim、空部位为「未分类」

动作库操作（`ExerciseLibraryService`）：
- [ ] `add`：重名（trim + 不区分大小写）抛 `.duplicateName`；空名抛 `.invalidName`
- [ ] `update` 改名：动作库条目更新；**所有** `exerciseID` 等于该 id 的历史条目 `name` 改为新名；其他条目不变；改后 `trend(for: 新名)` 与改名前 `trend(for: 旧名)` 结果相同，`trend(for: 旧名)` 为空
- [ ] `update` 改成与另一个动作同名抛 `.duplicateName`，什么都不改；只改大小写或部位、照片允许
- [ ] `delete`：未被任何历史引用时删除；被引用时抛 `.inUse(sessionCount:)`，什么都不删
- [ ] `merge(sourceID:into:)`：历史里所有 source 条目改为 target 的 id 和名字；同一场训练里两者都出现时合并成一条，位置取先出现的那条，组按原先出现顺序拼接；最后删除 source；source == target 时不做任何事
- [ ] 改名、合并中途仓储抛错：方法把错误抛出；**再次调用同一操作能补完**（幂等），用测试内的假仓储验证
- [ ] `grouped()`：按部位分组，组内按名字排序，组按部位名排序，「未分类」放最后

回填（数据迁移，人类已同意）：
- [ ] `backfill()`：历史中 `exerciseID == nil` 的条目，按名字（trim + 不区分大小写）匹配动作库；没有就新建（部位「未分类」）；然后给条目写上 id。返回新建条目数
- [ ] 幂等：第二次调用返回 0，数据不变
- [ ] 不删除、不改动任何组数据、日期、顺序；只增加 id（以及动作库条目）

上次成绩 / 最近动作 / 复制上次训练：
- [ ] `lastPerformance(exerciseID:before:)`：在 `date < before`（before 为 nil 表示不限）的场次里，取包含该动作的**最近**一场，返回该场此动作的最佳组（重量最大；同重量取次数多的）；没有则 nil
- [ ] `recentExercises(limit:)`：按最近一次使用的场次日期降序、去重，最多 limit 个；只返回动作库里仍存在的条目
- [ ] `lastSessionTemplate()`：最近一场训练的动作（按原顺序，映射为动作库条目，跳过已不存在的）；没有训练时 nil；**映射后一个动作都没有时也返回 nil**（hermes R1 裁定，2026-11-01）
- [ ] `RecordViewModel.addExercise(_ definition:)`：草稿记录 exerciseID；保存后的 session 条目带上 id；与已有草稿同 id 或同名时返回 false
- [ ] `RecordViewModel.apply(_ template:)`：只在草稿为空且模板至少有一个动作时生效（返回 true），带入动作名和 id，不带入组；草稿非空或模板为空时返回 false 且不改动（空模板部分为 hermes R1 裁定，2026-11-01）

持久化：
- [ ] `SwiftDataExerciseLibraryRepository` 行为与内存实现一致（建议共享用例，内存/磁盘参数化）
- [ ] `ExerciseRecord` 增加 `exerciseID: UUID?`，读写往返一致
- [ ] **旧存储兼容（关键）**：用 T006 已合并版本（main 上的 `bd79293` 代码）生成一个含 2 场训练、3 个动作的磁盘存储文件，作为测试资源提交；测试用新代码打开它：能读出全部场次且数据一致，`backfill()` 后每个条目都有 id、动作库有对应 3 条「未分类」。交付消息里写明样本是怎么生成的
- [ ] 动作库与训练在同一存储文件，重开后都在

R1 追加：原子重写（hermes 2026-11-01，依据 review R1 BLOCKER「删除后训练复活」）：
- [ ] 改名、合并、回填对历史的重写，必须在仓储内部**原子地**完成「读当前值 → 变换 → 保存」，并且**只更新仍然存在的记录**；不能在 service 里用两次 await 拼成「先查再存」
- [ ] 推荐做法：新增一个单独的协议（例如 `SessionRewriting`），提供原子的「按条件改写现有场次」能力，由 `InMemoryWorkoutRepository` 和 `SwiftDataWorkoutRepository` 实现；`ExerciseLibraryService` 依赖 `any WorkoutRepository & SessionRewriting`。这样不用给 `WorkoutRepository` 加必选方法，已有测试里的假仓储不受影响。若改用别的方案（如统一写操作协调器），历史页删除和所有相关保存必须真正经过同一个协调边界
- [ ] `save` 继续保持「新增或覆盖」的语义，不改
- [ ] 内存与 SwiftData 实现语义一致
- [ ] 确定性交错测试（只加在新文件里）：删除发生在候选枚举之后、重写提交之前，回填、改名、合并三条路径都不会让被删的训练复活；原有的覆盖、错误回滚、迁移幂等测试保持通过
- [ ] 变异：把原子重写改回「先读后存」，交错测试必须变红

通用：
- [ ] T001–T007 已有测试文件一字不改，全部通过
- [ ] Core 不得 import SwiftUI/UIKit/SwiftData
- [ ] `xcodegen generate` 后 Debug、Release `xcodebuild` 都退出 0；App 现有功能不受影响
- [ ] App 启动时创建动作库仓储并调用一次 `backfill()`；失败不崩溃（记录日志即可，T009 再做界面提示）；DEBUG 样例参数下仍全部走内存
- [ ] 测试不能恒真。review 会做变异：改名不同步历史、重名检查大小写敏感、delete 不检查引用、merge 同场不合并、backfill 不幂等（重复建条目）、lastPerformance 取最早一场、recentExercises 不去重、apply 覆盖非空草稿——每一种至少让一个测试变红
- [ ] CI 兼容：CI 是 Xcode 26.6 / Swift 6.3，部署目标 iOS 17 / macOS 14。不用 SwiftData 的 iOS 18 API（`#Unique`、`#Index`、`HistoryDescriptor` 等）；不用局部变量遮蔽同名函数
- [ ] 自查命令不要用 `perl -e` 包裹

## 计划

1. 在 `/Users/phx/dev/TrainingRecord` 切到分支 `task/trainingrecord-T008`（hermes 已建好并提交本任务单）
2. 先生成旧版存储样本（在临时 worktree 检出 bd79293 运行一段代码生成，不改该版本代码）
3. 先写测试 → 变红 → 实现 → 全绿
4. App 最小接线；构建 Debug/Release
5. commit、正常 push（不 force）。**里程碑模式：不开 PR。** 通知 review：任务单路径、分支名、对比基线 83c1bbc、最终签名、样本生成方法；并回报 hermes

## 审查记录

| 轮次 | 结论 | 关键 findings | 时间 |
|---|---|---|---|
| 1 | 打回（1 BLOCKER / 1 SHOULD-FIX） | BLOCKER：后台回填与历史删除交错，被删训练被重写复活（ExerciseLibraryService.swift:262–265）；SHOULD-FIX：空模板语义（hermes 裁定见 e0dfca5） | 2026-11-01 |

## 升级说明

（状态为 escalated 时必填）
