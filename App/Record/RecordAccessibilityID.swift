/// 录入界面关键控件的 accessibilityIdentifier，供 UI 测试使用。
/// 有多个动作时，动作内控件（重量、次数、添加组等）在每个动作里使用同一个 id，按出现顺序取用。
enum RecordAccessibilityID {
    static let datePicker = "record.datePicker"
    static let exerciseNameField = "record.exerciseNameField"
    static let addExerciseButton = "record.addExerciseButton"
    static let exerciseNameError = "record.exerciseNameError"
    static let exerciseMenu = "record.exerciseMenu"
    static let weightField = "record.weightField"
    static let repsField = "record.repsField"
    static let addSetButton = "record.addSetButton"
    static let setInputError = "record.setInputError"
    static let saveButton = "record.saveButton"
    static let savedToast = "record.savedToast"
    static let retryButton = "record.retryButton"
}
