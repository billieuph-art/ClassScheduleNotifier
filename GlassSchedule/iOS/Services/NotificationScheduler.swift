import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    nonisolated static let categoryID = "CLASS_REMINDER"
    nonisolated static let startActivityAction = "START_LIVE_ACTIVITY"
    private nonisolated static let idPrefix = "class-"

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startActivityAction,
                                         title: "在灵动岛显示倒计时",
                                         options: [.foreground],
                                         icon: UNNotificationActionIcon(systemImageName: "timer"))
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [start], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    enum PermissionOutcome: Equatable {
        case granted
        case deniedNeedsSettings
        case provisional
        case failed(String)

        var message: String {
            switch self {
            case .granted: return "通知权限已开启，上课前提醒会生效。"
            case .deniedNeedsSettings: return "通知权限此前被关闭。请在系统设置里打开「允许通知」。"
            case .provisional: return "已开启安静通知（临时授权）。"
            case .failed(let detail): return "请求失败：\(detail)"
            }
        }

        var shouldOpenSettings: Bool {
            if case .deniedNeedsSettings = self { return true }
            return false
        }
    }

    var authorizationStatusText: String {
        get async {
            switch await center.notificationSettings().authorizationStatus {
            case .authorized: return "已开启"
            case .provisional: return "安静通知"
            case .ephemeral: return "临时授权"
            case .denied: return "已关闭（需去系统设置开启）"
            case .notDetermined: return "尚未请求"
            @unknown default: return "未知"
            }
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let outcome = await ensurePermission()
        return outcome == .granted || outcome == .provisional
    }

    /// 尚未决定时弹出系统授权框；已被拒绝时返回需跳转设置，避免“点了没反应”。
    @discardableResult
    func ensurePermission() async -> PermissionOutcome {
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized:
            return .granted
        case .provisional, .ephemeral:
            return .provisional
        case .denied:
            return .deniedNeedsSettings
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                return granted ? .granted : .deniedNeedsSettings
            } catch {
                return .failed(error.localizedDescription)
            }
        @unknown default:
            return .failed("未知的授权状态")
        }
    }

    /// iOS 最多保留 64 条待发通知，这里只排未来 7 天内的前 60 节课，每次打开 App 或后台刷新时滚动更新。
    func reschedule(courses: [CourseSnapshot]) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) })

        let lead = TimeInterval(SharedSettings.reminderMinutes * 60)
        let now = Date.now
        let upcoming = ScheduleQuery.occurrences(of: courses, from: now, to: now.addingTimeInterval(7 * 86_400),
                                                 semesterStart: SharedSettings.semesterStart)
        for occurrence in upcoming.prefix(60) {
            let fireDate = occurrence.start.addingTimeInterval(-lead)
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            let course = occurrence.course
            content.title = "\(course.name) · \(SharedSettings.reminderMinutes) 分钟后上课"
            content.subtitle = course.classroom.isEmpty ? course.periodText : "\(course.classroom) · \(course.periodText)"
            content.body = "\(WeekdayName.full(course.weekday)) \(course.timeText)" + (course.teacher.isEmpty ? "" : " · \(course.teacher)")
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = Self.categoryID
            content.threadIdentifier = course.id.uuidString
            content.userInfo = ["courseID": course.id.uuidString, "start": occurrence.start.timeIntervalSince1970]

            let comps = SemesterCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: Self.idPrefix + occurrence.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.content.categoryIdentifier == Self.categoryID {
            await startActivity(from: notification.request.content.userInfo)
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await startActivity(from: response.notification.request.content.userInfo)
    }

    private nonisolated func startActivity(from userInfo: [AnyHashable: Any]) async {
        await MainActor.run {
            guard let idString = userInfo["courseID"] as? String, let id = UUID(uuidString: idString),
                  let course = DataStore.shared.course(id: id)?.snapshot,
                  let startTS = userInfo["start"] as? TimeInterval else { return }
            let start = Date(timeIntervalSince1970: startTS)
            let end = start.addingTimeInterval(TimeInterval((course.endMinutes - course.startMinutes) * 60))
            let week = SemesterCalendar.weekNumber(of: start, semesterStart: SharedSettings.semesterStart)
            Task { _ = await LiveActivityManager.shared.start(ClassOccurrence(course: course, start: start, end: end, week: week)) }
        }
    }
}
