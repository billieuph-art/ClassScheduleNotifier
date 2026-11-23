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
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.periodText, systemImage: "book.fill")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(state: context.state)
                        .font(.title3.monospacedDigit().bold())
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.courseName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack {
                            Label(context.state.classroom, systemImage: "mappin.and.ellipse")
                            Spacer()
                            Text(timeRange(context.state))
                        }
                        .font(.caption)
                        ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(color)
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill").foregroundStyle(color)
            } compactTrailing: {
                CountdownText(state: context.state)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "book.fill").foregroundStyle(color)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.courseName).font(.headline).lineLimit(1)
                Text(context.state.classroom).font(.caption).lineLimit(1)
                CountdownText(state: context.state).font(.caption.monospacedDigit()).foregroundStyle(color)
            }
            .padding(6)
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.isStale ? "已下课" : (Date.now < context.state.start ? "即将上课" : "正在上课"))
                            .font(.caption.bold())
                            .foregroundStyle(color)
                        Text(context.attributes.courseName).font(.title3.bold()).lineLimit(1)
                        HStack(spacing: 10) {
                            Label(context.state.classroom, systemImage: "mappin.and.ellipse")
                            Label(context.attributes.periodText, systemImage: "number")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        CountdownText(state: context.state).font(.title.monospacedDigit().bold())
                        Text(timeRange(context.state)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(color)
            }
            .padding(16)
        }
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
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "book.fill")
                    Text(TimeFormat.string(course.startMinutes)).font(.caption2.monospacedDigit())
                }
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text(course.name).font(.headline).lineLimit(1)
                    Text("\(course.classroom) · \(course.timeText)").font(.caption).lineLimit(1)
                    Text(occurrence.start, style: .relative).font(.caption2)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Text(occurrence.isOngoing(at: entry.date) ? "正在上课" : "下一节")
                        .font(.caption.bold())
                        .foregroundStyle(Color(hex: course.colorHex))
                    Text(course.name).font(.headline).lineLimit(2)
                    Label(course.classroom.isEmpty ? "未设置教室" : course.classroom, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                    Label("\(course.periodText) \(course.timeText)", systemImage: "clock").font(.caption)
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
