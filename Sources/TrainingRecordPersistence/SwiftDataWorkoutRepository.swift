import Foundation
import SwiftData
import TrainingRecordCore

/// 存储里的数据无法还原成合法的领域对象（只可能是存储被外部改坏）。
public enum SwiftDataWorkoutRepositoryError: Error, Equatable, Sendable {
    case corruptRecord
}

/// 各类存储记录的条数，供测试确认覆盖、删除没有留下孤儿记录。
struct StoredRecordCounts: Equatable, Sendable {
    var sessions: Int
    var exercises: Int
    var sets: Int
}

/// 用 SwiftData 实现的 `WorkoutRepository`：行为与 `InMemoryWorkoutRepository` 一致
/// （规范见 `WorkoutRepository` 的文档注释）。actor 串行化全部读写。
@ModelActor
public actor SwiftDataWorkoutRepository: ConditionalSessionUpdating {
    /// 内存模式：数据只在实例存活期间存在，每个实例互相独立。用于测试与「磁盘存储打不开」时的退路。
    public static func inMemory() throws -> SwiftDataWorkoutRepository {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return SwiftDataWorkoutRepository(modelContainer: try makeContainer(configuration))
    }

    /// 磁盘模式：`url` 是存储文件位置；父目录不存在时先创建。
    /// 释放实例后用同一个 `url` 再创建，可读回之前保存的全部数据。
    public static func onDisk(url: URL) throws -> SwiftDataWorkoutRepository {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
        return SwiftDataWorkoutRepository(modelContainer: try makeContainer(configuration))
    }

    private static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try StoreSchema.makeContainer(configuration)
    }

    // MARK: WorkoutRepository

    public func save(_ session: WorkoutSession) async throws {
        do {
            // 覆盖 = 删旧（级联删除其动作和组）再按新内容插入，不留孤儿记录。
            for existing in try records(id: session.id) {
                modelContext.delete(existing)
            }
            modelContext.insert(Self.makeRecord(from: session))
            try modelContext.save()
        } catch {
            // 保存失败时丢掉未提交的改动，避免它们混进下一次保存。
            modelContext.rollback()
            throw error
        }
    }

    /// 原子更新（`ConditionalSessionUpdating`）：整个「读 → 变换 → 写」在 actor 上没有挂起点，
    /// 不会被同一仓储上的删除打断；场次不存在时不创建。
    public func updateExisting(id: UUID, _ transform: @Sendable (WorkoutSession) -> WorkoutSession?) async throws -> Bool {
        do {
            guard let record = try records(id: id).first else { return false }
            guard let updated = transform(try Self.makeSession(from: record)) else { return false }
            for existing in try records(id: id) {
                modelContext.delete(existing)
            }
            modelContext.insert(Self.makeRecord(from: updated))
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func session(id: UUID) async throws -> WorkoutSession? {
        try records(id: id).first.map(Self.makeSession(from:))
    }

    public func allSessions() async throws -> [WorkoutSession] {
        // 排序在内存里做，规则与协议文档完全一致：date 降序，相同时 id.uuidString 升序。
        try modelContext.fetch(FetchDescriptor<SessionRecord>())
            .map(Self.makeSession(from:))
            .sorted { a, b in
                if a.date != b.date {
                    return a.date > b.date
                }
                return a.id.uuidString < b.id.uuidString
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

    // MARK: 内部

    func storedRecordCounts() throws -> StoredRecordCounts {
        StoredRecordCounts(
            sessions: try modelContext.fetchCount(FetchDescriptor<SessionRecord>()),
            exercises: try modelContext.fetchCount(FetchDescriptor<ExerciseRecord>()),
            sets: try modelContext.fetchCount(FetchDescriptor<SetRecord>())
        )
    }

    private func records(id: UUID) throws -> [SessionRecord] {
        try modelContext.fetch(FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.id == id }))
    }

    private static func makeRecord(from session: WorkoutSession) -> SessionRecord {
        let record = SessionRecord(id: session.id, date: session.date)
        for (exerciseIndex, exercise) in session.exercises.enumerated() {
            let exerciseRecord = ExerciseRecord(order: exerciseIndex, name: exercise.name, exerciseID: exercise.exerciseID)
            for (setIndex, set) in exercise.sets.enumerated() {
                exerciseRecord.sets.append(SetRecord(order: setIndex, weight: set.weight, reps: set.reps))
            }
            record.exercises.append(exerciseRecord)
        }
        return record
    }

    private static func makeSession(from record: SessionRecord) throws -> WorkoutSession {
        let exercises = try record.exercises
            .sorted { $0.order < $1.order }
            .map { exerciseRecord -> ExerciseEntry in
                let sets = try exerciseRecord.sets
                    .sorted { $0.order < $1.order }
                    .map { setRecord -> SetEntry in
                        guard let set = SetEntry(weight: setRecord.weight, reps: setRecord.reps) else {
                            throw SwiftDataWorkoutRepositoryError.corruptRecord
                        }
                        return set
                    }
                guard let exercise = ExerciseEntry(name: exerciseRecord.name, sets: sets, exerciseID: exerciseRecord.exerciseID) else {
                    throw SwiftDataWorkoutRepositoryError.corruptRecord
                }
                return exercise
            }
        return WorkoutSession(id: record.id, date: record.date, exercises: exercises)
    }
}
