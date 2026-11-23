import Foundation
import SwiftData

@MainActor
final class DataStore {
    static let shared = DataStore()

    let container: ModelContainer

    private init() {
        let schema = Schema([Course.self, StudyMaterial.self])
        let configuration: ModelConfiguration
        if AppGroup.isAvailable,
           let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("GlassSchedule.store") {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建数据库：\(error)")
        }
    }

    var context: ModelContext { container.mainContext }

    func courses() -> [Course] {
        (try? context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.weekday), SortDescriptor(\.startMinutes)]))) ?? []
    }

    func snapshots() -> [CourseSnapshot] { courses().map(\.snapshot) }

    func course(id: UUID) -> Course? {
        var descriptor = FetchDescriptor<Course>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func save() {
        do { try context.save() } catch { print("保存失败：\(error)") }
    }
}
