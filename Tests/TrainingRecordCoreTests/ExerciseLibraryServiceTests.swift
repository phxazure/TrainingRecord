import Foundation
import Testing
@testable import TrainingRecordCore

// MARK: - 辅助

private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))!
}

private func day(_ n: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(n) * 86_400)
}

private func entry(_ name: String, id: UUID? = nil, _ sets: [(Double, Int)] = [(100, 5)]) -> ExerciseEntry {
    ExerciseEntry(name: name, sets: sets.map { SetEntry(weight: $0.0, reps: $0.1)! }, exerciseID: id)!
}

private func session(_ n: Int, day d: Int, _ entries: [ExerciseEntry]) -> WorkoutSession {
    WorkoutSession(id: uuid(1000 + n), date: day(d), exercises: entries)
}

private func definition(_ n: Int, _ name: String, _ part: String = "") -> ExerciseDefinition {
    ExerciseDefinition(id: uuid(n), name: name, bodyPart: part)!
}

/// 前几次保存按序号失败的训练仓储，用来验证「中途出错、再调一次能补完」。
private actor FlakyWorkoutRepository: ConditionalSessionUpdating {
    struct Boom: Error, Equatable {}

    private let base: InMemoryWorkoutRepository
    private var calls = 0
    private var failingCalls: Set<Int>

    init(sessions: [WorkoutSession], failingSaveCalls: Set<Int>) {
        base = InMemoryWorkoutRepository(sessions: sessions)
        failingCalls = failingSaveCalls
    }

    func save(_ session: WorkoutSession) async throws {
        calls += 1
        if failingCalls.contains(calls) { throw Boom() }
        try await base.save(session)
    }

    /// 与 save 共用计数：第 N 次「写」（save 或 updateExisting）按序号失败。
    func updateExisting(id: UUID, _ transform: @Sendable (WorkoutSession) -> WorkoutSession?) async throws -> Bool {
        calls += 1
        if failingCalls.contains(calls) { throw Boom() }
        return try await base.updateExisting(id: id, transform)
    }

    func session(id: UUID) async throws -> WorkoutSession? { try await base.session(id: id) }
    func allSessions() async throws -> [WorkoutSession] { try await base.allSessions() }
    func delete(id: UUID) async throws { try await base.delete(id: id) }
    func saveCalls() -> Int { calls }
}

/// 第 N 次 save 或 delete 失败的动作库仓储。
private actor FlakyLibraryRepository: ExerciseLibraryRepository {
    struct Boom: Error, Equatable {}

    private let base: InMemoryExerciseLibraryRepository
    private var saveCalls = 0
    private var failingSaves: Set<Int>
    private var failDeletes: Bool

    init(items: [ExerciseDefinition], failingSaveCalls: Set<Int> = [], failDeletes: Bool = false) async {
        let seeded = InMemoryExerciseLibraryRepository()
        for item in items { try? await seeded.save(item) }
        base = seeded
        failingSaves = failingSaveCalls
        self.failDeletes = failDeletes
    }

    func allExercises() async throws -> [ExerciseDefinition] { try await base.allExercises() }
    func exercise(id: UUID) async throws -> ExerciseDefinition? { try await base.exercise(id: id) }

    func save(_ exercise: ExerciseDefinition) async throws {
        saveCalls += 1
        if failingSaves.contains(saveCalls) { throw Boom() }
        try await base.save(exercise)
    }

    func delete(id: UUID) async throws {
        if failDeletes { throw Boom() }
        try await base.delete(id: id)
    }

    func heal() { failingSaves = []; failDeletes = false }
}

private struct Fixture {
    let library: InMemoryExerciseLibraryRepository
    let workouts: InMemoryWorkoutRepository
    let service: ExerciseLibraryService

    init(library items: [ExerciseDefinition] = [], sessions: [WorkoutSession] = []) async throws {
        library = InMemoryExerciseLibraryRepository()
        for item in items { try await library.save(item) }
        workouts = InMemoryWorkoutRepository(sessions: sessions)
        service = ExerciseLibraryService(library: library, workouts: workouts)
    }
}

// MARK: - add / update / delete

@Suite struct ExerciseLibraryServiceCrudTests {
    @Test func addTrimsAndDefaultsBodyPart() async throws {
        let fixture = try await Fixture()
        let added = try await fixture.service.add(name: "  卧推 ", bodyPart: "  ", photoFileName: "p.jpg")
        #expect(added.name == "卧推")
        #expect(added.bodyPart == "未分类")
        #expect(added.photoFileName == "p.jpg")
        #expect(try await fixture.library.exercise(id: added.id) == added)
    }

    @Test(arguments: ["", "   ", "\n"])
    func addEmptyNameThrowsInvalidName(name: String) async throws {
        let fixture = try await Fixture()
        await #expect(throws: ExerciseLibraryError.invalidName) {
            try await fixture.service.add(name: name, bodyPart: "胸", photoFileName: nil)
        }
        #expect(try await fixture.library.allExercises().isEmpty)
    }

    @Test(arguments: ["Bench", "bench", "  BENCH  ", "bEnCh\n"])
    func addDuplicateNameThrowsRegardlessOfCaseAndWhitespace(name: String) async throws {
        let fixture = try await Fixture(library: [definition(1, "Bench")])
        await #expect(throws: ExerciseLibraryError.duplicateName) {
            try await fixture.service.add(name: name, bodyPart: "胸", photoFileName: nil)
        }
        #expect(try await fixture.library.allExercises().count == 1)
    }

    @Test func updateRenameRewritesAllLinkedHistoryEntriesOnly() async throws {
        let bench = uuid(1), squat = uuid(2)
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 10)]), entry("深蹲", id: squat, [(100, 5)])]),
            session(2, day: 2, [entry("卧推", id: bench, [(65, 8)]), entry("卧推", [(1, 1)])]),  // 第二条没有 id
            session(3, day: 3, [entry("深蹲", id: squat)]),
        ]
        let fixture = try await Fixture(library: [definition(1, "卧推", "胸"), definition(2, "深蹲", "腿")], sessions: sessions)

        let updated = try await fixture.service.update(id: bench, name: " 杠铃卧推 ", bodyPart: "胸", photoFileName: nil)

        #expect(updated.name == "杠铃卧推")
        #expect(try await fixture.library.exercise(id: bench)?.name == "杠铃卧推")
        let after = try await fixture.workouts.allSessions()
        let byID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        #expect(byID[uuid(1001)]?.exercises == [entry("杠铃卧推", id: bench, [(60, 10)]), entry("深蹲", id: squat, [(100, 5)])])
        #expect(byID[uuid(1002)]?.exercises == [entry("杠铃卧推", id: bench, [(65, 8)]), entry("卧推", [(1, 1)])])
        #expect(byID[uuid(1003)] == sessions[2])
        #expect(after.count == 3)
        #expect(after.map(\.date) == sessions.reversed().map(\.date))
    }

    @Test func renameKeepsTrendIdenticalUnderNewName() async throws {
        let bench = uuid(1)
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 10), (65, 8)])]),
            session(2, day: 8, [entry("卧推", id: bench, [(70, 6)])]),
            session(3, day: 15, [entry("深蹲", id: uuid(2)), entry("卧推", id: bench, [(72.5, 5)])]),
        ]
        let fixture = try await Fixture(library: [definition(1, "卧推", "胸")], sessions: sessions)
        let before = trend(for: "卧推", in: try await fixture.workouts.allSessions())
        #expect(before.count == 3)

        _ = try await fixture.service.update(id: bench, name: "杠铃卧推", bodyPart: "胸", photoFileName: nil)

        let all = try await fixture.workouts.allSessions()
        #expect(trend(for: "杠铃卧推", in: all) == before)
        #expect(trend(for: "卧推", in: all).isEmpty)
    }

    @Test func updateToAnotherExercisesNameThrowsAndChangesNothing() async throws {
        let bench = uuid(1)
        let sessions = [session(1, day: 1, [entry("卧推", id: bench), entry("Squat", id: uuid(2))])]
        let fixture = try await Fixture(library: [definition(1, "卧推", "胸"), definition(2, "Squat", "腿")], sessions: sessions)

        for name in ["Squat", "  squat ", "SQUAT"] {
            await #expect(throws: ExerciseLibraryError.duplicateName) {
                try await fixture.service.update(id: bench, name: name, bodyPart: "背", photoFileName: "x.jpg")
            }
        }
        #expect(try await fixture.library.exercise(id: bench) == definition(1, "卧推", "胸"))
        #expect(try await fixture.workouts.allSessions() == sessions)
    }

    @Test func updateAllowsCaseOnlyRenameAndBodyPartAndPhotoChanges() async throws {
        let bench = uuid(1)
        let sessions = [session(1, day: 1, [entry("bench", id: bench)])]
        let fixture = try await Fixture(library: [definition(1, "bench", "胸")], sessions: sessions)

        let caseOnly = try await fixture.service.update(id: bench, name: "Bench", bodyPart: "胸", photoFileName: nil)
        #expect(caseOnly.name == "Bench")
        #expect(try await fixture.workouts.allSessions().first?.exercises.first?.name == "Bench")

        let moved = try await fixture.service.update(id: bench, name: "Bench", bodyPart: "肩", photoFileName: "b.jpg")
        #expect(moved.bodyPart == "肩")
        #expect(moved.photoFileName == "b.jpg")
        #expect(try await fixture.library.exercise(id: bench) == moved)
        #expect(try await fixture.workouts.allSessions().first?.exercises.first?.name == "Bench")
    }

    @Test func updateNotFoundAndInvalidName() async throws {
        let fixture = try await Fixture(library: [definition(1, "A")])
        await #expect(throws: ExerciseLibraryError.notFound) {
            try await fixture.service.update(id: uuid(99), name: "B", bodyPart: "", photoFileName: nil)
        }
        await #expect(throws: ExerciseLibraryError.invalidName) {
            try await fixture.service.update(id: uuid(1), name: "  ", bodyPart: "", photoFileName: nil)
        }
        #expect(try await fixture.library.exercise(id: uuid(1)) == definition(1, "A"))
    }

    @Test func updateRepairsMissedHistoryEntriesWhenNameIsUnchanged() async throws {
        // 库里已是新名字、历史里还有旧名字（上次改名中途失败后的状态）：同名再调一次要补完。
        let bench = uuid(1)
        let sessions = [session(1, day: 1, [entry("卧推", id: bench)])]
        let fixture = try await Fixture(library: [definition(1, "杠铃卧推", "胸")], sessions: sessions)
        _ = try await fixture.service.update(id: bench, name: "杠铃卧推", bodyPart: "胸", photoFileName: nil)
        #expect(try await fixture.workouts.allSessions().first?.exercises.first?.name == "杠铃卧推")
    }

    @Test func deleteUnusedRemovesIt() async throws {
        let fixture = try await Fixture(
            library: [definition(1, "A"), definition(2, "B")],
            sessions: [session(1, day: 1, [entry("B", id: uuid(2))])]
        )
        try await fixture.service.delete(id: uuid(1))
        #expect(try await fixture.library.allExercises().map(\.id) == [uuid(2)])
    }

    @Test func deleteInUseThrowsWithSessionCountAndDeletesNothing() async throws {
        let id = uuid(1)
        let sessions = [
            session(1, day: 1, [entry("A", id: id), entry("A", id: id)]),  // 同场两条只算一场
            session(2, day: 2, [entry("A", id: id)]),
            session(3, day: 3, [entry("A")]),  // 没有 id，不算引用
        ]
        let fixture = try await Fixture(library: [definition(1, "A")], sessions: sessions)
        await #expect(throws: ExerciseLibraryError.inUse(sessionCount: 2)) {
            try await fixture.service.delete(id: id)
        }
        #expect(try await fixture.library.exercise(id: id) != nil)
        #expect(try await fixture.workouts.allSessions().count == 3)
    }

    @Test func deleteMissingIsSilent() async throws {
        let fixture = try await Fixture(library: [definition(1, "A")])
        try await fixture.service.delete(id: uuid(99))
        #expect(try await fixture.library.allExercises().count == 1)
    }
}

// MARK: - 合并

@Suite struct ExerciseLibraryServiceMergeTests {
    private let source = uuid(1), target = uuid(2)

    @Test func rewritesSourceEntriesToTargetAndDeletesSource() async throws {
        let sessions = [
            session(1, day: 1, [entry("Bench", id: source, [(60, 10)])]),
            session(2, day: 2, [entry("Flat Bench", id: target, [(70, 5)])]),
            session(3, day: 3, [entry("Row", id: uuid(3))]),
        ]
        let fixture = try await Fixture(
            library: [definition(1, "Bench", "胸"), definition(2, "Flat Bench", "胸"), definition(3, "Row", "背")],
            sessions: sessions
        )

        try await fixture.service.merge(sourceID: source, into: target)

        let after = Dictionary(uniqueKeysWithValues: try await fixture.workouts.allSessions().map { ($0.id, $0) })
        #expect(after[uuid(1001)]?.exercises == [entry("Flat Bench", id: target, [(60, 10)])])
        #expect(after[uuid(1002)] == sessions[1])
        #expect(after[uuid(1003)] == sessions[2])
        #expect(try await fixture.library.exercise(id: source) == nil)
        #expect(try await fixture.library.exercise(id: target) == definition(2, "Flat Bench", "胸"))
    }

    @Test func sameSessionBothPresentMergesIntoOneAtFirstPositionWithSetsInOrder() async throws {
        let sessions = [
            session(1, day: 1, [
                entry("Row", id: uuid(3), [(50, 10)]),
                entry("Flat Bench", id: target, [(70, 5), (72.5, 3)]),  // 先出现
                entry("Squat", id: uuid(4), [(100, 5)]),
                entry("Bench", id: source, [(60, 10)]),  // 后出现
            ])
        ]
        let fixture = try await Fixture(
            library: [definition(1, "Bench"), definition(2, "Flat Bench"), definition(3, "Row"), definition(4, "Squat")],
            sessions: sessions
        )

        try await fixture.service.merge(sourceID: source, into: target)

        let merged = try #require(try await fixture.workouts.allSessions().first)
        #expect(merged.exercises == [
            entry("Row", id: uuid(3), [(50, 10)]),
            entry("Flat Bench", id: target, [(70, 5), (72.5, 3), (60, 10)]),
            entry("Squat", id: uuid(4), [(100, 5)]),
        ])
    }

    @Test func sourceAppearingFirstTakesTheFirstPositionAndTargetNameAndId() async throws {
        let sessions = [
            session(1, day: 1, [
                entry("Bench", id: source, [(60, 10)]),
                entry("Row", id: uuid(3)),
                entry("Flat Bench", id: target, [(70, 5)]),
            ])
        ]
        let fixture = try await Fixture(
            library: [definition(1, "Bench"), definition(2, "Flat Bench"), definition(3, "Row")],
            sessions: sessions
        )
        try await fixture.service.merge(sourceID: source, into: target)
        let merged = try #require(try await fixture.workouts.allSessions().first)
        #expect(merged.exercises == [
            entry("Flat Bench", id: target, [(60, 10), (70, 5)]),
            entry("Row", id: uuid(3)),
        ])
    }

    @Test func trendAfterMergeCombinesBothNames() async throws {
        let sessions = [
            session(1, day: 1, [entry("Bench", id: source, [(60, 10)])]),
            session(2, day: 8, [entry("Flat Bench", id: target, [(70, 5)])]),
        ]
        let fixture = try await Fixture(library: [definition(1, "Bench"), definition(2, "Flat Bench")], sessions: sessions)
        try await fixture.service.merge(sourceID: source, into: target)
        let all = try await fixture.workouts.allSessions()
        #expect(trend(for: "Flat Bench", in: all).count == 2)
        #expect(trend(for: "Bench", in: all).isEmpty)
    }

    @Test func sourceEqualsTargetDoesNothing() async throws {
        let sessions = [session(1, day: 1, [entry("Bench", id: source), entry("Bench", id: source)])]
        let fixture = try await Fixture(library: [definition(1, "Bench")], sessions: sessions)
        try await fixture.service.merge(sourceID: source, into: source)
        #expect(try await fixture.library.exercise(id: source) != nil)
        #expect(try await fixture.workouts.allSessions() == sessions)
    }

    @Test func missingSourceOrTargetThrowsNotFoundAndChangesNothing() async throws {
        let sessions = [session(1, day: 1, [entry("Bench", id: source)])]
        let fixture = try await Fixture(library: [definition(1, "Bench")], sessions: sessions)
        await #expect(throws: ExerciseLibraryError.notFound) {
            try await fixture.service.merge(sourceID: source, into: uuid(99))
        }
        await #expect(throws: ExerciseLibraryError.notFound) {
            try await fixture.service.merge(sourceID: uuid(99), into: source)
        }
        #expect(try await fixture.workouts.allSessions() == sessions)
        #expect(try await fixture.library.exercise(id: source) != nil)
    }

    @Test func unrelatedSessionsAreNotRewritten() async throws {
        let sessions = [
            session(1, day: 1, [entry("Bench", id: source)]),
            session(2, day: 2, [entry("Row", id: uuid(3)), entry("Row", id: uuid(3))]),
        ]
        let workouts = FlakyWorkoutRepository(sessions: sessions, failingSaveCalls: [])
        let library = InMemoryExerciseLibraryRepository()
        for item in [definition(1, "Bench"), definition(2, "Flat Bench"), definition(3, "Row")] { try await library.save(item) }
        let service = ExerciseLibraryService(library: library, workouts: workouts)
        try await service.merge(sourceID: source, into: target)
        #expect(await workouts.saveCalls() == 1)
    }
}

// MARK: - 中途失败后补完（幂等）

@Suite struct ExerciseLibraryServiceRetryTests {
    @Test func renameFailingMidwayThrowsAndSameCallCompletesIt() async throws {
        let bench = uuid(1)
        let sessions = (1...4).map { session($0, day: $0, [entry("卧推", id: bench, [(60, $0)])]) }
        let workouts = FlakyWorkoutRepository(sessions: sessions, failingSaveCalls: [2])
        let library = InMemoryExerciseLibraryRepository()
        try await library.save(definition(1, "卧推", "胸"))
        let service = ExerciseLibraryService(library: library, workouts: workouts)

        await #expect(throws: FlakyWorkoutRepository.Boom.self) {
            try await service.update(id: bench, name: "杠铃卧推", bodyPart: "胸", photoFileName: nil)
        }
        let partial = try await workouts.allSessions().flatMap(\.exercises).map(\.name)
        #expect(partial.contains("卧推") && partial.contains("杠铃卧推"), "中途失败应只改了一部分: \(partial)")

        let updated = try await service.update(id: bench, name: "杠铃卧推", bodyPart: "胸", photoFileName: nil)

        #expect(updated.name == "杠铃卧推")
        #expect(try await library.exercise(id: bench)?.name == "杠铃卧推")
        let names = try await workouts.allSessions().flatMap(\.exercises).map(\.name)
        #expect(names == Array(repeating: "杠铃卧推", count: 4))
        // 组数据没有被重复或丢失。
        #expect(try await workouts.allSessions().flatMap(\.exercises).flatMap(\.sets).map(\.reps).sorted() == [1, 2, 3, 4])
    }

    @Test func renameOnlyWritesSessionsThatActuallyChange() async throws {
        let bench = uuid(1)
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench)]),
            session(2, day: 2, [entry("深蹲", id: uuid(2))]),
            session(3, day: 3, [entry("卧推")]),  // 没有 id，不属于这个动作
        ]
        let workouts = FlakyWorkoutRepository(sessions: sessions, failingSaveCalls: [])
        let library = InMemoryExerciseLibraryRepository()
        try await library.save(definition(1, "卧推"))
        let service = ExerciseLibraryService(library: library, workouts: workouts)
        _ = try await service.update(id: bench, name: "杠铃卧推", bodyPart: "", photoFileName: nil)
        #expect(await workouts.saveCalls() == 1)
    }

    @Test func renameLibrarySaveFailingThrowsAndRetryCompletes() async throws {
        let bench = uuid(1)
        let sessions = [session(1, day: 1, [entry("卧推", id: bench)])]
        let library = await FlakyLibraryRepository(items: [definition(1, "卧推", "胸")], failingSaveCalls: [1])
        let workouts = InMemoryWorkoutRepository(sessions: sessions)
        let service = ExerciseLibraryService(library: library, workouts: workouts)

        await #expect(throws: FlakyLibraryRepository.Boom.self) {
            try await service.update(id: bench, name: "杠铃卧推", bodyPart: "胸", photoFileName: nil)
        }
        _ = try await service.update(id: bench, name: "杠铃卧推", bodyPart: "胸", photoFileName: nil)
        #expect(try await library.exercise(id: bench)?.name == "杠铃卧推")
        #expect(try await workouts.allSessions().first?.exercises.first?.name == "杠铃卧推")
    }

    @Test func mergeFailingMidwayThrowsAndSameCallCompletesIt() async throws {
        let source = uuid(1), target = uuid(2)
        let sessions = [
            session(1, day: 1, [entry("Bench", id: source, [(60, 10)])]),
            session(2, day: 2, [entry("Bench", id: source, [(62, 8)]), entry("Flat Bench", id: target, [(70, 5)])]),
            session(3, day: 3, [entry("Bench", id: source, [(64, 6)])]),
        ]
        let workouts = FlakyWorkoutRepository(sessions: sessions, failingSaveCalls: [2])
        let library = InMemoryExerciseLibraryRepository()
        try await library.save(definition(1, "Bench"))
        try await library.save(definition(2, "Flat Bench"))
        let service = ExerciseLibraryService(library: library, workouts: workouts)

        await #expect(throws: FlakyWorkoutRepository.Boom.self) {
            try await service.merge(sourceID: source, into: target)
        }
        #expect(try await library.exercise(id: source) != nil, "合并没做完时不能删 source")

        try await service.merge(sourceID: source, into: target)

        #expect(try await library.exercise(id: source) == nil)
        let all = try await workouts.allSessions()
        #expect(all.flatMap(\.exercises).allSatisfy { $0.exerciseID == target && $0.name == "Flat Bench" })
        #expect(all.map { $0.exercises.count } == [1, 1, 1])
        #expect(all.flatMap(\.exercises).flatMap(\.sets).map(\.reps).sorted() == [5, 6, 8, 10])
    }

    @Test func mergeSourceDeleteFailingKeepsSourceAndRetryDeletesIt() async throws {
        let source = uuid(1), target = uuid(2)
        let sessions = [session(1, day: 1, [entry("Bench", id: source)])]
        let library = await FlakyLibraryRepository(
            items: [definition(1, "Bench"), definition(2, "Flat Bench")],
            failDeletes: true
        )
        let workouts = InMemoryWorkoutRepository(sessions: sessions)
        let service = ExerciseLibraryService(library: library, workouts: workouts)
        await #expect(throws: FlakyLibraryRepository.Boom.self) {
            try await service.merge(sourceID: source, into: target)
        }
        await library.heal()
        try await service.merge(sourceID: source, into: target)
        #expect(try await library.exercise(id: source) == nil)
        #expect(try await workouts.allSessions().first?.exercises.first?.exerciseID == target)
    }

    @Test func backfillFailingMidwayThenRerunCreatesNoDuplicates() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推"), entry("深蹲")]),
            session(2, day: 2, [entry("硬拉")]),
            session(3, day: 3, [entry("卧推")]),
        ]
        let workouts = FlakyWorkoutRepository(sessions: sessions, failingSaveCalls: [2])
        let library = InMemoryExerciseLibraryRepository()
        let service = ExerciseLibraryService(library: library, workouts: workouts)

        await #expect(throws: FlakyWorkoutRepository.Boom.self) { try await service.backfill() }
        _ = try await service.backfill()

        let names = try await library.allExercises().map(\.name).sorted()
        #expect(names == ["卧推", "深蹲", "硬拉"])
        let all = try await workouts.allSessions()
        #expect(all.flatMap(\.exercises).allSatisfy { $0.exerciseID != nil })
        #expect(try await service.backfill() == 0)
    }
}

// MARK: - 回填

@Suite struct ExerciseLibraryServiceBackfillTests {
    @Test func linksEntriesToNewUncategorizedLibraryItemsAndChangesNothingElse() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", [(60, 10), (62.5, 8)]), entry("深蹲", [(100, 5)])]),
            session(2, day: 2, [entry("硬拉", [(120, 5)])]),
        ]
        let fixture = try await Fixture(sessions: sessions)

        let created = try await fixture.service.backfill()

        #expect(created == 3)
        let library = try await fixture.library.allExercises()
        #expect(library.map(\.name).sorted() == ["卧推", "深蹲", "硬拉"])
        #expect(library.allSatisfy { $0.bodyPart == "未分类" && $0.photoFileName == nil })

        let after = try await fixture.workouts.allSessions()
        #expect(after.count == 2)
        let idByName = Dictionary(uniqueKeysWithValues: library.map { ($0.name, $0.id) })
        for (old, new) in zip(sessions.sorted { $0.date > $1.date }, after) {
            #expect(new.id == old.id)
            #expect(new.date == old.date)
            #expect(new.exercises.map(\.name) == old.exercises.map(\.name))
            #expect(new.exercises.map(\.sets) == old.exercises.map(\.sets))
            #expect(new.exercises.map(\.exerciseID) == old.exercises.map { idByName[$0.name] })
        }
    }

    @Test func isIdempotent() async throws {
        let fixture = try await Fixture(sessions: [session(1, day: 1, [entry("卧推"), entry("深蹲")])])
        _ = try await fixture.service.backfill()
        let sessionsAfterFirst = try await fixture.workouts.allSessions()
        let libraryAfterFirst = try await fixture.library.allExercises()

        #expect(try await fixture.service.backfill() == 0)
        #expect(try await fixture.service.backfill() == 0)

        #expect(try await fixture.workouts.allSessions() == sessionsAfterFirst)
        #expect(try await fixture.library.allExercises() == libraryAfterFirst)
    }

    @Test func matchesExistingLibraryItemsByTrimmedCaseInsensitiveNameAndKeepsEntryName() async throws {
        let sessions = [
            session(1, day: 1, [entry("bench press", [(60, 10)])]),
            session(2, day: 2, [entry("BENCH PRESS", [(65, 8)])]),
        ]
        let fixture = try await Fixture(library: [definition(1, "Bench Press", "胸")], sessions: sessions)

        let created = try await fixture.service.backfill()

        #expect(created == 0)
        #expect(try await fixture.library.allExercises() == [definition(1, "Bench Press", "胸")])
        let after = try await fixture.workouts.allSessions()
        #expect(after.flatMap(\.exercises).map(\.exerciseID) == [uuid(1), uuid(1)])
        // 条目自己的名字不改（只增加 id）。
        #expect(Set(after.flatMap(\.exercises).map(\.name)) == ["bench press", "BENCH PRESS"])
    }

    @Test func differentCasingsOfNewNamesShareOneLibraryItemUsingMostRecentSpelling() async throws {
        let sessions = [
            session(1, day: 1, [entry("pull-up")]),
            session(2, day: 5, [entry("Pull-Up")]),
        ]
        let fixture = try await Fixture(sessions: sessions)
        #expect(try await fixture.service.backfill() == 1)
        #expect(try await fixture.library.allExercises().map(\.name) == ["Pull-Up"])
    }

    @Test func leavesEntriesThatAlreadyHaveAnIdUntouched() async throws {
        let sessions = [session(1, day: 1, [entry("旧名字", id: uuid(7)), entry("新动作")])]
        let fixture = try await Fixture(library: [definition(7, "现名字")], sessions: sessions)
        #expect(try await fixture.service.backfill() == 1)
        let first = try #require(try await fixture.workouts.allSessions().first?.exercises.first)
        #expect(first.exerciseID == uuid(7))
        #expect(first.name == "旧名字")
    }

    @Test func emptyHistoryCreatesNothing() async throws {
        let fixture = try await Fixture()
        #expect(try await fixture.service.backfill() == 0)
        #expect(try await fixture.library.allExercises().isEmpty)
    }

    @Test func doesNotRewriteSessionsThatNeedNoChange() async throws {
        let sessions = [session(1, day: 1, [entry("A", id: uuid(1))])]
        let workouts = FlakyWorkoutRepository(sessions: sessions, failingSaveCalls: [])
        let library = InMemoryExerciseLibraryRepository()
        try await library.save(definition(1, "A"))
        let service = ExerciseLibraryService(library: library, workouts: workouts)
        #expect(try await service.backfill() == 0)
        #expect(await workouts.saveCalls() == 0)
    }
}

// MARK: - 分组

@Suite struct ExerciseLibraryServiceGroupingTests {
    @Test func groupsByBodyPartSortedWithUncategorizedLast() async throws {
        let fixture = try await Fixture(library: [
            definition(1, "Squat", "Legs"), definition(2, "Mystery B", ""), definition(3, "Curl", "Arms"),
            definition(4, "Leg Press", "Legs"), definition(5, "Mystery A", "未分类"), definition(6, "Bench 10", "Chest"),
            definition(7, "Bench 2", "Chest"),
        ])
        let groups = try await fixture.service.grouped()
        #expect(groups.map(\.bodyPart) == ["Arms", "Chest", "Legs", "未分类"])
        #expect(groups.map { $0.exercises.map(\.name) } == [
            ["Curl"], ["Bench 2", "Bench 10"], ["Leg Press", "Squat"], ["Mystery A", "Mystery B"],
        ])
    }

    @Test func emptyLibraryGivesNoGroups() async throws {
        let fixture = try await Fixture()
        #expect(try await fixture.service.grouped().isEmpty)
    }
}

// MARK: - 上次成绩 / 最近动作 / 复制上次训练

@Suite struct ExerciseLibraryServiceHistoryQueriesTests {
    private let bench = uuid(1), squat = uuid(2), row = uuid(3)

    private var library: [ExerciseDefinition] {
        [definition(1, "卧推", "胸"), definition(2, "深蹲", "腿"), definition(3, "划船", "背")]
    }

    @Test func lastPerformanceTakesMostRecentSessionAndBestSet() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(100, 1)])]),
            session(2, day: 5, [entry("卧推", id: bench, [(60, 10), (80, 5), (80, 8), (70, 12)])]),
            session(3, day: 3, [entry("卧推", id: bench, [(90, 3)])]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        let last = try #require(try await fixture.service.lastPerformance(exerciseID: bench, before: nil))
        #expect(last.date == day(5))
        #expect(last.bestSet == SetEntry(weight: 80, reps: 8)!)  // 同重量取次数多
    }

    @Test func lastPerformanceBeforeIsExclusive() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 10)])]),
            session(2, day: 5, [entry("卧推", id: bench, [(70, 8)])]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.lastPerformance(exerciseID: bench, before: day(5))?.date == day(1))
        #expect(try await fixture.service.lastPerformance(exerciseID: bench, before: day(6))?.date == day(5))
        #expect(try await fixture.service.lastPerformance(exerciseID: bench, before: day(1)) == nil)
    }

    @Test func lastPerformanceSkipsSessionsWithoutThatExercise() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 10)])]),
            session(2, day: 9, [entry("深蹲", id: squat)]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.lastPerformance(exerciseID: bench, before: nil)?.date == day(1))
        #expect(try await fixture.service.lastPerformance(exerciseID: row, before: nil) == nil)
    }

    @Test func lastPerformanceUsesExerciseIdNotName() async throws {
        let sessions = [session(1, day: 1, [entry("卧推", [(60, 10)])])]  // 没有 id
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.lastPerformance(exerciseID: bench, before: nil) == nil)
    }

    @Test func lastPerformanceSkipsSessionWhereExerciseHasNoSets() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench, [(60, 10)])]),
            session(2, day: 2, [entry("卧推", id: bench, [])]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.lastPerformance(exerciseID: bench, before: nil)?.date == day(1))
    }

    @Test func lastPerformanceCombinesSetsOfDuplicateEntriesInOneSession() async throws {
        let sessions = [session(1, day: 1, [entry("卧推", id: bench, [(60, 10)]), entry("卧推", id: bench, [(90, 3)])])]
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.lastPerformance(exerciseID: bench, before: nil)?.bestSet == SetEntry(weight: 90, reps: 3)!)
    }

    @Test func recentExercisesOrderedByLastUsedDedupedAndLimited() async throws {
        let sessions = [
            session(1, day: 1, [entry("划船", id: row)]),
            session(2, day: 2, [entry("卧推", id: bench), entry("深蹲", id: squat)]),
            session(3, day: 3, [entry("划船", id: row), entry("卧推", id: bench)]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.recentExercises(limit: 10).map(\.name) == ["划船", "卧推", "深蹲"])
        #expect(try await fixture.service.recentExercises(limit: 2).map(\.name) == ["划船", "卧推"])
        #expect(try await fixture.service.recentExercises(limit: 1).map(\.name) == ["划船"])
        #expect(try await fixture.service.recentExercises(limit: 0).isEmpty)
        #expect(try await fixture.service.recentExercises(limit: -3).isEmpty)
    }

    @Test func recentExercisesSkipsDeletedLibraryItemsWithoutCountingThem() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench)]),
            session(2, day: 2, [entry("已删除", id: uuid(99)), entry("无 id")]),
            session(3, day: 3, [entry("深蹲", id: squat)]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.recentExercises(limit: 2).map(\.name) == ["深蹲", "卧推"])
    }

    @Test func lastSessionTemplateIsNilWithoutSessions() async throws {
        let fixture = try await Fixture(library: library)
        #expect(try await fixture.service.lastSessionTemplate() == nil)
    }

    @Test func lastSessionTemplateMapsLatestSessionInOrderSkippingMissing() async throws {
        let sessions = [
            session(1, day: 1, [entry("划船", id: row)]),
            session(2, day: 4, [entry("深蹲", id: squat), entry("已删除", id: uuid(99)), entry("无 id"), entry("卧推", id: bench)]),
            session(3, day: 2, [entry("卧推", id: bench)]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        let template = try #require(try await fixture.service.lastSessionTemplate())
        #expect(template.date == day(4))
        #expect(template.exercises.map(\.name) == ["深蹲", "卧推"])
        #expect(template.exercises.map(\.id) == [squat, bench])
    }

    @Test func lastSessionTemplateIsNilWhenNoExerciseOfTheLatestSessionMapsToTheLibrary() async throws {
        let sessions = [
            session(1, day: 1, [entry("卧推", id: bench)]),  // 更早的一场能映射，但只看最近一场
            session(2, day: 2, [entry("已删除", id: uuid(99)), entry("无 id")]),
        ]
        let fixture = try await Fixture(library: library, sessions: sessions)
        #expect(try await fixture.service.lastSessionTemplate() == nil)
    }

    @Test func lastSessionTemplateUsesCurrentLibraryNames() async throws {
        let sessions = [session(1, day: 1, [entry("旧名", id: bench)])]
        let fixture = try await Fixture(library: [definition(1, "新名", "胸")], sessions: sessions)
        #expect(try await fixture.service.lastSessionTemplate()?.exercises.map(\.name) == ["新名"])
    }
}
