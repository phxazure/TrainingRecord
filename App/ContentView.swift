import SwiftUI
import TrainingRecordCore

/// 根视图：标签页（记录 / 历史）。
struct ContentView: View {
    let repository: any WorkoutRepository
    @State private var recordModel: RecordViewModel
    @State private var historyModel: HistoryViewModel
    @State private var selectedTab: Tab = .record

    enum Tab: Hashable {
        case record
        case history
    }

    init(repository: any WorkoutRepository) {
        self.repository = repository
        let record = RecordViewModel(repository: repository)
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

            HistoryView(model: historyModel)
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        // 每次切到「历史」都重新加载，保证刚在「记录」保存的训练能看到。
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .history {
                Task { await historyModel.reload() }
            }
        }
        #if DEBUG
        .task {
            await HistoryDebugLaunch.seedIfRequested(repository)
            if HistoryDebugLaunch.opensHistoryTab {
                selectedTab = .history
            }
        }
        #endif
        // 界面文案只有中文；App 包尚未声明 zh-Hans 本地化（开发区域为 en），
        // 不显式指定时日期等系统格式会按英文显示，与中文界面不一致。
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }
}

#if DEBUG
/// 仅 DEBUG：`-recordScrollToBottom` 让「记录」页多填两个动作（RecordView 据此初始滚到底部），
/// 用于截图验证最后一个输入区不被底部标签栏遮挡。Release 不参与编译。
private enum RecordScrollDebug {
    static let launchArgument = "-recordScrollToBottom"

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    @MainActor
    static func seedIfRequested(_ model: RecordViewModel) {
        guard isRequested else { return }
        let extra: [(name: String, sets: [(weight: String, reps: String)])] = [
            ("硬拉", [("120", "5"), ("130", "3")]),
            ("引体向上", [("0", "10"), ("0", "8"), ("0", "6")]),
        ]
        for exercise in extra {
            guard model.addExercise(name: exercise.name), let id = model.exercises.last?.id else { continue }
            for set in exercise.sets {
                model.addSet(toExercise: id, weightText: set.weight, repsText: set.reps)
            }
        }
    }
}
#endif

#Preview { ContentView(repository: InMemoryWorkoutRepository()) }
