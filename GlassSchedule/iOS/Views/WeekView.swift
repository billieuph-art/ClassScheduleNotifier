import SwiftData
import SwiftUI

struct WeekView: View {
    @Query private var courses: [Course]
    @AppStorage(SharedSettings.Key.semesterStart, store: SharedSettings.defaults) private var semesterStartRaw: Double = 0
    @AppStorage(SharedSettings.Key.showWeekend, store: SharedSettings.defaults) private var showWeekend = false
    @State private var week: Int?
    @State private var editing: Course?
    @State private var creating = false

    /// 每分钟对应高度；40 分钟一节 ≈ 48pt，课间 10 分钟也会留出空隙。
    private let pointsPerMinute: CGFloat = 1.2
    private let periodColumnWidth: CGFloat = 44
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
    private var timelineHeight: CGFloat { CGFloat(max(60, timelineEnd - timelineStart)) * pointsPerMinute }

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
        GeometryReader { proxy in
            let columnWidth = (proxy.size.width - periodColumnWidth) / CGFloat(max(days.count, 1))
            ZStack(alignment: .topLeading) {
                // 表头
                HStack(spacing: 0) {
                    Color.clear.frame(width: periodColumnWidth, height: headerHeight)
                    ForEach(days, id: \.self) { day in
                        VStack(spacing: 0) {
                            Text(WeekdayName.full(day)).font(.caption.bold())
                            Text(dateText(for: day)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: columnWidth, height: headerHeight)
                        .background(isToday(day) ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 8))
                    }
                }

                // 节次轨道：按真实上课/下课分钟定位，课间自然留白
                ForEach(slots) { slot in
                    let top = yOffset(for: slot.startMinutes)
                    let height = max(28, CGFloat(max(1, slot.endMinutes - slot.startMinutes)) * pointsPerMinute)
                    HStack(spacing: 0) {
                        VStack(spacing: 1) {
                            Text("\(slot.index)").font(.caption.bold())
                            Text(TimeFormat.string(slot.startMinutes))
                                .font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(TimeFormat.string(slot.endMinutes))
                                .font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                        .frame(width: periodColumnWidth, height: height, alignment: .top)
                        .padding(.top, 2)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary.opacity(0.22))
                            .frame(height: height)
                            .padding(.trailing, 2)
                    }
                    .offset(y: headerHeight + top)
                }

                // 课程块：用课程的实际上下课时间，而不是「节次数 × 等行高」
                ForEach(courses.filter { $0.snapshot.occurs(inWeek: displayedWeek) && days.contains($0.weekday) }) { course in
                    let column = CGFloat(days.firstIndex(of: course.weekday) ?? 0)
                    let start = resolvedStart(course)
                    let end = resolvedEnd(course)
                    let top = yOffset(for: start)
                    let height = max(28, CGFloat(max(1, end - start)) * pointsPerMinute - 3)
                    CourseBlock(course: course)
                        .frame(width: columnWidth - 4, height: height)
                        .offset(x: periodColumnWidth + column * columnWidth + 2,
                                y: headerHeight + top + 1)
                        .onTapGesture { editing = course }
                }
            }
        }
        .frame(height: headerHeight + timelineHeight + 8)
    }

    private func yOffset(for minutes: Int) -> CGFloat {
        CGFloat(minutes - timelineStart) * pointsPerMinute
    }

    /// 优先用课程已存时间；若与节次表不一致，以当前作息表为准。
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

struct CourseBlock: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.name).font(.caption.bold()).lineLimit(3)
            if !course.classroom.isEmpty {
                Text("@" + course.classroom).font(.system(size: 10)).lineLimit(2).foregroundStyle(.secondary)
            }
            Text(course.snapshot.timeText).font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(Color(hex: course.colorHex).opacity(0.55)).interactive(), in: .rect(cornerRadius: 10))
    }
}
