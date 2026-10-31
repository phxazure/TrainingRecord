import SwiftUI
import TrainingRecordCore

/// 根视图：四个标签（训练 / 动作库 / 历史 / 趋势）。每个标签是一个 NavigationStack，二级内容用「点进去」，不用分段切换。
struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            RecordView()
                .tabItem { Label("训练", systemImage: "square.and.pencil") }
                .tag(AppTab.record)

            LibraryView()
                .tabItem { Label("动作库", systemImage: "dumbbell") }
                .tag(AppTab.library)

            HistoryView()
                .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            TrendView()
                .tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.trend)
        }
        // 每次切标签都重新加载，保证改名 / 合并 / 删除 / 刚保存的训练在各页立即反映。
        .onChange(of: app.selectedTab) {
            Task { await app.refresh() }
        }
    }
}

#Preview {
    ContentView().environment(AppModel.preview())
}
