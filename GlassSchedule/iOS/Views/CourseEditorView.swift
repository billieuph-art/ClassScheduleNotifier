import SwiftData
import SwiftUI

struct CourseEditorView: View {
    private let course: Course?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var classroom = ""
    @State private var teacher = ""
    @State private var major = SharedSettings.defaultMajor
    @State private var weekday = 1
    @State private var startPeriod = 1
    @State private var endPeriod = 2
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var weeksText = ""
    @State private var color = Color.blue
    @State private var notes = ""
    @State private var confirmDelete = false

    private let slots = SharedSettings.periodSlots

    init(course: Course?) {
        self.course = course
        let slots = SharedSettings.periodSlots
        guard let course else {
            _start = State(initialValue: SemesterCalendar.date(on: .now, minutes: PeriodTable.slot(1, in: slots)?.startMinutes ?? 480))
            _end = State(initialValue: SemesterCalendar.date(on: .now, minutes: PeriodTable.slot(2, in: slots)?.endMinutes ?? 575))
            return
        }
        _name = State(initialValue: course.name)
        _classroom = State(initialValue: course.classroom)
        _teacher = State(initialValue: course.teacher)
        _major = State(initialValue: course.major)
        _weekday = State(initialValue: course.weekday)
        _startPeriod = State(initialValue: course.startPeriod)
        _endPeriod = State(initialValue: course.endPeriod)
        _start = State(initialValue: SemesterCalendar.date(on: .now, minutes: course.startMinutes))
        _end = State(initialValue: SemesterCalendar.date(on: .now, minutes: course.endMinutes))
        _weeksText = State(initialValue: course.weeks.isEmpty ? "" : WeeksParser.format(course.weeks))
        _color = State(initialValue: Color(hex: course.colorHex))
        _notes = State(initialValue: course.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("课程") {
                    TextField("课程名称", text: $name)
                    TextField("教室", text: $classroom)
                    TextField("教师", text: $teacher)
                    TextField("专业（用于资料归档文件夹）", text: $major)
                    ColorPicker("颜色", selection: $color, supportsOpacity: false)
                }
                Section("时间") {
                    Picker("星期", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text(WeekdayName.full($0)).tag($0) }
                    }
                    Picker("开始节次", selection: $startPeriod) {
                        ForEach(slots) { Text("第\($0.index)节").tag($0.index) }
                    }
                    .onChange(of: startPeriod) { _, value in
                        if endPeriod < value { endPeriod = value }
                        applySlotTimes()
                    }
                    Picker("结束节次", selection: $endPeriod) {
                        ForEach(slots.filter { $0.index >= startPeriod }) { Text("第\($0.index)节").tag($0.index) }
                    }
                    .onChange(of: endPeriod) { _, _ in applySlotTimes() }
                    DatePicker("上课时间", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("下课时间", selection: $end, displayedComponents: .hourAndMinute)
                    TextField("上课周次，如 1-16 或 1-8,10-16，留空为每周", text: $weeksText)
                }
                Section("备注") {
                    TextField("备注", text: $notes, axis: .vertical)
                }
                if course != nil {
                    Section {
                        Button("删除课程", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle(course == nil ? "添加课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", systemImage: "checkmark", role: .confirm) { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("确定删除这门课程？已归类的资料记录也会删除（照片本身不受影响）。",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let course { context.delete(course) }
                    try? context.save()
                    Task { await AppCoordinator.shared.refreshAll() }
                    dismiss()
                }
            }
        }
    }

    private func applySlotTimes() {
        if let s = PeriodTable.slot(startPeriod, in: slots) { start = SemesterCalendar.date(on: .now, minutes: s.startMinutes) }
        if let e = PeriodTable.slot(endPeriod, in: slots) { end = SemesterCalendar.date(on: .now, minutes: e.endMinutes) }
    }

    private func minutes(_ date: Date) -> Int {
        let c = SemesterCalendar.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func save() {
        let target = course ?? Course(name: name, major: major, weekday: weekday, startPeriod: startPeriod,
                                      endPeriod: endPeriod, startMinutes: 0, endMinutes: 0)
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.classroom = classroom
        target.teacher = teacher
        target.major = major
        target.weekday = weekday
        target.startPeriod = startPeriod
        target.endPeriod = max(startPeriod, endPeriod)
        target.startMinutes = minutes(start)
        target.endMinutes = max(minutes(end), minutes(start) + 5)
        target.weeks = WeeksParser.parse(weeksText)
        target.colorHex = color.hexString
        target.notes = notes
        if course == nil { context.insert(target) }
        try? context.save()
        Task { await AppCoordinator.shared.refreshAll() }
        dismiss()
    }
}

extension Color {
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }
}
