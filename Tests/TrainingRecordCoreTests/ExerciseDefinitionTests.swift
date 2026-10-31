import Foundation
import Testing
@testable import TrainingRecordCore

@Suite struct ExerciseDefinitionTests {
    @Test func trimsNameAndBodyPart() throws {
        let definition = try #require(ExerciseDefinition(name: "  卧推 \n", bodyPart: " 胸 "))
        #expect(definition.name == "卧推")
        #expect(definition.bodyPart == "胸")
        #expect(definition.photoFileName == nil)
    }

    @Test(arguments: ["", "   ", "\n\t "])
    func emptyNameReturnsNil(name: String) {
        #expect(ExerciseDefinition(name: name, bodyPart: "胸") == nil)
    }

    @Test(arguments: ["", "  ", "\n"])
    func emptyBodyPartBecomesUncategorized(bodyPart: String) throws {
        let definition = try #require(ExerciseDefinition(name: "深蹲", bodyPart: bodyPart))
        #expect(definition.bodyPart == ExerciseDefinition.uncategorized)
        #expect(ExerciseDefinition.uncategorized == "未分类")
    }

    @Test func keepsIdAndPhotoFileName() throws {
        let id = UUID()
        let definition = try #require(ExerciseDefinition(id: id, name: "硬拉", bodyPart: "背", photoFileName: "a.jpg"))
        #expect(definition.id == id)
        #expect(definition.photoFileName == "a.jpg")
        // 空白文件名视为没有照片。
        #expect(ExerciseDefinition(name: "硬拉", bodyPart: "背", photoFileName: "  ")?.photoFileName == nil)
    }

    @Test func newDefinitionsGetDistinctIds() throws {
        let a = try #require(ExerciseDefinition(name: "A", bodyPart: ""))
        let b = try #require(ExerciseDefinition(name: "A", bodyPart: ""))
        #expect(a.id != b.id)
    }

    @Test func exerciseEntryKeepsOldInitializerAndDefaultsIdToNil() throws {
        let entry = try #require(ExerciseEntry(name: "卧推", sets: [SetEntry(weight: 60, reps: 8)!]))
        #expect(entry.exerciseID == nil)
        #expect(entry.name == "卧推")
        #expect(entry.sets == [SetEntry(weight: 60, reps: 8)!])
        let id = UUID()
        let linked = try #require(ExerciseEntry(name: "卧推", sets: entry.sets, exerciseID: id))
        #expect(linked.exerciseID == id)
        #expect(linked != entry)
        // 名字仍然去首尾空白、空名仍然失败。
        #expect(ExerciseEntry(name: "  ", sets: [], exerciseID: id) == nil)
        #expect(ExerciseEntry(name: " 卧推 ", sets: [], exerciseID: id)?.name == "卧推")
    }

    @Test func libraryOrderSortsByBodyPartThenNameNumericAware() throws {
        func make(_ name: String, _ part: String) -> ExerciseDefinition {
            ExerciseDefinition(name: name, bodyPart: part)!
        }
        let sorted = [
            make("Fly", "Chest"), make("Bench 10", "Chest"), make("Curl", "Arms"),
            make("Bench 2", "Chest"), make("Row", "Back"),
        ].sortedForLibrary()
        #expect(sorted.map(\.name) == ["Curl", "Row", "Bench 2", "Bench 10", "Fly"])
    }
}

// MARK: - 内存动作库仓储

@Suite struct InMemoryExerciseLibraryRepositoryTests {
    private func make(_ name: String, _ part: String = "", id: UUID = UUID()) -> ExerciseDefinition {
        ExerciseDefinition(id: id, name: name, bodyPart: part)!
    }

    @Test func emptyRepository() async throws {
        let repository = InMemoryExerciseLibraryRepository()
        #expect(try await repository.allExercises().isEmpty)
        #expect(try await repository.exercise(id: UUID()) == nil)
    }

    @Test func saveThenReadBack() async throws {
        let repository = InMemoryExerciseLibraryRepository()
        let item = ExerciseDefinition(name: "卧推", bodyPart: "胸", photoFileName: "p.jpg")!
        try await repository.save(item)
        #expect(try await repository.exercise(id: item.id) == item)
        #expect(try await repository.allExercises() == [item])
    }

    @Test func saveWithSameIdOverwrites() async throws {
        let repository = InMemoryExerciseLibraryRepository()
        let id = UUID()
        try await repository.save(make("A", "胸", id: id))
        let renamed = make("B", "背", id: id)
        try await repository.save(renamed)
        #expect(try await repository.allExercises() == [renamed])
    }

    @Test func deleteRemovesAndMissingIsSilent() async throws {
        let repository = InMemoryExerciseLibraryRepository()
        let keep = make("Keep")
        let drop = make("Drop")
        try await repository.save(keep)
        try await repository.save(drop)
        try await repository.delete(id: drop.id)
        try await repository.delete(id: UUID())
        #expect(try await repository.allExercises() == [keep])
    }

    @Test func allExercisesSortedByBodyPartThenName() async throws {
        let repository = InMemoryExerciseLibraryRepository()
        for item in [make("Fly", "Chest"), make("Bench 10", "Chest"), make("Curl", "Arms"), make("Bench 2", "Chest")] {
            try await repository.save(item)
        }
        #expect(try await repository.allExercises().map(\.name) == ["Curl", "Bench 2", "Bench 10", "Fly"])
    }
}
