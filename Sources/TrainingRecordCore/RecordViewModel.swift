import Foundation
import Observation

/// 保存训练时的错误（仓储自身的错误原样抛出，不包装）。
public enum RecordSaveError: Error, Equatable, Sendable {
    /// 没有任何含组的动作，`canSave == false`。
    case nothingToSave
    /// 上一次保存还没结束。
    case saveInProgress
}

/// 训练录入：日期、动作、组的草稿编辑与保存。界面只做展示和绑定，业务规则都在这里。
@MainActor @Observable
public final class RecordViewModel {
    /// 训练日期，初始为 `now()`，保存成功后重置为 `now()`。
    public var date: Date
    /// 已添加的动作，按录入顺序。
    public private(set) var exercises: [ExerciseDraft] = []
    /// 正在等待仓储写入。
    public private(set) var isSaving = false

    /// 草稿动作 → 动作库条目 id。只记录从动作库添加的动作；自由输入的动作没有。
    /// 用 `exerciseID(of:)` 读取。
    private var linkedExerciseIDs: [ExerciseDraft.ID: UUID] = [:]

    @ObservationIgnored private let repository: any WorkoutRepository
    @ObservationIgnored private let now: @Sendable () -> Date

    public init(repository: any WorkoutRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
        self.date = now()
    }

    // MARK: - 动作

    /// 新增动作。名称去首尾空白；空名、或与已有动作重名（不区分大小写）时返回 false 且不新增。
    @discardableResult
    public func addExercise(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let key = trimmed.lowercased()
        guard !exercises.contains(where: { $0.name.lowercased() == key }) else { return false }
        exercises.append(ExerciseDraft(name: trimmed))
        return true
    }

    /// 从动作库添加动作：草稿记录它的 `exerciseID`，保存后的场次条目带上这个 id。
    /// 与已有草稿动作同 id、或同名（去首尾空白、不区分大小写）时返回 false 且不新增。
    @discardableResult
    public func addExercise(_ definition: ExerciseDefinition) -> Bool {
        let key = definition.name.lowercased()
        let taken = exercises.contains { draft in
            linkedExerciseIDs[draft.id] == definition.id || draft.name.lowercased() == key
        }
        guard !taken else { return false }
        let draft = ExerciseDraft(name: definition.name)
        exercises.append(draft)
        linkedExerciseIDs[draft.id] = definition.id
        return true
    }

    /// 草稿动作对应的动作库条目 id；自由输入的动作、或 id 不存在时为 nil。
    public func exerciseID(of draftID: ExerciseDraft.ID) -> UUID? {
        linkedExerciseIDs[draftID]
    }

    /// 复制上次训练：只在草稿为空且模板至少有一个动作时生效（返回 true），按模板顺序带入动作名和 id，不带入组；
    /// 草稿非空、或模板为空时返回 false 且不改动。
    @discardableResult
    public func apply(_ template: SessionTemplate) -> Bool {
        guard exercises.isEmpty, !template.exercises.isEmpty else { return false }
        for definition in template.exercises {
            addExercise(definition)
        }
        return true
    }

    /// 删除指定动作（连同它的组）；id 不存在时什么也不做。
    public func removeExercise(id: ExerciseDraft.ID) {
        exercises.removeAll { $0.id == id }
        linkedExerciseIDs[id] = nil
    }

    // MARK: - 组

    /// 给动作追加一组。先校验重量再校验次数，非法时返回对应错误且不新增；成功返回 nil。
    /// 动作 id 不存在时：输入非法照常返回错误；输入合法则静默忽略并返回 nil。
    @discardableResult
    public func addSet(toExercise id: ExerciseDraft.ID, weightText: String, repsText: String) -> SetInputError? {
        switch SetInputParser.parseSet(weightText: weightText, repsText: repsText) {
        case .failure(let error):
            return error
        case .success(let set):
            if let index = exercises.firstIndex(where: { $0.id == id }) {
                exercises[index].sets.append(set)
            }
            return nil
        }
    }

    /// 删除指定组；动作或组不存在时什么也不做。
    public func removeSet(exerciseID: ExerciseDraft.ID, setID: SetDraft.ID) {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        exercises[index].sets.removeAll { $0.id == setID }
    }

    // MARK: - 保存

    /// 至少有一个动作含 ≥1 组。
    public var canSave: Bool {
        exercises.contains { !$0.sets.isEmpty }
    }

    /// 把草稿写入仓储：只保存含组的动作，顺序与录入一致。
    /// `canSave == false` 时抛 `RecordSaveError.nothingToSave`，已有保存进行中时抛 `RecordSaveError.saveInProgress`，均不写入。
    ///
    /// 保存期间的编辑：仓储写入的是开始保存那一刻的快照；await 期间草稿照常可编辑，编辑如实生效。
    /// - 成功：只从草稿移除快照里已保存的组，快照中的动作因此变空则一并移除（快照里原本就没有组的空动作也移除）；
    ///   快照之后新增的动作和组保留，顺序不变。日期在保存期间未改动则重置为 `now()`，被改动过则保留新值。
    ///   返回写入仓储的场次。
    /// - 失败：仓储的错误原样抛出；草稿不做任何移除（快照内容和保存期间的新编辑都保留），日期不变。
    @discardableResult
    public func save() async throws -> WorkoutSession {
        guard !isSaving else { throw RecordSaveError.saveInProgress }
        guard canSave else { throw RecordSaveError.nothingToSave }

        let snapshot = exercises
        let snapshotDate = date
        let entries = snapshot.compactMap { draft -> ExerciseEntry? in
            guard !draft.sets.isEmpty else { return nil }
            let sets = draft.sets.compactMap { SetEntry(weight: $0.weight, reps: $0.reps) }
            return ExerciseEntry(name: draft.name, sets: sets, exerciseID: linkedExerciseIDs[draft.id])
        }
        let session = WorkoutSession(date: snapshotDate, exercises: entries)

        isSaving = true
        defer { isSaving = false }
        try await repository.save(session)

        removeSaved(snapshot)
        if date == snapshotDate {
            date = now()
        }
        return session
    }

    /// 从当前草稿中移除快照里已保存的内容，保留快照之后的新编辑。
    private func removeSaved(_ snapshot: [ExerciseDraft]) {
        let savedExerciseIDs = Set(snapshot.map(\.id))
        let savedSetIDs = Set(snapshot.flatMap { $0.sets.map(\.id) })
        exercises = exercises.compactMap { exercise in
            guard savedExerciseIDs.contains(exercise.id) else { return exercise }
            var remaining = exercise
            remaining.sets.removeAll { savedSetIDs.contains($0.id) }
            return remaining.sets.isEmpty ? nil : remaining
        }
        let remainingIDs = Set(exercises.map(\.id))
        linkedExerciseIDs = linkedExerciseIDs.filter { remainingIDs.contains($0.key) }
    }
}
