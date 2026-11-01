import Foundation

// 动作照片的存储规则（T009 第 4 轮升级后的方案）：
//
// - 每次存图都用**新文件名** `<动作 id>-<UUID>.jpg`，绝不覆盖、改名、移动已有文件；
// - 保存顺序：先写新文件 → 再保存到动作库 → 保存成功才尽力删旧文件；保存失败则尽力删新文件；
// - 「尽力删」失败不报错、不重试、不记录，一律交给启动清理；
// - 启动清理：动作库加载成功后，删除库里没有任何动作引用的文件；库加载失败时跳过；
//   清理不会删掉本进程里正在保存、尚未提交到库的新文件；
// - 没有备份文件、没有恢复日志、不持久化任何绝对路径：库里只存文件名，运行时用当前容器路径拼出文件位置。
//
// 本文件只用 Foundation；文件系统通过 `PhotoFileSystem` 注入。

// MARK: - 文件系统抽象

/// 照片目录的文件系统访问。所有名字都是目录内的纯文件名。
public protocol PhotoFileSystem: Sendable {
    /// 目录里全部文件名。目录不存在 → 空数组。
    func list() throws -> [String]
    /// 写入新文件（目录不存在则创建）。同名文件已存在时必须抛错，绝不覆盖。
    func write(_ data: Data, named fileName: String) throws
    /// 删除文件。
    func remove(named fileName: String) throws
}

/// 真实目录上的实现。
public struct LocalPhotoFileSystem: PhotoFileSystem {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 文件名 → 当前容器下的位置（运行时拼，从不持久化）。
    public func url(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    public func list() throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    public func write(_ data: Data, named fileName: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = url(for: fileName)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try data.write(to: target, options: .atomic)
    }

    public func remove(named fileName: String) throws {
        try FileManager.default.removeItem(at: url(for: fileName))
    }
}

// MARK: - 命名

public enum ExercisePhotoNaming {
    /// `<动作 id>-<UUID>.jpg`。`token` 默认随机，测试可注入。
    public static func makeFileName(ownerID: UUID, token: UUID = UUID()) -> String {
        "\(ownerID.uuidString)-\(token.uuidString).jpg"
    }
}

// MARK: - 错误与结果

public enum PhotoStorageError: Error, Equatable, Sendable {
    /// 新照片文件没能写下来。此时不会去保存动作库，已有数据都没动。
    case writeFailed
}

public enum PhotoSweepResult: Equatable, Sendable {
    /// 没有清理：动作库没能加载（不知道哪些文件被引用），或者列不出目录。
    case skipped
    /// 清理完成：`deleted` 是删掉的孤立文件，`failed` 是想删但没删掉的（留给下次启动）。
    case completed(deleted: [String], failed: [String])
}

// MARK: - 存储

/// 照片文件的保存顺序与清理判定。actor 只保护「进行中的保存」登记；文件系统调用本身是同步的。
public actor ExercisePhotoStorage {
    private let fileSystem: any PhotoFileSystem
    private let makeToken: @Sendable () -> UUID

    /// 正在保存、还没结束（提交或失败）的新文件名。
    private var inFlight: Set<String> = []
    /// 每个正在进行的清理各自的「受保护」集合：清理开始时的进行中文件，加上清理期间登记的所有新文件
    /// （即使它们在清理结束前已经提交完成——清理拿到的「被引用」快照可能早于那次提交）。
    private var activeSweeps: [UUID: Set<String>] = [:]

    public init(fileSystem: any PhotoFileSystem, makeToken: @escaping @Sendable () -> UUID = { UUID() }) {
        self.fileSystem = fileSystem
        self.makeToken = makeToken
    }

    /// 保存一张新照片。
    ///
    /// 1. 新文件名，写新文件；写失败 → 抛 `PhotoStorageError.writeFailed`，`commit` 不会被调用；
    /// 2. 调用 `commit(新文件名)`（保存到动作库）；
    /// 3. 成功 → 尽力删 `oldFileName`（若有，且不同于新文件名）；失败 → 尽力删新文件，错误原样抛出。
    ///
    /// `commit` 运行期间新文件处于「进行中」，启动清理不会删它。
    public func save<Result: Sendable>(
        jpeg: Data,
        ownerID: UUID,
        replacing oldFileName: String?,
        commit: @Sendable (String) async throws -> Result
    ) async throws -> Result {
        let fileName = ExercisePhotoNaming.makeFileName(ownerID: ownerID, token: makeToken())
        // 先登记再写：任何时刻只要文件可能已经在磁盘上，它就已经受保护。
        inFlight.insert(fileName)
        for key in activeSweeps.keys { activeSweeps[key]?.insert(fileName) }
        defer { inFlight.remove(fileName) }

        do {
            try fileSystem.write(jpeg, named: fileName)
        } catch {
            // 写失败：不保存动作库。不去删这个名字——同名文件若存在是别人的（write 不覆盖，也就不属于我们）。
            throw PhotoStorageError.writeFailed
        }

        let result: Result
        do {
            result = try await commit(fileName)
        } catch {
            try? fileSystem.remove(named: fileName)
            throw error
        }
        if let oldFileName, oldFileName != fileName {
            try? fileSystem.remove(named: oldFileName)
        }
        return result
    }

    /// 动作库已经不再引用这个文件（移除照片 / 删除动作 / 合并之后）：尽力删。失败不报错，交给启动清理。
    public nonisolated func discard(_ fileName: String?) {
        guard let fileName else { return }
        try? fileSystem.remove(named: fileName)
    }

    /// 启动清理：删除动作库里没有任何动作引用的文件。
    /// - Parameter loadReferenced: 读出动作库当前引用的全部照片文件名；抛错 → 本次不清理。
    public func sweepUnreferenced(
        loadReferenced: @Sendable () async throws -> Set<String>
    ) async -> PhotoSweepResult {
        let sweepID = UUID()
        activeSweeps[sweepID] = inFlight  // 先登记：从这一刻起的新文件都受保护
        defer { activeSweeps[sweepID] = nil }

        let referenced: Set<String>
        do {
            referenced = try await loadReferenced()
        } catch {
            return .skipped
        }
        let names: [String]
        do {
            names = try fileSystem.list()
        } catch {
            return .skipped
        }

        // 从这里到循环结束没有 await：受保护集合在判定时是最新的。
        let protected = activeSweeps[sweepID] ?? []
        var deleted: [String] = []
        var failed: [String] = []
        for name in names where !referenced.contains(name) && !protected.contains(name) {
            do {
                try fileSystem.remove(named: name)
                deleted.append(name)
            } catch {
                failed.append(name)
            }
        }
        return .completed(deleted: deleted.sorted(), failed: failed.sorted())
    }
}
