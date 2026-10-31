import SwiftUI
import TrainingRecordCore

/// 某次训练的明细：按动作分组，每组显示重量 × 次数。
struct HistoryDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                Text(session.date, format: .dateTime.year().month().day().weekday())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // ExerciseEntry / SetEntry 不是 Identifiable，按下标取（明细只读，顺序稳定）。
            ForEach(session.exercises.indices, id: \.self) { exerciseIndex in
                let exercise = session.exercises[exerciseIndex]
                Section(exercise.name) {
                    ForEach(exercise.sets.indices, id: \.self) { setIndex in
                        SetRowView(number: setIndex + 1, set: exercise.sets[setIndex])
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("训练明细")
        .accessibilityIdentifier(HistoryAccessibilityID.detailList)
    }
}

/// 明细里的一组：「第 n 组 …… 60 kg × 8」。
private struct SetRowView: View {
    let number: Int
    let set: SetEntry

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
