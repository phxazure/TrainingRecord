import SwiftUI

/// 主按钮（§8.1）：capsule。default 填充 tint + on-tint；disabled 填充 surface-2 + label-disabled；
/// 按下透明度 0.7。可点区域不小于 `Space.hit`。
struct ProminentCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.onTint : Color.labelDisabled)
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .background(isEnabled ? Color.accentColor : Color.surface2, in: Capsule())
            .frame(minHeight: Space.hit)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? Metrics.pressedOpacity : 1)
    }
}

/// 加组按钮（§8.3）：44×44 圆，tint 填充 + on-tint 图标；disabled 填充 surface-2 + label-disabled。
struct ProminentCircleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(isEnabled ? Color.onTint : Color.labelDisabled)
            .frame(width: Space.hit, height: Space.hit)
            .background(isEnabled ? Color.accentColor : Color.surface2, in: Circle())
            .contentShape(Circle())
            .opacity(configuration.isPressed ? Metrics.pressedOpacity : 1)
    }
}
