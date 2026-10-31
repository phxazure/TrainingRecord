import SwiftUI
import TrainingRecordCore

/// 「历史」标签：本周汇总 + 按月分组的训练列表；点行进明细，左滑删除。
/// 每次切到本标签都由 ContentView 触发重新加载，保证刚在「训练」保存的训练能看到。
struct HistoryView: View {
    @Environment(AppModel.self) private var app

    private var model: HistoryViewModel { app.history }
    @State private var hasLoaded = false
    @State private var lastAction: Action = .load

    private enum Action { case load, delete }

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.historyPath) {
            content
                .navigationTitle("历史")
                .navigationDestination(for: UUID.self) { sessionID in
                    if let session = model.sessions.first(where: { $0.id == sessionID }) {
                        HistoryDetailView(session: session)
                    }
                }
                .exerciseDestinations()
        }
        .task { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded && model.rows.isEmpty {
            // 首次加载且没有旧数据；之后的刷新静默进行。
            ProgressView {
                Text("正在加载…")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            .accessibilityIdentifier(HistoryAccessibilityID.loading)
        } else if model.rows.isEmpty && model.errorMessage == nil {
            ContentUnavailableView {
                Label("还没有训练记录", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("在「训练」里保存一次训练，就会出现在这里。")
            } actions: {
                Button("去训练") { app.selectedTab = .record }
                    .buttonStyle(ProminentCapsuleButtonStyle())
                    .accessibilityIdentifier(HistoryAccessibilityID.goRecordButton)
            }
            // 先声明为容器再加 id：否则 id 会下传给子按钮，覆盖 history.goRecordButton。
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(HistoryAccessibilityID.emptyState)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if model.errorMessage != nil {
                Section { errorCard }
            }
            if !model.rows.isEmpty {
                WeekSummaryCard(summary: WeekSummary.make(rows: model.rows, now: .now))
                ForEach(MonthGroup.group(model.rows)) { group in
                    Section {
                        ForEach(group.rows) { row in
                            NavigationLink(value: row.id) {
                                HistoryRowView(row: row)
                            }
                            .accessibilityIdentifier(HistoryAccessibilityID.row)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await delete(row.id) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .tint(.danger)
                                .foregroundStyle(.onDanger)
                                .accessibilityIdentifier(HistoryAccessibilityID.deleteButton)
                            }
                        }
                    } header: {
                        Text(monthTitle(for: group.firstDate))
                            .font(.footnote)
                            .foregroundStyle(.label2)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(HistoryAccessibilityID.list)
        .refreshable { await reload() }
    }

    /// 列表顶部错误卡片（§8.8）：加载失败保留上次结果并可重试；删除失败说明训练还在。
    private var errorCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s1) {
                switch lastAction {
                case .load:
                    Text("无法加载训练历史").font(.headline)
                    Text("下面是上次加载的结果。")
                        .font(.subheadline)
                        .foregroundStyle(.label2)
                case .delete:
                    Text("删除失败，这次训练还在。").font(.headline)
                }
            }
            Spacer(minLength: Space.s2)
            if lastAction == .load {
                Button("重试") { Task { await reload() } }
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: Space.hit)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(HistoryAccessibilityID.retryButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HistoryAccessibilityID.errorMessage)
    }

    private func reload() async {
        lastAction = .load
        await model.reload()
        hasLoaded = true
    }

    private func delete(_ id: UUID) async {
        await model.delete(id: id)
        if model.errorMessage != nil { lastAction = .delete }
    }

    /// 「10月」；不是今年时带年份「2025年10月」。
    private func monthTitle(for date: Date) -> String {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear
            ? date.formatted(.dateTime.month())
            : date.formatted(.dateTime.year().month())
    }
}

/// 本周汇总卡片：训练次数、容量（metric-volume）、哪几天练过（周一起）。
private struct WeekSummaryCard: View {
    let summary: WeekSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let weekdayLabels = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Space.s3) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s3))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: Space.s4))
                layout {
                    stat("训练") {
                        ValueWithUnit(
                            value: "\(summary.sessionCount)",
                            unit: "次",
                            style: .title2,
                            weight: .bold
                        )
                    }
                    stat("容量") {
                        ValueWithUnit(
                            value: Format.volume(summary.volume),
                            unit: "kg",
                            style: .title2,
                            weight: .bold,
                            valueColor: .metricVolume
                        )
                    }
                }
                Divider()
                weekdayDots
            }
            .padding(.vertical, Space.s1)
            .accessibilityIdentifier(HistoryAccessibilityID.weekSummary)
        } header: {
            Text("本周 · \(summary.startDate.formatted(.dateTime.month().day()))–\(summary.endDate.formatted(.dateTime.month().day()))")
                .font(.footnote)
                .foregroundStyle(.label2)
                .textCase(nil)
        }
    }

    private func stat<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.label2)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekdayDots: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let active = summary.activeWeekdays.contains(index)
                VStack(spacing: Space.s1) {
                    Circle()
                        .fill(active ? Color.accentColor : Color.surface2)
                        .frame(width: Space.s6, height: Space.s6)
                    Text(Self.weekdayLabels[index])
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.label2)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("周\(Self.weekdayLabels[index])")
                .accessibilityValue(active ? "练过" : "没练")
            }
        }
    }
}

/// 历史列表的一行（§8.5）：日期块 ｜ 动作名 + 组数 ｜ 容量（metric-volume）。
private struct HistoryRowView: View {
    let row: HistoryRow
    @ScaledMetric(relativeTo: .title2) private var dateColumnWidth: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Space.s3) {
            VStack(spacing: 0) {
                // 只要数字：`.dateTime.day()` 在中文环境会带「日」字。
                Text("\(Calendar.current.component(.day, from: row.date))")
                    .numeric(.title2, weight: .bold)
                Text(row.date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.label2)
            }
            .frame(width: dateColumnWidth)
            .accessibilityIdentifier(HistoryAccessibilityID.rowDate)

            VStack(alignment: .leading, spacing: Space.s1) {
                Text(row.exerciseNames.joined(separator: "、"))
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .accessibilityIdentifier(HistoryAccessibilityID.rowSummary)
                Text("\(row.setCount) 组")
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            Spacer(minLength: Space.s2)
            ValueWithUnit(value: Format.volume(row.totalVolume), unit: "kg", valueColor: .metricVolume)
                .accessibilityIdentifier(HistoryAccessibilityID.rowStats)
        }
    }
}
