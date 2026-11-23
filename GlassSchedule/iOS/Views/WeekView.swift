import SwiftData
import SwiftUI

struct WeekView: View {
    @Query private var courses: [Course]
    @AppStorage(SharedSettings.Key.semesterStart, store: SharedSettings.defaults) private var semesterStartRaw: Double = 0
    @AppStorage(SharedSettings.Key.showWeekend, store: SharedSettings.defaults) private var showWeekend = false
    @State private var week: Int?
    @State private var editing: Course?
    @State private var creating = false

    private let rowHeight: CGFloat = 58
    private let periodColumnWidth: CGFloat = 34

    private var semesterStart: Date { Date(timeIntervalSinceReferenceDate: semesterStartRaw) }
    private var currentWeek: Int { max(1, SemesterCalendar.weekNumber(of: .now, semesterStart: semesterStart)) }
    private var displayedWeek: Int { week ?? currentWeek }
    private var slots: [PeriodSlot] { SharedSettings.periodSlots }
    private var days: [Int] {
        let hasWeekendClass = courses.contains { $0.weekday >= 6 }
        return Array(1...((showWeekend || hasWeekendClass) ? 7 : 5))
    }

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
            let columnWidth = (proxy.size.width - periodColumnWidth) / CGFloat(days.count)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: periodColumnWidth, height: 40)
                        ForEach(days, id: \.self) { day in
                            VStack(spacing: 0) {
                                Text(WeekdayName.full(day)).font(.caption.bold())
                                Text(dateText(for: day)).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: columnWidth, height: 40)
                            .background(isToday(day) ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 8))
                        }
                    }
                    ForEach(slots) { slot in
                        HStack(spacing: 0) {
                            VStack(spacing: 0) {
                                Text("\(slot.index)").font(.caption.bold())
                                Text(TimeFormat.string(slot.startMinutes)).font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                            .frame(width: periodColumnWidth, height: rowHeight)
                            Rectangle().fill(.quaternary.opacity(0.4)).frame(height: 0.5).frame(maxHeight: .infinity, alignment: .top)
                        }
                        .frame(height: rowHeight)
                    }
                }

                ForEach(courses.filter { $0.snapshot.occurs(inWeek: displayedWeek) && days.contains($0.weekday) }) { course in
                    let column = CGFloat(days.firstIndex(of: course.weekday) ?? 0)
                    let span = CGFloat(max(1, course.endPeriod - course.startPeriod + 1))
                    CourseBlock(course: course)
                        .frame(width: columnWidth - 4, height: span * rowHeight - 4)
                        .offset(x: periodColumnWidth + column * columnWidth + 2,
                                y: 40 + CGFloat(max(0, course.startPeriod - 1)) * rowHeight + 2)
                        .onTapGesture { editing = course }
                }
            }
        }
        .frame(height: 40 + CGFloat(slots.count) * rowHeight)
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
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular.tint(Color(hex: course.colorHex).opacity(0.55)).interactive(), in: .rect(cornerRadius: 10))
    }
}
