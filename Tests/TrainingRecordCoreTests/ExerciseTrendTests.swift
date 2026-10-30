import Foundation
import Testing
@testable import TrainingRecordCore

private func fixedUUID(_ s: String) -> UUID {
    UUID(uuidString: s)!
}

private func entry(_ name: String, _ sets: [SetEntry]) -> ExerciseEntry {
    ExerciseEntry(name: name, sets: sets)!
}

private func s(_ weight: Double, _ reps: Int) -> SetEntry {
    SetEntry(weight: weight, reps: reps)!
}

// MARK: - 模型（ExerciseEntry / WorkoutSession 新结构）

@Test func exerciseEntryTrimsSurroundingWhitespace() {
    let e = ExerciseEntry(name: "  卧推 ", sets: [s(1, 1)])
    #expect(e != nil)
    #expect(e?.name == "卧推")
}

@Test func exerciseEntryBlankOrEmptyNameIsNil() {
    #expect(ExerciseEntry(name: "   ", sets: [s(1, 1)]) == nil)
    #expect(ExerciseEntry(name: "", sets: [s(1, 1)]) == nil)
}

@Test func exerciseVolumeSumsItsSets() {
    let e = entry("卧推", [s(100, 5), s(2.5, 4)])   // 500 + 10
    #expect(volume(of: e) == 510)
    #expect(volume(of: entry("卧推", [])) == 0)
}

@Test func totalVolumeSumsAllExercises() {
    let session = WorkoutSession(date: Date(timeIntervalSince1970: 1), exercises: [
        entry("卧推", [s(100, 5), s(2.5, 4)]),   // 510
        entry("深蹲", [s(0, 10)]),                // 0
    ])
    #expect(totalVolume(of: session) == 510)
    let empty = WorkoutSession(date: Date(timeIntervalSince1970: 2), exercises: [])
    #expect(totalVolume(of: empty) == 0)
}

// MARK: - 单动作趋势

@Test func e1rmValuesFollowEpley() {
    let sessions = [
        WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000101"), date: Date(timeIntervalSince1970: 100), exercises: [entry("Bench", [s(100, 5)])]),   // 116.7
        WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000102"), date: Date(timeIntervalSince1970: 200), exercises: [entry("Bench", [s(60, 10)])]),    // 80.0
        WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000103"), date: Date(timeIntervalSince1970: 300), exercises: [entry("Bench", [s(100, 1)])]),    // 100.0
    ]
    let points = trend(for: "Bench", in: sessions)
    #expect(points.map(\.bestE1RM) == [116.7, 80.0, 100.0])
}

@Test func bestE1RMIsTheMaxAcrossSetsAndVolumeSumsAll() {
    // 组序故意让最大 e1RM 不在第一组：60×10 → 80.0，100×5 → 116.7，50×3 → 55.0
    let session = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000110"), date: Date(timeIntervalSince1970: 100), exercises: [
        entry("Bench", [s(60, 10), s(100, 5), s(50, 3)]),
    ])
    let points = trend(for: "Bench", in: [session])
    #expect(points.count == 1)
    #expect(points[0].bestE1RM == 116.7)
    #expect(points[0].volume == 600 + 500 + 150)   // 1250
}

@Test func exerciseNameMatchesTrimmedAndCaseInsensitive() {
    let session = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000120"), date: Date(timeIntervalSince1970: 100), exercises: [
        entry(" bench press ", [s(100, 5)]),   // 500
        entry("Deadlift", [s(200, 2)]),        // 400，不得计入
    ])
    let points = trend(for: "Bench Press", in: [session])
    #expect(points.count == 1)
    #expect(points[0].volume == 500)
}

@Test func sameNameWithinOneSessionMergesIntoSinglePoint() {
    let session = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000130"), date: Date(timeIntervalSince1970: 100), exercises: [
        entry("Squat", [s(100, 5)]),   // 500，116.7
        entry("Squat", [s(50, 5)]),    // 250，58.3
    ])
    let points = trend(for: "Squat", in: [session])
    #expect(points.count == 1)
    #expect(points[0].volume == 750)
    #expect(points[0].bestE1RM == 116.7)
}

@Test func pointsSortedByDateAscendingThenUuidStringAscending() {
    // 每次训练给不同次数使各点可区分（100kg 下 Epley 值各不相同）
    let a = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000201"), date: Date(timeIntervalSince1970: 100), exercises: [entry("Bench", [s(100, 11)])])   // 136.7
    let t2 = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000212"), date: Date(timeIntervalSince1970: 150), exercises: [entry("Bench", [s(100, 22)])])   // 173.3
    let t1 = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000211"), date: Date(timeIntervalSince1970: 150), exercises: [entry("Bench", [s(100, 12)])])   // 140.0
    let b = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000220"), date: Date(timeIntervalSince1970: 200), exercises: [entry("Bench", [s(100, 21)])])   // 170.0
    // 乱序输入：同日期两场次的 uuidString 靠后的排在前面
    let sessions = [t2, b, t1, a]
    let points = trend(for: "Bench", in: sessions)
    #expect(points.map(\.date) == [100, 150, 150, 200].map(Date.init(timeIntervalSince1970:)))
    #expect(points.map(\.bestE1RM) == [136.7, 140.0, 173.3, 170.0])
}

@Test func sessionsWithoutTheExerciseProduceNoPoint() {
    let without = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000230"), date: Date(timeIntervalSince1970: 100), exercises: [entry("Squat", [s(100, 5)])])
    let emptySets = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000240"), date: Date(timeIntervalSince1970: 200), exercises: [entry("Bench", [])])
    // 不含该动作 + 该动作组为空：均不产生点
    #expect(trend(for: "Bench", in: [without, emptySets]) == [])
    // 完全没有匹配
    #expect(trend(for: "Plank", in: [without]) == [])
}

@Test func allZeroRepsProducesZeroPointAndZeroRepsNeverJoinE1RM() {
    let s1 = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000250"), date: Date(timeIntervalSince1970: 100), exercises: [entry("Bench", [s(200, 0), s(100, 0)])])
    let s2 = WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000260"), date: Date(timeIntervalSince1970: 200), exercises: [entry("Bench", [s(200, 0), s(60, 10)])])
    let points = trend(for: "Bench", in: [s2, s1])
    #expect(points.count == 2)
    let p1 = points[0]   // date 100：组全 reps==0
    let p2 = points[1]   // date 200：0 次组不得计入 e1RM
    #expect(p1.bestE1RM == 0)
    #expect(p1.volume == 0)
    #expect(p2.bestE1RM == 80.0)   // 只由 60×10 决定，而不是 200×0
    #expect(p2.volume == 600)      // 200×0 容量为 0
}

@Test func bestE1RMRoundedToOneDecimal() {
    let sessions = [
        WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000270"), date: Date(timeIntervalSince1970: 100), exercises: [entry("Bench", [s(100, 7)])]),   // 123.333… → 123.3
        WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000280"), date: Date(timeIntervalSince1970: 200), exercises: [entry("Bench", [s(80, 8)])]),    // 101.333… → 101.3
        WorkoutSession(id: fixedUUID("00000000-0000-0000-0000-000000000290"), date: Date(timeIntervalSince1970: 300), exercises: [entry("Bench", [s(65, 6)])]),    // 78.0
    ]
    #expect(trend(for: "Bench", in: sessions).map(\.bestE1RM) == [123.3, 101.3, 78.0])
}
