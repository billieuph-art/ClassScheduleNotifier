import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

public final class LiveActivityController {
    #if canImport(ActivityKit)
    private var currentActivity: Activity<NextClassAttributes>?
    #endif

    public func update(for course: Course) {
        #if canImport(ActivityKit)
        let state = NextClassAttributes.ContentState(
            status: "即将开始",
            countdown: "20分钟"
        )

        let attributes = NextClassAttributes(
            courseName: course.name,
            room: course.location,
            startTime: course.startTime
        )

        if currentActivity == nil {
            do {
                currentActivity = try Activity.request(attributes: attributes, contentState: state)
            } catch {
                print("Live Activity 启动失败: \(error)")
            }
        } else {
            Task {
                await currentActivity?.update(using: state)
            }
        }
        #endif
    }

    public func stop() {
        #if canImport(ActivityKit)
        Task {
            guard let current = currentActivity else { return }
            await current.end(dismissalPolicy: .immediate)
            currentActivity = nil
        }
        #endif
    }
}

#if canImport(ActivityKit)
public struct NextClassAttributes: ActivityAttributes {
    public typealias ContentState = LiveCourseState

    public var courseName: String
    public var room: String
    public var startTime: Date

    public struct LiveCourseState: Codable, Hashable {
        public var status: String
        public var countdown: String
    }
}
#endif
