import Foundation

/// 动作库里的一个动作。动作库不预置任何动作，全部由用户添加。
public struct ExerciseDefinition: Identifiable, Equatable, Sendable {
    /// 「未分类」：部位为空时的默认部位，也是迁移回填的默认部位。
    public static let uncategorized = "未分类"

    public let id: UUID
    /// 动作名，已去首尾空白，非空。
    public let name: String
    /// 训练部位，已去首尾空白；空 → 「未分类」。
    public let bodyPart: String
    /// 照片文件名（只存文件名，文件的读写、缩放由 App 负责）；空白视为没有照片。
    public let photoFileName: String?

    /// 名字去首尾空白后为空时返回 nil。
    public init?(id: UUID = UUID(), name: String, bodyPart: String, photoFileName: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedPart = bodyPart.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhoto = photoFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = trimmedName
        self.bodyPart = trimmedPart.isEmpty ? Self.uncategorized : trimmedPart
        self.photoFileName = (trimmedPhoto?.isEmpty ?? true) ? nil : trimmedPhoto
    }
}

extension ExerciseDefinition {
    /// 名字的比较键：去首尾空白、不区分大小写。动作库内名字按它唯一。
    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension Sequence where Element == ExerciseDefinition {
    /// 动作库的标准顺序：先按部位、再按名字，升序，`localizedStandardCompare`（数字按大小比，「2」在「10」前）。
    /// 完全相同时按 id 兜底，保证结果确定。
    public func sortedForLibrary() -> [ExerciseDefinition] {
        sorted { a, b in
            let part = a.bodyPart.localizedStandardCompare(b.bodyPart)
            if part != .orderedSame { return part == .orderedAscending }
            let name = a.name.localizedStandardCompare(b.name)
            if name != .orderedSame { return name == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }
}

/// 动作库存取抽象。名字是否唯一由 `ExerciseLibraryService` 保证，仓储只负责存取。
public protocol ExerciseLibraryRepository: Sendable {
    /// 全部动作：按 bodyPart、再按 name（localizedStandardCompare）升序。
    func allExercises() async throws -> [ExerciseDefinition]
    /// 按 id 读取；不存在返回 nil。
    func exercise(id: UUID) async throws -> ExerciseDefinition?
    /// 新增，或按 id 覆盖。
    func save(_ exercise: ExerciseDefinition) async throws
    /// 按 id 删除；不存在时静默成功。
    func delete(id: UUID) async throws
}

/// 内存实现：适合单元测试与「磁盘存储打不开」时的退路。
public actor InMemoryExerciseLibraryRepository: ExerciseLibraryRepository {
    private var items: [UUID: ExerciseDefinition] = [:]

    public init() {}

    public func allExercises() async throws -> [ExerciseDefinition] {
        items.values.sortedForLibrary()
    }

    public func exercise(id: UUID) async throws -> ExerciseDefinition? {
        items[id]
    }

    public func save(_ exercise: ExerciseDefinition) async throws {
        items[exercise.id] = exercise
    }

    public func delete(id: UUID) async throws {
        items[id] = nil
    }
}
