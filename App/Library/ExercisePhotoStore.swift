import UIKit

/// 动作照片的文件存取：Application Support/ExercisePhotos/<动作 id>.jpg。
/// 数据层（Core）只存文件名；文件的读写、缩放在这里。
struct ExercisePhotoStore: Sendable {
    /// 长边最大像素。
    static let maxLongEdge: CGFloat = 1024
    /// JPEG 质量。
    static let jpegQuality: CGFloat = 0.8

    static let stagingExtension = "staging"
    static let backupExtension = "backup"

    enum PhotoError: Error, Equatable {
        case invalidImage
        case encodingFailed
        /// 上一次换图的善后（还原 / 删除备份）还没完成，这次先不动照片。
        case recoveryPending
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

    /// 恢复日志的位置：照片目录旁边的 `<目录名>.recovery.json`（不在照片目录里）。
    var journalURL: URL {
        directory.deletingLastPathComponent()
            .appending(path: directory.lastPathComponent + ".recovery.json", directoryHint: .notDirectory)
    }

    func url(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    func fileName(for exerciseID: UUID) -> String { "\(exerciseID.uuidString).jpg" }

    /// 已缩放、编码好、写在目录里的临时文件（还不是任何动作的照片）。
    struct StagedPhoto {
        let url: URL
    }

    /// 已经放到 `<动作 id>.jpg` 的新照片；`backup` 是被它替换的旧照片（没有旧照片时为 nil）。
    struct InstalledPhoto {
        let fileName: String
        let url: URL
        let backup: URL?
    }

    /// 第一步：缩放（长边 ≤ 1024 px）、编码 JPEG 0.8，写成目录里的临时文件。失败时不留任何文件。
    /// 这一步不动任何现有照片，所以可以在创建 / 修改动作条目**之前**做：写盘失败时数据一点没变。
    func stage(imageData: Data) throws -> StagedPhoto {
        guard let image = UIImage(data: imageData) else { throw PhotoError.invalidImage }
        let resized = Self.resized(image)
        guard let jpeg = resized.jpegData(compressionQuality: Self.jpegQuality) else { throw PhotoError.encodingFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).\(Self.stagingExtension)", directoryHint: .notDirectory)
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return StagedPhoto(url: url)
    }

    func discard(_ staged: StagedPhoto) {
        try? FileManager.default.removeItem(at: staged.url)
    }

    /// 第二步：把临时文件放到 `<动作 id>.jpg`。已有旧照片时先把它挪成备份，出错就原样还原。
    func install(_ staged: StagedPhoto, exerciseID: UUID) throws -> InstalledPhoto {
        let fileManager = FileManager.default
        let name = fileName(for: exerciseID)
        let final = url(for: name)
        var backup: URL?
        if fileManager.fileExists(atPath: final.path) {
            let backupURL = backupURL(for: name)
            // 已有一份备份说明上一次换图的善后还没做完（恢复日志会处理）；不能覆盖它。
            guard !fileManager.fileExists(atPath: backupURL.path) else { throw PhotoError.recoveryPending }
            try fileManager.moveItem(at: final, to: backupURL)
            backup = backupURL
        }
        do {
            try fileManager.moveItem(at: staged.url, to: final)
        } catch {
            if let backup { try? fileManager.moveItem(at: backup, to: final) }
            try? fileManager.removeItem(at: staged.url)
            throw error
        }
        return InstalledPhoto(fileName: name, url: final, backup: backup)
    }

    /// 目录里是否已经有这个动作的照片文件（换图时它会被挪成备份）。
    func hasPhoto(exerciseID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName(for: exerciseID)).path)
    }

    /// 动作条目已经成功更新：删除备份。删不掉时抛出（调用方把它记入恢复日志，之后重试）。
    func finalize(_ installed: InstalledPhoto) throws {
        guard installed.backup != nil else { return }
        try removeBackup(fileName: installed.fileName)
    }

    /// 动作条目更新失败：还原旧照片；原来没有照片则删掉本次放进去的文件。失败时抛出（调用方记入恢复日志，之后重试）。
    func rollback(_ installed: InstalledPhoto) throws {
        if installed.backup != nil {
            try restoreBackup(fileName: installed.fileName)
        } else if FileManager.default.fileExists(atPath: installed.url.path) {
            try FileManager.default.removeItem(at: installed.url)
        }
    }

    func backupURL(for fileName: String) -> URL {
        directory.appending(path: "\(fileName).\(Self.backupExtension)", directoryHint: .notDirectory)
    }

    /// 删除 `<fileName>.backup`；不存在不算错。
    func removeBackup(fileName: String) throws {
        let url = backupURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// 用 `<fileName>.backup` 还原 `<fileName>`（先删掉现在的那张）；备份不存在则什么也不做。幂等。
    func restoreBackup(fileName: String) throws {
        let fileManager = FileManager.default
        let backup = backupURL(for: fileName)
        guard fileManager.fileExists(atPath: backup.path) else { return }
        let final = url(for: fileName)
        if fileManager.fileExists(atPath: final.path) { try fileManager.removeItem(at: final) }
        try fileManager.moveItem(at: backup, to: final)
    }

    /// 删除照片文件。文件本来就不存在不算错；真正的删除失败（权限、I/O）抛出，由调用方记录并稍后重试。
    func remove(fileName: String?) throws {
        guard let fileName else { return }
        let url = url(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// 清理没有被引用的文件（失败的换图 / 删除留下的临时文件、孤立 JPEG）；`.backup` 文件不在此列。返回删除失败的文件名。
    /// 只在没有进行中的照片操作时调用（`LibraryStore` 把它放在串行队列里）。
    func sweep(keeping referenced: Set<String>) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var failed: [String] = []
        for name in names where !referenced.contains(name) {
            // 备份可能是唯一的旧图（换图失败且还原失败时），是否该删由恢复日志决定，扫描绝不动它。
            if name.hasSuffix(".\(Self.backupExtension)") { continue }
            do {
                try FileManager.default.removeItem(at: url(for: name))
            } catch {
                failed.append(name)
            }
        }
        return failed
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
