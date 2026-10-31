import SwiftUI

// 设计 token（ui/DESIGN.md）。颜色来自 Asset Catalog 或系统色，间距、圆角按 §3 / §4，
// 视图里一律引用这里，不写魔法数。

// MARK: - 颜色（§1）

extension ShapeStyle where Self == Color {
    /// surface：卡片 / 分组行。
    static var surface: Color { Color(.secondarySystemGroupedBackground) }
    /// surface-2：输入框底、序号徽章、禁用填充。
    static var surface2: Color { Color("Surface2") }
    /// label-2：次文字、占位符、单位。
    static var label2: Color { Color("Label2") }
    /// label-disabled：禁用文字。
    static var labelDisabled: Color { Color("LabelDisabled") }
    /// on-tint：tint 填充上的文字。
    static var onTint: Color { Color("OnTint") }
    /// metric-strength：最佳 1RM（数字、线、点）。
    static var metricStrength: Color { Color("MetricStrength") }
    /// metric-volume：容量（数字、线、点）。
    static var metricVolume: Color { Color("MetricVolume") }
    /// danger：错误文字、删除。
    static var danger: Color { Color("Danger") }
    /// on-danger：删除滑块上的文字。
    static var onDanger: Color { Color("OnDanger") }
    /// separator：分隔线、图表网格。
    static var hairline: Color { Color(.separator) }
}

// MARK: - 间距（§3）

enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    /// hit：最小可点区域。
    static let hit: CGFloat = 44
}

// MARK: - 圆角、线宽、其他本设计的值（§4 / §4.1 / §5）

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
}

enum Stroke {
    /// 输入框描边（§4.1）。
    static let field: CGFloat = 1.5
    /// 趋势折线宽（§4.1 / §8.9）。
    static let chartLine: CGFloat = 2.5
}

enum Metrics {
    /// 趋势图点大小：最新一点 / 其余（§8.9）。
    static let latestPointSize: CGFloat = 100
    static let pointSize: CGFloat = 40
    /// 趋势图高度：space-8 的 6 倍。图表需要一个确定高度，设计稿约 192。
    static let chartHeight: CGFloat = Space.s8 * 6
    /// 按下态透明度（§8.1，系统 borderedProminent 默认）。
    static let pressedOpacity: Double = 0.7
    /// 分段切换指标时图表交叉淡化时长（§5）。
    static let metricFadeDuration: Double = 0.25
    /// 保存成功提示条停留时间（§5）。
    static let toastSeconds: Double = 2
    /// 保存成功提示条弹出动画时长（§5）。
    static let toastSpringDuration: Double = 0.35
}

// MARK: - 数字与单位（§2）

extension View {
    /// 数字用圆体 + 等宽数字（所有重量、次数、容量、1RM、日期数字）。
    func numeric(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> some View {
        font(.system(style, design: .rounded, weight: weight)).monospacedDigit()
    }
}

/// 「数字 + 单位」：数字走 `numeric`，单位 footnote + label-2，基线对齐。
struct ValueWithUnit: View {
    let value: String
    let unit: String
    var style: Font.TextStyle = .headline
    var weight: Font.Weight = .semibold
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s1) {
            Text(value)
                .numeric(style, weight: weight)
                .foregroundStyle(valueColor)
                // 窄列里的大数字宁可缩小也不换行断开（如「3,522.」「5」）。
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .font(.footnote)
                .foregroundStyle(.label2)
                .fixedSize()
        }
        // 辅助功能朗读为一个整体，如「60 kg」。
        .accessibilityElement(children: .combine)
    }
}

/// 数字格式化。保留系统的分组分隔符与当前语言环境。
enum Format {
    /// 重量：最多 2 位小数。
    static func weight(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    /// 容量：最多 1 位小数。
    static func volume(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// 估算 1RM：固定 1 位小数（Core 已四舍五入到 0.1）。
    static func oneRM(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    /// 变化量：带正负号。
    static func signed(_ value: Double, fraction: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fraction)).sign(strategy: .always()))
    }
}

/// 序号徽章（surface-2，radius-sm，caption）：组序号。
struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.label2)
            .frame(minWidth: Space.s6, minHeight: Space.s6)
            .background(Color.surface2, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// 行内错误：`exclamationmark.circle.fill` + footnote danger。
struct InlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.danger)
    }
}
