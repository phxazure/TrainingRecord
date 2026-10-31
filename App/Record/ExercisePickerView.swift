import SwiftUI
import TrainingRecordCore

/// 选择动作（训练页 push 进来）：按部位分组 + 搜索 + 「新建动作」。点一个动作加进当前训练并返回。
struct ExercisePickerView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [ExerciseDefinition] {
        guard !trimmedQuery.isEmpty else { return app.library.exercises }
        return app.library.exercises.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private func isAdded(_ exercise: ExerciseDefinition) -> Bool {
        app.record.exercises.contains { app.record.exerciseID(of: $0.id) == exercise.id }
    }

    var body: some View {
        List {
            Section {
                NavigationLink(value: ExerciseEditRoute(addToRecord: true, prefillName: trimmedQuery)) {
                    Label(trimmedQuery.isEmpty ? "新建动作" : "新建动作「\(trimmedQuery)」", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .frame(minHeight: Space.hit, alignment: .leading)
                }
                .accessibilityIdentifier(PickerAccessibilityID.newButton)
            }

            if app.library.exercises.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("动作库是空的", systemImage: "dumbbell")
                    } description: {
                        Text("先新建一个动作，之后就能直接从这里选。")
                    }
                    .accessibilityIdentifier(PickerAccessibilityID.emptyState)
                }
            } else if filtered.isEmpty {
                Section {
                    ContentUnavailableView.search(text: trimmedQuery)
                        .accessibilityIdentifier(PickerAccessibilityID.emptyState)
                }
            } else {
                ForEach(groupByBodyPart(filtered), id: \.bodyPart) { group in
                    Section {
                        ForEach(group.exercises) { exercise in
                            row(exercise)
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索动作")
        .navigationTitle("选择动作")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(PickerAccessibilityID.root)
    }

    private func row(_ exercise: ExerciseDefinition) -> some View {
        let added = isAdded(exercise)
        return Button {
            guard !added else { return }
            app.record.addExercise(exercise)
            app.recordPath = NavigationPath()
        } label: {
            HStack(spacing: Space.s3) {
                ExercisePhotoView(fileName: exercise.photoFileName, size: Metrics.photoThumbnail)
                Text(exercise.name)
                    .font(.headline)
                    .foregroundStyle(added ? Color.labelDisabled : Color.primary)
                Spacer(minLength: 0)
                if added {
                    Text("已添加")
                        .font(.footnote)
                        .foregroundStyle(.label2)
                }
            }
            .frame(minHeight: Space.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .accessibilityIdentifier(PickerAccessibilityID.row)
    }
}
