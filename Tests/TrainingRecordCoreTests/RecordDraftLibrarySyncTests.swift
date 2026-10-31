import Foundation
import Testing
@testable import TrainingRecordCore

// T009 review F1：训练草稿必须跟随动作库的改名 / 合并 / 删除，保存时不能写出旧名字或悬空的动作 id，也不能丢已录入的组。

@MainActor
private func makeModel() -> (RecordViewModel, InMemoryWorkoutRepository) {
    let repository = InMemoryWorkoutRepository()
    return (RecordViewModel(repository: repository, now: { Date(timeIntervalSince1970: 1_700_000_000) }), repository)
}

private func definition(_ name: String, id: UUID = UUID(), part: String = "胸") -> ExerciseDefinition {
    ExerciseDefinition(id: id, name: name, bodyPart: part)!
}

@MainActor
private func addSets(_ model: RecordViewModel, to index: Int, _ sets: [(String, String)]) {
    let id = model.exercises[index].id
    for set in sets { #expect(model.addSet(toExercise: id, weightText: set.0, repsText: set.1) == nil) }
}

private func setPairs(_ draft: ExerciseDraft) -> [String] {
    draft.sets.map { "\($0.weight)x\($0.reps)" }
}

@MainActor
@Suite struct RecordDraftLibrarySyncTests {
    @Test func renameUpdatesDraftNameKeepingSetsOrderAndLink() {
        let (model, _) = makeModel()
        let bench = definition("卧推"), squat = definition("深蹲")
        model.addExercise(bench); model.addExercise(squat)
        addSets(model, to: 0, [("60", "10"), ("62.5", "8")])
        addSets(model, to: 1, [("100", "5")])
        let date = Date(timeIntervalSince1970: 123)
        model.date = date

        let renamed = definition("平板卧推", id: bench.id)
        #expect(model.syncExercises(with: [renamed, squat]) == true)

        #expect(model.exercises.map(\.name) == ["平板卧推", "深蹲"])
        #expect(model.exercises.map { model.exerciseID(of: $0.id) } == [bench.id, squat.id])
        #expect(setPairs(model.exercises[0]) == ["60.0x10", "62.5x8"])
        #expect(setPairs(model.exercises[1]) == ["100.0x5"])
        #expect(model.date == date)
    }

    @Test func nothingToChangeReturnsFalseAndKeepsDraftIdentity() {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        model.addExercise(bench)
        addSets(model, to: 0, [("60", "10")])
        let before = model.exercises
        #expect(model.syncExercises(with: [bench]) == false)
        #expect(model.exercises == before)
    }

    @Test func mergedSourceBecomesTargetAndKeepsSets() {
        let (model, _) = makeModel()
        let source = definition("卧推"), target = definition("杠铃卧推")
        model.addExercise(source)
        addSets(model, to: 0, [("60", "10")])

        // source 已从库里删除，merged 记录 source → target。
        #expect(model.syncExercises(with: [target], merged: [source.id: target.id]) == true)

        #expect(model.exercises.map(\.name) == ["杠铃卧推"])
        #expect(model.exerciseID(of: model.exercises[0].id) == target.id)
        #expect(setPairs(model.exercises[0]) == ["60.0x10"])
    }

    @Test func mergedSourceAndTargetBothInDraftCombineSetsAtFirstPosition() {
        let (model, _) = makeModel()
        let source = definition("卧推"), target = definition("杠铃卧推"), other = definition("深蹲")
        model.addExercise(source); model.addExercise(other); model.addExercise(target)
        addSets(model, to: 0, [("60", "10")])
        addSets(model, to: 1, [("100", "5")])
        addSets(model, to: 2, [("70", "8")])

        #expect(model.syncExercises(with: [target, other], merged: [source.id: target.id]))

        #expect(model.exercises.map(\.name) == ["杠铃卧推", "深蹲"])
        #expect(setPairs(model.exercises[0]) == ["60.0x10", "70.0x8"])
        #expect(setPairs(model.exercises[1]) == ["100.0x5"])
    }

    @Test func mergeChainsAreFollowed() {
        let (model, _) = makeModel()
        let a = definition("A"), b = definition("B"), c = definition("C")
        model.addExercise(a)
        addSets(model, to: 0, [("10", "1")])
        #expect(model.syncExercises(with: [c], merged: [a.id: b.id, b.id: c.id]))
        #expect(model.exercises.map { model.exerciseID(of: $0.id) } == [c.id])
    }

    @Test func mergeCycleDoesNotHang() {
        let (model, _) = makeModel()
        let a = definition("A"), b = definition("B")
        model.addExercise(a)
        addSets(model, to: 0, [("10", "1")])
        // 不可能出现的环：不能死循环，也不能丢组；解析不到就当作自由输入保留。
        _ = model.syncExercises(with: [], merged: [a.id: b.id, b.id: a.id])
        #expect(model.exercises.count == 1)
        #expect(setPairs(model.exercises[0]) == ["10.0x1"])
        #expect(model.exerciseID(of: model.exercises[0].id) == nil)
    }

    @Test func deletedWithoutMappingKeepsSetsAsFreeExercise() {
        let (model, _) = makeModel()
        let gone = definition("消失的动作")
        model.addExercise(gone)
        addSets(model, to: 0, [("20", "12"), ("22.5", "10")])

        #expect(model.syncExercises(with: []) == true)

        #expect(model.exercises.map(\.name) == ["消失的动作"])
        #expect(model.exerciseID(of: model.exercises[0].id) == nil)
        #expect(setPairs(model.exercises[0]) == ["20.0x12", "22.5x10"])
        // 再同步一次：已经是自由输入，不再变化。
        #expect(model.syncExercises(with: []) == false)
    }

    @Test func savedSessionNeverCarriesStaleNameOrDanglingId() async throws {
        let (model, repository) = makeModel()
        let source = definition("卧推"), target = definition("杠铃卧推"), other = definition("深蹲")
        let gone = definition("已删")
        model.addExercise(source); model.addExercise(other); model.addExercise(gone)
        addSets(model, to: 0, [("60", "10")])
        addSets(model, to: 1, [("100", "5")])
        addSets(model, to: 2, [("5", "5")])

        let renamedOther = definition("傻蹲", id: other.id)
        model.syncExercises(with: [target, renamedOther], merged: [source.id: target.id])
        let saved = try await model.save()

        #expect(saved.exercises.map(\.name) == ["杠铃卧推", "傻蹲", "已删"])
        #expect(saved.exercises.map(\.exerciseID) == [target.id, other.id, nil])
        #expect(try await repository.allSessions().first == saved)
    }

    @Test func weightTextRoundTripIsExact() {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        model.addExercise(bench)
        let weights = ["0", "62.5", "0.0000001", "1000", "99.99", "0.1", "33.333333"]
        addSets(model, to: 0, weights.map { ($0, "1") })
        let before = model.exercises[0].sets.map(\.weight)
        #expect(model.syncExercises(with: [definition("新名字", id: bench.id)]))
        #expect(model.exercises[0].sets.map(\.weight) == before)
        #expect(model.exercises[0].sets.map(\.reps) == Array(repeating: 1, count: weights.count))
    }

    @Test func skippedWhileSaving() async throws {
        let gate = SyncGateRepository()
        let model = RecordViewModel(repository: gate, now: { Date(timeIntervalSince1970: 1) })
        let bench = definition("卧推")
        model.addExercise(bench)
        addSets(model, to: 0, [("60", "10")])
        let saving = Task { try await model.save() }
        await gate.waitForSave()
        #expect(model.isSaving)

        #expect(model.syncExercises(with: [definition("新名字", id: bench.id)]) == false)
        #expect(model.exercises.map(\.name) == ["卧推"])

        await gate.release()
        _ = try await saving.value
        #expect(model.exercises.isEmpty)
    }
}

private actor SyncGateRepository: WorkoutRepository {
    private var saved: [WorkoutSession] = []
    private var arrived = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var gate: CheckedContinuation<Void, Never>?

    func waitForSave() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() { gate?.resume(); gate = nil }

    func save(_ session: WorkoutSession) async throws {
        arrived = true
        arrival?.resume(); arrival = nil
        await withCheckedContinuation { gate = $0 }
        saved.append(session)
    }

    func allSessions() async throws -> [WorkoutSession] { saved }
    func session(id: UUID) async throws -> WorkoutSession? { saved.first { $0.id == id } }
    func delete(id: UUID) async throws { saved.removeAll { $0.id == id } }
}
