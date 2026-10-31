import SwiftUI
import TrainingRecordCore

/// 全 App 共用的状态：训练草稿、历史、动作库、四个标签各自的导航路径。
/// 视图通过 `@Environment(AppModel.self)` 取用。
@MainActor @Observable
final class AppModel {
    let repository: any ConditionalSessionUpdating
    let history: HistoryViewModel
    let library: LibraryStore
    let record: RecordViewModel

    var selectedTab: AppTab = .record
    var recordPath = NavigationPath()
    var libraryPath = NavigationPath()
    var historyPath = NavigationPath()
    var trendPath = NavigationPath()

    /// 每次刷新（改名、合并、删除、保存训练、切标签）后自增；视图用 `.task(id:)` 据此重新加载自己的派生数据。
    private(set) var dataRevision = 0

    init(
        repository: any ConditionalSessionUpdating,
        libraryRepository: any ExerciseLibraryRepository,
        photos: ExercisePhotoStore
    ) {
        self.repository = repository
        history = HistoryViewModel(repository: repository)
        library = LibraryStore(
            service: ExerciseLibraryService(library: libraryRepository, workouts: repository),
            repository: libraryRepository,
            photos: photos
        )
        #if DEBUG
        record = RecordViewModel(repository: RecordSaveSimulation.wrap(repository))
        #else
        record = RecordViewModel(repository: repository)
        #endif
    }

    /// 内存里的一份，给 Preview 用。
    static func preview() -> AppModel {
        AppModel(
            repository: InMemoryWorkoutRepository(),
            libraryRepository: InMemoryExerciseLibraryRepository(),
            photos: .temporary()
        )
    }

    // MARK: 启动与刷新

    /// 启动：回填一次（数据迁移）→ 加载数据。DEBUG 下样例数据写完后再回填一次，保证样例条目有动作库 id。
    func start() async {
        #if DEBUG
        await DebugLaunch.seedData(self)
        #endif
        await library.runBackfill()
        await refresh()
        #if DEBUG
        await DebugLaunch.applyUI(self)
        #endif
    }

    /// 重新加载历史与动作库。
    func refresh() async {
        await history.reload()
        await library.reload()
        dataRevision += 1
    }

    /// 当前标签回到根页面（删除 / 合并动作后，被删动作的详情页不能再留在栈里）。
    func popToRoot() {
        switch selectedTab {
        case .record: recordPath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        case .history: historyPath = NavigationPath()
        case .trend: trendPath = NavigationPath()
        }
    }

    // MARK: 训练页的建议（T008 的查询）

    func recentExercises(limit: Int) async -> [ExerciseDefinition] {
        (try? await library.service.recentExercises(limit: limit)) ?? []
    }

    func lastSessionTemplate() async -> SessionTemplate? {
        (try? await library.service.lastSessionTemplate()) ?? nil
    }
}
