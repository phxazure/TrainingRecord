import SwiftUI
import TrainingRecordCore

/// 训练明细（§7）：顶部三项汇总（容量 / 组数 / 动作，宽度 1.6 : 1 : 1）；
/// 每个动作一张卡片：最佳估算 1RM（metric-strength）、每组右侧是该组估算 1RM、容量与「查看趋势」。
struct HistoryDetailView: View {
    let session: WorkoutSession
    let openTrend: (String) -> Void

    var body: some View {
        List {
            Section { SummaryRow(session: session) }

            // ExerciseEntry 不是 Identifiable，按下标取（明细只读，顺序稳定）。
            ForEach(session.exercises.indices, id: \.self) { index in
                ExerciseDetailCard(session: session, exercise: session.exercises[index], openTrend: openTrend)
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
    let session: WorkoutSession
    let exercise: ExerciseEntry
    let openTrend: (String) -> Void

    var body: some View {
        // 该场次该动作的最佳估算 1RM 直接取 Core 的趋势算法；模块名限定避免被同名成员遮蔽。
        let best = TrainingRecordCore.trend(for: exercise.name, in: [session]).first?.bestE1RM
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: Space.s2)
                if let best {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("最佳 1RM")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.label2)
                        ValueWithUnit(
                            value: Format.oneRM(best),
                            unit: "kg",
                            weight: .semibold,
                            valueColor: .metricStrength
                        )
                    }
                }
            }

            ForEach(exercise.sets.indices, id: \.self) { index in
                let set = exercise.sets[index]
                HStack(spacing: Space.s3) {
                    NumberBadge(number: index + 1)
                    SetValue(weight: set.weight, reps: set.reps)
                    Spacer(minLength: Space.s2)
                    if let oneRM = estimatedOneRM(of: set) {
                        Text(Format.oneRM(oneRM))
                            .numeric(.subheadline)
                            .foregroundStyle(oneRM == best ? Color.metricStrength : Color.label2)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            HStack {
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
                }
                Spacer(minLength: Space.s2)
                Button {
                    openTrend(exercise.name)
                } label: {
                    HStack(spacing: Space.s1) {
                        Text("查看趋势")
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Space.hit)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier(HistoryAccessibilityID.viewTrendButton)
            }
        }
    }

    /// 单组估算 1RM（Epley，四舍五入到 0.1），与 Core 趋势算法一致；0 次的组不参与。
    private func estimatedOneRM(of set: SetEntry) -> Double? {
        guard set.reps >= 1 else { return nil }
        let raw = set.reps == 1 ? set.weight : set.weight * (1 + Double(set.reps) / 30)
        return (raw * 10).rounded() / 10
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
