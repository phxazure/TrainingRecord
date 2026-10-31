#if DEBUG
import SwiftUI
import TrainingRecordCore

/// 仅 DEBUG：截图与手动验证用的启动参数。整个文件在 Release 中不参与编译，Release 不含任何这些参数。
///
/// 会注入样例数据的参数（`sampleDataArguments`）一律改用内存仓储 + 临时照片目录，绝不写真实的本地存储。
///
/// - `-seedLibrarySample`：预填动作库（带训练部位，卧推带 1 张示例照片）+ 样例训练历史；
///   样例写完后再回填一次，保证样例训练里的动作都有动作库 id。
/// - `-uiScreen <名称>`：启动后直达某个界面：
///   record（训练页）、recordFilled（已添加动作）、picker（选择动作）、library、libraryDetail、libraryEdit、
///   mergePicker、history、historyDetail、historyExercise（历史明细 → 动作详情）、trend、trendDetail。
/// - `-uiDialog scrollBottom`：编辑页滚到底（看「合并记录」「删除动作」）。
/// - `-uiDialog deleteRejected|mergeConfirm`：在编辑页弹出「删除被拒」提示 / 在合并页弹出确认框。
/// - `-simulateBackfillFailure`：回填抛错，看训练页顶部提示。
enum DebugLaunch {
    static let seedLibraryArgument = "-seedLibrarySample"
    static let screenArgument = "-uiScreen"
    static let dialogArgument = "-uiDialog"

    /// 会注入样例 / 预填草稿的参数：带任何一个都只用内存仓储。新增这类参数必须加到这里。
    static let sampleDataArguments: Set<String> = [
        HistoryDebugLaunch.seedArgument,  // -seedHistorySample：直接写仓储
        RecordSampleData.launchArgument,  // -seedRecordSample：预填草稿，保存即写仓储
        RecordScrollDebug.launchArgument,  // -recordScrollToBottom：预填两个动作的草稿
        seedLibraryArgument,  // -seedLibrarySample：写动作库、照片与历史
        screenArgument,  // -uiScreen recordFilled 会预填草稿
    ]

    static func usesInMemoryStorage(arguments: [String]) -> Bool {
        !sampleDataArguments.isDisjoint(with: arguments)
    }

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    private static func value(after argument: String) -> String? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var screen: String? { value(after: screenArgument) }
    static var dialog: String? { value(after: dialogArgument) }

    // MARK: 数据

    @MainActor
    static func seedData(_ app: AppModel) async {
        RecordSampleData.seedIfRequested(app.record)
        RecordScrollDebug.seedIfRequested(app.record)
        await HistoryDebugLaunch.seedIfRequested(app.repository)
        guard arguments.contains(seedLibraryArgument) || screen != nil else { return }
        if arguments.contains(seedLibraryArgument) || arguments.contains(HistoryDebugLaunch.seedArgument) == false {
            await seedLibrary(app)
        }
    }

    /// 动作库样例：先写带部位的条目，再写样例训练；调用方随后会回填，把训练里的动作关联到这些条目。
    @MainActor
    private static func seedLibrary(_ app: AppModel) async {
        let parts: [(String, String)] = [
            ("卧推", "胸"), ("杠铃卧推", "胸"), ("深蹲", "腿"), ("硬拉", "背"), ("推举", "肩"), ("引体向上", "背"), ("平板支撑", "核心"),
        ]
        for (name, part) in parts {
            var photo: String?
            if name == "卧推", let data = samplePhotoData() {
                let created = try? await app.library.service.add(name: name, bodyPart: part, photoFileName: nil)
                if let created, let file = try? app.library.photos.save(imageData: data, exerciseID: created.id) {
                    photo = file
                    _ = try? await app.library.service.update(id: created.id, name: name, bodyPart: part, photoFileName: photo)
                }
                continue
            }
            _ = try? await app.library.service.add(name: name, bodyPart: part, photoFileName: nil)
        }
        if !arguments.contains(HistoryDebugLaunch.seedArgument) {
            await HistoryDebugLaunch.seedSessions(app.repository)
        }
    }

    /// 示例照片：画一张渐变底 + 哑铃符号的图（不依赖任何外部文件）。
    private static func samplePhotoData() -> Data? {
        let size = CGSize(width: 1600, height: 1200)  // 故意超过 1024，验证缩放
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemIndigo.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: 520, weight: .bold)
            if let symbol = UIImage(systemName: "dumbbell.fill", withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2))
            }
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    // MARK: 导航

    @MainActor
    static func applyUI(_ app: AppModel) async {
        guard let screen else { return }
        let bench = app.library.exercises.first { $0.name == "卧推" }
        switch screen {
        case "record":
            app.selectedTab = .record
        case "recordFilled":
            app.selectedTab = .record
            for (name, sets) in [("卧推", [("60", "10"), ("65", "8"), ("70", "6")]), ("深蹲", [("100", "5"), ("102.5", "5")])] {
                guard let definition = app.library.exercises.first(where: { $0.name == name }),
                      app.record.addExercise(definition), let id = app.record.exercises.last?.id
                else { continue }
                for set in sets { app.record.addSet(toExercise: id, weightText: set.0, repsText: set.1) }
            }
        case "picker":
            app.selectedTab = .record
            app.recordPath.append(RecordRoute.picker)
        case "library":
            app.selectedTab = .library
        case "libraryDetail":
            app.selectedTab = .library
            if let bench { app.libraryPath.append(ExerciseRoute(id: bench.id)) }
        case "libraryEdit":
            app.selectedTab = .library
            if let bench {
                app.libraryPath.append(ExerciseRoute(id: bench.id))
                app.libraryPath.append(ExerciseEditRoute(id: bench.id))
            }
        case "mergePicker":
            app.selectedTab = .library
            if let bench {
                app.libraryPath.append(ExerciseRoute(id: bench.id))
                app.libraryPath.append(ExerciseEditRoute(id: bench.id))
                app.libraryPath.append(MergePickerRoute(sourceID: bench.id))
            }
        case "history":
            app.selectedTab = .history
        case "historyDetail", "historyExercise":
            app.selectedTab = .history
            if let first = app.history.rows.first {
                app.historyPath.append(first.id)
                if screen == "historyExercise", let bench { app.historyPath.append(ExerciseRoute(id: bench.id)) }
            }
        case "trend":
            app.selectedTab = .trend
        case "trendDetail":
            app.selectedTab = .trend
            if let bench { app.trendPath.append(ExerciseRoute(id: bench.id)) }
        default:
            break
        }
        if HistoryDebugLaunch.opensFirstSession, let first = app.history.rows.first {
            app.selectedTab = .history
            app.historyPath.append(first.id)
        }
    }

    /// 编辑页：按 `-uiDialog deleteRejected` 弹出「无法删除」。
    static func presentEditDialog(showRejected: @MainActor () -> Void) async {
        guard dialog == "deleteRejected" else { return }
        try? await Task.sleep(for: .milliseconds(700))
        await showRejected()
    }

    /// 合并页：按 `-uiDialog mergeConfirm` 直接对「杠铃卧推」弹出确认。
    static func mergeConfirmTarget(from candidates: [ExerciseDefinition]) async -> ExerciseDefinition? {
        guard dialog == "mergeConfirm" else { return nil }
        try? await Task.sleep(for: .milliseconds(700))
        return candidates.first { $0.name == "杠铃卧推" } ?? candidates.first
    }
}
#endif
