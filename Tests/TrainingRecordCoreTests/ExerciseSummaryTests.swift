import Foundation
import Testing
@testable import TrainingRecordCore

private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))!
}

private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

private func entry(_ name: String, id: UUID?, _ sets: [(Double, Int)]) -> ExerciseEntry {
    ExerciseEntry(name: name, sets: sets.map { SetEntry(weight: $0.0, reps: $0.1)! }, exerciseID: id)!
}

private func session(_ n: Int, day d: Int, _ entries: [ExerciseEntry]) -> WorkoutSession {
    WorkoutSession(id: uuid(1000 + n), date: day(d), exercises: entries)
}

private func definition(_ n: Int, _ name: String, _ part: String = "胸") -> ExerciseDefinition {
    ExerciseDefinition(id: uuid(n), name: name, bodyPart: part)!
}

@Suite struct ExerciseSummaryTests {
    private let bench = uuid(1), squat = uuid(2), row = uuid(3)

    @Test func latestBestE1RMUsesEpleyAndRoundingOfTheTrendFunction() throws {
        // 60 × 10 → 60 × (1 + 10/30) = 80.0；65 × 8 → 82.333… → 82.3
        let sessions = [session(1, day: 1, [entry("卧推", id: bench, [(60, 10), (65, 8)])])]
        let summary = try #require(exerciseSummaries(library: [definition(1, "卧推")], sessions: sessions).first)
        #expect(summary.latestBestE1RM == 82.3)
        #expect(summary.latestDate == day(1))
        #expect(summary.exercise.name == "卧推")
        #expect(summary.sessionCount == 1)
    }

    @Test func changeIsComparedWithThePreviousSessionOnly() throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(100, 1)])]),
            session(2, day: 8, [entry("卧推", id: bench, [(80, 1)])]),
            session(3, day: 15, [entry("卧推", id: bench, [(90, 1)])]),
        ]
        let summary = try #require(exerciseSummaries(library: [definition(1, "卧推")], sessions: sessions).first)
        #expect(summary.latestBestE1RM == 90)
        #expect(summary.change == .up(10))
        #expect(summary.sessionCount == 3)
    }

    @Test func changeKinds() throws {
        func change(_ previous: Double, _ latest: Double) throws -> ExerciseSummary.Change {
            let sessions = [
                session(1, day: 1, [entry("卧推", id: bench, [(previous, 1)])]),
                session(2, day: 2, [entry("卧推", id: bench, [(latest, 1)])]),
            ]
            return try #require(exerciseSummaries(library: [definition(1, "卧推")], sessions: sessions).first).change
        }
        #expect(try change(80, 90) == .up(10))
        #expect(try change(90, 80) == .down(10))
        #expect(try change(90, 90) == .flat)
        #expect(try change(80, 81.7) == .up(1.7))
        #expect(try change(81.7, 80) == .down(1.7))
        let single = [session(1, day: 1, [entry("卧推", id: bench, [(80, 1)])])]
        #expect(exerciseSummaries(library: [definition(1, "卧推")], sessions: single).first?.change == .noPrevious)
    }

    @Test func orderedByMostRecentUseDescendingThenName() {
        let sessions = [
            session(1, day: 1, [entry("划船", id: row, [(50, 10)])]),
            session(2, day: 5, [entry("卧推", id: bench, [(60, 5)]), entry("深蹲", id: squat, [(100, 5)])]),
            session(3, day: 3, [entry("划船", id: row, [(55, 10)])]),
        ]
        let library = [definition(1, "Bench"), definition(2, "Squat"), definition(3, "Row")]
        let names = exerciseSummaries(library: library, sessions: sessions).map(\.exercise.name)
        // Bench 与 Squat 同在 day 5：按名字排；Row 最近在 day 3。
        #expect(names == ["Bench", "Squat", "Row"])
    }

    @Test func onlyExercisesStillInTheLibraryAndWithHistoryAreIncluded() {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 5)]), entry("已删除", id: uuid(99), [(1, 1)]), entry("无 id", id: nil, [(1, 1)])]),
        ]
        let library = [definition(1, "卧推"), definition(2, "从没练过")]
        #expect(exerciseSummaries(library: library, sessions: sessions).map(\.exercise.name) == ["卧推"])
    }

    @Test func usesCurrentLibraryNameNotTheEntrySnapshotAndMatchesById() throws {
        let sessions = [
            session(1, day: 1, [entry("旧名字", id: bench, [(60, 5)])]),
            session(2, day: 2, [entry("新名字", id: bench, [(70, 5)])]),
        ]
        let summaries = exerciseSummaries(library: [definition(1, "新名字")], sessions: sessions)
        let summary = try #require(summaries.first)
        #expect(summaries.count == 1)
        #expect(summary.sessionCount == 2)
        #expect(summary.change != .noPrevious)
    }

    @Test func sameExerciseTwiceInOneSessionCountsAsOneSessionAndCombinesSets() throws {
        let sessions = [session(1, day: 1, [entry("卧推", id: bench, [(60, 5)]), entry("卧推", id: bench, [(100, 1)])])]
        let summary = try #require(exerciseSummaries(library: [definition(1, "卧推")], sessions: sessions).first)
        #expect(summary.sessionCount == 1)
        #expect(summary.latestBestE1RM == 100)
    }

    @Test func emptyInputs() {
        #expect(exerciseSummaries(library: [], sessions: []).isEmpty)
        #expect(exerciseSummaries(library: [definition(1, "卧推")], sessions: []).isEmpty)
    }
}

@Suite struct ExerciseHistoryQueriesTests {
    private let bench = uuid(1)

    @Test func exerciseTrendMatchesByIdAndMatchesTheNameBasedTrend() {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 10)])]),
            session(2, day: 8, [entry("卧推", id: bench, [(70, 5)]), entry("深蹲", id: uuid(2), [(100, 5)])]),
            session(3, day: 9, [entry("卧推", id: nil, [(999, 1)])]),  // 没有 id：不计入
        ]
        let points = exerciseTrend(for: definition(1, "卧推"), in: sessions)
        #expect(points.count == 2)
        #expect(points == trend(for: "卧推", in: Array(sessions.prefix(2))))
        #expect(points.map(\.date) == [day(1), day(8)])
    }

    @Test func recentRecordsAreNewestFirstLimitedAndCarryTheSets() {
        let sessions = (1...5).map { session($0, day: $0, [entry("卧推", id: bench, [(Double(50 + $0), $0)])]) }
            + [session(9, day: 9, [entry("深蹲", id: uuid(2), [(100, 5)])])]
        let records = recentRecords(of: bench, in: sessions, limit: 3)
        #expect(records.map(\.date) == [day(5), day(4), day(3)])
        #expect(records.first?.sets == [SetEntry(weight: 55, reps: 5)!])
        #expect(records.map(\.sessionID) == [uuid(1005), uuid(1004), uuid(1003)])
        #expect(recentRecords(of: bench, in: sessions, limit: 0).isEmpty)
        #expect(recentRecords(of: bench, in: sessions, limit: 99).count == 5)
        #expect(recentRecords(of: uuid(77), in: sessions, limit: 3).isEmpty)
    }

    @Test func recentRecordsMergeDuplicateEntriesOfOneSession() {
        let sessions = [session(1, day: 1, [entry("卧推", id: bench, [(60, 5)]), entry("卧推", id: bench, [(70, 3)])])]
        let records = recentRecords(of: bench, in: sessions, limit: 5)
        #expect(records.count == 1)
        #expect(records.first?.sets == [SetEntry(weight: 60, reps: 5)!, SetEntry(weight: 70, reps: 3)!])
    }

    @Test func sessionCountCountsSessionsNotEntries() {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 5)]), entry("卧推", id: bench, [(70, 3)])]),
            session(2, day: 2, [entry("卧推", id: bench, [(60, 5)])]),
            session(3, day: 3, [entry("卧推", id: nil, [(60, 5)])]),
        ]
        #expect(sessionCount(of: bench, in: sessions) == 2)
        #expect(sessionCount(of: uuid(9), in: sessions) == 0)
    }

    private func session(_ n: Int, day d: Int, _ entries: [ExerciseEntry]) -> WorkoutSession {
        WorkoutSession(id: uuid(1000 + n), date: day(d), exercises: entries)
    }
}

@Suite struct ExerciseGroupingTests {
    private func make(_ name: String, _ part: String) -> ExerciseDefinition {
        ExerciseDefinition(name: name, bodyPart: part)!
    }

    @Test func groupsByPartSortedWithUncategorizedLast() {
        let groups = groupByBodyPart([
            make("Squat", "Legs"), make("Mystery B", ""), make("Curl", "Arms"),
            make("Leg Press", "Legs"), make("Mystery A", "未分类"), make("Bench 10", "Chest"), make("Bench 2", "Chest"),
        ])
        #expect(groups.map(\.bodyPart) == ["Arms", "Chest", "Legs", "未分类"])
        #expect(groups.map { $0.exercises.map(\.name) } == [["Curl"], ["Bench 2", "Bench 10"], ["Leg Press", "Squat"], ["Mystery A", "Mystery B"]])
    }

    @Test func emptyInputGivesNoGroups() {
        #expect(groupByBodyPart([]).isEmpty)
    }
}
