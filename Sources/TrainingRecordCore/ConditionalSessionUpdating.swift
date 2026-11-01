import Foundation

/// 支持「仅当场次仍存在才更新」的原子更新的训练仓储。
///
/// 为什么需要它：`WorkoutRepository.save` 是 upsert。后台任务（改名、合并、回填）如果先读一场训练、
/// 再 `save` 写回，读和写之间用户删掉这场训练，`save` 就会把它重新创建出来（静默复活已删除的数据）。
/// 重读一次只能缩小窗口，不能消除。`updateExisting` 把「按 id 读取 → 变换 → 写回」放在仓储内部一次完成，
/// 仓储自己的串行保证（actor）使它不会被删除打断：场次已不存在就什么都不写。
public protocol ConditionalSessionUpdating: WorkoutRepository {
    /// 原子地更新一场已存在的训练：读取 → `transform` → 覆盖写回，整个过程不会被该仓储的其他操作打断。
    /// 场次不存在时返回 false 且**不写入、不创建**；`transform` 返回 nil 表示无需改动，也返回 false。
    /// 写入了返回 true。`transform` 必须是纯函数（在仓储内部同步执行）。
    ///
    /// **`transform` 返回的场次 id 必须等于 `id`**（本方法只更新这一场，不能改 id、不能借此创建或覆盖别的场次）。
    /// id 不同时视为无效更新：返回 false，**不改动任何数据**（原场次保持原样，也不会出现新 id，
    /// 更不会覆盖另一条已存在的记录）。所有实现行为一致。
    func updateExisting(id: UUID, _ transform: @Sendable (WorkoutSession) -> WorkoutSession?) async throws -> Bool
}

extension InMemoryWorkoutRepository: ConditionalSessionUpdating {
    /// actor 内部的 `session(id:)` 与 `save` 都不挂起，所以整个「读 → 变换 → 写」在 actor 上不可被打断。
    public func updateExisting(id: UUID, _ transform: @Sendable (WorkoutSession) -> WorkoutSession?) async throws -> Bool {
        guard let current = try await session(id: id), let updated = transform(current), updated.id == id else {
            return false
        }
        try await save(updated)
        return true
    }
}
