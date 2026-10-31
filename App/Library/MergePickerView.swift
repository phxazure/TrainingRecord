import SwiftUI
import TrainingRecordCore

/// 合并记录：先选目标动作，再弹确认。
/// 合并 = 把「源动作」的所有训练记录并入「目标动作」，源动作从动作库删除。
struct MergePickerView: View {
    @Environment(AppModel.self) private var app
    let sourceID: UUID

    @State private var pending: ExerciseDefinition?
    @State private var failed = false

    private var source: ExerciseDefinition? { app.library.definition(id: sourceID) }
    private var others: [ExerciseDefinition] { app.library.exercises.filter { $0.id != sourceID } }
    private var sourceSessionCount: Int { sessionCount(of: sourceID, in: app.history.sessions) }

    var body: some View {
        List {
            Section {
                Text("合并记录：把「\(source?.name ?? "")」的训练记录并入你选的动作，之后「\(source?.name ?? "")」会从动作库删除。适用于同一个动作被记成了两个名字。")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            if others.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("没有其他动作", systemImage: "dumbbell")
                    } description: {
                        Text("动作库里只有这一个动作，没有可以合并到的目标。")
                    }
                }
            } else {
                ForEach(groupByBodyPart(others), id: \.bodyPart) { group in
                    Section {
                        ForEach(group.exercises) { exercise in
                            Button { pending = exercise } label: {
                                HStack(spacing: Space.s3) {
                                    ExercisePhotoView(fileName: exercise.photoFileName, size: Metrics.photoThumbnail)
                                    Text(exercise.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(MergePickerAccessibilityID.row)
                        }
                    } header: {
                        Text(group.bodyPart)
                            .font(.footnote)
                            .foregroundStyle(.label2)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("选择要并入的动作")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(MergePickerAccessibilityID.root)
        .alert(
            "合并记录",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { target in
            Button("合并", role: .destructive) { merge(into: target) }
            Button("取消", role: .cancel) {}
        } message: { target in
            Text(Self.confirmationMessage(source: source?.name ?? "", count: sourceSessionCount, target: target.name))
        }
        .alert("合并失败", isPresented: $failed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("两个动作都没有改动，请稍后再试。")
        }
        #if DEBUG
        .task { pending = await DebugLaunch.mergeConfirmTarget(from: others) }
        #endif
    }

    /// 确认文案（逐字，来自任务单）。N = 源动作出现的训练场次数。
    static func confirmationMessage(source: String, count: Int, target: String) -> String {
        "把「\(source)」的 \(count) 次训练记录并入「\(target)」，之后「\(source)」会从动作库删除。适用于同一个动作被记成了两个名字。此操作不能撤销。"
    }

    private func merge(into target: ExerciseDefinition) {
        Task {
            do {
                try await app.library.merge(sourceID: sourceID, into: target.id)
                await app.refresh()
                app.popToRoot()
            } catch {
                await app.refresh()
                failed = true
            }
        }
    }
}
