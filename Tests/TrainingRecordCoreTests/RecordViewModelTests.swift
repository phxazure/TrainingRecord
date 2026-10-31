import Foundation
import Testing
@testable import TrainingRecordCore

/// 仓储写入总是失败的假仓储，用于验证保存失败时草稿保持不变。
private struct FailingRepository: WorkoutRepository {
    struct Boom: Error, Equatable {}

    func save(_ session: WorkoutSession) async throws { throw Boom() }
    func session(id: UUID) async throws -> WorkoutSession? { nil }
    func allSessions() async throws -> [WorkoutSession] { [] }
    func delete(id: UUID) async throws {}
}

/// 固定的「当前时间」，测试不依赖真实时钟。
private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
@Suite struct RecordViewModelTests {
    let repository = InMemoryWorkoutRepository()

    private func makeModel(repository: (any WorkoutRepository)? = nil) -> RecordViewModel {
        RecordViewModel(repository: repository ?? self.repository, now: { fixedNow })
    }

    /// 新增一个动作并返回其 id；失败直接让测试失败。
    private func addExercise(_ name: String, to model: RecordViewModel) throws -> ExerciseDraft.ID {
        #expect(model.addExercise(name: name))
        return try #require(model.exercises.last?.id)
    }

    private func exercise(_ id: ExerciseDraft.ID, in model: RecordViewModel) throws -> ExerciseDraft {
        try #require(model.exercises.first { $0.id == id })
    }

    // MARK: - 初始状态

    @Test func initialStateUsesInjectedNow() {
        let model = makeModel()
        #expect(model.date == fixedNow)
        #expect(model.exercises.isEmpty)
        #expect(model.canSave == false)
    }

    // MARK: - 动作

    @Test func addExerciseTrimsName() {
        let model = makeModel()
        #expect(model.addExercise(name: "  卧推 "))
        #expect(model.exercises.map(\.name) == ["卧推"])
        #expect(model.exercises.first?.sets.isEmpty == true)
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func addExerciseRejectsBlankName(_ name: String) {
        let model = makeModel()
        #expect(model.addExercise(name: name) == false)
        #expect(model.exercises.isEmpty)
    }

    @Test func addExerciseRejectsDuplicateIgnoringCaseAndWhitespace() {
        let model = makeModel()
        #expect(model.addExercise(name: "Bench Press"))
        #expect(model.addExercise(name: "卧推"))
        #expect(model.addExercise(name: " bench press ") == false)
        #expect(model.addExercise(name: "BENCH PRESS") == false)
        #expect(model.addExercise(name: "卧推  ") == false)
        #expect(model.exercises.map(\.name) == ["Bench Press", "卧推"])
    }

    @Test func removeExerciseKeepsOthersAndTheirSets() throws {
        let model = makeModel()
        let a = try addExercise("深蹲", to: model)
        let b = try addExercise("卧推", to: model)
        let c = try addExercise("硬拉", to: model)
        #expect(model.addSet(toExercise: a, weightText: "100", repsText: "5") == nil)
        #expect(model.addSet(toExercise: b, weightText: "60", repsText: "8") == nil)
        #expect(model.addSet(toExercise: c, weightText: "140", repsText: "3") == nil)
        let before = model.exercises

        model.removeExercise(id: b)

        #expect(model.exercises.map(\.id) == [a, c])
        #expect(model.exercises == [before[0], before[2]])
    }

    @Test func removeExerciseWithUnknownIdIsNoOp() throws {
        let model = makeModel()
        _ = try addExercise("卧推", to: model)
        let before = model.exercises
        model.removeExercise(id: UUID())
        #expect(model.exercises == before)
    }

    // MARK: - 组输入解析

    @Test(arguments: zip(
        ["60", "60.5", "60,5", "  60 ", " 60,5\n", "0", "1000", "0.5"],
        [60.0, 60.5, 60.5, 60.0, 60.5, 0.0, 1000.0, 0.5]
    ))
    func addSetAcceptsValidWeight(_ text: String, _ expected: Double) throws {
        let model = makeModel()
        let id = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: id, weightText: text, repsText: "8") == nil)
        let sets = try exercise(id, in: model).sets
        #expect(sets.map(\.weight) == [expected])
        #expect(sets.map(\.reps) == [8])
    }

    @Test(arguments: ["-1", "-0.5", "", "   ", "abc", "60kg", "1000.1", "1001", "6,0,5", "nan", "inf"])
    func addSetRejectsInvalidWeight(_ text: String) throws {
        let model = makeModel()
        let id = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: id, weightText: text, repsText: "8") == .invalidWeight)
        #expect(try exercise(id, in: model).sets.isEmpty)
    }

    @Test(arguments: zip(["1", "8", " 12 ", "1000"], [1, 8, 12, 1000]))
    func addSetAcceptsValidReps(_ text: String, _ expected: Int) throws {
        let model = makeModel()
        let id = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: id, weightText: "60", repsText: text) == nil)
        #expect(try exercise(id, in: model).sets.map(\.reps) == [expected])
    }

    @Test(arguments: ["0", "-1", "5.5", "5,5", "", "  ", "abc", "1001", "+5"])
    func addSetRejectsInvalidReps(_ text: String) throws {
        let model = makeModel()
        let id = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: id, weightText: "60", repsText: text) == .invalidReps)
        #expect(try exercise(id, in: model).sets.isEmpty)
    }

    @Test func addSetReportsWeightFirstWhenBothInvalid() throws {
        let model = makeModel()
        let id = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: id, weightText: "abc", repsText: "0") == .invalidWeight)
        #expect(try exercise(id, in: model).sets.isEmpty)
    }

    @Test func addSetAppendsInEntryOrderToTargetExerciseOnly() throws {
        let model = makeModel()
        let squat = try addExercise("深蹲", to: model)
        let bench = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: bench, weightText: "60", repsText: "10") == nil)
        #expect(model.addSet(toExercise: bench, weightText: "65", repsText: "8") == nil)
        #expect(model.addSet(toExercise: bench, weightText: "70", repsText: "6") == nil)

        let sets = try exercise(bench, in: model).sets
        #expect(sets.map(\.weight) == [60, 65, 70])
        #expect(sets.map(\.reps) == [10, 8, 6])
        #expect(Set(sets.map(\.id)).count == 3)
        #expect(try exercise(squat, in: model).sets.isEmpty)
    }

    /// 对不存在的动作 id 添加组：输入合法时返回 nil、静默忽略（与仓储 delete 不存在 id 的语义一致）；
    /// 输入非法时照常返回解析错误。两种情况都不新增、不崩溃。
    @Test func addSetToUnknownExerciseIsIgnored() throws {
        let model = makeModel()
        _ = try addExercise("卧推", to: model)
        let before = model.exercises

        #expect(model.addSet(toExercise: UUID(), weightText: "60", repsText: "8") == nil)
        #expect(model.addSet(toExercise: UUID(), weightText: "x", repsText: "8") == .invalidWeight)
        #expect(model.addSet(toExercise: UUID(), weightText: "60", repsText: "0") == .invalidReps)
        #expect(model.exercises == before)
    }

    @Test func removeSetRemovesOnlyThatSet() throws {
        let model = makeModel()
        let bench = try addExercise("卧推", to: model)
        let row = try addExercise("划船", to: model)
        #expect(model.addSet(toExercise: bench, weightText: "60", repsText: "10") == nil)
        #expect(model.addSet(toExercise: bench, weightText: "65", repsText: "8") == nil)
        #expect(model.addSet(toExercise: bench, weightText: "70", repsText: "6") == nil)
        #expect(model.addSet(toExercise: row, weightText: "50", repsText: "12") == nil)
        let rowBefore = try exercise(row, in: model)
        let middle = try exercise(bench, in: model).sets[1].id

        model.removeSet(exerciseID: bench, setID: middle)

        let sets = try exercise(bench, in: model).sets
        #expect(sets.map(\.weight) == [60, 70])
        #expect(sets.map(\.reps) == [10, 6])
        #expect(try exercise(row, in: model) == rowBefore)
    }

    @Test func removeSetWithUnknownIdsIsNoOp() throws {
        let model = makeModel()
        let bench = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: bench, weightText: "60", repsText: "10") == nil)
        let setID = try exercise(bench, in: model).sets[0].id
        let before = model.exercises

        model.removeSet(exerciseID: bench, setID: UUID())
        model.removeSet(exerciseID: UUID(), setID: setID)

        #expect(model.exercises == before)
    }

    // MARK: - canSave

    @Test func canSaveRequiresAtLeastOneExerciseWithASet() throws {
        let model = makeModel()
        #expect(model.canSave == false)

        let bench = try addExercise("卧推", to: model)
        _ = try addExercise("深蹲", to: model)
        #expect(model.canSave == false)

        #expect(model.addSet(toExercise: bench, weightText: "60", repsText: "8") == nil)
        #expect(model.canSave == true)

        let setID = try exercise(bench, in: model).sets[0].id
        model.removeSet(exerciseID: bench, setID: setID)
        #expect(model.canSave == false)
    }

    // MARK: - 保存

    @Test func saveWritesOnlyNonEmptyExercisesInEntryOrder() async throws {
        let model = makeModel()
        let chosenDate = Date(timeIntervalSince1970: 1_600_000_000)
        model.date = chosenDate
        let squat = try addExercise("深蹲", to: model)
        _ = try addExercise("空动作", to: model)
        let bench = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: squat, weightText: "100", repsText: "5") == nil)
        #expect(model.addSet(toExercise: squat, weightText: "102,5", repsText: "3") == nil)
        #expect(model.addSet(toExercise: bench, weightText: "0", repsText: "15") == nil)

        let saved = try await model.save()

        #expect(saved.date == chosenDate)
        #expect(saved.exercises.map(\.name) == ["深蹲", "卧推"])
        #expect(saved.exercises[0].sets == [SetEntry(weight: 100, reps: 5)!, SetEntry(weight: 102.5, reps: 3)!])
        #expect(saved.exercises[1].sets == [SetEntry(weight: 0, reps: 15)!])
    }

    @Test func saveSuccessClearsDraftResetsDateAndReturnsStoredSession() async throws {
        let model = makeModel()
        model.date = Date(timeIntervalSince1970: 1_600_000_000)
        let bench = try addExercise("卧推", to: model)
        #expect(model.addSet(toExercise: bench, weightText: "60", repsText: "8") == nil)

        let saved = try await model.save()

        #expect(model.exercises.isEmpty)
        #expect(model.date == fixedNow)
        #expect(model.canSave == false)
        #expect(try await repository.allSessions() == [saved])
        #expect(try await repository.session(id: saved.id) == saved)
    }

    @Test func saveWithoutSavableContentThrowsAndDoesNotWrite() async throws {
        let model = makeModel()
        await #expect(throws: RecordSaveError.nothingToSave) { try await model.save() }

        _ = try addExercise("卧推", to: model)
        await #expect(throws: RecordSaveError.nothingToSave) { try await model.save() }

        #expect(try await repository.allSessions().isEmpty)
        #expect(model.exercises.map(\.name) == ["卧推"])
    }

    @Test func repositoryFailureRethrowsAndKeepsDraft() async throws {
        let model = makeModel(repository: FailingRepository())
        let chosenDate = Date(timeIntervalSince1970: 1_600_000_000)
        model.date = chosenDate
        let bench = try addExercise("卧推", to: model)
        _ = try addExercise("空动作", to: model)
        #expect(model.addSet(toExercise: bench, weightText: "60", repsText: "8") == nil)
        let before = model.exercises

        await #expect(throws: FailingRepository.Boom.self) { try await model.save() }

        #expect(model.exercises == before)
        #expect(model.date == chosenDate)
        #expect(model.canSave == true)
    }
}
