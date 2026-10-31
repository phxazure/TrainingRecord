import SwiftUI
import TrainingRecordCore

/// 根视图：标签页（记录 / 历史 / 趋势，§7）。
struct ContentView: View {
    let repository: any WorkoutRepository
    @State private var recordModel: RecordViewModel
    @State private var historyModel: HistoryViewModel
    @State private var selectedTab: Tab = .record
    /// 趋势标签当前选中的动作；明细里的「查看趋势」会改它。
    @State private var trendExercise: String?

    enum Tab: Hashable {
        case record
        case history
        case trend
    }

    init(repository: any WorkoutRepository) {
        self.repository = repository
        #if DEBUG
        let record = RecordViewModel(repository: RecordSaveSimulation.wrap(repository))
        #else
        let record = RecordViewModel(repository: repository)
        #endif
        #if DEBUG
        RecordSampleData.seedIfRequested(record)
        RecordScrollDebug.seedIfRequested(record)
        #endif
        _recordModel = State(initialValue: record)
        _historyModel = State(initialValue: HistoryViewModel(repository: repository))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordView(model: recordModel)
                .tabItem { Label("记录", systemImage: "square.and.pencil") }
                .tag(Tab.record)

            HistoryView(
                model: historyModel,
                goToRecord: { selectedTab = .record },
                openTrend: { exercise in
                    trendExercise = exercise
                    selectedTab = .trend
                }
            )
            .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            .tag(Tab.history)

            TrendView(model: historyModel, selectedExercise: $trendExercise)
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trend)
        }
        // 每次切到「历史」「趋势」都重新加载，保证刚在「记录」保存的训练能看到。
        .onChange(of: selectedTab) { _, newValue in
            if newValue != .record {
                Task { await historyModel.reload() }
            }
        }
        #if DEBUG
        .task {
            await HistoryDebugLaunch.seedIfRequested(repository)
            if let exercise = HistoryDebugLaunch.trendExercise { trendExercise = exercise }
            if let tab = HistoryDebugLaunch.initialTab { selectedTab = tab }
        }
        #endif
    }
}

#Preview { ContentView(repository: InMemoryWorkoutRepository()) }
