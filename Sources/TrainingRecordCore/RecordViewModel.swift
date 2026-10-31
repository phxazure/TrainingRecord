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

    /// 删除指定动作（连同它的组）；id 不存在时什么也不做。
    public func removeExercise(id: ExerciseDraft.ID) {
        exercises.removeAll { $0.id == id }
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
    /// 成功后清空动作、日期重置为 `now()`，返回写入的场次；
    /// `canSave == false` 时抛 `RecordSaveError.nothingToSave` 且不写入；仓储抛错时原样抛出，草稿不变。
    @discardableResult
    public func save() async throws -> WorkoutSession {
        guard !isSaving else { throw RecordSaveError.saveInProgress }
        guard canSave else { throw RecordSaveError.nothingToSave }

        let entries = exercises.compactMap { draft -> ExerciseEntry? in
            guard !draft.sets.isEmpty else { return nil }
            let sets = draft.sets.compactMap { SetEntry(weight: $0.weight, reps: $0.reps) }
            return ExerciseEntry(name: draft.name, sets: sets)
        }
        let session = WorkoutSession(date: date, exercises: entries)

        isSaving = true
        defer { isSaving = false }
        try await repository.save(session)

        exercises = []
        date = now()
        return session
    }
}
