import ActivityKit
import Foundation

struct CourseActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var classroom: String
        var start: Date
        var end: Date
    }

    var courseID: String
    var courseName: String
    var periodText: String
    var teacher: String
    var colorHex: String
}
