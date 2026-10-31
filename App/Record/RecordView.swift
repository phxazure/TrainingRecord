import SwiftUI
import TrainingRecordCore

/// 录入界面：日期、动作列表（每个动作的组与添加组输入）、添加动作、保存。
/// 只做展示与绑定，规则全部在 `RecordViewModel`。
struct RecordView: View {
    @Bindable var model: RecordViewModel

    @State private var newExerciseName = ""
    @State private var exerciseNameRejected = false
    @State private var saveFailed = false
    @State private var showSavedToast = false
    @State private var saveCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日期", selection: $model.date, displayedComponents: .date)
                        .accessibilityIdentifier(RecordAccessibilityID.datePicker)
                }

                if model.exercises.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("还没有动作", systemImage: "dumbbell")
                        } description: {
                            Text("在下方添加一个动作，再为它记录每组的重量和次数。")
                        }
                    }
                }

                ForEach(model.exercises) { exercise in
                    ExerciseSection(model: model, exercise: exercise)
                }

                addExerciseSection

                if saveFailed {
                    Section {
                        Label("保存失败，请重试", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(model.isSaving)
            .navigationTitle("记录训练")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(!model.canSave || model.isSaving)
                        .accessibilityIdentifier(RecordAccessibilityID.saveButton)
                }
            }
            .overlay(alignment: .bottom) {
                if showSavedToast {
                    SavedToast()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: showSavedToast)
            .sensoryFeedback(.success, trigger: saveCount)
        }
    }

    private var addExerciseSection: some View {
        Section {
            HStack {
                TextField("动作名称，如「卧推」", text: $newExerciseName)
                    .submitLabel(.done)
                    .onSubmit(addExercise)
                    .accessibilityIdentifier(RecordAccessibilityID.exerciseNameField)
                Button(action: addExercise) {
                    Label("添加动作", systemImage: "plus.circle.fill")
                        .labelStyle(.iconOnly)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .disabled(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier(RecordAccessibilityID.addExerciseButton)
            }
        } header: {
            Text("添加动作")
        } footer: {
            if exerciseNameRejected {
                Text("动作名不能为空，也不能与已有动作重复。")
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: newExerciseName) {
            exerciseNameRejected = false
        }
    }

    private func addExercise() {
        if model.addExercise(name: newExerciseName) {
            newExerciseName = ""
            exerciseNameRejected = false
        } else {
            exerciseNameRejected = true
        }
    }

    private func save() {
        Task {
            do {
                try await model.save()
                saveFailed = false
                saveCount += 1
                showSavedToast = true
                try? await Task.sleep(for: .seconds(1.5))
                showSavedToast = false
            } catch {
                saveFailed = true
            }
        }
    }
}

/// 保存成功后的轻量提示。
private struct SavedToast: View {
    var body: some View {
        Label("已保存", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom)
            .accessibilityIdentifier(RecordAccessibilityID.savedToast)
    }
}

#Preview {
    RecordView(model: RecordViewModel(repository: InMemoryWorkoutRepository()))
}
