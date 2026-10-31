import OSLog
import SwiftUI
import TrainingRecordCore
import TrainingRecordPersistence

@main
struct TrainingRecordApp: App {
    /// 本地存储（失败时退回内存仓储）。整个 App 生命周期只打开一次。
    private let storage = LaunchStorage.open()
    /// 动作库业务操作（T009 的界面会用到）。
    private let libraryService: ExerciseLibraryService

    init() {
        let storage = storage
        libraryService = ExerciseLibraryService(library: storage.library, workouts: storage.repository)
    }

    var body: some Scene {
        WindowGroup {
            // 提示条放在 ContentView 上方的独立一行，而不是盖在它上面：
            // 这样不会遮住各页导航栏里的按钮（如「保存」）。
            VStack(spacing: 0) {
                if let warning = storage.warning {
                    StorageWarningBanner(message: warning)
                }
                ContentView(repository: storage.repository)
            }
            // 启动时回填一次（数据迁移）：把已有历史里的动作关联到动作库。幂等；失败不影响使用。
            .task { await LaunchStorage.backfill(libraryService) }
        }
    }
}

/// 启动时选定的仓储，以及（仅当退回内存仓储时）要给用户看的提示。
struct LaunchStorage {
    let repository: any WorkoutRepository
    let library: any ExerciseLibraryRepository
    let warning: String?

    static let openFailureMessage = "无法打开本地数据，本次记录不会保存"

    /// 本地存储文件位置：Application Support/TrainingRecord/workouts.store（目录由 `onDisk` 创建）。
    static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "TrainingRecord", directoryHint: .isDirectory)
            .appending(path: "workouts.store", directoryHint: .notDirectory)
    }

    static func open() -> LaunchStorage {
        #if DEBUG
        // 截图用的样例数据启动参数会注入样例（预填草稿的，点保存就会写进仓储）：
        // 只能用内存仓储，绝不污染真实的本地存储。必须在创建持久容器之前决定。
        if usesInMemoryStorage(arguments: ProcessInfo.processInfo.arguments) {
            return LaunchStorage(
                repository: InMemoryWorkoutRepository(),
                library: InMemoryExerciseLibraryRepository(),
                warning: nil
            )
        }
        #endif
        return open(at: defaultStoreURL) { url in
            // 训练记录与动作库共用同一个存储文件。
            let store = try TrainingRecordStore.onDisk(url: url)
            return (store.workouts, store.library)
        }
    }

    #if DEBUG
    /// 会注入样例数据的 DEBUG 启动参数。新增任何会预填数据 / 草稿的参数，都要加到这里。
    static let sampleDataArguments: Set<String> = [
        HistoryDebugLaunch.seedArgument,  // -seedHistorySample：直接写仓储
        RecordSampleData.launchArgument,  // -seedRecordSample：预填草稿，保存即写仓储
        "-recordScrollToBottom",  // 预填两个动作的草稿（见 RecordScrollDebug）
    ]

    static func usesInMemoryStorage(arguments: [String]) -> Bool {
        !sampleDataArguments.isDisjoint(with: arguments)
    }
    #endif

    /// 打开失败时不崩溃：退回内存仓储，并带上提示文案。
    static func open(
        at url: URL,
        openOnDisk: (URL) throws -> (any WorkoutRepository, any ExerciseLibraryRepository)
    ) -> LaunchStorage {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-simulateStoreOpenFailure") {
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            let (repository, library) = try openOnDisk(url)
            return LaunchStorage(repository: repository, library: library, warning: nil)
        } catch {
            return LaunchStorage(
                repository: InMemoryWorkoutRepository(),
                library: InMemoryExerciseLibraryRepository(),
                warning: openFailureMessage
            )
        }
    }

    private static let logger = Logger(subsystem: "com.phx.TrainingRecord", category: "ExerciseLibrary")

    /// 启动时的数据迁移：失败不崩溃、不打扰用户，只记日志（界面提示在 T009）。
    static func backfill(_ service: ExerciseLibraryService) async {
        do {
            let created = try await service.backfill()
            logger.info("动作库回填完成，新建 \(created) 个条目")
        } catch {
            logger.error("动作库回填失败：\(String(describing: error))")
        }
    }
}

/// 顶部的持续性提示条：退回内存仓储后，用户须知道本次记录不会保存。
private struct StorageWarningBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(.orange, ignoresSafeAreaEdges: .top)
            .accessibilityIdentifier("app.storageWarning")
    }
}
