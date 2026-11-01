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
    /// 指向动作库条目；旧版存储里没有这一列，打开时按 nil 迁移（可选属性，轻量迁移）。
    var exerciseID: UUID?
    var session: SessionRecord?
    @Relationship(deleteRule: .cascade, inverse: \SetRecord.exercise)
    var sets: [SetRecord] = []

    init(order: Int, name: String, exerciseID: UUID? = nil) {
        self.order = order
        self.name = name
        self.exerciseID = exerciseID
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

/// 动作库条目。与训练记录放在同一个存储里。
@Model
final class ExerciseDefinitionRecord {
    var id: UUID
    var name: String
    var bodyPart: String
    var photoFileName: String?

    init(id: UUID, name: String, bodyPart: String, photoFileName: String?) {
        self.id = id
        self.name = name
        self.bodyPart = bodyPart
        self.photoFileName = photoFileName
    }
}
