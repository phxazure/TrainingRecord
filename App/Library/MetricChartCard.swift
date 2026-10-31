import Charts
import SwiftUI

/// 一个指标的趋势卡片：标题、当前值（大号圆体数字）、较上次变化、折线图。
/// 最佳 1RM 用 metric-strength，容量用 metric-volume；只有 1 个点时不画线，给一句提示。
struct MetricChartCard: View {
    struct Point: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    let title: String
    let color: Color
    /// 日期升序。
    let points: [Point]
    let format: (Double) -> String
    /// 变化量保留几位小数。
    let deltaFraction: Int
    let identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.label2)
            if let latest = points.last {
                currentValue(latest)
                if points.count >= 2 {
                    chart
                } else {
                    Text("再记录一次就能连成趋势")
                        .font(.subheadline)
                        .foregroundStyle(.label2)
                }
            }
        }
        .padding(.vertical, Space.s1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func currentValue(_ latest: Point) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            ValueWithUnit(value: format(latest.value), unit: "kg", style: .largeTitle, weight: .bold, valueColor: color)
            if points.count >= 2 {
                let delta = latest.value - points[points.count - 2].value
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s1))
                    : AnyLayout(HStackLayout(spacing: Space.s1))
                layout {
                    HStack(spacing: Space.s1) {
                        Image(systemName: icon(delta))
                        Text(deltaText(delta))
                    }
                    .foregroundStyle(delta > 0 ? color : Color.label2)
                    Text("\(dynamicTypeSize.isAccessibilitySize ? "" : "· ")\(latest.date.formatted(.dateTime.month().day())) · 近 \(points.count) 次")
                        .foregroundStyle(.label2)
                }
                .font(.footnote)
            } else {
                Text("\(latest.date.formatted(.dateTime.month().day())) · 第 1 次")
                    .font(.footnote)
                    .foregroundStyle(.label2)
            }
        }
    }

    private func icon(_ delta: Double) -> String {
        if delta > 0 { return "arrow.up.right" }
        if delta < 0 { return "arrow.down.right" }
        return "arrow.right"
    }

    private func deltaText(_ delta: Double) -> String {
        if abs(delta) < pow(10, -Double(deltaFraction)) / 2 { return "较上次持平" }
        return "较上次 \(Format.signed(delta, fraction: deltaFraction)) kg"
    }

    private var chart: some View {
        Chart(points) { point in
            LineMark(x: .value("日期", point.date), y: .value(title, point.value))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: Stroke.chartLine, lineCap: .round, lineJoin: .round))
            PointMark(x: .value("日期", point.date), y: .value(title, point.value))
                .foregroundStyle(color)
                .symbolSize(point.id == points.last?.id ? Metrics.latestPointSize : Metrics.pointSize)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        // 首尾两个点离轴一点距离：最新点的大圆不压住右侧刻度数字。
        .chartXScale(range: .plotDimension(startPadding: Space.s2, endPadding: Space.s2))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 5)) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel().font(.caption.weight(.medium)).foregroundStyle(Color.label2)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 3)) { value in
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
        .frame(height: Metrics.chartHeight)
        .accessibilityLabel("\(title)趋势图，共 \(points.count) 个点")
    }
}
