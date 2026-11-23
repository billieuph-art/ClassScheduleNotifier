import Foundation
import SwiftData

@Model
final class Course {
    @Attribute(.unique) var id: UUID
    var name: String
    var classroom: String
    var teacher: String
    var major: String
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    var startMinutes: Int
    var endMinutes: Int
    var weeks: [Int]
    var colorHex: String
    var notes: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StudyMaterial.course)
    var materials: [StudyMaterial] = []

    init(id: UUID = UUID(), name: String, classroom: String = "", teacher: String = "", major: String,
         weekday: Int, startPeriod: Int, endPeriod: Int, startMinutes: Int, endMinutes: Int,
         weeks: [Int] = [], colorHex: String? = nil, notes: String = "") {
        self.id = id
        self.name = name
        self.classroom = classroom
        self.teacher = teacher
        self.major = major
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.weeks = weeks
        self.colorHex = colorHex ?? CoursePalette.color(for: name)
        self.notes = notes
        self.createdAt = .now
    }

    var snapshot: CourseSnapshot {
        CourseSnapshot(id: id, name: name, classroom: classroom, teacher: teacher, major: major,
                       weekday: weekday, startPeriod: startPeriod, endPeriod: endPeriod,
                       startMinutes: startMinutes, endMinutes: endMinutes, weeks: weeks, colorHex: colorHex)
    }

    var majorFolderName: String {
        major.trimmingCharacters(in: .whitespaces).isEmpty ? "未分类专业" : major
    }
}

@Model
final class StudyMaterial {
    @Attribute(.unique) var assetLocalIdentifier: String
    var capturedAt: Date
    var week: Int
    /// 相对于 Documents 目录的路径（导出到“文件”App 的副本）。
    var relativeFilePath: String?
    var title: String
    var summary: String
    var keywords: [String]
    var course: Course?

    init(assetLocalIdentifier: String, capturedAt: Date, week: Int, relativeFilePath: String?,
         title: String, summary: String, keywords: [String], course: Course?) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.capturedAt = capturedAt
        self.week = week
        self.relativeFilePath = relativeFilePath
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.course = course
    }
}
