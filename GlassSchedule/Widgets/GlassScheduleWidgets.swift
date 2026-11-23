import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GlassScheduleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CourseLiveActivityWidget()
        NextClassWidget()
    }
}

// MARK: - 实时活动（锁屏 / 灵动岛 / Apple Watch 智能叠放）

struct CourseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            CourseActivityView(context: context)
                .activityBackgroundTint(Color(hex: context.attributes.colorHex).opacity(0.25))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let color = Color(hex: context.attributes.colorHex)
            return DynamicIsland {
                // leading/trailing 只放极简内容，避开传感器裁切区；倒计时居中
                DynamicIslandExpandedRegion(.leading) {
                    Color.clear.frame(width: 1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Color.clear.frame(width: 1)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        CountdownText(state: context.state)
                            .font(.title2.monospacedDigit().bold())
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text(timeRange(context.state))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        Text(context.attributes.courseName)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        HStack(spacing: 8) {
                            Text(context.attributes.periodText)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color)
                                .lineLimit(1)
                            if !context.state.classroom.isEmpty {
                                Label(context.state.classroom, systemImage: "mappin.and.ellipse")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                            Text(context.isStale ? "已下课" : (Date.now < context.state.start ? "即将上课" : "上课中"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(color)
                    }
                    .padding(.horizontal, 10)
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(color)
            } compactTrailing: {
                // 紧凑态用短格式，避免「9:02:57」被灵动岛右侧裁切
                CompactCountdownText(state: context.state)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .frame(minWidth: 28, maxWidth: 54, alignment: .trailing)
            } minimal: {
                Image(systemName: "book.fill")
                    .foregroundStyle(color)
            }
            .keylineTint(color)
        }
        .supplementalActivityFamilies([.small, .medium])
    }
}

struct CourseActivityView: View {
    let context: ActivityViewContext<CourseActivityAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        let color = Color(hex: context.attributes.colorHex)
        switch family {
        case .small:
            VStack(spacing: 4) {
                Text(context.attributes.courseName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                CountdownText(state: context.state)
                    .font(.title3.monospacedDigit().bold())
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(context.state.classroom)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
        default:
            // 锁屏横幅：倒计时居中，信息上下排布，避免左右分栏在小宽度上挤压
            VStack(spacing: 10) {
                Text(context.isStale ? "已下课" : (Date.now < context.state.start ? "即将上课" : "正在上课"))
                    .font(.caption.bold())
                    .foregroundStyle(color)
                    .frame(maxWidth: .infinity)

                Text(context.attributes.courseName)
                    .font(.title3.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                CountdownText(state: context.state)
                    .font(.largeTitle.monospacedDigit().bold())
                    .minimumScaleFactor(0.55)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(timeRange(context.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        activityMeta(context)
                    }
                    VStack(spacing: 4) {
                        activityMeta(context)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

                ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(color)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private func activityMeta(_ context: ActivityViewContext<CourseActivityAttributes>) -> some View {
        if !context.state.classroom.isEmpty {
            Label(context.state.classroom, systemImage: "mappin.and.ellipse")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        Label(context.attributes.periodText, systemImage: "number")
            .lineLimit(1)
    }
}

/// 上课前显示到上课的倒计时，上课后显示到下课的倒计时；系统会自动刷新数字。
struct CountdownText: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        let now = Date.now
        if now < state.start {
            Text(timerInterval: now...state.start, countsDown: true)
        } else if now < state.end {
            Text(timerInterval: now...state.end, countsDown: true)
        } else {
            Text("已下课")
        }
    }
}

/// 紧凑灵动岛用：长倒计时显示「H:MM」，短倒计时显示「M:SS」，避免被裁切。
struct CompactCountdownText: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let target: Date? = {
                if now < state.start { return state.start }
                if now < state.end { return state.end }
                return nil
            }()
            if let target {
                let remaining = max(0, Int(target.timeIntervalSince(now)))
                Text(compactCountdownString(remaining))
                    .monospacedDigit()
            } else {
                Text("结束")
            }
        }
    }

    private func compactCountdownString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d", h, m)
        }
        return String(format: "%d:%02d", m, s)
    }
}

private func timeRange(_ state: CourseActivityAttributes.ContentState) -> String {
    let f = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute()
    return "\(state.start.formatted(f))–\(state.end.formatted(f))"
}

// MARK: - 下一节课小组件

struct NextClassEntry: TimelineEntry {
    let date: Date
    let occurrence: ClassOccurrence?
    let remainingToday: Int
}

struct NextClassProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextClassEntry {
        let sample = CourseSnapshot(id: UUID(), name: "高等数学", classroom: "教三-305", teacher: "", major: "",
                                    weekday: 1, startPeriod: 1, endPeriod: 2, startMinutes: 480, endMinutes: 575,
                                    weeks: [], colorHex: "4F8EF7")
        return NextClassEntry(date: .now,
                              occurrence: ClassOccurrence(course: sample, start: .now.addingTimeInterval(1_800),
                                                          end: .now.addingTimeInterval(7_500), week: 1),
                              remainingToday: 3)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextClassEntry) -> Void) {
        completion(entries(from: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextClassEntry>) -> Void) {
        let list = entries(from: .now)
        completion(Timeline(entries: list, policy: .after(list.last?.date.addingTimeInterval(3_600) ?? .now.addingTimeInterval(3_600))))
    }

    /// 在每节课开始、结束时各生成一个条目，保证小组件按时切换到下一节。
    private func entries(from now: Date) -> [NextClassEntry] {
        guard let payload = SharedSettings.payload else { return [NextClassEntry(date: now, occurrence: nil, remainingToday: 0)] }
        let upcoming = ScheduleQuery.occurrences(of: payload.courses, from: now, to: now.addingTimeInterval(2 * 86_400),
                                                 semesterStart: payload.semesterStart)
        var dates = [now] + upcoming.flatMap { [$0.start, $0.end] }.filter { $0 > now }
        dates = Array(dates.prefix(20))
        return dates.map { date in
            let next = upcoming.first { $0.end > date }
            let endOfDay = SemesterCalendar.calendar.startOfDay(for: date).addingTimeInterval(86_400)
            let remaining = upcoming.filter { $0.end > date && $0.start < endOfDay }.count
            return NextClassEntry(date: date, occurrence: next, remainingToday: remaining)
        }
    }
}

struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextClassWidget", provider: NextClassProvider()) { entry in
            NextClassWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(hex: entry.occurrence?.course.colorHex ?? "4F8EF7").opacity(0.35), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("下一节课")
        .description("显示下一节课的名称、教室和时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextClassWidgetView: View {
    let entry: NextClassEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let occurrence = entry.occurrence {
            let course = occurrence.course
            switch family {
            case .accessoryInline:
                Text("\(TimeFormat.string(course.startMinutes)) \(course.name) @\(course.classroom)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "book.fill")
                    Text(TimeFormat.string(course.startMinutes)).font(.caption2.monospacedDigit())
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                    Text("\(course.classroom) · \(course.timeText)").font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                    Text(occurrence.start, style: .relative).font(.caption2)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text(occurrence.isOngoing(at: entry.date) ? "正在上课" : "下一节")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: course.colorHex))
                    Text(course.name).font(.headline).lineLimit(2).minimumScaleFactor(0.75)
                    Label(course.classroom.isEmpty ? "未设置教室" : course.classroom, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Label("\(course.periodText) \(course.timeText)", systemImage: "clock")
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if family == .systemMedium {
                        Text("今天还有 \(entry.remainingToday) 节课").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                Text("近期没有课").font(.caption)
            }
        }
    }
}
