import SwiftUI

/// 底部提示条的内容（§8.7）。
enum RecordToast: Equatable {
    /// 保存成功：「已保存 · 5 组 · 1,890 kg」，2 秒后自动消失。
    case saved(setCount: Int, volume: Double)
    /// 保存失败：不自动消失，可「重试」，可下滑关闭。
    case failed
}

/// 底部提示条：capsule，`.regularMaterial`。
struct ToastView: View {
    let toast: RecordToast
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.s2) {
            switch toast {
            case .saved(let setCount, let volume):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("已保存 · \(setCount) 组 · \(Format.volume(volume)) kg")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.danger)
                Text("保存失败，训练还在，可以再试一次")
                    .font(.subheadline.weight(.semibold))
                Button("重试", action: retry)
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: Space.hit)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(RecordAccessibilityID.retryButton)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .background(.regularMaterial, in: Capsule())
        .gesture(
            DragGesture().onEnded { value in
                if toast == .failed, value.translation.height > Space.s4 { dismiss() }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(RecordAccessibilityID.savedToast)
    }
}
