import Foundation
import UIKit
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
            case .granted:
                return "通知权限已开启，上课前提醒会生效。"
            case .deniedNeedsSettings:
                return "侧载安装时系统常常不弹出授权框（UNError 1）。请到「设置 › 通知 › 玻璃课表」打开「允许通知」，然后回到 App 再点一次「重新检查通知权限」。"
            case .provisional:
                return "已开启安静通知。如需横幅提醒，请到系统设置里把通知改为「横幅」。"
            case .failed(let detail):
                return "请求失败：\(detail)\n\n请到「设置 › 通知 › 玻璃课表」手动打开允许通知。"
            }
        }

        var shouldOpenSettings: Bool {
            switch self {
            case .deniedNeedsSettings, .failed: return true
            default: return false
            }
        }
    }

    var authorizationStatusText: String {
        get async {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized: return "已开启"
            case .provisional: return "安静通知"
            case .ephemeral: return "临时授权"
            case .denied: return "已关闭（需去系统设置开启）"
            case .notDetermined: return "尚未授权（侧载请去系统设置打开）"
            @unknown default: return "未知"
            }
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let outcome = await ensurePermission()
        return outcome == .granted || outcome == .provisional
    }

    /// 侧载包上 `requestAuthorization` 常直接抛 UNErrorDomain 1 且不弹窗，这时引导用户去系统设置。
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
            break
        @unknown default:
            return .failed("未知的授权状态")
        }

        // 1) 先尝试标准弹窗授权
        if let outcome = await request(options: [.alert, .sound, .badge]) {
            return outcome
        }
        // 2) 再试安静通知（部分侧载环境只允许 provisional）
        if let outcome = await request(options: [.alert, .sound, .badge, .provisional]) {
            return outcome
        }

        // 3) 仍失败：再读一次状态；很多情况下其实已经变成 denied / notDetermined，只能去设置
        let again = await center.notificationSettings().authorizationStatus
        switch again {
        case .authorized: return .granted
        case .provisional, .ephemeral: return .provisional
        default: return .deniedNeedsSettings
        }
    }

    private func request(options: UNAuthorizationOptions) async -> PermissionOutcome? {
        do {
            let granted = try await center.requestAuthorization(options: options)
            if granted {
                return options.contains(.provisional) ? .provisional : .granted
            }
            // 用户点了不允许，或系统没弹窗直接返回 false
            let status = await center.notificationSettings().authorizationStatus
            if status == .denied || status == .notDetermined { return .deniedNeedsSettings }
            return .deniedNeedsSettings
        } catch {
            let ns = error as NSError
            // UNErrorCode.notificationsNotAllowed = 1：侧载常见，当作需去设置处理，不要只弹原始错误。
            if ns.domain == "UNErrorDomain", ns.code == 1 {
                return nil // 交给上层尝试 provisional / 最终去设置
            }
            return .failed(error.localizedDescription)
        }
    }

    /// 打开系统里本 App 的通知设置页（比通用设置页更准确）。
    func openNotificationSettings() {
        let candidates = [
            UIApplication.openNotificationSettingsURLString,
            UIApplication.openSettingsURLString,
        ]
        for raw in candidates {
            if let url = URL(string: raw), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
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
            // 侧载/免费证书没有 time-sensitive 权限，用 active 避免安装失败。
            content.interruptionLevel = .active
            content.categoryIdentifier = Self.categoryID
            content.threadIdentifier = course.id.uuidString
            content.userInfo = ["courseID": course.id.uuidString, "start": occurrence.start.timeIntervalSince1970]

            let comps = SemesterCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: Self.idPrefix + occurrence.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// 发一条 5 秒后的测试通知，方便确认权限是否真的可用。
    func scheduleTestNotification() async -> String {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return "还没有通知权限，请先到系统设置打开「允许通知」。"
        }
        let content = UNMutableNotificationContent()
        content.title = "玻璃课表"
        content.body = "通知已接通。上课前会按你设置的时间提醒。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "glassschedule-test", content: content, trigger: trigger)
        do {
            try await center.add(request)
            return "已安排 5 秒后的测试通知，请回到桌面或锁屏查看。"
        } catch {
            return "测试通知发送失败：\(error.localizedDescription)"
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
