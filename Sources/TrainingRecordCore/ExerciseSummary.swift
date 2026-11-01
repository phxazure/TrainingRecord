import Foundation

/// 趋势第一屏的动作列表的一行：某个动作最近一次的最佳估算 1RM，以及与上一次的变化。
public struct ExerciseSummary: Identifiable, Equatable, Sendable {
    /// 与上一次相比。幅度都是正数（已四舍五入到 0.1）。
    public enum Change: Equatable, Sendable {
        case noPrevious
        case flat
        case up(Double)
        case down(Double)
    }

    public var id: UUID { exercise.id }
    public let exercise: ExerciseDefinition
    /// 最近一次使用的场次日期。
    public let latestDate: Date
    /// 最近一次该动作的最佳估算 1RM（Epley，四舍五入到 0.1，与 `trend(for:in:)` 一致）。
    public let latestBestE1RM: Double
    public let change: Change
    /// 用过这个动作的场次数。
    public let sessionCount: Int

    public init(exercise: ExerciseDefinition, latestDate: Date, latestBestE1RM: Double, change: Change, sessionCount: Int) {
        self.exercise = exercise
        self.latestDate = latestDate
        self.latestBestE1RM = latestBestE1RM
        self.change = change
        self.sessionCount = sessionCount
    }
}

/// 某次训练里某个动作的记录（用于动作详情的「最近记录」）。
public struct ExerciseRecordEntry: Equatable, Sendable {
    public let sessionID: UUID
    public let date: Date
    /// 该场此动作的所有组，按出现顺序（同场出现多条时拼接）。
    public let sets: [SetEntry]

    public init(sessionID: UUID, date: Date, sets: [SetEntry]) {
        self.sessionID = sessionID
        self.date = date
        self.sets = sets
    }
}

/// 只保留某动作（按 `exerciseID` 匹配）的条目，名字统一成动作库里的当前名字；没有该动作的场次丢掉。
private func sessionsKeeping(_ sessions: [WorkoutSession], keeping definition: ExerciseDefinition) -> [WorkoutSession] {
    sessions.compactMap { session in
        let entries = session.exercises
            .filter { $0.exerciseID == definition.id }
            .compactMap { ExerciseEntry(name: definition.name, sets: $0.sets, exerciseID: definition.id) }
        return entries.isEmpty ? nil : WorkoutSession(id: session.id, date: session.date, exercises: entries)
    }
}

/// 单个动作的趋势（按 `exerciseID` 匹配，不按名字）；算法直接复用 `trend(for:in:)`。按日期升序。
public func exerciseTrend(for definition: ExerciseDefinition, in sessions: [WorkoutSession]) -> [ExerciseTrendPoint] {
    trend(for: definition.name, in: sessionsKeeping(sessions, keeping: definition))
}

/// 趋势第一屏的动作列表：动作库里存在、且有训练记录的动作；按最近使用日期降序，同日按名字（localizedStandardCompare）。
public func exerciseSummaries(library: [ExerciseDefinition], sessions all: [WorkoutSession]) -> [ExerciseSummary] {
    let summaries = library.compactMap { definition -> ExerciseSummary? in
        let kept = sessionsKeeping(all, keeping: definition)
        let points = trend(for: definition.name, in: kept)
        guard let latest = points.last else { return nil }
        let change: ExerciseSummary.Change
        if let previous = points.dropLast().last {
            let delta = ((latest.bestE1RM - previous.bestE1RM) * 10).rounded() / 10
            change = delta > 0 ? .up(delta) : (delta < 0 ? .down(-delta) : .flat)
        } else {
            change = .noPrevious
        }
        return ExerciseSummary(
            exercise: definition,
            latestDate: latest.date,
            latestBestE1RM: latest.bestE1RM,
            change: change,
            sessionCount: kept.count
        )
    }
    return summaries.sorted { a, b in
        if a.latestDate != b.latestDate { return a.latestDate > b.latestDate }
        let name = a.exercise.name.localizedStandardCompare(b.exercise.name)
        if name != .orderedSame { return name == .orderedAscending }
        return a.exercise.id.uuidString < b.exercise.id.uuidString
    }
}

/// 某动作最近的记录：日期降序（同日按场次 id 升序），最多 `limit` 场；`limit <= 0` 返回空。
public func recentRecords(of exerciseID: UUID, in sessions: [WorkoutSession], limit: Int) -> [ExerciseRecordEntry] {
    guard limit > 0 else { return [] }
    let ordered = sessions.sorted { a, b in
        a.date != b.date ? a.date > b.date : a.id.uuidString < b.id.uuidString
    }
    var result: [ExerciseRecordEntry] = []
    for session in ordered {
        let sets = session.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.sets)
        guard session.exercises.contains(where: { $0.exerciseID == exerciseID }) else { continue }
        result.append(ExerciseRecordEntry(sessionID: session.id, date: session.date, sets: sets))
        if result.count == limit { break }
    }
    return result
}

/// 用过某动作的场次数（同一场出现多条只算一场）。
public func sessionCount(of exerciseID: UUID, in sessions: [WorkoutSession]) -> Int {
    sessions.filter { session in session.exercises.contains { $0.exerciseID == exerciseID } }.count
}
