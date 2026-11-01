import SwiftUI
import TrainingRecordCore

/// 训练明细（§7）：顶部三项汇总（容量 / 组数 / 动作，宽度 1.6 : 1 : 1）；
/// 每个动作一张卡片：每组「重量 × 次数」、容量与「查看动作详情」。
/// 历史里不显示最佳 1RM（人类的要求）；最佳 1RM 在「趋势」和「动作详情」里看。
struct HistoryDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List {
            Section { SummaryRow(session: session) }

            // ExerciseEntry 不是 Identifiable，按下标取（明细只读，顺序稳定）。
            ForEach(session.exercises.indices, id: \.self) { index in
                ExerciseDetailCard(exercise: session.exercises[index])
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(session.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(HistoryAccessibilityID.detailList)
    }
}

/// 顶部汇总：容量（large-title，metric-volume，最宽）｜ 组数 ｜ 动作。
private struct SummaryRow: View {
    let session: WorkoutSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let setCount = session.exercises.reduce(0) { $0 + $1.sets.count }
        if dynamicTypeSize.isAccessibilitySize {
            // 大字号：三项上下排，主数字可换行不截断。
            VStack(alignment: .leading, spacing: Space.s3) {
                volumeColumn
                column("组数", value: "\(setCount)", unit: "组")
                column("动作", value: "\(session.exercises.count)", unit: "个")
            }
        } else {
            WeightedColumns(weights: [1.6, 1, 1]) {
                volumeColumn
                column("组数", value: "\(setCount)", unit: "组")
                    .padding(.leading, Space.s3)
                    .overlay(alignment: .leading) { separator }
                column("动作", value: "\(session.exercises.count)", unit: "个")
                    .padding(.leading, Space.s3)
                    .overlay(alignment: .leading) { separator }
            }
        }
    }

    private var separator: some View {
        Rectangle().fill(Color.hairline).frame(width: 1 / displayScale)
    }

    private var volumeColumn: some View {
        column("容量", value: Format.volume(totalVolume(of: session)), unit: "kg", color: .metricVolume)
    }

    private func column(_ title: String, value: String, unit: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.label2)
            ValueWithUnit(value: value, unit: unit, style: .largeTitle, weight: .bold, valueColor: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 一个动作的明细卡片。
private struct ExerciseDetailCard: View {
    let exercise: ExerciseEntry
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            Text(exercise.name)
                .font(.title3.weight(.semibold))

            ForEach(exercise.sets.indices, id: \.self) { index in
                let set = exercise.sets[index]
                HStack(spacing: Space.s3) {
                    NumberBadge(number: index + 1)
                    SetValue(weight: set.weight, reps: set.reps)
                }
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: Space.s1) {
                Text("容量")
                    .font(.subheadline)
                ValueWithUnit(
                    value: Format.volume(volume(of: exercise)),
                    unit: "kg",
                    style: .subheadline,
                    weight: .regular,
                    valueColor: .metricVolume
                )
                Spacer(minLength: 0)
            }

            // 点进去看这个动作的详情（和动作库、趋势里是同一个视图）。
            if let id = exercise.exerciseID, app.library.definition(id: id) != nil {
                NavigationLink(value: ExerciseRoute(id: id)) {
                    Text("查看动作详情")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(minHeight: Space.hit, alignment: .leading)
                }
                .accessibilityIdentifier(HistoryAccessibilityID.viewTrendButton)
            }
        }
    }
}

/// 按权重分宽的横排：子视图数量与权重数量一致。
private struct WeightedColumns: Layout {
    let weights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 0
        let widths = columnWidths(total: total)
        let height = zip(subviews, widths)
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, columnWidths(total: bounds.width)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width
        }
    }

    private func columnWidths(total: CGFloat) -> [CGFloat] {
        let sum = weights.reduce(0, +)
        return weights.map { total * $0 / sum }
    }
}
