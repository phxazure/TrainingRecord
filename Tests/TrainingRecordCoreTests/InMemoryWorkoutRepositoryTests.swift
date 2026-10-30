import Foundation
import Testing
@testable import TrainingRecordCore

private func fixedUUID(_ s: String) -> UUID {
    UUID(uuidString: s)!
}

private func session(id: UUID, date: Date, reps: Int) -> WorkoutSession {
    WorkoutSession(id: id, date: date, exercises: [ExerciseEntry(name: "卧推", sets: [SetEntry(weight: 100, reps: reps)!])!])
}

@Test func emptyRepository() async throws {
    let repo = InMemoryWorkoutRepository()
    #expect(try await repo.allSessions() == [])
    #expect(try await repo.session(id: UUID()) == nil)
}

@Test func saveThenFetchReturnsSameSession() async throws {
    let repo = InMemoryWorkoutRepository()
    let original = session(id: UUID(), date: Date(timeIntervalSince1970: 100), reps: 5)
    try await repo.save(original)
    #expect(try await repo.session(id: original.id) == original)
    #expect(try await repo.allSessions().count == 1)
}

@Test func saveWithSameIdOverwritesInsteadOfAppending() async throws {
    let repo = InMemoryWorkoutRepository()
    let id = fixedUUID("00000000-0000-0000-0000-0000000000aa")
    let first = session(id: id, date: Date(timeIntervalSince1970: 100), reps: 5)
    let second = session(id: id, date: Date(timeIntervalSince1970: 200), reps: 8)
    try await repo.save(first)
    try await repo.save(second)
    #expect(try await repo.allSessions().count == 1)
    #expect(try await repo.session(id: id) == second)
}

@Test func allSessionsSortsByDateDescending() async throws {
    let repo = InMemoryWorkoutRepository()
    let oldest = session(id: UUID(), date: Date(timeIntervalSince1970: 100), reps: 1)
    let middle = session(id: UUID(), date: Date(timeIntervalSince1970: 200), reps: 2)
    let newest = session(id: UUID(), date: Date(timeIntervalSince1970: 300), reps: 3)
    // 乱序插入
    try await repo.save(middle)
    try await repo.save(oldest)
    try await repo.save(newest)
    let all = try await repo.allSessions()
    #expect(all.map(\.date) == [300, 200, 100].map(Date.init(timeIntervalSince1970:)))
}

@Test func allSessionsTieBreaksByUuidStringAscending() async throws {
    let repo = InMemoryWorkoutRepository()
    let date = Date(timeIntervalSince1970: 500)
    let b = session(id: fixedUUID("00000000-0000-0000-0000-000000000002"), date: date, reps: 1)
    let a = session(id: fixedUUID("00000000-0000-0000-0000-000000000001"), date: date, reps: 2)
    // 乱序插入：uuidString 靠后的先插入
    try await repo.save(b)
    try await repo.save(a)
    let all = try await repo.allSessions()
    // 结果须按 uuidString 升序，不依赖插入顺序
    #expect(all.map(\.id) == [a.id, b.id])
}

@Test func deleteRemovesTargetAndKeepsOthers() async throws {
    let repo = InMemoryWorkoutRepository()
    let keep1 = session(id: UUID(), date: Date(timeIntervalSince1970: 100), reps: 1)
    let target = session(id: UUID(), date: Date(timeIntervalSince1970: 200), reps: 2)
    let keep2 = session(id: UUID(), date: Date(timeIntervalSince1970: 300), reps: 3)
    try await repo.save(keep1)
    try await repo.save(target)
    try await repo.save(keep2)
    try await repo.delete(id: target.id)
    #expect(try await repo.session(id: target.id) == nil)
    let remaining = try await repo.allSessions()
    #expect(remaining.map(\.id).sorted() == [keep1.id, keep2.id].sorted())
}

@Test func deleteMissingIdIsSilentNoOp() async throws {
    let repo = InMemoryWorkoutRepository()
    let s = session(id: UUID(), date: Date(timeIntervalSince1970: 100), reps: 1)
    try await repo.save(s)
    let before = try await repo.allSessions()
    try await repo.delete(id: fixedUUID("ffffffff-ffff-ffff-ffff-ffffffffffff"))
    #expect(try await repo.allSessions() == before)
}

@Test func initPresetDataIsRetrievableAndLaterDuplicateWins() async throws {
    let id = fixedUUID("00000000-0000-0000-0000-0000000000bb")
    let earlier = session(id: id, date: Date(timeIntervalSince1970: 100), reps: 1)
    let later = session(id: id, date: Date(timeIntervalSince1970: 400), reps: 9)
    let repo = InMemoryWorkoutRepository(sessions: [earlier, later])
    #expect(try await repo.session(id: id) == later)
    #expect(try await repo.allSessions().count == 1)
}

@Test func concurrentSavesDoNotLoseSessions() async throws {
    let repo = InMemoryWorkoutRepository()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<100 {
            let id = fixedUUID(String(format: "00000000-0000-0000-0000-%012x", i))
            group.addTask {
                try await repo.save(session(id: id, date: Date(timeIntervalSince1970: 0), reps: i))
            }
        }
        // 必须等待全部子任务完成：否则闭包返回后 group 取消未完成的子任务并吞掉错误，
        // 子任务抛错不会让测试失败。
        try await group.waitForAll()
    }
    #expect(try await repo.allSessions().count == 100)
}
