import Foundation
import Testing
@testable import TrainingRecordCore

// 固定日历 / 时区：UTC、公历，周一起算。
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

private func session(_ iso: String, volume: Double, id: Int = 0) -> WorkoutSession {
    WorkoutSession(
        id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", id))!,
        date: date(iso),
        exercises: [ExerciseEntry(name: "卧推", sets: [SetEntry(weight: volume, reps: 1)!])!]
    )
}

// now = 2026-11-04（周三）→ 本周 2026-11-02(一) … 2026-11-08(日)
private let now = date("2026-11-04T10:00:00Z")

@Suite struct WeeklyTrendTests {
    @Test func returnsRequestedNumberOfWeeksOldestFirstEndingWithCurrentWeek() {
        let points = weeklyTrend(of: [], weeks: 4, now: now, calendar: utc)
        #expect(points.map(\.weekStart) == [
            date("2026-10-12T00:00:00Z"), date("2026-10-19T00:00:00Z"),
            date("2026-10-26T00:00:00Z"), date("2026-11-02T00:00:00Z"),
        ])
    }

    @Test func defaultsToTwelveWeeks() {
        #expect(weeklyTrend(of: [], now: now, calendar: utc).count == 12)
    }

    @Test func emptyWeeksAreFilledWithZero() {
        let points = weeklyTrend(of: [], weeks: 3, now: now, calendar: utc)
        #expect(points.map(\.sessionCount) == [0, 0, 0])
        #expect(points.map(\.volume) == [0, 0, 0])
    }

    @Test func countsSessionsAndSumsVolumePerWeek() {
        let sessions = [
            session("2026-11-03T08:00:00Z", volume: 100, id: 1),  // 本周
            session("2026-11-05T08:00:00Z", volume: 50, id: 2),  // 本周
            session("2026-10-28T08:00:00Z", volume: 70, id: 3),  // 上周
        ]
        let points = weeklyTrend(of: sessions, weeks: 3, now: now, calendar: utc)
        #expect(points.map(\.sessionCount) == [0, 1, 2])
        #expect(points.map(\.volume) == [0, 70, 150])
    }

    @Test func weekBoundariesAreHalfOpenMondayToMonday() {
        let sessions = [
            session("2026-11-02T00:00:00Z", volume: 1, id: 1),  // 周一 00:00：本周
            session("2026-11-01T23:59:59Z", volume: 10, id: 2),  // 上周日 23:59:59：上周
            session("2026-10-26T00:00:00Z", volume: 100, id: 3),  // 上周一 00:00：上周
        ]
        let points = weeklyTrend(of: sessions, weeks: 2, now: now, calendar: utc)
        #expect(points.map(\.sessionCount) == [2, 1])
        #expect(points.map(\.volume) == [110, 1])
    }

    @Test func sundayLateNightBelongsToCurrentWeekAndNextMondayDoesNot() {
        let sessions = [
            session("2026-11-08T23:59:59Z", volume: 5, id: 1),  // 本周日：算
            session("2026-11-09T00:00:00Z", volume: 1000, id: 2),  // 下周一：不算
        ]
        let points = weeklyTrend(of: sessions, weeks: 2, now: now, calendar: utc)
        #expect(points.last?.sessionCount == 1)
        #expect(points.last?.volume == 5)
        #expect(points.map(\.volume).reduce(0, +) == 5)
    }

    @Test func sessionsOlderThanTheWindowAreNotCounted() {
        let sessions = [
            session("2026-10-11T23:59:59Z", volume: 999, id: 1),  // 4 周窗口之前的周日
            session("2026-10-12T00:00:00Z", volume: 1, id: 2),  // 窗口第一周周一 00:00
        ]
        let points = weeklyTrend(of: sessions, weeks: 4, now: now, calendar: utc)
        #expect(points.map(\.sessionCount) == [1, 0, 0, 0])
        #expect(points.map(\.volume) == [1, 0, 0, 0])
    }

    @Test func nonPositiveWeeksGivesEmpty() {
        #expect(weeklyTrend(of: [], weeks: 0, now: now, calendar: utc).isEmpty)
        #expect(weeklyTrend(of: [], weeks: -2, now: now, calendar: utc).isEmpty)
    }

    @Test func calendarsWithOtherFirstWeekdayStillUseMonday() {
        var sundayFirst = utc
        sundayFirst.firstWeekday = 1
        let points = weeklyTrend(of: [], weeks: 1, now: now, calendar: sundayFirst)
        #expect(points.first?.weekStart == date("2026-11-02T00:00:00Z"))
    }

    @Test func respectsTheCalendarsTimeZone() {
        var tokyo = utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!  // UTC+9
        // UTC 周日 15:30 = 东京周一 00:30：东京日历下属于下一周（即“本周”）。
        let sessions = [session("2026-11-01T15:30:00Z", volume: 7, id: 1)]
        let nowTokyo = date("2026-11-04T01:00:00Z")
        let points = weeklyTrend(of: sessions, weeks: 2, now: nowTokyo, calendar: tokyo)
        #expect(points.map(\.sessionCount) == [0, 1])
    }
}
