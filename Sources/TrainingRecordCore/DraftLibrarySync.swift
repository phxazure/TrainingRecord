import Foundation

extension RecordViewModel {
    /// 让现有训练草稿跟随动作库的变化（改名、合并、删除），保存时不会写出旧名字或悬空的动作 id，也不会丢已录入的组。
    ///
    /// 对草稿里每个从动作库添加的动作（有 `exerciseID`）：
    /// - 沿 `merged`（被并入的 id → 目标 id，可连续）找到最终 id；库里有它 → 改成库里的当前名字和最终 id，组原样保留；
    /// - 库里已经没有它（删除，且没有合并去向）→ 变成**自由输入**的动作（保留名字和所有组，不再带 id），
    ///   这样保存不会写出指向不存在条目的 id，已录入的组也不会丢；
    /// - 合并后草稿里出现两个同一动作 → 并成一个，放在第一个出现的位置，组按原顺序拼接。
    /// 没有 id 的自由输入动作原样保留。日期不变。
    ///
    /// 正在保存（`isSaving`）时什么都不做（保存成功后要按组 id 从草稿移除快照里的组，此时重建草稿会让它对不上）；
    /// 保存完成后再同步一次即可。没有任何变化时返回 false 且不改动草稿（组 id、动作 id 保持不变）。
    ///
    /// - Parameters:
    ///   - library: 动作库当前的全部条目（必须是成功加载的结果；不要拿加载失败时的空数组来同步）。
    ///   - merged: 合并记录：被并入（已删除）的动作 id → 目标动作 id。
    /// - Returns: 草稿是否被改动。
    @discardableResult
    public func syncExercises(with library: [ExerciseDefinition], merged: [UUID: UUID] = [:]) -> Bool {
        guard !isSaving else { return false }

        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [SyncItem] = []
        var changed = false

        for draft in exercises {
            var item = SyncItem(target: .free(draft.name), sets: draft.sets)
            if let linked = exerciseID(of: draft.id) {
                let finalID = Self.resolve(linked, through: merged)
                if let definition = byID[finalID] {
                    item.target = .linked(definition)
                    if finalID != linked || definition.name != draft.name { changed = true }
                } else {
                    changed = true  // 变成自由输入
                }
            }
            if let index = items.firstIndex(where: { $0.target.sameExercise(as: item.target) }) {
                items[index].sets += item.sets
                changed = true
            } else {
                items.append(item)
            }
        }
        guard changed else { return false }

        for draft in exercises { removeExercise(id: draft.id) }
        for item in items {
            let added: Bool
            switch item.target {
            case .linked(let definition): added = addExercise(definition)
            case .free(let name): added = addExercise(name: name)
            }
            let draftID: ExerciseDraft.ID?
            if added {
                draftID = exercises.last?.id
            } else {
                // 同名的动作已经在草稿里（例如自由输入的名字和改名后的名字相同）：并进去，不丢组。
                let key = item.target.name.lowercased()
                draftID = exercises.first { $0.name.lowercased() == key }?.id
            }
            guard let draftID else { continue }
            for set in item.sets {
                addSet(toExercise: draftID, weightText: Self.text(of: set.weight), repsText: String(set.reps))
            }
        }
        return true
    }

    private struct SyncItem {
        var target: SyncTarget
        var sets: [SetDraft]
    }

    private enum SyncTarget {
        case linked(ExerciseDefinition)
        case free(String)

        var name: String {
            switch self {
            case .linked(let definition): definition.name
            case .free(let name): name
            }
        }

        func sameExercise(as other: SyncTarget) -> Bool {
            switch (self, other) {
            case (.linked(let a), .linked(let b)): a.id == b.id
            case (.free(let a), .free(let b)): a.lowercased() == b.lowercased()
            default: false
            }
        }
    }

    /// 沿合并记录走到最终 id；有环或过长时停在当前位置（调用方随后会因库里找不到而当作自由输入处理）。
    private static func resolve(_ id: UUID, through merged: [UUID: UUID]) -> UUID {
        var current = id
        var seen: Set<UUID> = [id]
        while let next = merged[current] {
            if !seen.insert(next).inserted { return id }  // 环
            current = next
        }
        return current
    }

    /// 重量转回输入框文本，保证 `SetInputParser.parseWeight` 解析回完全相同的数值（不出现科学计数法）。
    private static func text(of weight: Double) -> String {
        var text = String(format: "%.12f", weight)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
