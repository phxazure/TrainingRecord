import Foundation
import Testing
@testable import TrainingRecordCore

// MARK: - 测试数据

/// 固定日期，测试不依赖真实时钟。
private let day1 = Date(timeIntervalSince1970: 1_700_000_000)   // 最旧
private let day2 = Date(timeIntervalSince1970: 1_700_100_000)
private let day3 = Date(timeIntervalSince1970: 1_700_200_000)   // 最新

private let s1ID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
private let s2ID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
private let s3ID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!

/// s1（最旧）：Bench Press 100×5，Squat 100×5。
private let s1 = WorkoutSession(id: s1ID, date: day1, exercises: [
    ExerciseEntry(name: "Bench Press", sets: [SetEntry(weight: 100, reps: 5)!])!,
    ExerciseEntry(name: "Squat", sets: [SetEntry(weight: 100, reps: 5)!])!,
])
/// s2（中间）：Bench Press 60×10、65×8、67.5×6；Squat 200×2、200×2（2 个动作共 5 组）。
private let s2 = WorkoutSession(id: s2ID, date: day2, exercises: [
    ExerciseEntry(name: "Bench Press", sets: [SetEntry(weight: 60, reps: 10)!, SetEntry(weight: 65, reps: 8)!, SetEntry(weight: 67.5, reps: 6)!])!,
    ExerciseEntry(name: "Squat", sets: [SetEntry(weight: 200, reps: 2)!, SetEntry(weight: 200, reps: 2)!])!,
])
/// s3（最新）：Deadlift 200×2；bench press 70×6（大小写变体，录入顺序在 Deadlift 之后）。
private let s3 = WorkoutSession(id: s3ID, date: day3, exercises: [
    ExerciseEntry(name: "Deadlift", sets: [SetEntry(weight: 200, reps: 2)!])!,
    ExerciseEntry(name: "bench press", sets: [SetEntry(weight: 70, reps: 6)!])!,
])

/// 三个场次按仓储顺序（日期降序）。
private let allSessions = [s3, s2, s1]

// MARK: - 假仓储

/// 可控制读取/删除行为的假仓储，用于验证失败场景。
private actor ScriptedRepository: WorkoutRepository {
    struct Boom: Error, Equatable {}

    private var stored: [UUID: WorkoutSession]
    private var failAllSessions = false
    private var failDelete = false

    init(sessions: [WorkoutSession]) {
        stored = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    func setFailAllSessions(_ flag: Bool) {
        failAllSessions = flag
    }

    func setFailDelete(_ flag: Bool) {
        failDelete = flag
    }

    func save(_ session: WorkoutSession) async throws {
        stored[session.id] = session
    }

    func session(id: UUID) async throws -> WorkoutSession? {
        stored[id]
    }

    func allSessions() async throws -> [WorkoutSession] {
        if failAllSessions { throw Boom() }
        return stored.values.sorted { a, b in
            if a.date != b.date { return a.date > b.date }
            return a.id.uuidString < b.id.uuidString
        }
    }

    func delete(id: UUID) async throws {
        if failDelete { throw Boom() }
        stored[id] = nil
    }
}

// MARK: - 测试

@MainActor
@Suite struct HistoryViewModelTests {
    private func makeModel(repository: any WorkoutRepository) -> HistoryViewModel {
        HistoryViewModel(repository: repository)
    }

    // MARK: 初始状态与空仓储

    @Test func initialIsEmptyAndEmptyReloadStaysEmpty() async {
        let model = makeModel(repository: InMemoryWorkoutRepository())
        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == nil)

        await model.reload()

        #expect(model.sessions.isEmpty)
        #expect(model.errorMessage == nil)
    }

    // MARK: reload

    @Test func reloadMatchesRepositoryIncludingOrder() async throws {
        let repo = InMemoryWorkoutRepository(sessions: [s1, s2, s3])
        let model = makeModel(repository: repo)

        await model.reload()

        let expected = try await repo.allSessions()
        #expect(model.sessions == expected)
        #expect(model.sessions.map(\.id) == [s3ID, s2ID, s1ID])
        #expect(model.errorMessage == nil)
    }

    // MARK: rows

    @Test func rowsMirrorSessionsWithConcreteValues() async {
        let model = makeModel(repository: InMemoryWorkoutRepository(sessions: [s1, s2, s3]))
        await model.reload()

        #expect(model.rows == [
            HistoryRow(id: s3ID, date: day3, exerciseNames: ["Deadlift", "bench press"], setCount: 2, totalVolume: 820),
            HistoryRow(id: s2ID, date: day2, exerciseNames: ["Bench Press", "Squat"], setCount: 5, totalVolume: 2325),
            HistoryRow(id: s1ID, date: day1, exerciseNames: ["Bench Press", "Squat"], setCount: 2, totalVolume: 1000),
        ])
    }

    // MARK: exerciseNames

    @Test func exerciseNamesDedupByMostRecentAppearance() async {
        let model = makeModel(repository: InMemoryWorkoutRepository(sessions: [s1, s2, s3]))
        await model.reload()

        // bench press 最近出现在 s3（day3，写法 "bench press"）；deadlift 也在 s3（录入序在前）；
        // squat 最近出现在 s2（day2，写法 "Squat"）。
        #expect(model.exerciseNames == ["Deadlift", "bench press", "Squat"])
    }

    // MARK: trend

    @Test func trendMatchesGlobalFunctionAndConcreteValues() async {
        let model = makeModel(repository: InMemoryWorkoutRepository(sessions: [s1, s2, s3]))
        await model.reload()

        let points = model.trend(for: "Bench Press")

        #expect(points == trend(for: "Bench Press", in: model.sessions))
        #expect(points == [
            ExerciseTrendPoint(date: day1, bestE1RM: 116.7, volume: 500),
            ExerciseTrendPoint(date: day2, bestE1RM: 82.3, volume: 1525),
            ExerciseTrendPoint(date: day3, bestE1RM: 84.0, volume: 420),
        ])
    }

    @Test func trendForUnknownExerciseIsEmpty() async {
        let model = makeModel(repository: InMemoryWorkoutRepository(sessions: [s1, s2, s3]))
        await model.reload()

        #expect(model.trend(for: "Clean and Jerk").isEmpty)
    }

    // MARK: delete

    @Test func deleteSuccessRemovesFromRepositoryAndSessions() async throws {
        let repo = InMemoryWorkoutRepository(sessions: [s1, s2, s3])
        let model = makeModel(repository: repo)
        await model.reload()

        await model.delete(id: s2ID)

        #expect(try await repo.session(id: s2ID) == nil)
        #expect(model.sessions.map(\.id) == [s3ID, s1ID])
        #expect(model.errorMessage == nil)
    }

    @Test func deleteFailureKeepsSessionsAndReportsError() async {
        let repo = ScriptedRepository(sessions: [s1, s2, s3])
        await repo.setFailDelete(true)
        let model = makeModel(repository: repo)
        await model.reload()
        let before = model.sessions

        await model.delete(id: s2ID)

        #expect(model.sessions == before)
        #expect(model.errorMessage != nil)
    }

    // MARK: reload 失败

    @Test func reloadFailureKeepsLastGoodValueAndReportsError() async {
        let repo = ScriptedRepository(sessions: [s1, s2, s3])
        let model = makeModel(repository: repo)
        await model.reload()
        #expect(model.sessions.count == 3)
        let lastGood = model.sessions

        await repo.setFailAllSessions(true)
        await model.reload()

        #expect(model.sessions == lastGood)
        #expect(model.errorMessage != nil)

        await repo.setFailAllSessions(false)
        await model.reload()

        #expect(model.errorMessage == nil)
        #expect(model.sessions == lastGood)
    }
}
