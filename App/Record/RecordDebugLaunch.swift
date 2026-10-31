#if DEBUG
import SwiftUI
import TrainingRecordCore

/// 仅 DEBUG、且仅带启动参数 `-recordScrollToBottom` 时生效的截图辅助：
/// 「记录」页多填两个动作，并在启动后滚到最后一个输入区，用于截图验证它不被底部标签栏遮挡。
/// 不带参数时不加 `.id`、不包 `ScrollViewReader`；整个文件在 Release 中不参与编译。
enum RecordScrollDebug {
    static let launchArgument = "-recordScrollToBottom"
    static let anchorID = "recordScrollDebug.addExerciseSection"

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

    struct ScrollToBottomOnLaunch: ViewModifier {
        func body(content: Content) -> some View {
            if RecordScrollDebug.isRequested {
                ScrollViewReader { proxy in
                    content.task {
                        try? await Task.sleep(for: .milliseconds(500))
                        proxy.scrollTo(RecordScrollDebug.anchorID, anchor: .bottom)
                    }
                }
            } else {
                content
            }
        }
    }
}

extension View {
    @ViewBuilder
    func recordScrollDebugAnchor() -> some View {
        if RecordScrollDebug.isRequested {
            id(RecordScrollDebug.anchorID)
        } else {
            self
        }
    }
}
#endif

#if DEBUG
/// 仅 DEBUG 的保存行为模拟，用于截图与手动验证 §8.1 / §8.7 的状态：
/// - `-simulateSlowSave`：保存前等 3 秒（看「保存中」）。
/// - `-simulateSaveFailure`：第一次保存失败，之后的保存正常（看失败提示条与「重试」）。
/// 只包装「记录」页用的仓储，不改变其他页面；Release 不参与编译。
enum RecordSaveSimulation {
    static let slowArgument = "-simulateSlowSave"
    static let failureArgument = "-simulateSaveFailure"

    static func wrap(_ repository: any WorkoutRepository) -> any WorkoutRepository {
        let arguments = ProcessInfo.processInfo.arguments
        let slow = arguments.contains(slowArgument)
        let failOnce = arguments.contains(failureArgument)
        guard slow || failOnce else { return repository }
        return SimulatedSaveRepository(base: repository, delay: slow ? .seconds(3) : .zero, failOnce: failOnce)
    }
}

private actor SimulatedSaveRepository: WorkoutRepository {
    struct SimulatedFailure: Error {}

    let base: any WorkoutRepository
    let delay: Duration
    var failuresLeft: Int

    init(base: any WorkoutRepository, delay: Duration, failOnce: Bool) {
        self.base = base
        self.delay = delay
        self.failuresLeft = failOnce ? 1 : 0
    }

    func save(_ session: WorkoutSession) async throws {
        try await Task.sleep(for: delay)
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw SimulatedFailure()
        }
        try await base.save(session)
    }

    func session(id: UUID) async throws -> WorkoutSession? { try await base.session(id: id) }
    func allSessions() async throws -> [WorkoutSession] { try await base.allSessions() }
    func delete(id: UUID) async throws { try await base.delete(id: id) }
}
#endif
