import SwiftUI
import TrainingRecordCore
import TrainingRecordPersistence

@main
struct TrainingRecordApp: App {
    /// 本地存储（失败时退回内存仓储）。整个 App 生命周期只打开一次。
    private let storage: LaunchStorage
    @State private var model: AppModel

    init() {
        let storage = LaunchStorage.open()
        self.storage = storage
        _model = State(
            initialValue: AppModel(
                repository: storage.repository,
                libraryRepository: storage.library,
                photos: storage.photos
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            // 提示条放在 ContentView 上方的独立一行，而不是盖在它上面：
            // 这样不会遮住各页导航栏里的按钮（如「保存」）。
            VStack(spacing: 0) {
                if let warning = storage.warning {
                    StorageWarningBanner(message: warning)
                }
                ContentView()
            }
            .environment(model)
            // 启动：回填一次（数据迁移，幂等，失败只标记不崩溃），然后加载数据。
            .task { await model.start() }
        }
    }
}

/// 启动时选定的仓储，以及（仅当退回内存仓储时）要给用户看的提示。
struct LaunchStorage {
    let repository: any ConditionalSessionUpdating
    let library: any ExerciseLibraryRepository
    let photos: ExercisePhotoStore
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
        // 只能用内存仓储，绝不污染真实的本地存储（照片也放临时目录）。必须在创建持久容器之前决定。
        if DebugLaunch.usesInMemoryStorage(arguments: ProcessInfo.processInfo.arguments) {
            return LaunchStorage(
                repository: InMemoryWorkoutRepository(),
                library: InMemoryExerciseLibraryRepository(),
                photos: .temporary(),
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

    /// 打开失败时不崩溃：退回内存仓储，并带上提示文案。
    static func open(
        at url: URL,
        openOnDisk: (URL) throws -> (any ConditionalSessionUpdating, any ExerciseLibraryRepository)
    ) -> LaunchStorage {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-simulateStoreOpenFailure") {
                throw CocoaError(.fileWriteUnknown)
            }
            #endif
            let (repository, library) = try openOnDisk(url)
            return LaunchStorage(repository: repository, library: library, photos: .standard, warning: nil)
        } catch {
            return LaunchStorage(
                repository: InMemoryWorkoutRepository(),
                library: InMemoryExerciseLibraryRepository(),
                photos: .temporary(),
                warning: openFailureMessage
            )
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
