import Foundation
import Testing
@testable import TrainingRecordCore

// 「重写历史」与用户删除训练之间的竞态：服务按候选列表重写场次时，场次可能已被用户（HistoryViewModel）删掉。
// 重写必须是「仅当场次仍存在才更新」，绝不能把已删除的训练重新创建出来。

private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))!
}

private func entry(_ name: String, id: UUID? = nil) -> ExerciseEntry {
    ExerciseEntry(name: name, sets: [SetEntry(weight: 100, reps: 5)!], exerciseID: id)!
}

private func session(_ n: Int, _ entries: [ExerciseEntry]) -> WorkoutSession {
    WorkoutSession(id: uuid(1000 + n), date: Date(timeIntervalSince1970: TimeInterval(n) * 86_400), exercises: entries)
}

private func definition(_ n: Int, _ name: String) -> ExerciseDefinition {
    ExerciseDefinition(id: uuid(n), name: name, bodyPart: "")!
}

/// 「用户在重写提交前最后一刻删除了一场训练」的训练仓储。
/// 对 victim 的**第一次写操作**（`save` 或 `updateExisting`）转发给内部仓储之前，先把 victim 删掉——
/// 即候选枚举（allSessions）之后、重写提交之前的删除：
/// - 原子的「仅当仍存在才更新」→ 更新发现场次没了，什么都不写，victim 保持已删除；
/// - 「先读后存」（session(id:) 之后 save）→ 读成功、删除、save 作为 upsert 把 victim 重新创建出来。
private actor InterleavingWorkoutRepository: ConditionalSessionUpdating {
    private let inner: InMemoryWorkoutRepository
    private let victim: UUID
    private var pendingDelete = true
    private(set) var readCalls = 0
    private(set) var saveCalls = 0

    init(sessions: [WorkoutSession], victim: UUID) {
        inner = InMemoryWorkoutRepository(sessions: sessions)
        self.victim = victim
    }

    private func userDeletesVictimOnce(beforeWriting id: UUID) async throws {
        guard pendingDelete, id == victim else { return }
        pendingDelete = false
        try await inner.delete(id: victim)
    }

    func allSessions() async throws -> [WorkoutSession] { try await inner.allSessions() }

    func session(id: UUID) async throws -> WorkoutSession? {
        readCalls += 1
        return try await inner.session(id: id)
    }

    func save(_ session: WorkoutSession) async throws {
        saveCalls += 1
        try await userDeletesVictimOnce(beforeWriting: session.id)
        try await inner.save(session)
    }

    func delete(id: UUID) async throws { try await inner.delete(id: id) }

    func updateExisting(id: UUID, _ transform: @Sendable (WorkoutSession) -> WorkoutSession?) async throws -> Bool {
        try await userDeletesVictimOnce(beforeWriting: id)
        return try await inner.updateExisting(id: id, transform)
    }

    func remainingIDs() async throws -> Set<UUID> { Set(try await inner.allSessions().map(\.id)) }
}

@Suite struct ExerciseLibraryRaceTests {
    private let bench = uuid(1), flat = uuid(2)

    @Test func renameNeverResurrectsASessionDeletedBeforeTheRewriteCommits() async throws {
        let sessions = (1...3).map { session($0, [entry("卧推", id: bench)]) }
        let victim = sessions[1].id
        let workouts = InterleavingWorkoutRepository(sessions: sessions, victim: victim)
        let library = InMemoryExerciseLibraryRepository()
        try await library.save(definition(1, "卧推"))
        let service = ExerciseLibraryService(library: library, workouts: workouts)

        _ = try await service.update(id: bench, name: "杠铃卧推", bodyPart: "", photoFileName: nil)

        let remaining = try await workouts.remainingIDs()
        #expect(!remaining.contains(victim), "已删除的训练被改名重写写回来了")
        #expect(remaining.count == 2)
        #expect(await workouts.readCalls == 0, "重写不应该走「先读后存」")
        #expect(await workouts.saveCalls == 0)
    }

    @Test func mergeNeverResurrectsASessionDeletedBeforeTheRewriteCommits() async throws {
        let sessions = (1...3).map { session($0, [entry("Bench", id: bench), entry("Flat", id: flat)]) }
        let victim = sessions[0].id
        let workouts = InterleavingWorkoutRepository(sessions: sessions, victim: victim)
        let library = InMemoryExerciseLibraryRepository()
        try await library.save(definition(1, "Bench"))
        try await library.save(definition(2, "Flat"))
        let service = ExerciseLibraryService(library: library, workouts: workouts)

        try await service.merge(sourceID: bench, into: flat)

        let remaining = try await workouts.remainingIDs()
        #expect(!remaining.contains(victim), "已删除的训练被合并重写写回来了")
        #expect(remaining.count == 2)
        #expect(await workouts.readCalls == 0)
        #expect(await workouts.saveCalls == 0)
    }

    @Test func backfillNeverResurrectsASessionDeletedBeforeTheRewriteCommits() async throws {
        let sessions = (1...3).map { session($0, [entry("卧推")]) }
        let victim = sessions[2].id
        let workouts = InterleavingWorkoutRepository(sessions: sessions, victim: victim)
        let service = ExerciseLibraryService(library: InMemoryExerciseLibraryRepository(), workouts: workouts)

        _ = try await service.backfill()

        let remaining = try await workouts.remainingIDs()
        #expect(!remaining.contains(victim), "已删除的训练被回填写回来了")
        #expect(remaining.count == 2)
        #expect(await workouts.readCalls == 0)
        #expect(await workouts.saveCalls == 0)
    }

    @Test func concurrentUserDeletesAndServiceRewritesNeverLeaveDeletedSessionsBehind() async throws {
        let sessions = (1...40).map { session($0, [entry("卧推", id: bench)]) }
        let workouts = InMemoryWorkoutRepository(sessions: sessions)
        let library = InMemoryExerciseLibraryRepository()
        try await library.save(definition(1, "卧推"))
        let service = ExerciseLibraryService(library: library, workouts: workouts)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { _ = try await service.update(id: bench, name: "杠铃卧推", bodyPart: "", photoFileName: nil) }
            for s in sessions { group.addTask { try await workouts.delete(id: s.id) } }
            try await group.waitForAll()
        }
        #expect(try await workouts.allSessions().isEmpty)
    }

    @Test func updateExistingOnInMemoryRepositoryOnlyTouchesExistingSessions() async throws {
        let existing = session(1, [entry("A")])
        let repository = InMemoryWorkoutRepository(sessions: [existing])
        let replacement = session(1, [entry("B")])

        #expect(try await repository.updateExisting(id: existing.id) { _ in replacement } == true)
        #expect(try await repository.session(id: existing.id) == replacement)
        #expect(try await repository.updateExisting(id: existing.id) { _ in nil } == false)
        #expect(try await repository.session(id: existing.id) == replacement)
        #expect(try await repository.updateExisting(id: uuid(99)) { _ in replacement } == false)
        #expect(try await repository.session(id: uuid(99)) == nil)
        #expect(try await repository.allSessions().count == 1)
    }
}
