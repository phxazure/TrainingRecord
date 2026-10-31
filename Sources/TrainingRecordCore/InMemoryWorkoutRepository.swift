import Foundation

/// 内存实现：适合单元测试与纯内存运行场景。actor 保证并发安全。
public actor InMemoryWorkoutRepository: WorkoutRepository {
    /// id → 场次。
    private var sessions: [UUID: WorkoutSession] = [:]

    /// 预置数据；重复 id 以数组中靠后的为准。
    public init(sessions: [WorkoutSession] = []) {
        for session in sessions {
            self.sessions[session.id] = session
        }
    }

    public func save(_ session: WorkoutSession) async throws {
        sessions[session.id] = session
    }

    public func session(id: UUID) async throws -> WorkoutSession? {
        sessions[id]
    }

    public func allSessions() async throws -> [WorkoutSession] {
        sessions.values.sorted { a, b in
            if a.date != b.date {
                return a.date > b.date
            }
            return a.id.uuidString < b.id.uuidString
        }
    }

    public func delete(id: UUID) async throws {
        sessions[id] = nil
    }
}
