import SwiftUI
import Charts
import TrainingRecordCore

/// 指标：最佳 1RM（metric-strength）/ 容量（metric-volume）。颜色即身份：同一个数字在各处颜色一致。
enum TrendMetric: String, CaseIterable, Identifiable {
    case oneRM = "最佳 1RM"
    case volume = "容量"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .oneRM: .metricStrength
        case .volume: .metricVolume
        }
    }

    func value(of point: ExerciseTrendPoint) -> Double {
        switch self {
        case .oneRM: point.bestE1RM
        case .volume: point.volume
        }
    }

    func text(_ value: Double) -> String {
        switch self {
        case .oneRM: Format.oneRM(value)
        case .volume: Format.volume(value)
        }
    }
}

/// 「趋势」标签（§7 / §8.6 / §8.9）：选动作 → 选指标 → 当前值 + 变化 → 折线图 → 数据列表。
struct TrendView: View {
    let model: HistoryViewModel
    @Binding var selectedExercise: String?

    @State private var metric: TrendMetric = TrendView.initialMetric
    @State private var hasLoaded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 48

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("趋势")
        }
        .accessibilityIdentifier(TrendAccessibilityID.root)
        .onAppear(perform: syncSelection)
        // 删除/重新加载后动作列表可能变化：选中项不在列表里时回到第一个。
        .onChange(of: model.exerciseNames) { syncSelection() }
        .task {
            await model.reload()
            hasLoaded = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded && model.exerciseNames.isEmpty {
            ProgressView {
                Text("正在加载…")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            .accessibilityIdentifier(HistoryAccessibilityID.loading)
        } else if model.exerciseNames.isEmpty && model.errorMessage == nil {
            ContentUnavailableView {
                Label("还没有可看的趋势", systemImage: "chart.xyaxis.line")
            } description: {
                Text("保存训练后，每个动作都会有自己的趋势图。")
            }
            .accessibilityIdentifier(TrendAccessibilityID.emptyState)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s5) {
                    if model.errorMessage != nil { errorCard }
                    if let exercise = selectedExercise, model.exerciseNames.contains(exercise) {
                        controls(selected: exercise)
                        trendBody(for: exercise)
                    }
                }
                .padding(.horizontal, Space.s4)
                .padding(.bottom, Space.s4)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: 选择器

    private func controls(selected: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Menu {
                Picker("动作", selection: $selectedExercise) {
                    ForEach(model.exerciseNames, id: \.self) { name in
                        Text(name).tag(name as String?)
                    }
                }
            } label: {
                HStack(spacing: Space.s2) {
                    Text(selected).font(.headline)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.label2)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, Space.s4)
                .frame(minHeight: Space.hit)
                .background(Color.surface, in: Capsule())
                .contentShape(Capsule())
            }
            // Menu 的标签会被染成 tint；药丸里的动作名按设计稿用主文字色。
            .tint(.primary)
            .accessibilityLabel("动作")
            .accessibilityValue(selected)
            .accessibilityIdentifier(HistoryAccessibilityID.exercisePicker)

            Picker("指标", selection: $metric) {
                ForEach(TrendMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(HistoryAccessibilityID.trendMetricToggle)
        }
    }

    // MARK: 当前值、图、列表

    @ViewBuilder
    private func trendBody(for exercise: String) -> some View {
        let points = model.trend(for: exercise)
        if let latest = points.last {
            currentValue(latest: latest, previous: points.dropLast().last, count: points.count)
            if points.count >= 2 {
                chart(points)
            } else {
                singlePointCard(exercise)
            }
            dataList(points)
        }
    }

    private func currentValue(latest: ExerciseTrendPoint, previous: ExerciseTrendPoint?, count: Int) -> some View {
        let current = metric.value(of: latest)
        let dateText = latest.date.formatted(.dateTime.month().day())
        return VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
                Text(metric.text(current))
                    .font(.system(size: displaySize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metric.color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("kg")
                    .font(.headline)
                    .foregroundStyle(.label2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(TrendAccessibilityID.currentValue)

            if let previous {
                let delta = current - metric.value(of: previous)
                // 大字号时变化量与日期分两行，避免在句中被拦腰折断。
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s1))
                    : AnyLayout(HStackLayout(spacing: Space.s1))
                layout {
                    HStack(spacing: Space.s1) {
                        Image(systemName: deltaIcon(delta))
                        Text(deltaText(delta))
                    }
                    .foregroundStyle(delta > 0 ? metric.color : Color.label2)
                    Text("\(dynamicTypeSize.isAccessibilitySize ? "" : "· ")\(dateText) · 近 \(count) 次")
                        .foregroundStyle(.label2)
                }
                .font(.footnote)
            } else {
                Text("\(dateText) · 第 1 次")
                    .font(.footnote)
                    .foregroundStyle(.label2)
            }
        }
    }

    /// 上升用指标色 + 向上箭头，下降 / 持平用 label-2 + 向下 / 向右箭头；不用红绿。
    private func deltaIcon(_ delta: Double) -> String {
        if delta > 0 { return "arrow.up.right" }
        if delta < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private func deltaText(_ delta: Double) -> String {
        if delta == 0 { return "较上次持平" }
        let fraction = metric == .oneRM ? 1 : 0
        return "较上次 \(Format.signed(delta, fraction: fraction)) kg"
    }

    private func chart(_ points: [ExerciseTrendPoint]) -> some View {
        // ExerciseTrendPoint 不是 Identifiable，且同日可有多个点，按下标区分。
        Chart(points.indices, id: \.self) { index in
            let value = metric.value(of: points[index])
            LineMark(x: .value("日期", points[index].date), y: .value(metric.rawValue, value))
                .foregroundStyle(metric.color)
                .lineStyle(StrokeStyle(lineWidth: Stroke.chartLine, lineCap: .round, lineJoin: .round))
            PointMark(x: .value("日期", points[index].date), y: .value(metric.rawValue, value))
                .foregroundStyle(metric.color)
                .symbolSize(index == points.count - 1 ? Metrics.latestPointSize : Metrics.pointSize)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel().font(.caption.weight(.medium)).foregroundStyle(Color.label2)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        // 「9/12」：纯数字，避免中文环境下「9月12日」太长。
                        let calendar = Calendar.current
                        Text("\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.label2)
                    }
                }
            }
        }
        .frame(height: Metrics.chartHeight)
        .padding(Space.s4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        // 切换指标：折线与颜色交叉淡化；减弱动态效果时直接切换。
        .id(metric)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: Metrics.metricFadeDuration), value: metric)
        .accessibilityLabel("\(metric.rawValue)趋势图，共 \(points.count) 个点")
        .accessibilityIdentifier(HistoryAccessibilityID.trendChart)
    }

    private func singlePointCard(_ exercise: String) -> some View {
        VStack(spacing: Space.s3) {
            Image(systemName: "chart.xyaxis.line")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.label2)
                .accessibilityHidden(true)
            Text("再记录一次「\(exercise)」就能连成趋势")
                .font(.subheadline)
                .foregroundStyle(.label2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s8)
        .padding(.horizontal, Space.s4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(TrendAccessibilityID.singlePoint)
    }

    /// 数据列表：日期 → 数值，最新在前，给 VoiceOver 和精确读数用。
    private func dataList(_ points: [ExerciseTrendPoint]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(points.indices.reversed()), id: \.self) { index in
                if index != points.count - 1 { Divider() }
                HStack {
                    Text(points[index].date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                        .font(.body)
                    Spacer(minLength: Space.s2)
                    ValueWithUnit(
                        value: metric.text(metric.value(of: points[index])),
                        unit: "kg",
                        valueColor: metric.color
                    )
                }
                .padding(.vertical, Space.s3)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, Space.s4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityIdentifier(TrendAccessibilityID.dataList)
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
            Button("重试") { Task { await model.reload() } }
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: Space.hit)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
        }
        .padding(Space.s4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HistoryAccessibilityID.errorMessage)
    }

    private func syncSelection() {
        let names = model.exerciseNames
        // 还没加载出动作时保留外部指定的选择（例如从明细跳来）。
        guard !names.isEmpty else { return }
        if let selectedExercise, names.contains(selectedExercise) { return }
        selectedExercise = names.first
    }

    private static var initialMetric: TrendMetric {
        #if DEBUG
        HistoryDebugLaunch.initialMetric ?? .oneRM
        #else
        .oneRM
        #endif
    }
}
