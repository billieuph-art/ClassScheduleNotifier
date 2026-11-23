import Foundation
import Combine

@MainActor
final class ScheduleStore: ObservableObject {
    @Published var courses: [Course] = []

    private var storageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("courses.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL) else {
            courses = []
            return
        }
        do {
            courses = try JSONDecoder().decode([Course].self, from: data)
        } catch {
            courses = []
            print("读取课表失败：\(error)")
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(courses)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("保存课表失败：\(error)")
        }
    }

    func add(_ course: Course) {
        courses.append(course)
        save()
    }

    func delete(_ course: Course) {
        courses.removeAll { $0.id == course.id }
        save()
    }
}