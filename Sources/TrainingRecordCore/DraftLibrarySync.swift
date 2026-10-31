import Foundation

extension RecordViewModel {
    /// 让现有训练草稿跟随动作库的变化（改名、合并、删除），保存时不会写出旧名字或悬空的动作 id，也不会丢已录入的内容。
    ///
    /// **就地更新**：草稿动作的 id、已录入的组（重量、次数、顺序、组 id）都原样不动，只改动作名和动作库 id——
    /// 所以界面上还没点「添加」的输入也不会丢（视图身份不变），重量等数值不经任何格式化往返。
    ///
    /// 对草稿里每个从动作库添加的动作（有 `exerciseID`）：
    /// - 沿 `merged`（被并入的 id → 目标 id，可连续）找到最终 id；库里有它 → 改成库里的当前名字和最终 id；
    /// - 库里已经没有它（删除，且没有合并去向）→ 断开关联，变成**自由输入**的动作（保留名字和所有组），
    ///   这样保存不会写出指向不存在条目的 id；
    /// - 合并后草稿里出现两个同一动作（或改名后与另一个自由输入的名字相同）→ 并成一个，留在第一个出现的位置，
    ///   组按原顺序拼接（后面那个动作被移除，它还没提交的输入框内容随之消失）。
    /// 没有 id 的自由输入动作原样保留。日期不变。
    ///
    /// 正在保存（`isSaving`）时什么都不做（保存成功后要按组 id 从草稿移除快照里的组，同步应等保存结束）；
    /// 保存完成后再同步一次即可。没有任何变化时返回 false 且不改动草稿。
    ///
    /// - Parameters:
    ///   - library: 动作库当前的全部条目（必须是**本次成功读到**的结果；读取失败时不要拿旧缓存或空数组来同步）。
    ///   - merged: 合并记录：被并入（已删除）的动作 id → 目标动作 id。
    /// - Returns: 草稿是否被改动。
    @discardableResult
    public func syncExercises(with library: [ExerciseDefinition], merged: [UUID: UUID] = [:]) -> Bool {
        guard !isSaving else { return false }

        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        // 已处理（保留）的动作：草稿 id、当前的关联 id（自由输入为 nil）、名字小写。
        var kept: [(draftID: ExerciseDraft.ID, linkedID: UUID?, nameKey: String)] = []

        for draft in exercises {
            var newName = draft.name
            var newLinkedID: UUID?
            if let linked = exerciseID(of: draft.id) {
                let finalID = Self.resolve(linked, through: merged)
                if let definition = byID[finalID] {
                    newName = definition.name
                    newLinkedID = definition.id
                }  // 否则：库里没有，断开关联（保留名字）
            }

            let key = newName.lowercased()
            if let index = kept.firstIndex(where: { existing in
                (newLinkedID != nil && existing.linkedID == newLinkedID) || existing.nameKey == key
            }) {
                // 同一个动作出现了两次：把这个的组接到前一个上，移除这个。
                let existing = kept[index]
                if existing.linkedID == nil, let newLinkedID {
                    updateExercise(existing.draftID, name: newName, exerciseID: newLinkedID)  // 自由输入并上了关联的 → 采用关联
                    kept[index] = (existing.draftID, newLinkedID, key)
                }
                moveSets(from: draft.id, into: existing.draftID)
                changed = true
                continue
            }

            if newName != draft.name || newLinkedID != exerciseID(of: draft.id) {
                updateExercise(draft.id, name: newName, exerciseID: newLinkedID)
                changed = true
            }
            kept.append((draft.id, newLinkedID, key))
        }
        return changed
    }

    /// 沿合并记录走到最终 id；有环时返回起点（调用方随后会因库里找不到而断开关联）。
    private static func resolve(_ id: UUID, through merged: [UUID: UUID]) -> UUID {
        var current = id
        var seen: Set<UUID> = [id]
        while let next = merged[current] {
            if !seen.insert(next).inserted { return id }  // 环
            current = next
        }
        return current
    }
}
