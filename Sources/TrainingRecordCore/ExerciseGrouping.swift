import Foundation

/// 按训练部位分组（动作库列表、选择动作页用）：组内按名字排序（localizedStandardCompare），
/// 组按部位名排序，「未分类」放最后。空部位名视为「未分类」。
public func groupByBodyPart(_ items: [ExerciseDefinition]) -> [(bodyPart: String, exercises: [ExerciseDefinition])] {
    var buckets: [String: [ExerciseDefinition]] = [:]
    for item in items.sortedForLibrary() { buckets[item.bodyPart, default: []].append(item) }
    let parts = buckets.keys.sorted { a, b in
        if a == ExerciseDefinition.uncategorized { return false }
        if b == ExerciseDefinition.uncategorized { return true }
        return a.localizedStandardCompare(b) == .orderedAscending
    }
    return parts.map { (bodyPart: $0, exercises: buckets[$0] ?? []) }
}
