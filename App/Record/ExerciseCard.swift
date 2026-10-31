import SwiftUI
import TrainingRecordCore

/// 动作卡片（§8.4）：标题行（动作名 + 菜单）→ 小计 → 组行（左滑删除）→ 加组行 → 行内错误。
struct ExerciseCard: View {
    let model: RecordViewModel
    let exercise: ExerciseDraft

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var inputError: SetInputError?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            header
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(number: index + 1, weight: set.weight, reps: set.reps)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            model.removeSet(exerciseID: exercise.id, setID: set.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(.danger)
                    }
            }
            addSetRow
            if let inputError {
                InlineError(message: inputError.message)
                    .accessibilityIdentifier(RecordAccessibilityID.setInputError)
            }
        }
    }

    // MARK: 标题行 + 小计

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                subtotal
            }
            Spacer(minLength: Space.s2)
            Menu {
                Button(role: .destructive) {
                    model.removeExercise(id: exercise.id)
                } label: {
                    Label("删除动作", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .frame(minWidth: Space.hit, minHeight: Space.hit)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多")
            .accessibilityIdentifier(RecordAccessibilityID.exerciseMenu)
        }
    }

    @ViewBuilder
    private var subtotal: some View {
        if exercise.sets.isEmpty {
            Text("还没有组，在下方输入重量和次数")
                .font(.subheadline)
                .foregroundStyle(.label2)
        } else {
            let volume = exercise.sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
            HStack(spacing: Space.s1) {
                Text("\(exercise.sets.count) 组 ·")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
                ValueWithUnit(
                    value: Format.volume(volume),
                    unit: "kg",
                    style: .subheadline,
                    weight: .semibold,
                    valueColor: .metricVolume
                )
            }
        }
    }

    // MARK: 加组行

    private var addSetRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s2))
            : AnyLayout(HStackLayout(spacing: Space.s2))
        return layout {
            InputField(
                placeholder: "重量",
                unit: "kg",
                text: $weightText,
                keyboard: .decimalPad,
                isNumeric: true,
                isError: inputError == .invalidWeight,
                identifier: RecordAccessibilityID.weightField
            )
            InputField(
                placeholder: "次数",
                unit: "次",
                text: $repsText,
                keyboard: .numberPad,
                isNumeric: true,
                isError: inputError == .invalidReps,
                identifier: RecordAccessibilityID.repsField
            )
            Button(action: addSet) {
                Image(systemName: "plus")
            }
            .buttonStyle(ProminentCircleButtonStyle())
            .disabled(weightText.isEmpty && repsText.isEmpty)
            .accessibilityLabel("添加组")
            .accessibilityIdentifier(RecordAccessibilityID.addSetButton)
        }
        .onChange(of: weightText) { inputError = nil }
        .onChange(of: repsText) { inputError = nil }
    }

    private func addSet() {
        if let error = model.addSet(toExercise: exercise.id, weightText: weightText, repsText: repsText) {
            inputError = error
        } else {
            // 保留重量，方便连续录入同重量的下一组。
            repsText = ""
            inputError = nil
        }
    }
}

/// 已录入的一组（§8.4）：序号徽章 +「60 kg × 8 次」。
struct SetRow: View {
    let number: Int
    let weight: Double
    let reps: Int

    var body: some View {
        HStack(spacing: Space.s3) {
            NumberBadge(number: number)
            SetValue(weight: weight, reps: reps)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 「60 kg × 8 次」：数字圆体 headline，单位 footnote label-2。
struct SetValue: View {
    let weight: Double
    let reps: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
            ValueWithUnit(value: Format.weight(weight), unit: "kg")
            Text("×")
                .font(.footnote)
                .foregroundStyle(.label2)
            ValueWithUnit(value: "\(reps)", unit: "次")
        }
    }
}

extension SetInputError {
    /// 行内错误文案（§8.2）。
    var message: String {
        switch self {
        case .invalidWeight: "重量需为 0–1000 kg 的数字"
        case .invalidReps: "次数需为 1–1000 的整数"
        }
    }
}
