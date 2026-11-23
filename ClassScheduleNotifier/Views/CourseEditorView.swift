import SwiftUI

struct CourseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Course) -> Void

    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var weekday: Weekday = .monday
    @State private var startTime = Self.time(hour: 8, minute: 0)
    @State private var endTime = Self.time(hour: 9, minute: 40)

    var body: some View {
        NavigationStack {
            Form {
                Section("课程信息") {
                    TextField("课程名称", text: $name)
                    TextField("教师（选填）", text: $teacher)
                    TextField("上课地点（选填）", text: $location)
                }
                Section("上课时间") {
                    Picker("星期", selection: $weekday) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.title).tag(day)
                        }
                    }
                    DatePicker("开始时间", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("结束时间", selection: $endTime, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("添加课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let calendar = Calendar.current
                        let start = Self.date(on: weekday, time: startTime, calendar: calendar)
                        var end = Self.date(on: weekday, time: endTime, calendar: calendar)
                        if end <= start { end = end.addingTimeInterval(24 * 60 * 60) }
                        let course = Course(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            teacher: teacher,
                            location: location,
                            weekday: weekday,
                            startTime: start,
                            endTime: end
                        )
                        onSave(course)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || endTime <= startTime)
                }
            }
        }
    }

    private static func time(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    private static func date(on weekday: Weekday, time: Date, calendar: Calendar) -> Date {
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        let today = calendar.startOfDay(for: Date())
        let current = calendar.component(.weekday, from: today)
        let target = weekday == .sunday ? 1 : weekday.rawValue + 1
        let offset = (target - current + 7) % 7
        let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        return calendar.date(bySettingHour: timeParts.hour ?? 8, minute: timeParts.minute ?? 0, second: 0, of: day) ?? day
    }
}