import SwiftUI
import TrainingRecordCore

/// 「记录」标签：日期、动作卡片列表、添加动作；右上角保存，成功/失败在底部提示条反馈。
/// 只做展示与绑定，规则全部在 `RecordViewModel`。
struct RecordView: View {
    @Bindable var model: RecordViewModel

    @State private var toast: RecordToast?
    /// 每次出示新提示条自增：用于让「2 秒后淡出」只作用于当次提示条。
    @State private var toastToken = 0
    @State private var successCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("日期", selection: $model.date, displayedComponents: .date)
                        .accessibilityIdentifier(RecordAccessibilityID.datePicker)
                }

                if model.exercises.isEmpty {
                    Section { EmptyRecordCard() }
                }

                ForEach(model.exercises) { exercise in
                    ExerciseCard(model: model, exercise: exercise)
                }

                AddExerciseSection(model: model)
                    #if DEBUG
                    .recordScrollDebugAnchor()
                    #endif
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            #if DEBUG
            .modifier(RecordScrollDebug.ScrollToBottomOnLaunch())
            #endif
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    SaveButton(isSaving: model.isSaving, canSave: model.canSave, action: save)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: Space.s3) {
                if let toast {
                    ToastView(toast: toast, retry: save, dismiss: dismissToast)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: Metrics.metricFadeDuration) : .spring(duration: Metrics.toastSpringDuration),
                value: toast
            )
            .sensoryFeedback(.success, trigger: successCount)
        }
    }

    private func save() {
        Task {
            do {
                let session = try await model.save()
                successCount += 1
                let setCount = session.exercises.reduce(0) { $0 + $1.sets.count }
                show(.saved(setCount: setCount, volume: totalVolume(of: session)), autoDismiss: true)
            } catch RecordSaveError.saveInProgress {
                // 已有保存在进行，按钮此时不可点；忽略。
            } catch {
                show(.failed, autoDismiss: false)
            }
        }
    }

    private func show(_ newToast: RecordToast, autoDismiss: Bool) {
        toastToken += 1
        let token = toastToken
        toast = newToast
        guard autoDismiss else { return }
        Task {
            try? await Task.sleep(for: .seconds(Metrics.toastSeconds))
            if token == toastToken { toast = nil }
        }
    }

    private func dismissToast() {
        toastToken += 1
        toast = nil
    }
}

/// 保存按钮（§8.1）：default / disabled / loading（`ProgressView` +「保存中」，不可点）。
private struct SaveButton: View {
    let isSaving: Bool
    let canSave: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSaving {
                HStack(spacing: Space.s2) {
                    ProgressView().tint(Color.onTint)
                    Text("保存中")
                }
            } else {
                Text("保存")
            }
        }
        .buttonStyle(ProminentCapsuleButtonStyle())
        .disabled(!canSave || isSaving)
        .accessibilityIdentifier(RecordAccessibilityID.saveButton)
    }
}

/// 「记录」空状态（§8.8）：还没有任何动作。
private struct EmptyRecordCard: View {
    var body: some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, Space.s2)
                .accessibilityHidden(true)
            Text("开始记录今天的训练")
                .font(.headline)
            Text("添加第一个动作，再逐组记下重量和次数。")
                .font(.subheadline)
                .foregroundStyle(.label2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s8)
        .accessibilityElement(children: .combine)
    }
}

/// 添加动作：输入框 + 「添加」。名称为空时按钮禁用且不提示；重名时行内提示。
private struct AddExerciseSection: View {
    let model: RecordViewModel

    @State private var name = ""
    @State private var duplicateName: String?

    var body: some View {
        Section {
            HStack(spacing: Space.s2) {
                InputField(
                    placeholder: "动作名称，如 卧推",
                    text: $name,
                    isError: duplicateName != nil,
                    onSubmit: add,
                    identifier: RecordAccessibilityID.exerciseNameField
                )
                Button("添加", action: add)
                    .buttonStyle(ProminentCapsuleButtonStyle())
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier(RecordAccessibilityID.addExerciseButton)
            }
            if let duplicateName {
                InlineError(message: "本次训练已有「\(duplicateName)」")
                    .accessibilityIdentifier(RecordAccessibilityID.exerciseNameError)
            }
        } header: {
            Text("添加动作")
                .font(.footnote)
                .foregroundStyle(.label2)
                .textCase(nil)
        }
        .onChange(of: name) { duplicateName = nil }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let candidate = trimmedName
        guard !candidate.isEmpty else { return }
        if model.addExercise(name: candidate) {
            name = ""
            duplicateName = nil
        } else {
            duplicateName = candidate
        }
    }
}

#Preview {
    RecordView(model: RecordViewModel(repository: InMemoryWorkoutRepository()))
}
