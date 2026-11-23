import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activities: [Activity<CourseActivityAttributes>] { Activity<CourseActivityAttributes>.activities }

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(_ occurrence: ClassOccurrence) {
        guard isEnabled, occurrence.end > .now else { return }
        let courseID = occurrence.course.id.uuidString
        if activities.contains(where: { $0.attributes.courseID == courseID && $0.content.state.start == occurrence.start }) {
            return
        }
        endAll(except: nil)

        let course = occurrence.course
        let attributes = CourseActivityAttributes(courseID: courseID, courseName: course.name,
                                                  periodText: course.periodText, teacher: course.teacher,
                                                  colorHex: course.colorHex)
        let state = CourseActivityAttributes.ContentState(classroom: course.classroom.isEmpty ? "未设置教室" : course.classroom,
                                                          start: occurrence.start, end: occurrence.end)
        do {
            _ = try Activity.request(attributes: attributes,
                                     content: ActivityContent(state: state, staleDate: occurrence.end),
                                     pushType: nil)
        } catch {
            print("无法启动实时活动：\(error)")
        }
    }

    /// 距离上课不足提醒时间（默认 30 分钟）或正在上课时自动开启实时活动。
    func startIfUpcoming(courses: [CourseSnapshot]) {
        let lead = TimeInterval(SharedSettings.reminderMinutes * 60)
        guard let next = ScheduleQuery.current(courses: courses, semesterStart: SharedSettings.semesterStart, horizon: lead + 60),
              next.start.timeIntervalSinceNow <= lead else { return }
        start(next)
    }

    func cleanupEnded() {
        for activity in activities where activity.content.state.end < .now {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    func endAll(except id: String?) {
        for activity in activities where activity.id != id {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
