import Foundation
import Observation

/// 历史列表的一行：一次训练场次的摘要。
public struct HistoryRow: Identifiable, Equatable, Sendable {
    /// == 场次的 id。
    public let id: UUID
    /// 场次日期。
    public let date: Date
    /// 该场次的动作名，录入顺序。
    public let exerciseNames: [String]
    /// 所有动作的组数之和。
    public let setCount: Int
    /// == totalVolume(of: session)。
    public let totalVolume: Double

    public init(id: UUID, date: Date, exerciseNames: [String], setCount: Int, totalVolume: Double) {
        self.id = id
        self.date = date
        self.exerciseNames = exerciseNames
        self.setCount = setCount
        self.totalVolume = totalVolume
    }
}

/// 训练历史：已保存训练的列表（日期降序）、删除、单动作趋势。
/// 界面只做展示与绑定，规则都在这里。
@MainActor @Observable
public final class HistoryViewModel {
    /// 与仓储 allSessions() 同序（日期降序）。
    public private(set) var sessions: [WorkoutSession] = []
    /// 最近一次加载/删除失败时非 nil，成功时 nil。
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repository: any WorkoutRepository

    public init(repository: any WorkoutRepository) {
        self.repository = repository
    }

    /// 与 sessions 一一对应、同序。
    public var rows: [HistoryRow] {
        sessions.map { session in
            HistoryRow(
                id: session.id,
                date: session.date,
                exerciseNames: session.exercises.map(\.name),
                setCount: session.exercises.reduce(0) { $0 + $1.sets.count },
                totalVolume: totalVolume(of: session)
            )
        }
    }

    /// 所有场次中出现过的动作名，去重（去首尾空白、大小写不敏感视为同一个）：
    /// 按「最近一次出现的场次日期」降序；同一场次内按录入顺序；
    /// 最近日期相同但分属不同场次时按场次 id 升序（与仓储排序一致）；
    /// 显示用最近一次出现的写法。
    public var exerciseNames: [String] {
        var mostRecent: [String: (date: Date, sessionID: UUID, index: Int, display: String)] = [:]
        for session in sessions {
            for (index, exercise) in session.exercises.enumerated() {
                let key = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if mostRecent[key] == nil {
                    mostRecent[key] = (session.date, session.id, index, exercise.name)
                }
            }
        }
        return mostRecent.values
            .sorted { a, b in
                if a.date != b.date { return a.date > b.date }
                if a.sessionID != b.sessionID { return a.sessionID.uuidString < b.sessionID.uuidString }
                return a.index < b.index
            }
            .map(\.display)
    }

    /// 从仓储重新加载全部场次（日期降序）。失败时保留上一次成功值并记录错误。
    public func reload() async {
        do {
            sessions = try await repository.allSessions()
            errorMessage = nil
        } catch {
            errorMessage = "加载训练历史失败，请稍后重试"
        }
    }

    /// 按 id 删除一场训练。失败时保留 sessions 并记录错误。
    public func delete(id: UUID) async {
        do {
            try await repository.delete(id: id)
            sessions.removeAll { $0.id == id }
            errorMessage = nil
        } catch {
            errorMessage = "删除失败，请稍后重试"
        }
    }

    /// 单动作趋势（直接复用 T003 的 trend(for:in:)，不另写算法）。
    /// 用模块名显式限定：成员方法 trend(for:) 会遮蔽同名的全局函数，
    /// 裸调用会被解析到成员（CI 的 Swift 6.3 直接报错）。
    public func trend(for exerciseName: String) -> [ExerciseTrendPoint] {
        TrainingRecordCore.trend(for: exerciseName, in: sessions)
    }
}
