import SwiftUI
import TrainingRecordCore

/// 「历史」标签：列表 / 趋势 两个子页。每次切到本标签都由 ContentView 触发重新加载，
/// 保证刚在「记录」保存的训练能看到。
struct HistoryView: View {
    let model: HistoryViewModel

    @State private var selection: HistoryTab = HistoryView.initialSelection
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch selection {
                case .list:
                    listView
                case .trend:
                    TrendView(model: model)
                }
            }
            .navigationTitle("历史")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("视图", selection: $selection) {
                        ForEach(HistoryTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
            .safeAreaInset(edge: .top) {
                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.vertical, 6)
                        .accessibilityIdentifier(HistoryAccessibilityID.errorMessage)
                }
            }
            .navigationDestination(for: UUID.self) { sessionID in
                if let session = model.sessions.first(where: { $0.id == sessionID }) {
                    HistoryDetailView(session: session)
                }
            }
        }
        .task {
            await model.reload()
            #if DEBUG
            if HistoryDebugLaunch.opensFirstSession, let first = model.rows.first {
                path.append(first.id)
            }
            #endif
        }
    }

    private var listView: some View {
        Group {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "还没有训练",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("在「记录」里保存一次训练后，会出现在这里。")
                )
                .accessibilityIdentifier(HistoryAccessibilityID.emptyState)
            } else {
                List {
                    ForEach(model.rows) { row in
                        NavigationLink(value: row.id) {
                            HistoryRowView(row: row)
                        }
                        .accessibilityIdentifier(HistoryAccessibilityID.row)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await model.delete(id: row.id) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .accessibilityIdentifier(HistoryAccessibilityID.deleteButton)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier(HistoryAccessibilityID.list)
            }
        }
    }

    private static var initialSelection: HistoryTab {
        #if DEBUG
        HistoryDebugLaunch.initialSubtab ?? .list
        #else
        .list
        #endif
    }
}

/// 历史列表的一行：日期 + 动作名摘要 + 组数与总容量。
private struct HistoryRowView: View {
    let row: HistoryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.date, format: .dateTime.year().month().day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HistoryAccessibilityID.rowDate)
            Text(row.exerciseNames.joined(separator: "、"))
                .font(.body)
                .accessibilityIdentifier(HistoryAccessibilityID.rowSummary)
            Text("\(row.setCount) 组 · \(row.totalVolume.formatted(.number.precision(.fractionLength(0...1)))) kg")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(HistoryAccessibilityID.rowStats)
        }
    }
}

/// 历史子页：列表 / 趋势。
enum HistoryTab: String, CaseIterable, Identifiable {
    case list = "列表"
    case trend = "趋势"
    var id: String { rawValue }
}
