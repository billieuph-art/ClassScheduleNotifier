import Foundation
import Combine
import ActivityKit

struct NextClassAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var countdown: String
        var endTime: Date
    }

    var courseName: String
    var room: String
    var teacher: String
    var startTime: Date
}

@MainActor
final class LiveActivityController: ObservableObject {
    private var activity: Activity<NextClassAttributes>?

    func start(for course: Course) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = NextClassAttributes(
            courseName: course.name,
            room: course.location,
            teacher: course.teacher,
            startTime: course.startTime
        )
        let state = NextClassAttributes.ContentState(
            status: "即将开始",
            countdown: "20 分钟",
            endTime: course.endTime
        )
        let content = ActivityContent(state: state, staleDate: course.endTime)
        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("启动实时活动失败：\(error)")
        }
    }

    func stop() {
        Task {
            for item in Activity<NextClassAttributes>.activities {
                await item.end(nil, dismissalPolicy: .immediate)
            }
            activity = nil
        }
    }
}