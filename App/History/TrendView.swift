import SwiftUI
import Charts
import TrainingRecordCore

/// 单动作趋势：选动作，折线 + 点，纵轴在「最佳 1RM」与「容量」间切换。
struct TrendView: View {
    let model: HistoryViewModel

    @State private var selectedExercise: String?
    @State private var metric: Metric = .oneRM

    enum Metric: String, CaseIterable, Identifiable {
        case oneRM = "最佳 1RM"
        case volume = "容量"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 12) {
            if model.exerciseNames.isEmpty {
                ContentUnavailableView(
                    "还没有数据",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("保存包含动作的训练后，这里会显示它的趋势。")
                )
                .accessibilityIdentifier(HistoryAccessibilityID.emptyState)
            } else {
                Picker("动作", selection: $selectedExercise) {
                    ForEach(model.exerciseNames, id: \.self) { name in
                        Text(name).tag(name as String?)
                    }
                }
                .accessibilityIdentifier(HistoryAccessibilityID.exercisePicker)

                Picker("指标", selection: $metric) {
                    ForEach(Metric.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(HistoryAccessibilityID.trendMetricToggle)

                if let selectedExercise {
                    chart(for: selectedExercise)
                } else {
                    ContentUnavailableView(
                        "选择动作",
                        systemImage: "hand.point.up.left",
                        description: Text("从上方选择一个动作查看趋势。")
                    )
                }
            }
        }
        .padding()
        .onAppear(perform: syncSelection)
        // 删除/重新加载后动作列表可能变化：选中项不在列表里时回到第一个。
        .onChange(of: model.exerciseNames) { syncSelection() }
    }

    private func syncSelection() {
        if let selectedExercise, model.exerciseNames.contains(selectedExercise) { return }
        selectedExercise = model.exerciseNames.first
    }

    @ViewBuilder
    private func chart(for exerciseName: String) -> some View {
        let points = model.trend(for: exerciseName)
        if points.isEmpty {
            ContentUnavailableView(
                "暂无趋势",
                systemImage: "chart.line.downtrend.xyaxis",
                description: Text("这个动作还没有足够的训练数据。")
            )
        } else {
            // ExerciseTrendPoint 不是 Identifiable，且同日可有多个点，按下标区分。
            Chart(points.indices, id: \.self) { index in
                let point = points[index]
                LineMark(
                    x: .value("日期", point.date),
                    y: .value(metric.rawValue, metricValue(of: point))
                )
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("日期", point.date),
                    y: .value(metric.rawValue, metricValue(of: point))
                )
            }
            .chartYAxisLabel("\(metric.rawValue)（kg）")
            .accessibilityIdentifier(HistoryAccessibilityID.trendChart)
        }
    }

    private func metricValue(of point: ExerciseTrendPoint) -> Double {
        switch metric {
        case .oneRM: point.bestE1RM
        case .volume: point.volume
        }
    }
}
