import UIKit
import TrainingRecordCore

/// 动作照片：界面侧的图片处理（缩放、JPEG 编码、读取）。文件命名、保存顺序、清理都在 Core 的
/// `ExercisePhotoStorage` / `ExercisePhotoWorkflow`；这里只管把选中的图片变成 JPEG 数据，以及按文件名读图。
/// 库里只存文件名，文件位置每次用当前容器的目录拼出来（从不持久化绝对路径）。
struct ExercisePhotoStore: Sendable {
    /// 长边最大像素。
    static let maxLongEdge: CGFloat = 1024
    /// JPEG 质量。
    static let jpegQuality: CGFloat = 0.8

    enum PhotoError: Error, Equatable {
        case invalidImage
        case encodingFailed
    }

    let fileSystem: LocalPhotoFileSystem
    let storage: ExercisePhotoStorage

    init(directory: URL) {
        let fileSystem = LocalPhotoFileSystem(directory: directory)
        self.fileSystem = fileSystem
        self.storage = ExercisePhotoStorage(fileSystem: fileSystem)
    }

    /// 真实存储位置：Application Support/ExercisePhotos/。
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

    /// 缩放（长边 ≤ 1024 px）并编码为 JPEG（质量 0.8）。纯内存操作，不碰磁盘。
    func encode(imageData: Data) throws -> Data {
        guard let image = UIImage(data: imageData) else { throw PhotoError.invalidImage }
        let resized = Self.resized(image)
        guard let jpeg = resized.jpegData(compressionQuality: Self.jpegQuality) else { throw PhotoError.encodingFailed }
        return jpeg
    }

    func image(named fileName: String) -> UIImage? {
        UIImage(contentsOfFile: fileSystem.url(for: fileName).path)
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
