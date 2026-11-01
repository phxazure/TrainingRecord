import Foundation

/// 单组训练记录：重量 × 次数。
public struct SetEntry: Equatable, Sendable {
    /// 重量（kg），非负。
    public let weight: Double
    /// 次数，非负。
    public let reps: Int

    /// 重量或次数为负时返回 nil。
    public init?(weight: Double, reps: Int) {
        guard weight >= 0, reps >= 0 else { return nil }
        self.weight = weight
        self.reps = reps
    }
}

/// 单个动作及其组。结构：训练 → 动作 → 组。
public struct ExerciseEntry: Equatable, Sendable {
    /// 动作名，已去掉首尾空白。
    public let name: String
    /// 该动作的所有组。
    public let sets: [SetEntry]
    /// 指向动作库条目（`ExerciseDefinition.id`）；旧数据、自由输入的动作为 nil。
    /// `name` 仍然保存：它是显示名，也让按名字工作的逻辑（趋势、历史行）不依赖动作库。
    public let exerciseID: UUID?

    /// name 去掉首尾空白后为空时返回 nil。
    public init?(name: String, sets: [SetEntry], exerciseID: UUID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.name = trimmed
        self.sets = sets
        self.exerciseID = exerciseID
    }
}

/// 一次训练场次。
public struct WorkoutSession: Equatable, Sendable {
    /// 场次唯一标识。
    public let id: UUID
    /// 训练日期。
    public let date: Date
    /// 场次包含的所有动作。
    public let exercises: [ExerciseEntry]

    public init(id: UUID = UUID(), date: Date, exercises: [ExerciseEntry]) {
        self.id = id
        self.date = date
        self.exercises = exercises
    }
}
