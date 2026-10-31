import Foundation
import Testing
import TrainingRecordCore
@testable import TrainingRecordPersistence

// MARK: - 辅助

/// 同一组行为用例对两种存储方式各跑一遍：内存模式与磁盘模式。
enum StoreKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case onDisk

    var testDescription: String { rawValue }
}

/// 每个测试独占一个临时目录；测试结束（无论成败）删除。
private func makeTempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("TrainingRecordPersistenceTests-\(UUID().uuidString)", isDirectory: true)
}

/// 目录不预先创建：由 `onDisk(url:)` 负责创建不存在的父目录。
private func withRepository<T>(
    _ kind: StoreKind,
    _ body: (SwiftDataWorkoutRepository) async throws -> T
) async throws -> T {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository: SwiftDataWorkoutRepository
    switch kind {
    case .inMemory:
        repository = try SwiftDataWorkoutRepository.inMemory()
    case .onDisk:
        repository = try SwiftDataWorkoutRepository.onDisk(url: directory.appendingPathComponent("store.sqlite"))
    }
    return try await body(repository)
}

private func uuid(_ suffix: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", suffix))!
}

private func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
}

private typealias ExercisePlan = (name: String, sets: [(weight: Double, reps: Int)])

private func makeSession(id: UUID = UUID(), date: Date, _ plan: [ExercisePlan]) -> WorkoutSession {
    WorkoutSession(
        id: id,
        date: date,
        exercises: plan.map { exercise in
            ExerciseEntry(
                name: exercise.name,
                sets: exercise.sets.map { SetEntry(weight: $0.weight, reps: $0.reps)! }
            )!
        }
    )
}

/// 最简单的一场：一个动作一组，reps 用来区分内容。
private func simpleSession(id: UUID = UUID(), date: Date, reps: Int) -> WorkoutSession {
    makeSession(id: id, date: date, [("卧推", [(100, reps)])])
}

/// 动作顺序与组顺序都刻意不是按名字/重量/次数排序的，用来锁定「顺序按录入保存」。
private func orderSensitiveSession(id: UUID = UUID(), date: Date) -> WorkoutSession {
    makeSession(id: id, date: date, [
        ("深蹲", [(100, 5), (60, 12), (140, 1), (80, 8), (120, 3), (60, 11), (100, 6), (20, 30)]),
        ("卧推", [(62.5, 10), (60, 10), (67.5, 8), (65, 9)]),
        ("硬拉", [(180, 1), (100, 10), (140, 5)]),
        ("引体向上", [(0, 12), (0, 8), (0, 10), (0, 6), (0, 7)]),
        ("划船", [(50, 12)]),
        ("A 动作", [(10, 10), (30, 30), (20, 20)]),
    ])
}

// MARK: - 仓储行为（与 InMemoryWorkoutRepository 一致）

@Suite struct SwiftDataWorkoutRepositoryTests {
    @Test(arguments: StoreKind.allCases)
    func emptyRepository(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            #expect(try await repository.allSessions() == [])
            #expect(try await repository.session(id: UUID()) == nil)
        }
    }

    @Test(arguments: StoreKind.allCases)
    func saveThenFetchReturnsSameSession(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let original = makeSession(id: uuid(1), date: date(1_700_000_123.456), [
                ("卧推", [(62.5, 10), (0.1 + 0.2, 8), (0, 0)]),
                ("Pull-up  ", [(0, 12)]),
                ("空组动作", []),
                ("大数", [(Double.greatestFiniteMagnitude, Int.max)]),
            ])
            try await repository.save(original)

            #expect(try await repository.session(id: original.id) == original)
            #expect(try await repository.allSessions() == [original])
        }
    }

    @Test(arguments: StoreKind.allCases)
    func sessionWithoutExercisesRoundTrips(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let empty = WorkoutSession(id: uuid(2), date: date(10), exercises: [])
            try await repository.save(empty)
            #expect(try await repository.session(id: empty.id) == empty)
        }
    }

    @Test(arguments: StoreKind.allCases)
    func saveWithSameIdOverwritesInsteadOfAppending(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let id = uuid(0xaa)
            let first = makeSession(id: id, date: date(100), [("卧推", [(60, 5), (65, 4)]), ("深蹲", [(100, 5)])])
            let second = makeSession(id: id, date: date(200), [("硬拉", [(120, 3)])])
            try await repository.save(first)
            try await repository.save(second)

            #expect(try await repository.allSessions().count == 1)
            #expect(try await repository.session(id: id) == second)
            // 覆盖不留下旧场次的动作/组。
            let counts = try await repository.storedRecordCounts()
            #expect(counts == StoredRecordCounts(sessions: 1, exercises: 1, sets: 1))
        }
    }

    @Test(arguments: StoreKind.allCases)
    func allSessionsSortsByDateDescendingWithShuffledInsertion(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let sessions = [3, 1, 5, 2, 4].map { simpleSession(id: uuid($0), date: date(TimeInterval($0) * 100), reps: $0) }
            for session in sessions { try await repository.save(session) }

            let all = try await repository.allSessions()
            #expect(all.map(\.date) == [500, 400, 300, 200, 100].map(date))
        }
    }

    @Test(arguments: StoreKind.allCases)
    func allSessionsTieBreaksByUuidStringAscending(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let sameDate = date(500)
            // 乱序插入：uuidString 靠后的先插入。
            for suffix in [3, 1, 4, 2] {
                try await repository.save(simpleSession(id: uuid(suffix), date: sameDate, reps: suffix))
            }
            let newer = simpleSession(id: uuid(9), date: date(900), reps: 9)
            try await repository.save(newer)

            let all = try await repository.allSessions()
            #expect(all.map(\.id) == [uuid(9), uuid(1), uuid(2), uuid(3), uuid(4)])
        }
    }

    @Test(arguments: StoreKind.allCases)
    func deleteRemovesTargetAndKeepsOthers(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let keep1 = simpleSession(id: uuid(1), date: date(100), reps: 1)
            let target = orderSensitiveSession(id: uuid(2), date: date(200))
            let keep2 = simpleSession(id: uuid(3), date: date(300), reps: 3)
            for session in [keep1, target, keep2] { try await repository.save(session) }

            try await repository.delete(id: target.id)

            #expect(try await repository.session(id: target.id) == nil)
            #expect(try await repository.allSessions() == [keep2, keep1])
            // 级联删除：目标场次的动作和组一并清掉，只剩另外两场各 1 动作 1 组。
            let counts = try await repository.storedRecordCounts()
            #expect(counts == StoredRecordCounts(sessions: 2, exercises: 2, sets: 2))
        }
    }

    @Test(arguments: StoreKind.allCases)
    func deleteMissingIdIsSilentNoOp(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let session = simpleSession(id: uuid(1), date: date(100), reps: 1)
            try await repository.save(session)

            try await repository.delete(id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!)
            #expect(try await repository.allSessions() == [session])

            // 空仓储上删除也不抛错。
            let other = try SwiftDataWorkoutRepository.inMemory()
            try await other.delete(id: UUID())
        }
    }

    @Test(arguments: StoreKind.allCases)
    func concurrentSavesDoNotLoseSessions(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<100 {
                    group.addTask {
                        try await repository.save(simpleSession(id: uuid(i), date: date(0), reps: i))
                    }
                }
                // 必须等待全部子任务完成：否则闭包返回后 group 会取消未完成的子任务并吞掉错误，
                // 子任务抛错不会让测试失败。
                try await group.waitForAll()
            }
            #expect(try await repository.allSessions().count == 100)
        }
    }

    // MARK: 顺序

    @Test(arguments: StoreKind.allCases)
    func exerciseAndSetOrderIsPreserved(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let original = orderSensitiveSession(id: uuid(1), date: date(100))
            try await repository.save(original)

            let loaded = try #require(try await repository.session(id: original.id))
            #expect(loaded.exercises.map(\.name) == ["深蹲", "卧推", "硬拉", "引体向上", "划船", "A 动作"])
            #expect(loaded.exercises[0].sets.map(\.weight) == [100, 60, 140, 80, 120, 60, 100, 20])
            #expect(loaded.exercises[0].sets.map(\.reps) == [5, 12, 1, 8, 3, 11, 6, 30])
            #expect(loaded == original)
            // allSessions 走另一条读取路径，同样要保持顺序。
            #expect(try await repository.allSessions() == [original])
        }
    }

    @Test(arguments: StoreKind.allCases)
    func overwriteReplacesOrderToo(kind: StoreKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let id = uuid(1)
            try await repository.save(orderSensitiveSession(id: id, date: date(100)))
            let reordered = makeSession(id: id, date: date(100), [
                ("A 动作", [(30, 30), (10, 10)]),
                ("深蹲", [(20, 30), (100, 5)]),
            ])
            try await repository.save(reordered)
            #expect(try await repository.session(id: id) == reordered)
        }
    }
}

// MARK: - 持久性（磁盘）

@Suite struct SwiftDataPersistenceTests {
    @Test func dataSurvivesReleasingAndReopeningTheSameFile() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")

        let sessions = [
            orderSensitiveSession(id: uuid(1), date: date(300)),
            simpleSession(id: uuid(2), date: date(100), reps: 7),
            makeSession(id: uuid(3), date: date(200), [("卧推", [(62.5, 10)]), ("深蹲", [(100, 5), (105, 4)])]),
        ]
        do {
            let first = try SwiftDataWorkoutRepository.onDisk(url: url)
            for session in sessions { try await first.save(session) }
            #expect(try await first.allSessions().count == 3)
        }  // first 在此释放

        let reopened = try SwiftDataWorkoutRepository.onDisk(url: url)
        let expected = [sessions[0], sessions[2], sessions[1]]  // date 300, 200, 100
        #expect(try await reopened.allSessions() == expected)
        for session in sessions {
            #expect(try await reopened.session(id: session.id) == session)
        }
    }

    @Test func overwriteAndDeleteAlsoSurviveReopening() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")

        let overwritten = simpleSession(id: uuid(1), date: date(100), reps: 1)
        let replacement = simpleSession(id: uuid(1), date: date(100), reps: 99)
        let deleted = simpleSession(id: uuid(2), date: date(200), reps: 2)
        let kept = simpleSession(id: uuid(3), date: date(300), reps: 3)
        do {
            let first = try SwiftDataWorkoutRepository.onDisk(url: url)
            try await first.save(overwritten)
            try await first.save(deleted)
            try await first.save(kept)
            try await first.save(replacement)
            try await first.delete(id: deleted.id)
        }

        let reopened = try SwiftDataWorkoutRepository.onDisk(url: url)
        #expect(try await reopened.allSessions() == [kept, replacement])
        #expect(try await reopened.storedRecordCounts() == StoredRecordCounts(sessions: 2, exercises: 2, sets: 2))
    }

    @Test func onDiskCreatesMissingParentDirectories() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("store.sqlite")
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))

        let repository = try SwiftDataWorkoutRepository.onDisk(url: url)
        try await repository.save(simpleSession(date: date(1), reps: 1))

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func inMemoryInstancesDoNotShareData() async throws {
        let a = try SwiftDataWorkoutRepository.inMemory()
        let b = try SwiftDataWorkoutRepository.inMemory()
        try await a.save(simpleSession(date: date(1), reps: 1))
        #expect(try await a.allSessions().count == 1)
        #expect(try await b.allSessions().isEmpty)
    }

    @Test func inMemoryDataDoesNotSurviveANewInstance() async throws {
        do {
            let first = try SwiftDataWorkoutRepository.inMemory()
            try await first.save(simpleSession(date: date(1), reps: 1))
        }
        let second = try SwiftDataWorkoutRepository.inMemory()
        #expect(try await second.allSessions().isEmpty)
    }

    @Test func openingAnUnwritableLocationThrowsInsteadOfCrashing() async throws {
        // 父路径是一个普通文件，目录无法创建 → 应抛错（App 据此退回内存仓储）。
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blocker)

        #expect(throws: (any Error).self) {
            _ = try SwiftDataWorkoutRepository.onDisk(url: blocker.appendingPathComponent("store.sqlite"))
        }
    }
}
