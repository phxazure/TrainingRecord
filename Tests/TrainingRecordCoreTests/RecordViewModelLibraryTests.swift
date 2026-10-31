import Foundation
import Testing
@testable import TrainingRecordCore

@MainActor
private func makeModel(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> (RecordViewModel, InMemoryWorkoutRepository) {
    let repository = InMemoryWorkoutRepository()
    return (RecordViewModel(repository: repository, now: { now }), repository)
}

private func definition(_ name: String, id: UUID = UUID()) -> ExerciseDefinition {
    ExerciseDefinition(id: id, name: name, bodyPart: "胸")!
}

@MainActor
@Suite struct RecordViewModelLibraryTests {
    @Test func addDefinitionRecordsExerciseIdAndName() throws {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        #expect(model.addExercise(bench))
        #expect(model.exercises.map(\.name) == ["卧推"])
        #expect(model.exercises.map { model.exerciseID(of: $0.id) } == [bench.id])
    }

    @Test func plainNameExercisesHaveNoExerciseId() {
        let (model, _) = makeModel()
        #expect(model.addExercise(name: "卧推"))
        #expect(model.exercises.first.flatMap { model.exerciseID(of: $0.id) } == nil)
    }

    @Test func savedSessionEntriesCarryExerciseId() async throws {
        let (model, repository) = makeModel()
        let bench = definition("卧推")
        let free = "自由输入"
        #expect(model.addExercise(bench))
        #expect(model.addExercise(name: free))
        let benchDraft = try #require(model.exercises.first?.id)
        let freeDraft = try #require(model.exercises.last?.id)
        #expect(model.addSet(toExercise: benchDraft, weightText: "60", repsText: "8") == nil)
        #expect(model.addSet(toExercise: freeDraft, weightText: "10", repsText: "10") == nil)

        let saved = try await model.save()

        #expect(saved.exercises.map(\.exerciseID) == [bench.id, nil])
        #expect(try await repository.allSessions().first?.exercises.map(\.exerciseID) == [bench.id, nil])
    }

    @Test func addDefinitionWithSameIdOrSameNameReturnsFalse() {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        #expect(model.addExercise(bench))
        #expect(model.addExercise(bench) == false)
        // 同名（不区分大小写、忽略首尾空白由定义保证）但不同 id。
        #expect(model.addExercise(definition("卧推")) == false)
        #expect(model.addExercise(definition("卧推".uppercased())) == false)
        // 同 id 但改了名字（库里改名后又加）。
        #expect(model.addExercise(definition("杠铃卧推", id: bench.id)) == false)
        #expect(model.exercises.count == 1)
    }

    @Test func addDefinitionConflictsWithPlainNameDraftsAndViceVersa() {
        let (model, _) = makeModel()
        #expect(model.addExercise(name: "Bench"))
        #expect(model.addExercise(definition("bench")) == false)
        #expect(model.addExercise(definition("Squat")))
        #expect(model.addExercise(name: "SQUAT") == false)
    }

    @Test func applyTemplateOnEmptyDraftAddsNamesAndIdsWithoutSets() throws {
        let (model, _) = makeModel()
        let squat = definition("深蹲"), bench = definition("卧推")
        let template = SessionTemplate(date: Date(timeIntervalSince1970: 0), exercises: [squat, bench])

        #expect(model.apply(template))

        #expect(model.exercises.map(\.name) == ["深蹲", "卧推"])
        #expect(model.exercises.map { model.exerciseID(of: $0.id) } == [squat.id, bench.id])
        #expect(model.exercises.allSatisfy { $0.sets.isEmpty })
        #expect(model.canSave == false)
    }

    @Test func applyTemplateOnNonEmptyDraftReturnsFalseAndChangesNothing() {
        let (model, _) = makeModel()
        #expect(model.addExercise(name: "自由输入"))
        let before = model.exercises
        let template = SessionTemplate(date: Date(timeIntervalSince1970: 0), exercises: [definition("深蹲")])

        #expect(model.apply(template) == false)
        #expect(model.exercises == before)
    }

    @Test func applyTemplateTwiceSecondTimeIsRejected() {
        let (model, _) = makeModel()
        let template = SessionTemplate(date: Date(timeIntervalSince1970: 0), exercises: [definition("深蹲")])
        #expect(model.apply(template))
        #expect(model.apply(template) == false)
        #expect(model.exercises.count == 1)
    }

    @Test func applyTemplateAfterSuccessfulSaveWorksAgain() async throws {
        let (model, _) = makeModel()
        let squat = definition("深蹲")
        #expect(model.addExercise(squat))
        let draft = try #require(model.exercises.first?.id)
        #expect(model.addSet(toExercise: draft, weightText: "100", repsText: "5") == nil)
        try await model.save()
        #expect(model.exercises.isEmpty)
        #expect(model.apply(SessionTemplate(date: Date(timeIntervalSince1970: 0), exercises: [squat])))
    }

    @Test func removingALinkedDraftForgetsItsLinkAndAllowsAddingAgain() throws {
        let (model, _) = makeModel()
        let bench = definition("卧推")
        #expect(model.addExercise(bench))
        let draftID = try #require(model.exercises.first?.id)
        #expect(model.exerciseID(of: draftID) == bench.id)

        model.removeExercise(id: draftID)

        #expect(model.exerciseID(of: draftID) == nil)
        #expect(model.addExercise(bench))
        #expect(model.exercises.count == 1)
    }

    @Test func existingBehaviourUnchangedForPlainNames() throws {
        let (model, _) = makeModel()
        #expect(model.addExercise(name: "  卧推 "))
        #expect(model.addExercise(name: "卧推") == false)
        #expect(model.addExercise(name: "   ") == false)
        #expect(model.exercises.map(\.name) == ["卧推"])
    }
}
