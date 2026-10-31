import SwiftUI
import TrainingRecordCore

/// 「记录」标签：日期、动作卡片列表、添加动作；右上角保存，成功/失败在底部提示条反馈。
/// 只做展示与绑定，规则全部在 `RecordViewModel`。
struct RecordView: View {
    @Environment(AppModel.self) private var app

    private var model: RecordViewModel { app.record }
    @State private var recents: [ExerciseDefinition] = []
    @State private var template: SessionTemplate?

    @State private var toast: RecordToast?
    /// 每次出示新提示条自增：用于让「2 秒后淡出」只作用于当次提示条。
    @State private var toastToken = 0
    @State private var successCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var app = app
        @Bindable var model = app.record
        NavigationStack(path: $app.recordPath) {
            List {
                if app.library.backfillFailed {
                    Section {
                        BackfillWarning()
                    }
                }

                Section {
                    DatePicker("日期", selection: $model.date, displayedComponents: .date)
                        .accessibilityIdentifier(RecordAccessibilityID.datePicker)
                }

                if model.exercises.isEmpty {
                    Section {
                        EmptyRecordCard()
                        if let template {
                            CopyLastButton(template: template) {
                                if model.apply(template) { Task { await loadSuggestions() } }
                            }
                        }
                    }
                }

                if !recents.isEmpty {
                    Section {
                        RecentExercisesRow(recents: recents, model: model)
                    } header: {
                        Text("最近动作")
                            .font(.footnote)
                            .foregroundStyle(.label2)
                            .textCase(nil)
                    }
                }

                ForEach(model.exercises) { exercise in
                    ExerciseCard(model: model, exercise: exercise)
                }

                Section {
                    NavigationLink(value: RecordRoute.picker) {
                        Label("添加动作", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                            .frame(minHeight: Space.hit, alignment: .leading)
                    }
                    .accessibilityIdentifier(RecordAccessibilityID.addExerciseButton)
                }
                #if DEBUG
                .recordScrollDebugAnchor()
                #endif
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            #if DEBUG
            .modifier(RecordScrollDebug.ScrollToBottomOnLaunch())
            #endif
            .navigationTitle("训练")
            .navigationDestination(for: RecordRoute.self) { _ in
                ExercisePickerView()
            }
            .exerciseDestinations()
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
        // 草稿的动作数变化（添加 / 删除 / 复制）或数据刷新（保存、改名、合并、删除）后，重新取建议。
        .task(id: "\(app.dataRevision)#\(model.exercises.count)") { await loadSuggestions() }
    }

    private func loadSuggestions() async {
        recents = await app.recentExercises(limit: Metrics.recentExerciseLimit)
        template = await app.lastSessionTemplate()
    }

    private func save() {
        Task {
            do {
                let session = try await model.save()
                successCount += 1
                let setCount = session.exercises.reduce(0) { $0 + $1.sets.count }
                show(.saved(setCount: setCount, volume: totalVolume(of: session)), autoDismiss: true)
                await app.refresh()
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

/// 复制上次训练（P3）：次要按钮，文案带上日期和动作名。
private struct CopyLastButton: View {
    let template: SessionTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "doc.on.doc")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, minHeight: Space.hit)
                .background(Color.surface2, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(RecordAccessibilityID.copyLastButton)
    }

    private var title: String {
        let date = template.date.formatted(.dateTime.month().day())
        let names = template.exercises.prefix(3).map(\.name).joined(separator: "、")
        let more = template.exercises.count > 3 ? "…" : ""
        return "复制上次训练（\(date) · \(names)\(more)）"
    }
}

/// 最近动作胶囊行（P2）：横向滚动；已在本次训练里的置灰。
private struct RecentExercisesRow: View {
    let recents: [ExerciseDefinition]
    let model: RecordViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                ForEach(recents) { definition in
                    let added = model.exercises.contains { model.exerciseID(of: $0.id) == definition.id }
                    Button {
                        model.addExercise(definition)
                    } label: {
                        Text(definition.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(added ? Color.labelDisabled : Color.accentColor)
                            .padding(.horizontal, Space.s4)
                            .frame(minHeight: Space.hit)
                            .background(Color.surface2, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(added)
                    .accessibilityIdentifier(RecordAccessibilityID.recentChip)
                }
            }
            .padding(.vertical, Space.s1)
        }
        .listRowInsets(EdgeInsets(top: Space.s1, leading: Space.s4, bottom: Space.s1, trailing: Space.s4))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RecordAccessibilityID.recentRow)
    }
}

/// 回填（数据迁移）失败：训练页顶部一行提示。
private struct BackfillWarning: View {
    var body: some View {
        Label("动作库整理失败，已有训练不受影响，下次打开会重试。", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.multicolor)
            .accessibilityIdentifier(RecordAccessibilityID.backfillWarning)
    }
}

#Preview {
    RecordView().environment(AppModel.preview())
}
