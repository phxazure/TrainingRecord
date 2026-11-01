/// 动作库、动作详情、动作编辑、选择动作页关键控件的 accessibilityIdentifier，供 UI 测试使用。
enum LibraryAccessibilityID {
    static let list = "library.list"
    static let row = "library.row"
    static let addButton = "library.addButton"
    static let emptyState = "library.emptyState"
    static let emptyAddButton = "library.emptyAddButton"
}

enum ExerciseDetailAccessibilityID {
    static let root = "exerciseDetail.root"
    static let header = "exerciseDetail.header"
    static let chart1RM = "exerciseDetail.chart1RM"
    static let chartVolume = "exerciseDetail.chartVolume"
    /// 数据列表的每一行 / 最近记录的每一条（行级 id；Section 上加 id 会下传覆盖子元素）。
    static let dataList = "exerciseDetail.dataRow"
    static let recentRecords = "exerciseDetail.recordRow"
    static let editButton = "exerciseDetail.editButton"
    static let empty = "exerciseDetail.empty"
}

enum ExerciseEditAccessibilityID {
    static let root = "exerciseEdit.root"
    static let nameField = "exerciseEdit.nameField"
    static let partField = "exerciseEdit.partField"
    static let partChip = "exerciseEdit.partChip"
    static let duplicateError = "exerciseEdit.duplicateError"
    static let photoPicker = "exerciseEdit.photoPicker"
    static let removePhoto = "exerciseEdit.removePhoto"
    static let saveButton = "exerciseEdit.saveButton"
    static let mergeButton = "exerciseEdit.mergeButton"
    static let deleteButton = "exerciseEdit.deleteButton"
    static let saveError = "exerciseEdit.saveError"
}

enum MergePickerAccessibilityID {
    static let root = "mergePicker.root"
    static let row = "mergePicker.row"
}

enum PickerAccessibilityID {
    static let root = "exercisePicker.root"
    static let searchField = "exercisePicker.searchField"
    static let row = "exercisePicker.row"
    static let newButton = "exercisePicker.newButton"
    static let emptyState = "exercisePicker.emptyState"
}
