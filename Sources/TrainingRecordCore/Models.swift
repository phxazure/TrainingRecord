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

/// 一次训练场次。
public struct WorkoutSession: Equatable, Sendable {
    /// 场次唯一标识。
    public let id: UUID
    /// 训练日期。
    public let date: Date
    /// 场次包含的所有组。
    public let sets: [SetEntry]

    public init(id: UUID = UUID(), date: Date, sets: [SetEntry]) {
        self.id = id
        self.date = date
        self.sets = sets
    }
}
