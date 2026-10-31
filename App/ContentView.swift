import SwiftUI
import TrainingRecordCore

/// 根视图：标签页。本单只有「记录」；「历史」由后续任务加入。
struct ContentView: View {
    let repository: any WorkoutRepository
    @State private var recordModel: RecordViewModel

    init(repository: any WorkoutRepository) {
        self.repository = repository
        let model = RecordViewModel(repository: repository)
        #if DEBUG
        RecordSampleData.seedIfRequested(model)
        #endif
        _recordModel = State(initialValue: model)
    }

    var body: some View {
        TabView {
            RecordView(model: recordModel)
                .tabItem { Label("记录", systemImage: "square.and.pencil") }
        }
        // 界面文案只有中文；App 包尚未声明 zh-Hans 本地化（开发区域为 en），
        // 不显式指定时日期等系统格式会按英文显示，与中文界面不一致。
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }
}

#Preview { ContentView(repository: InMemoryWorkoutRepository()) }
