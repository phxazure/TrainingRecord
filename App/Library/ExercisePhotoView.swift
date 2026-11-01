import SwiftUI

/// 动作照片（方形，圆角 radius-sm）；没有照片或读不到文件时显示占位图标。
struct ExercisePhotoView: View {
    @Environment(AppModel.self) private var app
    let fileName: String?
    /// 基础边长；随 Dynamic Type 缩放。
    let size: CGFloat

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1
    @State private var image: UIImage?

    /// 随 Dynamic Type 放大，但最多 1.5 倍：照片不该因为大字号占满整行、把文字挤走。
    private var clampedScale: CGFloat { min(scale, 1.5) }

    var body: some View {
        ZStack {
            Color.surface2
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "dumbbell")
                    .font(.title3)
                    .foregroundStyle(.label2)
            }
        }
        .frame(width: size * clampedScale, height: size * clampedScale)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        // 每次存图都是新文件名，所以文件名变了就重新读。
        .task(id: fileName) {
            guard let fileName else {
                image = nil
                return
            }
            image = app.library.photos.image(named: fileName)
        }
        .accessibilityHidden(true)
    }
}
