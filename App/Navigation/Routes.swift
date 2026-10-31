import Foundation

/// 动作详情（四处入口共用同一个视图）。
struct ExerciseRoute: Hashable {
    let id: UUID
}

/// 动作编辑 / 新建页。`id == nil` 表示新建。
struct ExerciseEditRoute: Hashable {
    var id: UUID?
    /// 新建成功后是否把它加进当前训练（从「选择动作」页进来时为 true）。
    var addToRecord = false
    /// 新建时预填的名字（来自选择动作页的搜索词）。
    var prefillName = ""
}

/// 合并记录：选择目标动作。
struct MergePickerRoute: Hashable {
    let sourceID: UUID
}

/// 训练标签里的二级页面。
enum RecordRoute: Hashable {
    case picker
}

enum AppTab: Hashable {
    case record
    case library
    case history
    case trend
}
