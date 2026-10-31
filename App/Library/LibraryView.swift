import SwiftUI
import TrainingRecordCore

/// 「动作库」标签：按训练部位分组的动作列表；右上「+」新建；点行进入动作详情。
struct LibraryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.libraryPath) {
            content
                .navigationTitle("动作库")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink(value: ExerciseEditRoute()) {
                            Label("新建动作", systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .frame(minWidth: Space.hit, minHeight: Space.hit)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier(LibraryAccessibilityID.addButton)
                    }
                }
                .exerciseDestinations()
        }
    }

    @ViewBuilder
    private var content: some View {
        if app.library.exercises.isEmpty {
            ContentUnavailableView {
                Label("动作库是空的", systemImage: "dumbbell")
            } description: {
                Text("添加你常做的动作，设置训练部位和照片。记录训练时直接从这里选。")
            } actions: {
                NavigationLink(value: ExerciseEditRoute()) {
                    Text("新建动作")
                }
                .buttonStyle(ProminentCapsuleButtonStyle())
                .accessibilityIdentifier(LibraryAccessibilityID.emptyAddButton)
            }
            // 先声明为容器再加 id：否则 id 会下传给子按钮，覆盖 emptyAddButton。
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(LibraryAccessibilityID.emptyState)
        } else {
            List {
                ForEach(groupByBodyPart(app.library.exercises), id: \.bodyPart) { group in
                    Section {
                        ForEach(group.exercises) { exercise in
                            NavigationLink(value: ExerciseRoute(id: exercise.id)) {
                                LibraryRow(exercise: exercise, sessionCount: sessionCount(of: exercise.id, in: app.history.sessions))
                            }
                            .accessibilityIdentifier(LibraryAccessibilityID.row)
                        }
                    } header: {
                        Text(group.bodyPart)
                            .font(.footnote)
                            .foregroundStyle(.label2)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier(LibraryAccessibilityID.list)
        }
    }
}

/// 动作库的一行：照片缩略图（或占位图标）、名字、训练次数。
private struct LibraryRow: View {
    let exercise: ExerciseDefinition
    let sessionCount: Int

    var body: some View {
        HStack(spacing: Space.s3) {
            ExercisePhotoView(fileName: exercise.photoFileName, size: Metrics.photoThumbnail)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(exercise.name)
                    .font(.headline)
                Text(sessionCount == 0 ? "还没有记录" : "\(sessionCount) 次训练")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// 每个标签的 NavigationStack 都注册同样的二级页面：动作详情、动作编辑、合并记录选目标。
    /// 动作详情只有这一个视图，四处入口共用。
    func exerciseDestinations() -> some View {
        navigationDestination(for: ExerciseRoute.self) { route in
            ExerciseDetailView(exerciseID: route.id)
        }
        .navigationDestination(for: ExerciseEditRoute.self) { route in
            ExerciseEditView(route: route)
        }
        .navigationDestination(for: MergePickerRoute.self) { route in
            MergePickerView(sourceID: route.sourceID)
        }
    }
}
