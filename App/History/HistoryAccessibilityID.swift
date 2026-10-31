/// 历史、明细、趋势界面关键控件的 accessibilityIdentifier，供 UI 测试使用。
/// 列表行、删除等按出现顺序取用。
/// 趋势从「历史」里移成独立标签后，选动作 / 指标分段 / 趋势图沿用原来的字符串值。
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
    static let weekSummary = "history.weekSummary"
    static let loading = "history.loading"
    static let goRecordButton = "history.goRecordButton"
    static let retryButton = "history.retryButton"
    static let viewTrendButton = "history.viewTrendButton"
}

/// 趋势标签新增的 id。
enum TrendAccessibilityID {
    static let root = "trend.root"
    static let dataList = "trend.dataList"
    static let currentValue = "trend.currentValue"
    static let emptyState = "trend.emptyState"
    static let singlePoint = "trend.singlePoint"
}
