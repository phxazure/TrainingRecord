import Foundation
import SwiftData
import TrainingRecordCore

/// 存储的 schema 与容器创建，训练记录和动作库共用，保证它们总是在同一个存储里。
enum StoreSchema {
    static let models: [any PersistentModel.Type] = [
        SessionRecord.self, ExerciseRecord.self, SetRecord.self, ExerciseDefinitionRecord.self,
    ]

    static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: [configuration])
    }
}

/// 训练记录仓储与动作库仓储，共用**同一个**容器 / 存储文件。
public enum TrainingRecordStore {
    /// 内存模式：每次调用得到互相独立的一对仓储，数据只在存活期间存在。
    public static func inMemory() throws -> (workouts: SwiftDataWorkoutRepository, library: SwiftDataExerciseLibraryRepository) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try repositories(for: configuration)
    }

    /// 磁盘模式：`url` 是存储文件位置；父目录不存在时先创建。
    /// 能直接打开旧版（只有训练记录、没有动作 id 和动作库）创建的存储文件，打开时自动迁移，不丢数据。
    public static func onDisk(url: URL) throws -> (workouts: SwiftDataWorkoutRepository, library: SwiftDataExerciseLibraryRepository) {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try repositories(for: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }

    private static func repositories(
        for configuration: ModelConfiguration
    ) throws -> (workouts: SwiftDataWorkoutRepository, library: SwiftDataExerciseLibraryRepository) {
        let container = try StoreSchema.makeContainer(configuration)
        return (
            SwiftDataWorkoutRepository(modelContainer: container),
            SwiftDataExerciseLibraryRepository(modelContainer: container)
        )
    }
}
