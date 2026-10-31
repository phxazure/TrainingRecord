import SwiftUI

/// 文本输入（§8.2）：底 surface-2、radius-md、高 ≥ 44；占位符 label-2；
/// 聚焦 1.5 pt tint 描边；出错 1.5 pt danger 描边（错误优先于聚焦）。数字输入用圆体。
struct InputField: View {
    let placeholder: String
    var unit: String?
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isNumeric = false
    var isError = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}
    let identifier: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Space.s1) {
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(.label2)
            )
            .textFieldStyle(.plain)
            .keyboardType(keyboard)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .focused($isFocused)
            .font(isNumeric ? .system(.body, design: .rounded) : .body)
            .monospacedDigit()
            .foregroundStyle(.primary)
            .accessibilityIdentifier(identifier)

            if let unit {
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.label2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.s3)
        .frame(minHeight: Space.hit)
        .background(Color.surface2, in: shape)
        .overlay {
            if isError {
                shape.strokeBorder(Color.danger, lineWidth: Stroke.field)
            } else if isFocused {
                shape.strokeBorder(Color.accentColor, lineWidth: Stroke.field)
            }
        }
        .contentShape(shape)
        .onTapGesture { isFocused = true }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    }
}
