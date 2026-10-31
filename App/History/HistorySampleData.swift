#if DEBUG
import Foundation
import TrainingRecordCore

/// 仅 DEBUG：历史 / 趋势界面的启动参数，用于截图与手动验证。
/// 整个文件在 Release 构建中不参与编译，Release 不含样例数据。
///
/// - `-seedHistorySample`：往仓储预填若干场样例训练（卧推 5 场，可画 ≥4 点的趋势；推举只有 1 场）。
///   App 会改用内存仓储，样例不写进真实的本地存储。
/// - `-historyTab history|trend`：启动后直接切到对应标签（兼容旧值 list）。
/// - `-historyOpenFirst`：启动后切到「历史」并打开最近一场训练的明细。
/// - `-trendExercise <名称>`：趋势标签选中指定动作。
/// - `-trendMetric volume`：趋势标签启动时选「容量」。
enum HistoryDebugLaunch {
    static let seedArgument = "-seedHistorySample"
    static let tabArgument = "-historyTab"
    static let openFirstArgument = "-historyOpenFirst"
    static let trendExerciseArgument = "-trendExercise"
    static let trendMetricArgument = "-trendMetric"

    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    private static func value(after argument: String) -> String? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var initialTab: ContentView.Tab? {
        switch value(after: tabArgument) {
        case "trend": return .trend
        case "history", "list": return .history
        default: return opensFirstSession ? .history : nil
        }
    }

    static var opensFirstSession: Bool { arguments.contains(openFirstArgument) }

    static var trendExercise: String? { value(after: trendExerciseArgument) }

    static var initialMetric: TrendMetric? {
        value(after: trendMetricArgument) == "volume" ? .volume : nil
    }

    /// 按启动参数预填样例训练；未请求时什么都不做。
    static func seedIfRequested(_ repository: any WorkoutRepository) async {
        guard arguments.contains(seedArgument) else { return }
        for session in sampleSessions() {
            try? await repository.save(session)
        }
    }

    /// 最近 5 周、每周一场：卧推逐步加重，深蹲 4 场，硬拉 2 场，推举只在最近一场出现（单点趋势）。
    static func sampleSessions(now: Date = Date()) -> [WorkoutSession] {
        typealias Plan = [(name: String, sets: [(Double, Int)])]
        let plans: [Plan] = [
            [("卧推", [(60, 10), (65, 8), (70, 6)]), ("深蹲", [(100, 5), (100, 5), (100, 5)])],
            [("卧推", [(62.5, 10), (67.5, 8), (72.5, 5)]), ("硬拉", [(120, 5), (130, 3)])],
            [("深蹲", [(105, 5), (105, 5)]), ("卧推", [(65, 10), (70, 8), (75, 5)])],
            [("卧推", [(67.5, 10), (72.5, 7), (77.5, 4)]), ("深蹲", [(107.5, 5), (110, 4)])],
            [
                ("卧推", [(70, 10), (75, 8), (80, 4)]),
                ("深蹲", [(112.5, 5), (115, 3)]),
                ("硬拉", [(140, 3)]),
                ("推举", [(40, 8), (42.5, 6)]),
            ],
        ]
        let calendar = Calendar.current
        return plans.enumerated().compactMap { offset, plan in
            let weeksAgo = plans.count - 1 - offset
            guard let date = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now) else { return nil }
            let exercises = plan.compactMap { exercise in
                ExerciseEntry(
                    name: exercise.name,
                    sets: exercise.sets.compactMap { SetEntry(weight: $0.0, reps: $0.1) }
                )
            }
            return WorkoutSession(date: date, exercises: exercises)
        }
    }
}
#endif
