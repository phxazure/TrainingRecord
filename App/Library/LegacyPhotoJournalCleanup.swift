import Foundation

/// 旧版（已取消的「临时文件 + 备份 + 恢复日志」方案）留在设备上的恢复日志：启动时删掉。
/// 只删日志本身（UserDefaults 里的备份键、照片目录旁的 `.recovery.json`），**不据此改动任何照片或动作库记录**——
/// 照片是否保留只由动作库是否引用它决定（见启动清理）。
enum LegacyPhotoJournalCleanup {
    private static let defaultsKeyPrefix = "PhotoRecoveryJournal.fallback."

    static func run(photoDirectory: URL, defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(defaultsKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
        let journal = photoDirectory.deletingLastPathComponent()
            .appending(path: photoDirectory.lastPathComponent + ".recovery.json", directoryHint: .notDirectory)
        try? FileManager.default.removeItem(at: journal)
    }
}
