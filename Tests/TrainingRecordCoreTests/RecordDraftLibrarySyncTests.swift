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

    // R2：同步是就地更新——组的数值、顺序、id，动作的草稿 id 都原样保留，不经任何格式化重建。
    @Test func boundaryWeightsSurviveSyncBitForBit() {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        model.addExercise(bench)
        let texts = ["0.0000000000004", "62.12345678901234", "999.9999999999999", "0", "1000", "0.1", "33.333333"]
        addSets(model, to: 0, texts.map { ($0, "7") })
        let before = model.exercises[0].sets
        #expect(before.map(\.weight).prefix(3) == [4e-13, 62.12345678901234, 999.9999999999999])

        #expect(model.syncExercises(with: [definition("新名字", id: bench.id)]))

        #expect(model.exercises[0].sets == before)   // 逐值相等，含 id
        #expect(model.exercises[0].sets.map(\.weight).map(\.bitPattern) == before.map(\.weight).map(\.bitPattern))
    }

    @Test func renameKeepsDraftIdsAndSetIds() {
        let (model, _) = makeModel()
        let bench = definition("卧推"), squat = definition("深蹲")
        model.addExercise(bench); model.addExercise(squat)
        addSets(model, to: 0, [("60", "10"), ("62.5", "8")])
        addSets(model, to: 1, [("100", "5")])
        let draftIDs = model.exercises.map(\.id)
        let setIDs = model.exercises.map { $0.sets.map(\.id) }

        #expect(model.syncExercises(with: [definition("平板卧推", id: bench.id), squat]))

        #expect(model.exercises.map(\.id) == draftIDs)
        #expect(model.exercises.map { $0.sets.map(\.id) } == setIDs)
        #expect(model.exercises.map(\.name) == ["平板卧推", "深蹲"])
    }

    // R3-B1（263d98d）：合并后保留的是**目标**卡的身份（它未提交的输入不受影响），源卡未提交的输入可以丢；
    // 已录入的组两张卡的都在，数值、组 id 不变，顺序按原来的卡片顺序；合并后的卡片放在两张卡里靠前的位置。
    @Test func mergeKeepsTargetCardIdentityWhenSourceIsFirst() {
        let (model, _) = makeModel()
        let source = definition("卧推"), target = definition("杠铃卧推")
        model.addExercise(source); model.addExercise(target)
        addSets(model, to: 0, [("60", "10"), ("61", "9")])
        addSets(model, to: 1, [("70", "8")])
        let targetCard = model.exercises[1].id
        let allSetIDs = model.exercises.flatMap { $0.sets.map(\.id) }

        #expect(model.syncExercises(with: [target], merged: [source.id: target.id]))

        #expect(model.exercises.map(\.id) == [targetCard])      // 目标卡的身份（界面上它的未提交输入随之保留）
        #expect(model.exercises[0].sets.map(\.id) == allSetIDs) // 源卡的组在前，目标卡的组在后
        #expect(setPairs(model.exercises[0]) == ["60.0x10", "61.0x9", "70.0x8"])
        #expect(model.exerciseID(of: targetCard) == target.id)
        #expect(model.exercises[0].name == "杠铃卧推")
    }

    @Test func mergeKeepsTargetCardIdentityWhenTargetIsFirst() {
        let (model, _) = makeModel()
        let source = definition("卧推"), target = definition("杠铃卧推")
        model.addExercise(target); model.addExercise(source)
        addSets(model, to: 0, [("70", "8")])
        addSets(model, to: 1, [("60", "10"), ("61", "9")])
        let targetCard = model.exercises[0].id
        let allSetIDs = model.exercises.flatMap { $0.sets.map(\.id) }

        #expect(model.syncExercises(with: [target], merged: [source.id: target.id]))

        #expect(model.exercises.map(\.id) == [targetCard])
        #expect(model.exercises[0].sets.map(\.id) == allSetIDs)
        #expect(setPairs(model.exercises[0]) == ["70.0x8", "60.0x10", "61.0x9"])
    }

    @Test func mergedCardTakesTheEarlierPositionAndTargetIdentity() {
        let (model, _) = makeModel()
        let source = definition("卧推"), target = definition("杠铃卧推"), other = definition("深蹲")
        model.addExercise(source); model.addExercise(other); model.addExercise(target)
        addSets(model, to: 0, [("60", "10")])
        addSets(model, to: 1, [("100", "5")])
        addSets(model, to: 2, [("70", "8")])
        let otherCard = model.exercises[1].id, targetCard = model.exercises[2].id

        #expect(model.syncExercises(with: [target, other], merged: [source.id: target.id]))

        #expect(model.exercises.map(\.id) == [targetCard, otherCard])
        #expect(model.exercises.map(\.name) == ["杠铃卧推", "深蹲"])
        #expect(setPairs(model.exercises[0]) == ["60.0x10", "70.0x8"])
        #expect(setPairs(model.exercises[1]) == ["100.0x5"])
    }

    @Test func unlinkedDeletedKeepsDraftAndSetIds() {
        let (model, _) = makeModel()
        let gone = definition("消失")
        model.addExercise(gone)
        addSets(model, to: 0, [("20", "12")])
        let draftID = model.exercises[0].id
        let setIDs = model.exercises[0].sets.map(\.id)
        #expect(model.syncExercises(with: []))
        #expect(model.exercises.map(\.id) == [draftID])
        #expect(model.exercises[0].sets.map(\.id) == setIDs)
        #expect(model.exerciseID(of: draftID) == nil)
    }

    @Test func renamedToSameNameAsFreeExerciseCombinesWithoutLosingSets() {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        model.addExercise(bench)
        model.addExercise(name: "平板卧推")
        addSets(model, to: 0, [("60", "10")])
        addSets(model, to: 1, [("70", "8")])
        #expect(model.syncExercises(with: [definition("平板卧推", id: bench.id)]))
        #expect(model.exercises.count == 1)
        #expect(setPairs(model.exercises[0]) == ["60.0x10", "70.0x8"])
        #expect(model.exerciseID(of: model.exercises[0].id) == bench.id)
    }

    @Test func mergedSetsKeepTheirOrderAcrossMultipleSets() {
        let (model, _) = makeModel()
        let source = definition("卧推"), target = definition("杠铃卧推")
        model.addExercise(source); model.addExercise(target)
        addSets(model, to: 0, [("60", "10"), ("61", "9"), ("62", "8")])
        addSets(model, to: 1, [("70", "7"), ("71", "6")])
        #expect(model.syncExercises(with: [target], merged: [source.id: target.id]))
        #expect(setPairs(model.exercises[0]) == ["60.0x10", "61.0x9", "62.0x8", "70.0x7", "71.0x6"])
    }

    @Test func freeExerciseFirstThenRenamedLinkedOneWithSameNameKeepsTheLinkedCard() {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        model.addExercise(name: "平板卧推")      // 自由输入在前
        model.addExercise(bench)                // 关联的在后
        addSets(model, to: 0, [("70", "8")])
        addSets(model, to: 1, [("60", "10")])
        let linkedCard = model.exercises[1].id

        #expect(model.syncExercises(with: [definition("平板卧推", id: bench.id)]))

        // 带关联的那张卡保留身份（它的未提交输入不丢）；自由输入的组在前、关联卡的组在后。
        #expect(model.exercises.map(\.id) == [linkedCard])
        #expect(model.exerciseID(of: linkedCard) == bench.id)
        #expect(setPairs(model.exercises[0]) == ["70.0x8", "60.0x10"])
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
