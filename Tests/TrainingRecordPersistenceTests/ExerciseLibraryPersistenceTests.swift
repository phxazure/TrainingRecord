import Foundation
import Testing
import TrainingRecordCore
@testable import TrainingRecordPersistence

// MARK: - 辅助

private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))!
}

private func makeTempDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("TrainingRecordLibraryTests-\(UUID().uuidString)", isDirectory: true)
}

private func make(_ name: String, _ part: String = "", id: UUID = UUID(), photo: String? = nil) -> ExerciseDefinition {
    ExerciseDefinition(id: id, name: name, bodyPart: part, photoFileName: photo)!
}

/// 同一组动作库仓储行为用例，对内存实现和两种 SwiftData 模式各跑一遍。
enum LibraryKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case coreInMemory
    case swiftDataInMemory
    case swiftDataOnDisk

    var testDescription: String { rawValue }
}

private func withLibrary<T>(
    _ kind: LibraryKind,
    _ body: (any ExerciseLibraryRepository) async throws -> T
) async throws -> T {
    let directory = makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    switch kind {
    case .coreInMemory:
        return try await body(InMemoryExerciseLibraryRepository())
    case .swiftDataInMemory:
        return try await body(try TrainingRecordStore.inMemory().library)
    case .swiftDataOnDisk:
        return try await body(try TrainingRecordStore.onDisk(url: directory.appendingPathComponent("store.sqlite")).library)
    }
}

private func entry(_ name: String, id: UUID? = nil, _ sets: [(Double, Int)] = [(100, 5)]) -> ExerciseEntry {
    ExerciseEntry(name: name, sets: sets.map { SetEntry(weight: $0.0, reps: $0.1)! }, exerciseID: id)!
}

// MARK: - 动作库仓储行为（内存 / SwiftData 一致）

@Suite struct ExerciseLibraryRepositoryBehaviourTests {
    @Test(arguments: LibraryKind.allCases)
    func emptyRepository(kind: LibraryKind) async throws {
        try await withLibrary(kind) { (library) async throws in
            #expect(try await library.allExercises().isEmpty)
            #expect(try await library.exercise(id: UUID()) == nil)
        }
    }

    @Test(arguments: LibraryKind.allCases)
    func saveThenReadBackIsEqual(kind: LibraryKind) async throws {
        try await withLibrary(kind) { (library) async throws in
            let withPhoto = make("卧推", "胸", id: uuid(1), photo: "a-b_1.jpg")
            let withoutPhoto = make("深蹲", "", id: uuid(2))
            try await library.save(withPhoto)
            try await library.save(withoutPhoto)
            #expect(try await library.exercise(id: uuid(1)) == withPhoto)
            #expect(try await library.exercise(id: uuid(2)) == withoutPhoto)
            #expect(try await library.exercise(id: uuid(2))?.bodyPart == "未分类")
            #expect(try await library.exercise(id: uuid(2))?.photoFileName == nil)
        }
    }

    @Test(arguments: LibraryKind.allCases)
    func saveWithSameIdOverwrites(kind: LibraryKind) async throws {
        try await withLibrary(kind) { (library) async throws in
            try await library.save(make("A", "胸", id: uuid(1), photo: "x.jpg"))
            let replacement = make("B", "背", id: uuid(1))
            try await library.save(replacement)
            #expect(try await library.allExercises() == [replacement])
        }
    }

    @Test(arguments: LibraryKind.allCases)
    func deleteRemovesTargetKeepsOthersAndMissingIsSilent(kind: LibraryKind) async throws {
        try await withLibrary(kind) { (library) async throws in
            let keep = make("Keep", id: uuid(1))
            try await library.save(keep)
            try await library.save(make("Drop", id: uuid(2)))
            try await library.delete(id: uuid(2))
            try await library.delete(id: uuid(99))
            #expect(try await library.allExercises() == [keep])
            #expect(try await library.exercise(id: uuid(2)) == nil)
        }
    }

    @Test(arguments: LibraryKind.allCases)
    func allExercisesSortedByBodyPartThenNameNumericAware(kind: LibraryKind) async throws {
        try await withLibrary(kind) { (library) async throws in
            // 乱序写入。
            for (name, part) in [("Fly", "Chest"), ("Bench 10", "Chest"), ("Curl", "Arms"), ("Bench 2", "Chest"), ("Row", "Back")] {
                try await library.save(make(name, part))
            }
            #expect(try await library.allExercises().map(\.name) == ["Curl", "Row", "Bench 2", "Bench 10", "Fly"])
        }
    }

    @Test(arguments: LibraryKind.allCases)
    func concurrentSavesDoNotLoseItems(kind: LibraryKind) async throws {
        try await withLibrary(kind) { (library) async throws in
            try await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<100 {
                    group.addTask { try await library.save(make("Item \(i)", id: uuid(i))) }
                }
                try await group.waitForAll()
            }
            #expect(try await library.allExercises().count == 100)
        }
    }
}

// MARK: - 动作 id 随训练一起读写

@Suite struct ExerciseIDRoundTripTests {
    @Test(arguments: [false, true])
    func exerciseIdSurvivesSaveAndReload(onDisk: Bool) async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = onDisk
            ? try TrainingRecordStore.onDisk(url: directory.appendingPathComponent("s.sqlite"))
            : try TrainingRecordStore.inMemory()
        let session = WorkoutSession(id: uuid(1), date: Date(timeIntervalSince1970: 100), exercises: [
            entry("卧推", id: uuid(7), [(60, 10), (62.5, 8)]),
            entry("自由输入", [(10, 10)]),
            entry("深蹲", id: uuid(8), [(100, 5)]),
        ])
        try await store.workouts.save(session)
        #expect(try await store.workouts.session(id: uuid(1)) == session)
        #expect(try await store.workouts.allSessions() == [session])
        #expect(try await store.workouts.session(id: uuid(1))?.exercises.map(\.exerciseID) == [uuid(7), nil, uuid(8)])
    }

    @Test func overwriteReplacesExerciseIds() async throws {
        let store = try TrainingRecordStore.inMemory()
        try await store.workouts.save(WorkoutSession(id: uuid(1), date: Date(timeIntervalSince1970: 1), exercises: [entry("A")]))
        let linked = WorkoutSession(id: uuid(1), date: Date(timeIntervalSince1970: 1), exercises: [entry("A", id: uuid(5))])
        try await store.workouts.save(linked)
        #expect(try await store.workouts.session(id: uuid(1)) == linked)
    }
}

// MARK: - 同一存储文件

@Suite struct TrainingRecordStoreTests {
    @Test func workoutsAndLibrarySurviveReopeningTheSameFile() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("nested/store.sqlite")
        let session = WorkoutSession(id: uuid(1), date: Date(timeIntervalSince1970: 500), exercises: [entry("卧推", id: uuid(7))])
        let bench = make("卧推", "胸", id: uuid(7), photo: "p.jpg")
        do {
            let store = try TrainingRecordStore.onDisk(url: url)
            try await store.workouts.save(session)
            try await store.library.save(bench)
        }
        let reopened = try TrainingRecordStore.onDisk(url: url)
        #expect(try await reopened.workouts.allSessions() == [session])
        #expect(try await reopened.library.allExercises() == [bench])
    }

    @Test func storeCreatedByTheCombinedFactoryIsStillReadableThroughTheWorkoutsOnlyFactory() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        let session = WorkoutSession(id: uuid(1), date: Date(timeIntervalSince1970: 500), exercises: [entry("卧推", id: uuid(7))])
        do {
            let store = try TrainingRecordStore.onDisk(url: url)
            try await store.workouts.save(session)
            try await store.library.save(make("卧推", id: uuid(7)))
        }
        let workoutsOnly = try SwiftDataWorkoutRepository.onDisk(url: url)
        #expect(try await workoutsOnly.allSessions() == [session])
    }

    @Test func inMemoryStoresAreIndependentAndShareOneContainerPerStore() async throws {
        let a = try TrainingRecordStore.inMemory()
        let b = try TrainingRecordStore.inMemory()
        try await a.library.save(make("A"))
        try await a.workouts.save(WorkoutSession(date: Date(timeIntervalSince1970: 1), exercises: [entry("A")]))
        #expect(try await b.library.allExercises().isEmpty)
        #expect(try await b.workouts.allSessions().isEmpty)
        #expect(try await a.library.allExercises().count == 1)
        #expect(try await a.workouts.allSessions().count == 1)
    }

    @Test func serviceRenameAndBackfillWorkEndToEndOnDiskAndPersist() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.sqlite")
        do {
            let store = try TrainingRecordStore.onDisk(url: url)
            try await store.workouts.save(WorkoutSession(id: uuid(1), date: Date(timeIntervalSince1970: 100), exercises: [entry("卧推", [(60, 8)])]))
            try await store.workouts.save(WorkoutSession(id: uuid(2), date: Date(timeIntervalSince1970: 200), exercises: [entry("卧推", [(65, 8)])]))
            let service = ExerciseLibraryService(library: store.library, workouts: store.workouts)
            #expect(try await service.backfill() == 1)
            let bench = try #require(try await store.library.allExercises().first)
            _ = try await service.update(id: bench.id, name: "杠铃卧推", bodyPart: "胸", photoFileName: nil)
        }
        let reopened = try TrainingRecordStore.onDisk(url: url)
        let sessions = try await reopened.workouts.allSessions()
        #expect(sessions.flatMap(\.exercises).map(\.name) == ["杠铃卧推", "杠铃卧推"])
        let library = try await reopened.library.allExercises()
        #expect(library.map(\.name) == ["杠铃卧推"])
        #expect(sessions.flatMap(\.exercises).map(\.exerciseID) == [library[0].id, library[0].id])
        #expect(trend(for: "杠铃卧推", in: sessions).count == 2)
        let service = ExerciseLibraryService(library: reopened.library, workouts: reopened.workouts)
        #expect(try await service.backfill() == 0)
    }
}

// MARK: - 旧版存储兼容（T006 代码 bd79293 生成的磁盘存储样本）

@Suite struct LegacyStoreMigrationTests {
    /// 样本里的数据；与 Fixtures/README.md 里的生成脚本一致。
    private static let s1 = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!,
        date: Date(timeIntervalSince1970: 1_700_000_000),
        exercises: [
            entry("卧推", [(60, 10), (62.5, 8), (65, 6)]),
            entry("深蹲", [(100, 5), (100, 5)]),
        ]
    )
    private static let s2 = WorkoutSession(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!,
        date: Date(timeIntervalSince1970: 1_700_600_000),
        exercises: [entry("硬拉", [(120, 5), (140, 3)])]
    )

    /// 把样本复制到临时目录再打开：迁移会改文件，不能动测试资源本身。
    private func copyOfLegacyStore() throws -> (url: URL, cleanup: URL) {
        let source = try #require(Bundle.module.url(forResource: "legacy-T006", withExtension: "store", subdirectory: "Fixtures"))
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("workouts.store")
        try FileManager.default.copyItem(at: source, to: target)
        return (target, directory)
    }

    @Test func fixtureHasTheDocumentedShapeBeforeAnyMigration() throws {
        let source = try #require(Bundle.module.url(forResource: "legacy-T006", withExtension: "store", subdirectory: "Fixtures"))
        let data = try Data(contentsOf: source)
        // SQLite 文件头。
        #expect(String(decoding: data.prefix(15), as: UTF8.self) == "SQLite format 3")
        // 旧存储里没有动作 id 的列，也没有动作库的表。
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("ZEXERCISEID"))
        #expect(!text.contains("ZEXERCISEDEFINITIONRECORD"))
        #expect(text.contains("ZEXERCISERECORD"))
    }

    @Test func newCodeOpensLegacyStoreAndReadsEverythingUnchanged() async throws {
        let (url, directory) = try copyOfLegacyStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try TrainingRecordStore.onDisk(url: url)

        #expect(try await store.workouts.allSessions() == [Self.s2, Self.s1])
        #expect(try await store.workouts.session(id: Self.s1.id) == Self.s1)
        #expect(try await store.workouts.allSessions().flatMap(\.exercises).allSatisfy { $0.exerciseID == nil })
        #expect(try await store.library.allExercises().isEmpty)
    }

    @Test func workoutsOnlyFactoryAlsoOpensLegacyStore() async throws {
        let (url, directory) = try copyOfLegacyStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workouts = try SwiftDataWorkoutRepository.onDisk(url: url)
        #expect(try await workouts.allSessions() == [Self.s2, Self.s1])
    }

    @Test func backfillLinksEveryEntryAndCreatesThreeUncategorizedItemsWithoutTouchingData() async throws {
        let (url, directory) = try copyOfLegacyStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrainingRecordStore.onDisk(url: url)
        let service = ExerciseLibraryService(library: store.library, workouts: store.workouts)

        #expect(try await service.backfill() == 3)

        let library = try await store.library.allExercises()
        #expect(library.map(\.name).sorted() == ["卧推", "深蹲", "硬拉"])
        #expect(library.allSatisfy { $0.bodyPart == "未分类" && $0.photoFileName == nil })
        let idByName = Dictionary(uniqueKeysWithValues: library.map { ($0.name, $0.id) })

        let after = try await store.workouts.allSessions()
        #expect(after.map(\.id) == [Self.s2.id, Self.s1.id])
        #expect(after.map(\.date) == [Self.s2.date, Self.s1.date])
        for (new, old) in zip(after, [Self.s2, Self.s1]) {
            #expect(new.exercises.map(\.name) == old.exercises.map(\.name))
            #expect(new.exercises.map(\.sets) == old.exercises.map(\.sets))
            #expect(new.exercises.map(\.exerciseID) == old.exercises.map { idByName[$0.name] })
        }
        #expect(after.flatMap(\.exercises).count == 3)
        // 没有产生多余的记录。
        let counts = try await store.workouts.storedRecordCounts()
        #expect(counts == StoredRecordCounts(sessions: 2, exercises: 3, sets: 7))
    }

    @Test func migrationAndBackfillPersistAcrossReopenAndRerunIsNoOp() async throws {
        let (url, directory) = try copyOfLegacyStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let afterFirst: [WorkoutSession]
        let libraryAfterFirst: [ExerciseDefinition]
        do {
            let store = try TrainingRecordStore.onDisk(url: url)
            let service = ExerciseLibraryService(library: store.library, workouts: store.workouts)
            #expect(try await service.backfill() == 3)
            afterFirst = try await store.workouts.allSessions()
            libraryAfterFirst = try await store.library.allExercises()
        }
        let reopened = try TrainingRecordStore.onDisk(url: url)
        #expect(try await reopened.workouts.allSessions() == afterFirst)
        #expect(try await reopened.library.allExercises() == libraryAfterFirst)
        let service = ExerciseLibraryService(library: reopened.library, workouts: reopened.workouts)
        #expect(try await service.backfill() == 0)
        #expect(try await reopened.workouts.allSessions() == afterFirst)
    }

    @Test func renameAfterMigrationKeepsTrendWorking() async throws {
        let (url, directory) = try copyOfLegacyStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TrainingRecordStore.onDisk(url: url)
        let service = ExerciseLibraryService(library: store.library, workouts: store.workouts)
        _ = try await service.backfill()
        let squat = try #require(try await store.library.allExercises().first { $0.name == "深蹲" })
        let before = trend(for: "深蹲", in: try await store.workouts.allSessions())
        _ = try await service.update(id: squat.id, name: "杠铃深蹲", bodyPart: "腿", photoFileName: nil)
        let all = try await store.workouts.allSessions()
        #expect(trend(for: "杠铃深蹲", in: all) == before)
        #expect(trend(for: "深蹲", in: all).isEmpty)
    }
}
