import Foundation

/// 训练场次存取抽象。界面层只依赖本协议；
/// 本地持久化（SwiftData）与云同步以后作为本协议的其他实现接入，不改调用方。
public protocol WorkoutRepository: Sendable {
    /// 新增，或按 id 覆盖已有场次。
    func save(_ session: WorkoutSession) async throws
    /// 按 id 读取；不存在返回 nil。
    func session(id: UUID) async throws -> WorkoutSession?
    /// 全部场次：按 date 降序（最近在前）；date 相同时按 id.uuidString 升序（结果确定，不依赖插入顺序）。
    func allSessions() async throws -> [WorkoutSession]
    /// 按 id 删除；不存在时静默成功。
    func delete(id: UUID) async throws
}
