import PhotosUI
import SwiftUI
import TrainingRecordCore

/// 常用训练部位（也可以输入自定义）。
let commonBodyParts = ["胸", "背", "肩", "手臂", "腿", "臀", "核心", "全身", "有氧"]

/// 新建 / 编辑动作：名字（必填）、训练部位、照片。编辑页底部有「合并记录到其他动作…」和「删除动作」。
struct ExerciseEditView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let route: ExerciseEditRoute

    @State private var name = ""
    @State private var bodyPart = ""
    @State private var photoChange: PhotoChange = .keep
    @State private var pendingPhoto: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var serviceDuplicate: String?

    @State private var showDeleteConfirm = false
    @State private var showDeleteRejected = false
    @State private var showDeleteFailed = false

    private var editingID: UUID? { route.id }
    private var existing: ExerciseDefinition? { editingID.flatMap { app.library.definition(id: $0) } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 动作库里另一个同名动作（去首尾空白、不区分大小写）。
    private var duplicate: ExerciseDefinition? {
        let key = trimmedName.lowercased()
        guard !key.isEmpty else { return nil }
        return app.library.exercises.first { $0.id != editingID && $0.name.lowercased() == key }
    }

    private var duplicateMessage: String? {
        if let duplicate { return "动作库里已有「\(duplicate.name)」" }
        return serviceDuplicate.map { "动作库里已有「\($0)」" }
    }

    private var canSave: Bool { !trimmedName.isEmpty && duplicateMessage == nil && !isSaving }

    /// 这个动作的训练次数（用于删除 / 合并的提示）。
    private var sessionCountOfExercise: Int {
        guard let editingID else { return 0 }
        return sessionCount(of: editingID, in: app.history.sessions)
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            nameSection
            bodyPartSection
            photoSection
            if editingID != nil { dangerSection.id(Self.dangerAnchor) }
            if let saveError {
                Section {
                    InlineError(message: saveError)
                        .accessibilityIdentifier(ExerciseEditAccessibilityID.saveError)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        #if DEBUG
        .task {
            guard DebugLaunch.dialog == "scrollBottom" else { return }
            try? await Task.sleep(for: .milliseconds(600))
            proxy.scrollTo(Self.dangerAnchor, anchor: .top)
        }
        #endif
        .navigationTitle(editingID == nil ? "新建动作" : "编辑动作")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(editingID == nil ? "添加" : "保存", action: save)
                    .buttonStyle(ProminentCapsuleButtonStyle())
                    .disabled(!canSave)
                    .accessibilityIdentifier(ExerciseEditAccessibilityID.saveButton)
            }
        }
        .accessibilityIdentifier(ExerciseEditAccessibilityID.root)
        .onAppear(perform: loadInitialValues)
        .onChange(of: name) { serviceDuplicate = nil; saveError = nil }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    saveError = "无法读取这张照片"
                    return
                }
                pendingPhoto = image
                photoChange = .replace(data)
            }
        }
        .alert("删除「\(existing?.name ?? "")」？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive, action: performDelete)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不能撤销。")
        }
        .alert("无法删除", isPresented: $showDeleteRejected) {
            Button("好", role: .cancel) {}
        } message: {
            Text("「\(existing?.name ?? "")」有 \(sessionCountOfExercise) 次训练记录，不能直接删除。如果它和另一个动作是同一个，可以用「合并记录」。")
        }
        .alert("删除失败", isPresented: $showDeleteFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("这个动作还在，请稍后再试。")
        }
        #if DEBUG
        .task { await DebugLaunch.presentEditDialog { showDeleteRejected = true } }
        #endif
        }
    }

    private static let dangerAnchor = "exerciseEdit.dangerSection"

    // MARK: 区块

    private var nameSection: some View {
        Section {
            InputField(
                placeholder: "动作名称，如 卧推",
                text: $name,
                isError: duplicateMessage != nil,
                identifier: ExerciseEditAccessibilityID.nameField
            )
            if let duplicateMessage {
                InlineError(message: duplicateMessage)
                    .accessibilityIdentifier(ExerciseEditAccessibilityID.duplicateError)
            }
        } header: {
            sectionTitle("名字")
        }
    }

    private var bodyPartSection: some View {
        Section {
            InputField(
                placeholder: "选一个，或输入自定义部位",
                text: $bodyPart,
                identifier: ExerciseEditAccessibilityID.partField
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Space.hit + Space.s6), spacing: Space.s2)], alignment: .leading, spacing: Space.s2) {
                ForEach(commonBodyParts, id: \.self) { part in
                    PartChip(title: part, isSelected: bodyPart.trimmingCharacters(in: .whitespacesAndNewlines) == part) {
                        bodyPart = part
                    }
                }
            }
            .padding(.vertical, Space.s1)
        } header: {
            sectionTitle("训练部位")
        } footer: {
            Text("不填则为「未分类」。")
                .font(.footnote)
                .foregroundStyle(.label2)
        }
    }

    private var photoSection: some View {
        let hasPhoto = self.hasPhoto
        return Section {
            HStack(spacing: Space.s4) {
                photoPreview
                VStack(alignment: .leading, spacing: Space.s2) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Text(hasPhoto ? "更换照片" : "选择照片")
                            .font(.headline)
                            .frame(minHeight: Space.hit, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier(ExerciseEditAccessibilityID.photoPicker)
                    if hasPhoto {
                        Button("移除照片", role: .destructive) {
                            photoChange = .remove
                            pendingPhoto = nil
                            pickerItem = nil
                        }
                        .frame(minHeight: Space.hit, alignment: .leading)
                        .accessibilityIdentifier(ExerciseEditAccessibilityID.removePhoto)
                    }
                }
                Spacer(minLength: 0)
            }
        } header: {
            sectionTitle("照片")
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let pendingPhoto {
            Image(uiImage: pendingPhoto)
                .resizable()
                .scaledToFill()
                .frame(width: Metrics.photoLarge, height: Metrics.photoLarge)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .accessibilityHidden(true)
        } else if case .remove = photoChange {
            ExercisePhotoView(fileName: nil, size: Metrics.photoLarge)
        } else {
            ExercisePhotoView(fileName: existing?.photoFileName, size: Metrics.photoLarge)
        }
    }

    private var hasPhoto: Bool {
        switch photoChange {
        case .replace: true
        case .remove: false
        case .keep: existing?.photoFileName != nil
        }
    }

    private var dangerSection: some View {
        Section {
            if let editingID {
                NavigationLink(value: MergePickerRoute(sourceID: editingID)) {
                    Label("合并记录到其他动作…", systemImage: "arrow.triangle.merge")
                        .frame(minHeight: Space.hit, alignment: .leading)
                }
                .accessibilityIdentifier(ExerciseEditAccessibilityID.mergeButton)
            }
            Button(role: .destructive, action: requestDelete) {
                Label("删除动作", systemImage: "trash")
                    .frame(minHeight: Space.hit, alignment: .leading)
            }
            .foregroundStyle(.danger)
            .accessibilityIdentifier(ExerciseEditAccessibilityID.deleteButton)
        } footer: {
            Text("同一个动作被记成了两个名字时，用「合并记录」把它们并成一个。")
                .font(.footnote)
                .foregroundStyle(.label2)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.label2)
            .textCase(nil)
    }

    // MARK: 操作

    private func loadInitialValues() {
        guard !didLoad else { return }
        didLoad = true
        if let existing {
            name = existing.name
            bodyPart = existing.bodyPart
        } else {
            name = route.prefillName
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let editingID {
                    try await app.library.update(id: editingID, name: trimmedName, bodyPart: bodyPart, photo: photoChange)
                    await app.refresh()
                    dismiss()
                } else {
                    var photoData: Data?
                    if case .replace(let data) = photoChange { photoData = data }
                    let created = try await app.library.add(name: trimmedName, bodyPart: bodyPart, photoData: photoData)
                    await app.refresh()
                    if route.addToRecord {
                        _ = app.record.addExercise(created)
                        app.recordPath = NavigationPath()
                    } else {
                        dismiss()
                    }
                }
            } catch ExerciseLibraryError.duplicateName {
                serviceDuplicate = trimmedName
            } catch ExerciseLibraryError.invalidName {
                saveError = "请输入动作名称"
            } catch {
                saveError = "保存失败，请重试"
            }
        }
    }

    /// 没有记录时先确认再删除；有记录时直接给出拒绝提示。
    private func requestDelete() {
        if sessionCountOfExercise == 0 {
            showDeleteConfirm = true
        } else {
            showDeleteRejected = true
        }
    }

    private func performDelete() {
        guard let editingID else { return }
        Task {
            do {
                try await app.library.delete(id: editingID)
                await app.refresh()
                app.popToRoot()
            } catch ExerciseLibraryError.inUse {
                await app.refresh()
                showDeleteRejected = true
            } catch {
                showDeleteFailed = true
            }
        }
    }
}

/// 常用部位胶囊：选中时 tint 填充，未选中 surface-2。
private struct PartChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.onTint : Color.primary)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: Space.hit)
                .frame(maxWidth: .infinity)
                .background(isSelected ? Color.accentColor : Color.surface2, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(ExerciseEditAccessibilityID.partChip)
    }
}
