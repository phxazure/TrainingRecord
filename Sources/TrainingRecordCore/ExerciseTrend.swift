import Foundation

/// 单动作趋势的一个点：某场次中该动作的最佳估算 1RM 与总容量。
public struct ExerciseTrendPoint: Equatable, Sendable {
    /// 该场次日期。
    public let date: Date
    /// 该场次该动作的最佳估算 1RM（Epley），四舍五入到 0.1。
    public let bestE1RM: Double
    /// 该场次该动作的总容量。
    public let volume: Double
}

/// Epley 估算 1RM：reps == 1 时等于重量；reps ≥ 2 时为 weight × (1 + reps / 30)；
/// reps == 0 的组不参与，返回 nil。
private func e1RM(of set: SetEntry) -> Double? {
    guard set.reps >= 1 else { return nil }
    if set.reps == 1 {
        return set.weight
    }
    return set.weight * (1 + Double(set.reps) / 30)
}

/// 四舍五入到 1 位小数。
private func roundToTenth(_ x: Double) -> Double {
    (x * 10).rounded() / 10
}

/// 单动作趋势：
/// - 动作名匹配：双方去首尾空白后不区分大小写相等；不同动作的组不计入。
/// - 同一场次内同名动作合并为该场次的一个点（所有组放在一起算）。
/// - 不含该动作、或该动作组为空的场次不产生点。
/// - 结果按 date 升序；date 相同的不同场次各自一个点，按场次 id.uuidString 升序。
public func trend(for exerciseName: String, in sessions: [WorkoutSession]) -> [ExerciseTrendPoint] {
    let query = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var entries: [(session: WorkoutSession, point: ExerciseTrendPoint)] = []
    for session in sessions {
        let matchedSets = session.exercises
            .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == query }
            .flatMap(\.sets)
        guard !matchedSets.isEmpty else { continue }
        let bestE1RM = roundToTenth(matchedSets.compactMap(e1RM(of:)).max() ?? 0)
        let sessionVolume = matchedSets.reduce(0) { $0 + volume(of: $1) }
        let point = ExerciseTrendPoint(date: session.date, bestE1RM: bestE1RM, volume: sessionVolume)
        entries.append((session, point))
    }
    entries.sort { a, b in
        if a.session.date != b.session.date {
            return a.session.date < b.session.date
        }
        return a.session.id.uuidString < b.session.id.uuidString
    }
    return entries.map { $0.point }
}
