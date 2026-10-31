/// 历史界面关键控件的 accessibilityIdentifier，供 UI 测试使用。
/// 列表行、删除等按出现顺序取用。
enum HistoryAccessibilityID {
    static let list = "history.list"
    static let row = "history.row"
    static let rowDate = "history.rowDate"
    static let rowSummary = "history.rowSummary"
    static let rowStats = "history.rowStats"
    static let deleteButton = "history.deleteButton"
    static let emptyState = "history.emptyState"
    static let exercisePicker = "history.exercisePicker"
    static let trendChart = "history.trendChart"
    static let trendMetricToggle = "history.trendMetricToggle"
    static let detailList = "history.detailList"
    static let errorMessage = "history.errorMessage"
}
