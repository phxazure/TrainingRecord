import Foundation

/// 照片 / 动作条目操作的恢复日志：记录「做到一半、补偿也失败」的事，下一次操作或启动时接着处理。
///
/// 为什么需要它：换图时旧图被挪成 `<名字>.backup`。之后的结局有两种，磁盘上长得一样，意义却相反——
/// - 条目更新成功（已提交）：备份是该删的垃圾；
/// - 条目更新失败（要回滚）：备份是**唯一的旧图**，该还原，绝不能当垃圾删。
/// 补偿动作（删备份 / 还原备份）自己失败时，必须把「该做哪一个」记下来，否则只能猜。
///
/// 存储：主存储是照片目录旁边的 `<目录名>.recovery.json`（不在照片目录内：照片目录写不了的时候日志仍然写得进去）。
/// 主存储也写不进去时（例如那个目录也被锁了），**结果类**的写入（「已提交」「已补偿完」）退到 `UserDefaults` 备份存储，
/// 并且读取时备份存储优先（它只在主存储写失败时才写，主存储下一次写成功就会清掉它，所以总是更新的那份）。
/// **动手之前**的写入（登记「马上要换图 / 新建」）是严格的：主存储写不进去就直接失败，什么都还没改。
struct PhotoRecoveryJournal {
    enum Entry: Codable, Equatable {
        /// 换图：旧图在 `<fileName>.backup`。`committed == false` 表示还没确认条目更新成功 → 恢复时还原旧图；
        /// `true` 表示条目更新已成功 → 恢复时删除备份。
        case swap(fileName: String, committed: Bool)
        /// 新建动作时条目已创建、照片还没挂上：补偿（删除这个条目）还没完成。
        /// 恢复时要先核对：条目已经挂上照片就说明新建成功了，这条记录是过期的，只划掉、不删条目。
        case createdEntry(id: UUID)
    }

    let url: URL
    private let defaults: UserDefaults
    private let defaultsKey: String
    private(set) var entries: [Entry]

    init(url: URL, defaults: UserDefaults = .standard) {
        self.url = url
        self.defaults = defaults
        self.defaultsKey = "PhotoRecoveryJournal.fallback." + url.path
        if let data = defaults.data(forKey: defaultsKey), let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded  // 备份存储里的永远更新
        } else if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// 添加 / 替换一条。
    /// - Parameter strict: true = 只认主存储（动手之前的登记）；写不进去就抛出，内存里的条目也回到原样。
    ///   false = 主存储失败时退到备份存储（结果类的写入，必须尽量写成）。
    mutating func upsert(_ entry: Entry, replacing old: Entry? = nil, strict: Bool = false) throws {
        let before = entries
        if let old, let index = entries.firstIndex(of: old) {
            entries[index] = entry
        } else if !entries.contains(entry) {
            entries.append(entry)
        }
        do { try persist(strict: strict) } catch {
            entries = before
            throw error
        }
    }

    /// 移除一条；主存储写不进去时退到备份存储（结果类的写入）。
    mutating func remove(_ entry: Entry) throws {
        let before = entries
        entries.removeAll { $0 == entry }
        do { try persist(strict: false) } catch {
            entries = before
            throw error
        }
    }

    /// 主存储现在写得进去吗（动手之前探一下）：在日志文件旁写一个临时探针文件再删掉，不改变任何条目。
    func requireWritable() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe = directory.appending(path: ".\(url.lastPathComponent).probe-\(UUID().uuidString)", directoryHint: .notDirectory)
        try Data().write(to: probe)
        try FileManager.default.removeItem(at: probe)
    }

    private func persist(strict: Bool) throws {
        do {
            try writePrimary()
            defaults.removeObject(forKey: defaultsKey)  // 主存储是最新的了，备份存储作废
        } catch {
            if strict { throw error }
            defaults.set(try JSONEncoder().encode(entries), forKey: defaultsKey)  // 备份存储：不依赖文件权限
        }
    }

    private func writePrimary() throws {
        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            else { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}
