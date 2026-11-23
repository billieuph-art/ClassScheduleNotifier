import SwiftData
import SwiftUI

struct TodayView: View {
    @Query(sort: [SortDescriptor(\Course.startMinutes)]) private var courses: [Course]
    @AppStorage(SharedSettings.Key.semesterStart, store: SharedSettings.defaults) private var semesterStartRaw: Double = 0
    @State private var showImport = false
    @State private var editing: Course?

    private var semesterStart: Date { Date(timeIntervalSinceReferenceDate: semesterStartRaw) }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let snapshots = courses.map(\.snapshot)
                let today = ScheduleQuery.day(context.date, courses: snapshots, semesterStart: semesterStart)
                let tomorrowDate = context.date.addingTimeInterval(86_400)
                let tomorrow = ScheduleQuery.day(tomorrowDate, courses: snapshots, semesterStart: semesterStart)
                let next = ScheduleQuery.current(courses: snapshots, semesterStart: semesterStart, now: context.date)

                ScrollView {
                    VStack(spacing: 16) {
                        header(date: context.date)
                        if courses.isEmpty {
                            emptyState
                        } else {
                            if let next { NextClassHero(occurrence: next, now: context.date) }
                            SectionHeader(title: today.isEmpty ? "今天没有课" : "今天 · \(today.count) 节课")
                            GlassEffectContainer(spacing: 10) {
                                VStack(spacing: 10) {
                                    ForEach(today) { occurrence in
                                        CourseCard(occurrence: occurrence, highlighted: occurrence.id == next?.id)
                                            .onTapGesture { editing = courses.first { $0.id == occurrence.course.id } }
                                    }
                                }
                            }
                            if !tomorrow.isEmpty {
                                SectionHeader(title: "明天 · \(tomorrow.count) 节课")
                                VStack(spacing: 10) {
                                    ForEach(tomorrow) { CourseCard(occurrence: $0) }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(GlassBackground())
            .navigationTitle("今天")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入课表", systemImage: "square.and.arrow.down") { showImport = true }
                }
            }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(item: $editing) { CourseEditorView(course: $0) }
        }
    }

    private func header(date: Date) -> some View {
        let week = SemesterCalendar.weekNumber(of: date, semesterStart: semesterStart)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date, format: .dateTime.month().day().weekday(.wide)).font(.title2.bold())
                Text(week >= 1 ? "第 \(week) 教学周" : "尚未开学").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("还没有课程", systemImage: "calendar.badge.plus",
                                   description: Text("用截图、PDF 或日历文件导入课程表，也可以手动添加。"))
            Button("导入课程表", systemImage: "doc.viewfinder") { showImport = true }
                .buttonStyle(.glassProminent)
        }
        .padding(.vertical, 40)
    }
}

struct NextClassHero: View {
    let occurrence: ClassOccurrence
    let now: Date

    var body: some View {
        let course = occurrence.course
        let ongoing = occurrence.isOngoing(at: now)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(ongoing ? "正在上课" : "下一节课", systemImage: ongoing ? "book.fill" : "clock")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if ongoing {
                    Text("距下课 \(occurrence.end, style: .timer)")
                } else {
                    Text(occurrence.start, style: .relative)
                }
            }
            .font(.subheadline.monospacedDigit())

            Text(course.name).font(.largeTitle.bold()).lineLimit(2).minimumScaleFactor(0.7)

            HStack(spacing: 16) {
                Label(course.classroom.isEmpty ? "未设置教室" : course.classroom, systemImage: "mappin.and.ellipse")
                Label("\(course.periodText) · \(course.timeText)", systemImage: "clock")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if ongoing {
                ProgressView(timerInterval: occurrence.start...occurrence.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Color(hex: course.colorHex))
            } else {
                Button("在灵动岛显示倒计时", systemImage: "timer") {
                    LiveActivityManager.shared.start(occurrence)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(Color(hex: course.colorHex).opacity(0.3)).interactive(), in: .rect(cornerRadius: 28))
    }
}
