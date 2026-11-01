import Foundation

/// 动作库操作的错误。
public enum ExerciseLibraryError: Error, Equatable, Sendable {
    /// 名字去首尾空白后为空。
    case invalidName
    /// 动作库里已有同名动作（去首尾空白、不区分大小写）。
    case duplicateName
    /// 动作库里没有该 id 的动作。
    case notFound
    /// 动作仍被历史训练引用，不能删除；`sessionCount` 是引用它的场次数。
    case inUse(sessionCount: Int)
}

/// 某个动作上一次的成绩：那一场里的最佳组。
public struct LastPerformance: Equatable, Sendable {
    public let date: Date
    public let bestSet: SetEntry

    public init(date: Date, bestSet: SetEntry) {
        self.date = date
        self.bestSet = bestSet
    }
}

/// 「复制上次训练」的模板：最近一场训练的动作（按原顺序，映射为动作库条目），不含组。
public struct SessionTemplate: Equatable, Sendable {
    public let date: Date
    public let exercises: [ExerciseDefinition]

    public init(date: Date, exercises: [ExerciseDefinition]) {
        self.date = date
        self.exercises = exercises
    }
}

/// 动作库的业务操作：协调动作库仓储与训练仓储。
///
/// 会改数据的操作（add / update / delete / merge / backfill）一次只跑一个（actor 在 await 处可重入，
/// 这里额外串行化），且都是**幂等、可补完**的：改历史的步骤在前、改动作库的步骤在后，
/// 中途仓储抛错时错误原样抛出，再调用同一操作就会把剩下的做完。
public actor ExerciseLibraryService {
    private let library: any ExerciseLibraryRepository
    private let workouts: any ConditionalSessionUpdating

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(library: any ExerciseLibraryRepository, workouts: any ConditionalSessionUpdating) {
        self.library = library
        self.workouts = workouts
    }

    // MARK: - 增删改

    /// 新增动作。名字为空抛 `.invalidName`；与已有动作重名抛 `.duplicateName`。
    public func add(name: String, bodyPart: String, photoFileName: String?) async throws -> ExerciseDefinition {
        try await exclusive {
            guard let candidate = ExerciseDefinition(name: name, bodyPart: bodyPart, photoFileName: photoFileName) else {
                throw ExerciseLibraryError.invalidName
            }
            let key = ExerciseDefinition.nameKey(candidate.name)
            let existing = try await library.allExercises()
            guard !existing.contains(where: { ExerciseDefinition.nameKey($0.name) == key }) else {
                throw ExerciseLibraryError.duplicateName
            }
            try await library.save(candidate)
            return candidate
        }
    }

    /// 修改动作（名字、部位、照片）。改名会把历史里所有引用该 id 的条目的 `name` 一并改成新名字，
    /// 这样按名字工作的趋势、历史逻辑无需改动。
    /// 改成与*另一个*动作同名抛 `.duplicateName`（什么都不改）；只改大小写、部位、照片是允许的。
    /// 中途失败后用同样的参数再调一次即可补完（包括「库里已是新名字、历史里还有旧名字」的状态）。
    public func update(id: UUID, name: String, bodyPart: String, photoFileName: String?) async throws -> ExerciseDefinition {
        try await exclusive {
            guard try await library.exercise(id: id) != nil else { throw ExerciseLibraryError.notFound }
            guard let updated = ExerciseDefinition(id: id, name: name, bodyPart: bodyPart, photoFileName: photoFileName) else {
                throw ExerciseLibraryError.invalidName
            }
            let key = ExerciseDefinition.nameKey(updated.name)
            let others = try await library.allExercises().filter { $0.id != id }
            guard !others.contains(where: { ExerciseDefinition.nameKey($0.name) == key }) else {
                throw ExerciseLibraryError.duplicateName
            }

            let newName = updated.name
            try await rewriteSessions { session in
                let entries = session.exercises.map { entry -> ExerciseEntry in
                    guard entry.exerciseID == id, entry.name != newName,
                          let renamed = ExerciseEntry(name: newName, sets: entry.sets, exerciseID: id)
                    else { return entry }
                    return renamed
                }
                return entries == session.exercises ? nil : WorkoutSession(id: session.id, date: session.date, exercises: entries)
            }
            try await library.save(updated)
            return updated
        }
    }

    /// 删除动作。仍被历史引用时抛 `.inUse(sessionCount:)`，什么都不删；动作不存在且未被引用时静默成功。
    public func delete(id: UUID) async throws {
        try await exclusive {
            let used = try await workouts.allSessions().filter { session in
                session.exercises.contains { $0.exerciseID == id }
            }
            guard used.isEmpty else { throw ExerciseLibraryError.inUse(sessionCount: used.count) }
            try await library.delete(id: id)
        }
    }

    /// 把 `sourceID` 合并进 `targetID`：历史里所有 source 条目改为 target 的 id 和名字；
    /// 同一场训练里 source 与 target 都出现时合并成一条（位置取先出现的那条，组按原先出现的顺序拼接）；
    /// 最后删除 source。`sourceID == targetID` 时什么都不做。任一方不存在抛 `.notFound`。
    /// 只处理含 source 条目的场次；只含 target 的场次不动。
    public func merge(sourceID: UUID, into targetID: UUID) async throws {
        guard sourceID != targetID else { return }
        try await exclusive {
            guard try await library.exercise(id: sourceID) != nil,
                  let target = try await library.exercise(id: targetID)
            else { throw ExerciseLibraryError.notFound }

            let targetName = target.name
            try await rewriteSessions { session in
                guard session.exercises.contains(where: { $0.exerciseID == sourceID }) else { return nil }
                var result: [ExerciseEntry] = []
                var mergedIndex: Int?
                for entry in session.exercises {
                    guard entry.exerciseID == sourceID || entry.exerciseID == targetID else {
                        result.append(entry)
                        continue
                    }
                    if let index = mergedIndex {
                        let combined = ExerciseEntry(name: targetName, sets: result[index].sets + entry.sets, exerciseID: targetID)
                        result[index] = combined ?? result[index]
                    } else {
                        mergedIndex = result.count
                        result.append(ExerciseEntry(name: targetName, sets: entry.sets, exerciseID: targetID) ?? entry)
                    }
                }
                return WorkoutSession(id: session.id, date: session.date, exercises: result)
            }
            try await library.delete(id: sourceID)
        }
    }

    // MARK: - 数据迁移

    /// 回填（数据迁移）：历史中 `exerciseID == nil` 的条目按名字（去首尾空白、不区分大小写）匹配动作库；
    /// 没有就新建（部位「未分类」，名字取最近一次出现的写法）；然后给条目写上 id。
    /// **只增加 id 和动作库条目**：不删除、不改动任何组、日期、顺序，条目自己的名字也不改。
    /// 返回新建的动作库条目数；幂等，第二次返回 0。
    public func backfill() async throws -> Int {
        try await exclusive {
            let sessions = try await workouts.allSessions()  // 日期降序：先遇到的是最近的写法
            var idByKey: [String: UUID] = [:]
            for item in try await library.allExercises() {
                let key = ExerciseDefinition.nameKey(item.name)
                if idByKey[key] == nil { idByKey[key] = item.id }
            }

            // 先建动作库条目，再改历史：中途失败重跑时，已建的会被按名字匹配到，不会重复。
            var created = 0
            for session in sessions {
                for entry in session.exercises where entry.exerciseID == nil {
                    let key = ExerciseDefinition.nameKey(entry.name)
                    guard idByKey[key] == nil,
                          let item = ExerciseDefinition(name: entry.name, bodyPart: ExerciseDefinition.uncategorized)
                    else { continue }
                    try await library.save(item)
                    idByKey[key] = item.id
                    created += 1
                }
            }

            let ids = idByKey
            try await rewriteSessions { session in
                let entries = session.exercises.map { entry -> ExerciseEntry in
                    guard entry.exerciseID == nil,
                          let id = ids[ExerciseDefinition.nameKey(entry.name)],
                          let linked = ExerciseEntry(name: entry.name, sets: entry.sets, exerciseID: id)
                    else { return entry }
                    return linked
                }
                return entries == session.exercises ? nil : WorkoutSession(id: session.id, date: session.date, exercises: entries)
            }
            return created
        }
    }

    // MARK: - 查询

    /// 按部位分组：组内按名字排序，组按部位名排序，「未分类」放最后。
    public func grouped() async throws -> [(bodyPart: String, exercises: [ExerciseDefinition])] {
        let items = try await library.allExercises().sortedForLibrary()
        var buckets: [String: [ExerciseDefinition]] = [:]
        for item in items { buckets[item.bodyPart, default: []].append(item) }
        let parts = buckets.keys.sorted { a, b in
            if a == ExerciseDefinition.uncategorized { return false }
            if b == ExerciseDefinition.uncategorized { return true }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return parts.map { (bodyPart: $0, exercises: buckets[$0] ?? []) }
    }

    /// 上次成绩：在 `date < before`（nil 表示不限）的场次里，取包含该动作且有组的**最近**一场，
    /// 返回该场此动作的最佳组（重量最大；同重量取次数多的）。没有则 nil。
    /// 按 `exerciseID` 匹配，不按名字。同一场里该动作出现多条时，各条的组一起比。
    public func lastPerformance(exerciseID: UUID, before: Date?) async throws -> LastPerformance? {
        for session in try await workouts.allSessions() {  // 日期降序
            if let before, !(session.date < before) { continue }
            let sets = session.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.sets)
            let best = sets.max { a, b in
                a.weight != b.weight ? a.weight < b.weight : a.reps < b.reps
            }
            if let best { return LastPerformance(date: session.date, bestSet: best) }
        }
        return nil
    }

    /// 最近动作：按最近一次使用的场次日期降序、去重，最多 `limit` 个。
    /// 只返回动作库里仍存在的条目（不存在的跳过，不占名额）；没有 id 的旧条目不算。
    public func recentExercises(limit: Int) async throws -> [ExerciseDefinition] {
        guard limit > 0 else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: try await library.allExercises().map { ($0.id, $0) })
        var seen = Set<UUID>()
        var result: [ExerciseDefinition] = []
        for session in try await workouts.allSessions() {
            for entry in session.exercises {
                guard let id = entry.exerciseID, let item = byID[id], seen.insert(id).inserted else { continue }
                result.append(item)
                if result.count == limit { return result }
            }
        }
        return result
    }

    /// 复制上次训练：最近一场训练的动作（按原顺序，映射为动作库当前的条目，跳过已不存在的与没有 id 的，同一动作只取一次）。
    /// 没有任何训练、或最近一场的动作一个都映射不上时返回 nil（不会退回更早的一场）。
    public func lastSessionTemplate() async throws -> SessionTemplate? {
        guard let latest = try await workouts.allSessions().first else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: try await library.allExercises().map { ($0.id, $0) })
        var seen = Set<UUID>()
        let exercises = latest.exercises.compactMap { entry -> ExerciseDefinition? in
            guard let id = entry.exerciseID, let item = byID[id], seen.insert(id).inserted else { return nil }
            return item
        }
        return exercises.isEmpty ? nil : SessionTemplate(date: latest.date, exercises: exercises)
    }

    // MARK: - 内部

    /// 对 `transform` 返回非 nil 的场次保存新版本。先用全量列表找出候选，再逐个更新。
    ///
    /// 候选列表读完之后、写回之前，用户可能已经删掉了某场训练（`HistoryViewModel` 直接删仓储，不经过本 service）。
    /// 所以写回是仓储内部**原子**的「仅当场次仍存在才更新」（`ConditionalSessionUpdating`）：
    /// 已被删除的场次什么都不写，绝不重新创建。这里不能用 `session(id:)` + `save` 两次 await 拼起来——
    /// 两次调用之间的删除会被 `save`（upsert）复活。
    private func rewriteSessions(_ transform: @escaping @Sendable (WorkoutSession) -> WorkoutSession?) async throws {
        let candidates = try await workouts.allSessions().filter { transform($0) != nil }.map(\.id)
        for id in candidates {
            _ = try await workouts.updateExisting(id: id, transform)
        }
    }

    /// 串行化会改数据的操作（actor 在 await 处可重入，不加这个两次 add 可能同时通过重名检查）。
    private func exclusive<T>(_ body: () async throws -> T) async throws -> T {
        if isBusy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            isBusy = true
        }
        defer {
            if waiters.isEmpty {
                isBusy = false
            } else {
                waiters.removeFirst().resume()
            }
        }
        return try await body()
    }
}
