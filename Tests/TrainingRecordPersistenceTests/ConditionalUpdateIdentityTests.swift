import Foundation
import Testing
import TrainingRecordCore
@testable import TrainingRecordPersistence

// `updateExisting` 的约定：transform 返回的场次 id 必须等于被更新的 id。
// 不等时拒绝（返回 false）并且不改动任何数据——既不改原场次，也不创建新 id、不覆盖别的场次。
// 内存、SwiftData 内存、SwiftData 磁盘三种实现行为一致。

enum IdentityKind: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case inMemory
    case swiftDataInMemory
    case swiftDataOnDisk
    var testDescription: String { rawValue }
}

private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", n))!
}

private func make(_ n: Int, reps: Int) -> WorkoutSession {
    WorkoutSession(
        id: uuid(n),
        date: Date(timeIntervalSince1970: TimeInterval(n) * 100),
        exercises: [ExerciseEntry(name: "卧推", sets: [SetEntry(weight: 60, reps: reps)!])!]
    )
}

private func withRepository(
    _ kind: IdentityKind,
    _ body: (any ConditionalSessionUpdating) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConditionalUpdateIdentityTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    switch kind {
    case .inMemory:
        try await body(InMemoryWorkoutRepository())
    case .swiftDataInMemory:
        try await body(try TrainingRecordStore.inMemory().workouts)
    case .swiftDataOnDisk:
        try await body(try TrainingRecordStore.onDisk(url: directory.appendingPathComponent("store.sqlite")).workouts)
    }
}

@Suite struct ConditionalUpdateIdentityTests {
    @Test(arguments: IdentityKind.allCases)
    func transformReturningANewIdIsRejectedAndChangesNothing(kind: IdentityKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let original = make(1, reps: 5)
            let other = make(2, reps: 8)
            try await repository.save(original)
            try await repository.save(other)
            let newID = uuid(99)

            let written = try await repository.updateExisting(id: original.id) { current in
                WorkoutSession(id: newID, date: current.date, exercises: make(1, reps: 77).exercises)
            }

            #expect(written == false)
            #expect(try await repository.session(id: newID) == nil, "不应创建新 id 的场次")
            #expect(try await repository.session(id: original.id) == original, "原场次不应被改动或删除")
            #expect(try await repository.session(id: other.id) == other)
            #expect(try await repository.allSessions().count == 2)
        }
    }

    @Test(arguments: IdentityKind.allCases)
    func transformReturningAnotherExistingSessionsIdIsRejectedAndChangesNothing(kind: IdentityKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let original = make(1, reps: 5)
            let other = make(2, reps: 8)
            try await repository.save(original)
            try await repository.save(other)

            let written = try await repository.updateExisting(id: original.id) { _ in make(2, reps: 77) }

            #expect(written == false)
            #expect(try await repository.session(id: original.id) == original)
            #expect(try await repository.session(id: other.id) == other, "另一条记录不应被覆盖")
            #expect(try await repository.allSessions().count == 2)
        }
    }

    @Test(arguments: IdentityKind.allCases)
    func transformKeepingTheSameIdStillUpdates(kind: IdentityKind) async throws {
        try await withRepository(kind) { (repository) async throws in
            let original = make(1, reps: 5)
            try await repository.save(original)
            let changed = make(1, reps: 77)

            let written = try await repository.updateExisting(id: original.id) { _ in changed }

            #expect(written == true)
            #expect(try await repository.session(id: original.id) == changed)
            #expect(try await repository.allSessions().count == 1)
        }
    }
}
