import SwiftUI
import TrainingRecordCore

/// 动作详情：四处入口（动作库、历史明细、趋势、训练页的选择动作）共用的**同一个**视图。
/// 照片、名字、部位；最佳 1RM 和容量两张折线图**上下并列**（不切换）；按日期倒序的数据；最近几次记录；工具栏「编辑」。
struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var app
    let exerciseID: UUID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let exercise = app.library.definition(id: exerciseID) {
                content(for: exercise)
            } else {
                ContentUnavailableView("找不到这个动作", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(app.library.definition(id: exerciseID)?.name ?? "动作")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: ExerciseEditRoute(id: exerciseID)) {
                    Text("编辑")
                        .frame(minHeight: Space.hit)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier(ExerciseDetailAccessibilityID.editButton)
            }
        }
        .accessibilityIdentifier(ExerciseDetailAccessibilityID.root)
    }

    private func content(for exercise: ExerciseDefinition) -> some View {
        let sessions = app.history.sessions
        let points = exerciseTrend(for: exercise, in: sessions)
        let records = recentRecords(of: exercise.id, in: sessions, limit: 5)
        return List {
            Section { header(exercise) }

            if points.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("还没有训练记录", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("在「训练」里记录一次这个动作，趋势就会出现在这里。")
                    }
                    .accessibilityIdentifier(ExerciseDetailAccessibilityID.empty)
                }
            } else {
                Section {
                    MetricChartCard(
                        title: "最佳 1RM",
                        color: .metricStrength,
                        points: points.enumerated().map { .init(id: $0.offset, date: $0.element.date, value: $0.element.bestE1RM) },
                        format: Format.oneRM,
                        deltaFraction: 1,
                        identifier: ExerciseDetailAccessibilityID.chart1RM
                    )
                }
                Section {
                    MetricChartCard(
                        title: "容量",
                        color: .metricVolume,
                        points: points.enumerated().map { .init(id: $0.offset, date: $0.element.date, value: $0.element.volume) },
                        format: Format.volume,
                        deltaFraction: 0,
                        identifier: ExerciseDetailAccessibilityID.chartVolume
                    )
                }
                Section {
                    ForEach(Array(points.indices.reversed()), id: \.self) { index in
                        dataRow(points[index])
                    }
                } header: {
                    sectionTitle("数据")
                }

                Section {
                    ForEach(records, id: \.sessionID) { record in
                        recordRow(record)
                    }
                } header: {
                    sectionTitle("最近记录")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func header(_ exercise: ExerciseDefinition) -> some View {
        // 大字号：照片在上、文字在下，名字不被挤成窄栏。
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s3))
            : AnyLayout(HStackLayout(spacing: Space.s4))
        return layout {
            ExercisePhotoView(fileName: exercise.photoFileName, size: Metrics.photoLarge)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(exercise.name)
                    .font(.title2.weight(.bold))
                Text(exercise.bodyPart)
                    .font(.subheadline)
                    .foregroundStyle(.label2)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ExerciseDetailAccessibilityID.header)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.label2)
            .textCase(nil)
    }

    /// 数据列表：日期 → 1RM（metric-strength）｜容量（metric-volume），给 VoiceOver 和精确读数用。
    private func dataRow(_ point: ExerciseTrendPoint) -> some View {
        HStack(spacing: Space.s3) {
            Text(point.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.body)
            Spacer(minLength: Space.s2)
            ValueWithUnit(value: Format.oneRM(point.bestE1RM), unit: "kg", valueColor: .metricStrength)
            ValueWithUnit(value: Format.volume(point.volume), unit: "kg", valueColor: .metricVolume)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ExerciseDetailAccessibilityID.dataList)
    }

    /// 最近一次记录：日期 + 各组「重量 × 次数」。
    private func recordRow(_ record: ExerciseRecordEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(record.date.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
                .font(.subheadline)
                .foregroundStyle(.label2)
            ForEach(record.sets.indices, id: \.self) { index in
                HStack(spacing: Space.s3) {
                    NumberBadge(number: index + 1)
                    SetValue(weight: record.sets[index].weight, reps: record.sets[index].reps)
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(ExerciseDetailAccessibilityID.recentRecords)
    }
}
