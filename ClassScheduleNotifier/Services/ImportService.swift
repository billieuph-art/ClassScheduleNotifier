import Foundation

public final class ScheduleStore: ObservableObject {
    @Published public var courses: [Course] = []

    private let storageURL: URL = {
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent("courses.json")
    }()

    public func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            self.courses = SampleData.makeSampleCourses()
            save()
            return
        }

        do {
            let decoded = try JSONDecoder().decode([Course].self, from: data)
            self.courses = decoded
        } catch {
            self.courses = SampleData.makeSampleCourses()
            save()
        }
    }

    public func save() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(courses)
            try data.write(to: storageURL)
        } catch {
            print("保存课程失败: \(error)")
        }
    }

    public func add(_ course: Course) {
        courses.append(course)
        save()
    }

    public func remove(_ course: Course) {
        courses.removeAll { $0.id == course.id }
        save()
    }
}

public enum SampleData {
    public static func makeSampleCourses() -> [Course] {
        let calendar = Calendar(identifier: .gregorian)

        func date(for weekday: Weekday, hour: Int, minute: Int) -> Date {
            let now = Date()
            var components = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: now)
            components.weekday = weekday.rawValue
            components.hour = hour
            components.minute = minute
            components.second = 0
            return calendar.date(from: components) ?? now
        }

        return [
            Course(
                name: "高等数学",
                teacher: "李老师",
                location: "A101",
                weekday: .monday,
                startTime: date(for: .monday, hour: 8, minute: 30),
                endTime: date(for: .monday, hour: 10, minute: 0),
                notes: "第一节课"
            ),
            Course(
                name: "计算机网络",
                teacher: "王老师",
                location: "C208",
                weekday: .wednesday,
                startTime: date(for: .wednesday, hour: 10, minute: 15),
                endTime: date(for: .wednesday, hour: 11, minute: 45),
                notes: "实验课"
            ),
            Course(
                name: "英语口语",
                teacher: "陈老师",
                location: "B305",
                weekday: .friday,
                startTime: date(for: .friday, hour: 14, minute: 0),
                endTime: date(for: .friday, hour: 15, minute: 30),
                notes: "课堂互动"
            )
        ]
    }
}
