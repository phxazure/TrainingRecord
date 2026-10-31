import Foundation
import TrainingRecordCore

/// 「本周」汇总：周一起算，本周内的训练次数、总容量、哪几天练过（0 = 周一 … 6 = 周日）。
struct WeekSummary: Equatable {
    let startDate: Date
    /// 周日（含）。
    let endDate: Date
    let sessionCount: Int
    let volume: Double
    let activeWeekdays: Set<Int>

    static func make(rows: [HistoryRow], now: Date, calendar baseCalendar: Calendar = .current) -> WeekSummary {
        var calendar = baseCalendar
        calendar.firstWeekday = 2  // 周一
        let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 24 * 60 * 60)
        // 半开区间 [start, end)：DateInterval.contains 把结束端点也算进去，下周一 00:00 会被误计入本周。
        let inWeek = rows.filter { interval.start <= $0.date && $0.date < interval.end }
        let weekdays = Set(inWeek.map { weekdayIndex(of: $0.date, calendar: calendar) })
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return WeekSummary(
            startDate: interval.start,
            endDate: lastDay,
            sessionCount: inWeek.count,
            volume: inWeek.reduce(0) { $0 + $1.totalVolume },
            activeWeekdays: weekdays
        )
    }

    /// 0 = 周一 … 6 = 周日（`Calendar.weekday`：周日 = 1，周一 = 2）。
    private static func weekdayIndex(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}

/// 历史列表按月分组：保持输入顺序（日期降序），同一年月的相邻行归为一组。
struct MonthGroup: Identifiable {
    let id: DateComponents
    let rows: [HistoryRow]
    /// 该组第一行的日期，用来生成标题。
    var firstDate: Date { rows[0].date }

    static func group(_ rows: [HistoryRow], calendar: Calendar = .current) -> [MonthGroup] {
        var groups: [MonthGroup] = []
        for row in rows {
            let key = calendar.dateComponents([.year, .month], from: row.date)
            if let last = groups.last, last.id == key {
                groups[groups.count - 1] = MonthGroup(id: key, rows: last.rows + [row])
            } else {
                groups.append(MonthGroup(id: key, rows: [row]))
            }
        }
        return groups
    }
}
