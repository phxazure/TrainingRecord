import Foundation

/// 照片 / 动作条目操作的恢复日志：记录「做到一半、补偿也失败」的事，下一次操作或启动时接着处理。
/// 存在照片目录**旁边**的一个小文件里（不在照片目录内：照片目录写不了的时候，日志仍然写得进去）。
///
/// 为什么需要它：换图时旧图被挪成 `<名字>.backup`。之后的结局有两种，磁盘上长得一样，意义却相反——
/// - 条目更新成功（已提交）：备份是该删的垃圾；
/// - 条目更新失败（要回滚）：备份是**唯一的旧图**，该还原，绝不能当垃圾删。
/// 补偿动作（删备份 / 还原备份）自己失败时，必须把「该做哪一个」记下来，否则只能猜。
struct PhotoRecoveryJournal {
    enum Entry: Codable, Equatable {
        /// 换图：旧图在 `<fileName>.backup`。`committed == false` 表示还没确认条目更新成功 → 恢复时还原旧图；
        /// `true` 表示条目更新已成功 → 恢复时删除备份。
        case swap(fileName: String, committed: Bool)
        /// 新建动作时条目已创建、照片还没挂上：补偿（删除这个条目）还没完成。
        case createdEntry(id: UUID)
    }

    let url: URL
    private(set) var entries: [Entry]

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    /// 添加 / 替换一条；写盘失败则抛出，内存里的条目也回到原样。
    mutating func upsert(_ entry: Entry, replacing old: Entry? = nil) throws {
        let before = entries
        if let old, let index = entries.firstIndex(of: old) {
            entries[index] = entry
        } else if !entries.contains(entry) {
            entries.append(entry)
        }
        do { try persist() } catch {
            entries = before
            throw error
        }
    }

    /// 移除一条；写盘失败则抛出（条目留在内存里，下次再试；恢复动作本身是幂等的）。
    mutating func remove(_ entry: Entry) throws {
        let before = entries
        entries.removeAll { $0 == entry }
        do { try persist() } catch {
            entries = before
            throw error
        }
    }

    private func persist() throws {
        if entries.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}
