import ActivityKit
import Foundation

enum LiveActivityStartResult: Equatable {
    case started(String)
    case alreadyRunning(String)
    case disabled
    case noUpcoming
    case ended
    case failed(String)

    var message: String {
        switch self {
        case .started(let name): return "已开启「\(name)」的实时活动，请看锁屏或灵动岛。"
        case .alreadyRunning(let name): return "「\(name)」的实时活动已在显示。"
        case .disabled: return "系统未允许实时活动。请到「设置 > 玻璃课表」或「设置 > 面容 ID 与密码 / 专注模式」中开启实时活动，并确认侧载时保留了小组件扩展。"
        case .noUpcoming: return "近期没有可显示的课程。请先导入课表，或确认上课时间正确。"
        case .ended: return "该课程已结束，无法开启实时活动。"
        case .failed(let detail): return "启动失败：\(detail)"
        }
    }

    var isSuccess: Bool {
        if case .started = self { return true }
        if case .alreadyRunning = self { return true }
        return false
    }
}

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activities: [Activity<CourseActivityAttributes>] { Activity<CourseActivityAttributes>.activities }

    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    var statusText: String {
        if !isEnabled { return "系统未开启" }
        if let activity = activities.first {
            return "进行中：\(activity.attributes.courseName)"
        }
        return "已开启，当前没有进行中的实时活动"
    }

    @discardableResult
    func start(_ occurrence: ClassOccurrence) async -> LiveActivityStartResult {
        guard isEnabled else { return .disabled }
        guard occurrence.end > .now else { return .ended }

        let courseID = occurrence.course.id.uuidString
        if activities.contains(where: { $0.attributes.courseID == courseID && $0.content.state.start == occurrence.start }) {
            return .alreadyRunning(occurrence.course.name)
        }

        await endAllNow()

        let course = occurrence.course
        let attributes = CourseActivityAttributes(courseID: courseID, courseName: course.name,
                                                  periodText: course.periodText, teacher: course.teacher,
                                                  colorHex: course.colorHex)
        let state = CourseActivityAttributes.ContentState(classroom: course.classroom.isEmpty ? "未设置教室" : course.classroom,
                                                          start: occurrence.start, end: occurrence.end)
        // staleDate 稍晚于下课，避免刚上课就被标成过期。
        let stale = occurrence.end.addingTimeInterval(5 * 60)
        do {
            _ = try Activity.request(attributes: attributes,
                                     content: ActivityContent(state: state, staleDate: stale),
                                     pushType: nil)
            return .started(course.name)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 距离上课不足提醒时间，或正在上课时自动开启。
    @discardableResult
    func startIfUpcoming(courses: [CourseSnapshot]) async -> LiveActivityStartResult {
        let lead = TimeInterval(SharedSettings.reminderMinutes * 60)
        guard let next = ScheduleQuery.current(courses: courses, semesterStart: SharedSettings.semesterStart, horizon: max(lead + 60, 86_400)) else {
            return .noUpcoming
        }
        // 自动模式：只在临近或正在上课时开启；手动“立即开启”可用 startNext。
        if next.start.timeIntervalSinceNow <= lead || next.isOngoing() {
            return await start(next)
        }
        return .noUpcoming
    }

    @discardableResult
    func startNext(courses: [CourseSnapshot]) async -> LiveActivityStartResult {
        guard let next = ScheduleQuery.current(courses: courses, semesterStart: SharedSettings.semesterStart, horizon: 7 * 86_400) else {
            return .noUpcoming
        }
        return await start(next)
    }

    func cleanupEnded() {
        Task {
            for activity in activities where activity.content.state.end < .now {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func endAllNow() async {
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
