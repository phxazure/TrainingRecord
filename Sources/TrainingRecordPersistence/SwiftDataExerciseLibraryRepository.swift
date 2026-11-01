import Foundation
import SwiftData
import TrainingRecordCore

/// 用 SwiftData 实现的 `ExerciseLibraryRepository`：行为与 `InMemoryExerciseLibraryRepository` 一致。
/// 通过 `TrainingRecordStore` 创建，与训练记录仓储共用同一个存储。
@ModelActor
public actor SwiftDataExerciseLibraryRepository: ExerciseLibraryRepository {
    public func allExercises() async throws -> [ExerciseDefinition] {
        // 排序在内存里做（localizedStandardCompare 不能下推到存储层）。
        try modelContext.fetch(FetchDescriptor<ExerciseDefinitionRecord>())
            .compactMap(Self.makeDefinition(from:))
            .sortedForLibrary()
    }

    public func exercise(id: UUID) async throws -> ExerciseDefinition? {
        try records(id: id).first.flatMap(Self.makeDefinition(from:))
    }

    public func save(_ exercise: ExerciseDefinition) async throws {
        do {
            // 覆盖 = 删旧再插入，不留重复记录。
            for existing in try records(id: exercise.id) {
                modelContext.delete(existing)
            }
            modelContext.insert(
                ExerciseDefinitionRecord(
                    id: exercise.id,
                    name: exercise.name,
                    bodyPart: exercise.bodyPart,
                    photoFileName: exercise.photoFileName
                )
            )
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func delete(id: UUID) async throws {
        do {
            for existing in try records(id: id) {
                modelContext.delete(existing)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func records(id: UUID) throws -> [ExerciseDefinitionRecord] {
        try modelContext.fetch(FetchDescriptor<ExerciseDefinitionRecord>(predicate: #Predicate { $0.id == id }))
    }

    /// 存储里的名字为空（只可能是存储被外部改坏）的记录读不成合法的领域对象，跳过。
    private static func makeDefinition(from record: ExerciseDefinitionRecord) -> ExerciseDefinition? {
        ExerciseDefinition(
            id: record.id,
            name: record.name,
            bodyPart: record.bodyPart,
            photoFileName: record.photoFileName
        )
    }
}
