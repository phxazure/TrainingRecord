import Foundation
import SwiftData

// SwiftData 存储模型（仅本模块内部使用，不对外暴露）。
// 关系在 SwiftData 里默认无序，所以动作和组都带显式的 `order`，读取时按它排序；
// 不依赖数组或存储层的返回顺序。

@Model
final class SessionRecord {
    var id: UUID
    var date: Date
    @Relationship(deleteRule: .cascade, inverse: \ExerciseRecord.session)
    var exercises: [ExerciseRecord] = []

    init(id: UUID, date: Date) {
        self.id = id
        self.date = date
    }
}

@Model
final class ExerciseRecord {
    /// 在所属场次中的位置（从 0 起）。
    var order: Int
    var name: String
    var session: SessionRecord?
    @Relationship(deleteRule: .cascade, inverse: \SetRecord.exercise)
    var sets: [SetRecord] = []

    init(order: Int, name: String) {
        self.order = order
        self.name = name
    }
}

@Model
final class SetRecord {
    /// 在所属动作中的位置（从 0 起）。
    var order: Int
    var weight: Double
    var reps: Int
    var exercise: ExerciseRecord?

    init(order: Int, weight: Double, reps: Int) {
        self.order = order
        self.weight = weight
        self.reps = reps
    }
}
