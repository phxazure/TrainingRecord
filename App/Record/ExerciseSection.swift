import SwiftUI
import TrainingRecordCore

/// 一个动作：已录入的组（左滑删除）+ 添加组的输入行。
struct ExerciseSection: View {
    let model: RecordViewModel
    let exercise: ExerciseDraft

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var inputError: SetInputError?

    var body: some View {
        Section {
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRow(number: index + 1, set: set)
            }
            .onDelete(perform: deleteSets)

            addSetRow
        } header: {
            header
        } footer: {
            if let inputError {
                Text(inputError.message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(RecordAccessibilityID.setInputError)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(exercise.name)
                .textCase(nil)
            Spacer()
            Menu {
                Button("删除动作", systemImage: "trash", role: .destructive) {
                    model.removeExercise(id: exercise.id)
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
            }
            .accessibilityIdentifier(RecordAccessibilityID.exerciseMenu)
        }
    }

    private var addSetRow: some View {
        HStack {
            TextField("重量", text: $weightText)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier(RecordAccessibilityID.weightField)
            Text("kg")
                .foregroundStyle(.secondary)
            Divider()
            TextField("次数", text: $repsText)
                .keyboardType(.numberPad)
                .accessibilityIdentifier(RecordAccessibilityID.repsField)
            Text("次")
                .foregroundStyle(.secondary)
            Button(action: addSet) {
                Label("添加组", systemImage: "plus.circle.fill")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
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

    private func deleteSets(at offsets: IndexSet) {
        let ids = offsets.map { exercise.sets[$0].id }
        for id in ids {
            model.removeSet(exerciseID: exercise.id, setID: id)
        }
    }
}

/// 已录入的一组：「第 n 组 …… 60 kg × 8」。
private struct SetRow: View {
    let number: Int
    let set: SetDraft

    var body: some View {
        HStack {
            Text("第 \(number) 组")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(set.weight.formatted(.number.precision(.fractionLength(0...2)))) kg × \(set.reps)")
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

extension SetInputError {
    /// 就地提示文案。
    var message: String {
        switch self {
        case .invalidWeight: "重量需为 0–1000 之间的数字（kg）。"
        case .invalidReps: "次数需为 1–1000 之间的整数。"
        }
    }
}
