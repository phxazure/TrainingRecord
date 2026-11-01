import Charts
import SwiftUI
import TrainingRecordCore

/// 「趋势」标签：第一屏 = 整体训练趋势卡片 + 全部动作列表（一行一个）；点某个动作 push 进动作详情。
/// 不用 Picker / 分段控件切换内容。
struct TrendView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var hasLoaded = false

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.trendPath) {
            content
                .navigationTitle("趋势")
                .exerciseDestinations()
        }
        .accessibilityIdentifier(TrendAccessibilityID.root)
        .task {
            await app.history.reload()
            hasLoaded = true
        }
    }

    @ViewBuilder
    private var content: some View {
        let summaries = exerciseSummaries(library: app.library.exercises, sessions: app.history.sessions)
        if !hasLoaded && app.history.sessions.isEmpty {
            ProgressView {
                Text("正在加载…")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            .accessibilityIdentifier(HistoryAccessibilityID.loading)
        } else if app.history.sessions.isEmpty && app.history.errorMessage == nil {
            ContentUnavailableView {
                Label("还没有可看的趋势", systemImage: "chart.xyaxis.line")
            } description: {
                Text("保存训练后，这里会显示整体趋势，每个动作也有自己的趋势图。")
            }
            .accessibilityIdentifier(TrendAccessibilityID.emptyState)
        } else {
            List {
                if app.history.errorMessage != nil {
                    Section { errorCard }
                }
                Section {
                    OverallTrendCard(points: weeklyTrend(of: app.history.sessions, weeks: 12, now: .now))
                } header: {
                    sectionTitle("整体趋势")
                }
                Section {
                    if summaries.isEmpty {
                        Text("还没有关联到动作库的训练记录。")
                            .font(.subheadline)
                            .foregroundStyle(.label2)
                    }
                    ForEach(summaries) { summary in
                        NavigationLink(value: ExerciseRoute(id: summary.exercise.id)) {
                            SummaryRow(summary: summary)
                        }
                        .accessibilityIdentifier(TrendAccessibilityID.exerciseRow)
                    }
                } header: {
                    sectionTitle("动作")
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await app.refresh() }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.label2)
            .textCase(nil)
    }

    private var errorCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("无法加载训练历史").font(.headline)
                Text("下面是上次加载的结果。")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            Spacer(minLength: Space.s2)
            Button("重试") { Task { await app.history.reload() } }
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: Space.hit)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HistoryAccessibilityID.errorMessage)
    }
}

/// 整体趋势卡片：近 12 周每周总容量的柱状图（metric-volume），本周的训练次数与容量作标题。
private struct OverallTrendCard: View {
    let points: [WeeklyTrendPoint]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            if let current = points.last {
                Text("本周")
                    .font(.footnote)
                    .foregroundStyle(.label2)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.s5))
                layout {
                    ValueWithUnit(value: "\(current.sessionCount)", unit: "次训练", style: .title, weight: .bold)
                    ValueWithUnit(
                        value: Format.volume(current.volume),
                        unit: "kg",
                        style: .title,
                        weight: .bold,
                        valueColor: .metricVolume
                    )
                }
            }
            Chart(points, id: \.weekStart) { point in
                BarMark(x: .value("周", point.weekStart, unit: .weekOfYear), y: .value("容量", point.volume))
                    .foregroundStyle(Color.metricVolume)
                    .cornerRadius(Radius.sm / 2)
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel().font(.caption.weight(.medium)).foregroundStyle(Color.label2)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            let calendar = Calendar.current
                            Text("\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.label2)
                        }
                    }
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? Metrics.overallChartHeight * 1.5 : Metrics.overallChartHeight)
            .accessibilityLabel("近 \(points.count) 周每周训练容量柱状图")
            .accessibilityIdentifier(TrendAccessibilityID.overallChart)
            Text("近 \(points.count) 周每周总容量")
                .font(.footnote)
                .foregroundStyle(.label2)
        }
        .padding(.vertical, Space.s1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(TrendAccessibilityID.overallCard)
    }
}

/// 动作列表的一行：名字、部位、最近一次最佳 1RM（metric-strength）、较上一次变化（箭头 + 文案，不只靠颜色）。
private struct SummaryRow: View {
    let summary: ExerciseSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Space.s3))
        layout {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(summary.exercise.name)
                    .font(.headline)
                Text(summary.exercise.bodyPart)
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Space.s2) }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: Space.s1) {
                ValueWithUnit(value: Format.oneRM(summary.latestBestE1RM), unit: "kg", weight: .semibold, valueColor: .metricStrength)
                HStack(spacing: Space.s1) {
                    Image(systemName: icon)
                    Text(text)
                }
                .font(.footnote)
                .foregroundStyle(isUp ? Color.metricStrength : Color.label2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isUp: Bool {
        if case .up = summary.change { return true }
        return false
    }

    private var icon: String {
        switch summary.change {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        case .noPrevious: "circle.dotted"
        }
    }

    private var text: String {
        switch summary.change {
        case .up(let delta): "较上次 \(Format.signed(delta, fraction: 1)) kg"
        case .down(let delta): "较上次 \(Format.signed(-delta, fraction: 1)) kg"
        case .flat: "较上次持平"
        case .noPrevious: "第 1 次"
        }
    }
}
