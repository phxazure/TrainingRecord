import Foundation

/// 整体训练趋势的一周：这一周（周一 00:00 起，半开区间）的训练次数与总容量。
public struct WeeklyTrendPoint: Equatable, Sendable {
    /// 这一周周一 00:00（按传入日历的时区）。
    public let weekStart: Date
    public let sessionCount: Int
    /// 这一周所有场次的总容量（kg）。
    public let volume: Double

    public init(weekStart: Date, sessionCount: Int, volume: Double) {
        self.weekStart = weekStart
        self.sessionCount = sessionCount
        self.volume = volume
    }
}

/// 整体训练趋势：最近 `weeks` 周（含 `now` 所在周），按周聚合。
/// - 一周从周一 00:00 起，半开区间 `[周一 00:00, 下周一 00:00)`，与「历史」页的本周汇总一致；
///   无论传入日历的 `firstWeekday` 是什么都按周一起算。
/// - 结果按周升序（最旧在前，最后一个是本周）；没有训练的周补 0。
/// - 早于窗口第一周、或晚于本周的场次不计入。`weeks <= 0` 返回空数组。
public func weeklyTrend(
    of sessions: [WorkoutSession],
    weeks: Int = 12,
    now: Date,
    calendar baseCalendar: Calendar = .current
) -> [WeeklyTrendPoint] {
    guard weeks > 0 else { return [] }
    var calendar = baseCalendar
    calendar.firstWeekday = 2  // 周一
    guard let current = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }

    var starts: [Date] = []
    for offset in stride(from: weeks - 1, through: 0, by: -1) {
        if let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current.start) {
            starts.append(start)
        }
    }
    var counts = [Int](repeating: 0, count: starts.count)
    var volumes = [Double](repeating: 0, count: starts.count)
    for session in sessions {
        // 找 start <= date < 下一周的 start（最后一周的上界是本周结束）。
        for index in starts.indices {
            let upper = index + 1 < starts.count ? starts[index + 1] : current.end
            if starts[index] <= session.date && session.date < upper {
                counts[index] += 1
                volumes[index] += totalVolume(of: session)
                break
            }
        }
    }
    return starts.indices.map { WeeklyTrendPoint(weekStart: starts[$0], sessionCount: counts[$0], volume: volumes[$0]) }
}
