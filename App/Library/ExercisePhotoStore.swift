import UIKit

/// 动作照片的文件存取：Application Support/ExercisePhotos/<动作 id>.jpg。
/// 数据层（Core）只存文件名；文件的读写、缩放在这里。
struct ExercisePhotoStore: Sendable {
    /// 长边最大像素。
    static let maxLongEdge: CGFloat = 1024
    /// JPEG 质量。
    static let jpegQuality: CGFloat = 0.8

    enum PhotoError: Error, Equatable {
        case invalidImage
        case encodingFailed
    }

    let directory: URL

    /// 真实存储位置。
    static var standard: ExercisePhotoStore {
        ExercisePhotoStore(
            directory: URL.applicationSupportDirectory.appending(path: "ExercisePhotos", directoryHint: .isDirectory)
        )
    }

    /// 不落在真实目录的临时位置（DEBUG 样例数据、内存模式用）。
    static func temporary() -> ExercisePhotoStore {
        ExercisePhotoStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "ExercisePhotos-temporary", directoryHint: .isDirectory)
        )
    }

    func url(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    func fileName(for exerciseID: UUID) -> String { "\(exerciseID.uuidString).jpg" }

    /// 缩放（长边 ≤ 1024 px）并以 JPEG 0.8 存成 `<动作 id>.jpg`，返回文件名。同名文件被覆盖。
    func save(imageData: Data, exerciseID: UUID) throws -> String {
        guard let image = UIImage(data: imageData) else { throw PhotoError.invalidImage }
        let resized = Self.resized(image)
        guard let jpeg = resized.jpegData(compressionQuality: Self.jpegQuality) else { throw PhotoError.encodingFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = fileName(for: exerciseID)
        try jpeg.write(to: url(for: name), options: .atomic)
        return name
    }

    /// 删除照片文件；文件名为 nil 或文件不存在时什么也不做。
    func remove(fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    func image(named fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    /// 像素尺寸（已考虑 scale）长边超过上限时等比缩小；否则按像素重绘为 scale 1（统一方向）。
    static func resized(_ image: UIImage) -> UIImage {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longEdge = max(pixelSize.width, pixelSize.height)
        let ratio = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1
        let target = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
