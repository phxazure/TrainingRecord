import SwiftUI
import TrainingRecordCore

@main
struct TrainingRecordApp: App {
    /// 本阶段用内存仓储；换成本地持久化时只改这里，界面与 ViewModel 不变。
    private let repository: any WorkoutRepository = InMemoryWorkoutRepository()

    var body: some Scene {
        WindowGroup { ContentView(repository: repository) }
    }
}
