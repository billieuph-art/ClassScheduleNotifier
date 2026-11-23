import Foundation
import Combine
import ActivityKit

struct NextClassAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var endTime: Date
        var startTime: Date
    }

    var courseName: String
    var room: String
    var teacher: String
}

@MainActor
final class LiveActivityController: ObservableObject {
    private var activity: Activity<NextClassAttributes>?

    func start(for course: Course) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities 未开启")
            return
        }

        // 结束已有的
        await stop()

        let attributes = NextClassAttributes(
            courseName: course.name,
            room: course.location,
            teacher: course.teacher
        )
        let state = NextClassAttributes.ContentState(
            status: "即将开始",
            endTime: course.endTime,
            startTime: course.startTime
        )
        let content = ActivityContent(state: state, staleDate: course.endTime)

        do {
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("启动实时活动失败：\(error.localizedDescription)")
        }
    }

    func stop() async {
        for item in Activity<NextClassAttributes>.activities {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }

    func update(status: String, for course: Course) async {
        guard let activity else { return }
        let state = NextClassAttributes.ContentState(
            status: status,
            endTime: course.endTime,
            startTime: course.startTime
        )
        await activity.update(ActivityContent(state: state, staleDate: course.endTime))
    }
}
