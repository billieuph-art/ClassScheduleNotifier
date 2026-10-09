import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var notificationScheduler: NotificationScheduler

    public var body: some View {
        NavigationStack {
            List {
                Section("今天的课程") {
                    ForEach(todayCourses, id: \ .id) { course in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(course.name)
                                .font(.headline)
                            Text(course.timeRangeText)
                                .font(.subheadline)
                            Text("\(course.location) · \(course.teacher)")
                                .font(.caption)
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("操作") {
                    Button("导入 CSV / ICS") {
                        let csvSample = "name,teacher,location,weekday,start,end,notes\n高等数学,李老师,A101,1,08:30,10:00,第一节课\n"
                        _ = ImportService.parseCSV(csvSample)
                    }

                    Button("重新生成通知") {
                        notificationScheduler.scheduleAll(for: scheduleStore.courses)
                    }
                }
            }
            .navigationTitle("课程提醒")
        }
    }

    private var todayCourses: [Course] {
        let today = Calendar.current.component(.weekday, from: Date())
        return scheduleStore.courses.filter { $0.weekday.rawValue == today }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScheduleStore())
        .environmentObject(NotificationScheduler())
}
