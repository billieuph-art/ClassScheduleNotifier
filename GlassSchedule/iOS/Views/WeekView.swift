import SwiftData
import SwiftUI

struct WeekView: View {
    @Query private var courses: [Course]
    @AppStorage(SharedSettings.Key.semesterStart, store: SharedSettings.defaults) private var semesterStartRaw: Double = 0
    @AppStorage(SharedSettings.Key.showWeekend, store: SharedSettings.defaults) private var showWeekend = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var week: Int?
    @State private var editing: Course?
    @State private var creating = false
    @State private var gridWidth: CGFloat = 0

    private let headerHeight: CGFloat = 40

    private var semesterStart: Date { Date(timeIntervalSinceReferenceDate: semesterStartRaw) }
    private var currentWeek: Int { max(1, SemesterCalendar.weekNumber(of: .now, semesterStart: semesterStart)) }
    private var displayedWeek: Int { week ?? currentWeek }
    private var slots: [PeriodSlot] { SharedSettings.periodSlots }
    private var days: [Int] {
        let hasWeekendClass = courses.contains { $0.weekday >= 6 }
        return Array(1...((showWeekend || hasWeekendClass) ? 7 : 5))
    }

    private var timelineStart: Int { slots.map(\.startMinutes).min() ?? 8 * 60 }
    private var timelineEnd: Int { max(timelineStart + 60, slots.map(\.endMinutes).max() ?? 22 * 60) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    weekPicker
                    grid
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 20)
            }
            .background(GlassBackground())
            .navigationTitle("课表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加课程", systemImage: "plus") { creating = true }
                }
            }
            .sheet(item: $editing) { CourseEditorView(course: $0) }
            .sheet(isPresented: $creating) { CourseEditorView(course: nil) }
        }
    }

    private var weekPicker: some View {
        GlassEffectContainer {
            HStack {
                Button("上一周", systemImage: "chevron.left") { week = max(1, displayedWeek - 1) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                Spacer()
                VStack(spacing: 0) {
                    Text("第 \(displayedWeek) 周").font(.headline)
                    if displayedWeek != currentWeek {
                        Button("回到本周") { week = nil }.font(.caption)
                    } else {
                        Text("本周").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("下一周", systemImage: "chevron.right") { week = min(30, displayedWeek + 1) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
        }
    }

    private var grid: some View {
        let width = gridWidth > 0 ? gridWidth : 360
        let metrics = GridMetrics(width: width, dayCount: days.count, sizeClass: horizontalSizeClass)
        let timelineHeight = CGFloat(max(60, timelineEnd - timelineStart)) * metrics.pointsPerMinute

        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                Color.clear.frame(width: metrics.periodColumnWidth, height: headerHeight)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 0) {
                        Text(metrics.compactHeaders ? WeekdayName.short(day) : WeekdayName.full(day))
                            .font(.caption.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(dateText(for: day))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: metrics.columnWidth, height: headerHeight)
                    .background(isToday(day) ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 8))
                }
            }

            ForEach(slots) { slot in
                let top = yOffset(for: slot.startMinutes, ppm: metrics.pointsPerMinute)
                let height = max(26, CGFloat(max(1, slot.endMinutes - slot.startMinutes)) * metrics.pointsPerMinute)
                HStack(spacing: 0) {
                    VStack(spacing: 1) {
                        Text("\(slot.index)").font(.caption.bold())
                        Text(TimeFormat.string(slot.startMinutes))
                            .font(.system(size: metrics.timeFontSize))
                            .foregroundStyle(.secondary)
                        Text(TimeFormat.string(slot.endMinutes))
                            .font(.system(size: metrics.timeFontSize))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(width: metrics.periodColumnWidth, height: height, alignment: .top)
                    .padding(.top, 2)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(.quaternary.opacity(0.22))
                        .frame(height: height)
                        .padding(.trailing, 2)
                }
                .offset(y: headerHeight + top)
            }

            ForEach(courses.filter { $0.snapshot.occurs(inWeek: displayedWeek) && days.contains($0.weekday) }) { course in
                let column = CGFloat(days.firstIndex(of: course.weekday) ?? 0)
                let start = resolvedStart(course)
                let end = resolvedEnd(course)
                let top = yOffset(for: start, ppm: metrics.pointsPerMinute)
                let height = max(26, CGFloat(max(1, end - start)) * metrics.pointsPerMinute - 3)
                CourseBlock(course: course, compact: metrics.compactHeaders)
                    .frame(width: max(28, metrics.columnWidth - 4), height: height)
                    .offset(x: metrics.periodColumnWidth + column * metrics.columnWidth + 2,
                            y: headerHeight + top + 1)
                    .onTapGesture { editing = course }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: headerHeight + timelineHeight + 8, alignment: .topLeading)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: WeekGridWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(WeekGridWidthKey.self) { gridWidth = $0 }
    }

    private func yOffset(for minutes: Int, ppm: CGFloat) -> CGFloat {
        CGFloat(minutes - timelineStart) * ppm
    }

    private func resolvedStart(_ course: Course) -> Int {
        if let s = PeriodTable.slot(course.startPeriod, in: slots) { return s.startMinutes }
        return course.startMinutes
    }

    private func resolvedEnd(_ course: Course) -> Int {
        if let e = PeriodTable.slot(course.endPeriod, in: slots) { return e.endMinutes }
        return max(course.startMinutes + 1, course.endMinutes)
    }

    private func date(for day: Int) -> Date {
        let cal = SemesterCalendar.calendar
        let firstMonday = cal.dateInterval(of: .weekOfYear, for: semesterStart)?.start ?? semesterStart
        return cal.date(byAdding: .day, value: (displayedWeek - 1) * 7 + day - 1, to: firstMonday) ?? .now
    }

    private func dateText(for day: Int) -> String {
        date(for: day).formatted(.dateTime.month(.defaultDigits).day())
    }

    private func isToday(_ day: Int) -> Bool {
        SemesterCalendar.calendar.isDateInToday(date(for: day))
    }
}

private struct WeekGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 课表网格度量：按可用宽度调整节次列与纵向密度，不整体等比缩放 UI。
private struct GridMetrics {
    let periodColumnWidth: CGFloat
    let columnWidth: CGFloat
    let pointsPerMinute: CGFloat
    let compactHeaders: Bool
    let timeFontSize: CGFloat

    init(width: CGFloat, dayCount: Int, sizeClass: UserInterfaceSizeClass?) {
        let days = max(dayCount, 1)
        let compact = width < 380 || days >= 7
        compactHeaders = compact
        periodColumnWidth = compact ? 36 : (width < 420 ? 40 : 44)
        columnWidth = max(28, (width - periodColumnWidth) / CGFloat(days))
        // 窄屏略减纵向密度，保证一屏能看到更多节次，但仍保持「分钟轴」语义
        if compact {
            pointsPerMinute = 1.0
            timeFontSize = 7
        } else if sizeClass == .regular {
            pointsPerMinute = 1.35
            timeFontSize = 9
        } else {
            pointsPerMinute = 1.2
            timeFontSize = 8
        }
    }
}

struct CourseBlock: View {
    let course: Course
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text(course.name)
                .font(compact ? .caption2.bold() : .caption.bold())
                .lineLimit(compact ? 2 : 3)
                .minimumScaleFactor(0.65)
            if !course.classroom.isEmpty {
                Text("@" + course.classroom)
                    .font(.system(size: compact ? 8 : 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
            }
            if !compact {
                Text(course.snapshot.timeText)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 3 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(Color(hex: course.colorHex).opacity(0.55)).interactive(), in: .rect(cornerRadius: 10))
    }
}

#if DEBUG
#Preview("课表 · SE") {
    WeekView()
        .modelContainer(for: Course.self, inMemory: true)
}
#Preview("课表 · Pro Max", traits: .fixedLayout(width: 430, height: 932)) {
    WeekView()
        .modelContainer(for: Course.self, inMemory: true)
}
#endif
