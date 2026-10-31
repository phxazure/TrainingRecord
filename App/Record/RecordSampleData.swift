#if DEBUG
import Foundation
import TrainingRecordCore

/// 仅 DEBUG：用启动参数 `-seedRecordSample` 预填录入样例，用于截图与手动验证。
/// 整个文件在 Release 构建中不参与编译，Release 不含样例数据。
enum RecordSampleData {
    static let launchArgument = "-seedRecordSample"

    @MainActor
    static func seedIfRequested(_ model: RecordViewModel, arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains(launchArgument) else { return }
        let sample: [(name: String, sets: [(weight: String, reps: String)])] = [
            ("卧推", [("60", "10"), ("65", "8"), ("70", "6")]),
            ("深蹲", [("100", "5"), ("102.5", "5")]),
        ]
        for exercise in sample {
            guard model.addExercise(name: exercise.name), let id = model.exercises.last?.id else { continue }
            for set in exercise.sets {
                model.addSet(toExercise: id, weightText: set.weight, repsText: set.reps)
            }
        }
    }
}
#endif
