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
        // 让系统在「设置 › 玻璃课表」里出现通知入口（侧载尤其需要先登记一次）
        UIApplication.shared.registerForRemoteNotifications()
    }

    enum PermissionOutcome: Equatable {
        case granted
        case deniedNeedsSettings
        case provisional
        case failed(String)

        var message: String {
            switch self {
            case .granted:
                return "通知权限已开启，上课前提醒会生效。可再点「发送测试通知」确认。"
            case .deniedNeedsSettings:
                return """
                侧载时系统常不弹授权框，且「设置 › 通知」列表里可能暂时没有本 App。

                请按下面做：
                1. 点「打开本 App 设置页」
                2. 在「设置」主页滑到最底部，点「玻璃课表」
                3. 打开「通知 › 允许通知」
                4. 回到 App 发送测试通知
                """
            case .provisional:
                return "已开启安静通知（不弹横幅）。如需横幅，请到「玻璃课表 › 通知」改成横幅提醒。"
            case .failed(let detail):
                return "请求失败：\(detail)\n\n请打开「设置」最底部的「玻璃课表 › 通知」手动允许。"
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
            let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(Self.idPrefix) }.count
            let base: String
            switch settings.authorizationStatus {
            case .authorized: base = "已开启"
            case .provisional: base = "安静通知"
            case .ephemeral: base = "临时授权"
            case .denied: base = "已关闭（去 App 设置页开启）"
            case .notDetermined: base = "尚未登记（侧载请去 App 设置页打开）"
            @unknown default: base = "未知"
            }
            return pending > 0 ? "\(base) · 已排 \(pending) 条" : base
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
            UIApplication.shared.registerForRemoteNotifications()
            return .granted
        case .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            return .provisional
        case .denied:
            return .deniedNeedsSettings
        case .notDetermined:
            break
        @unknown default:
            return .failed("未知的授权状态")
        }

        // providesAppNotificationSettings：在系统通知设置里挂上「App 通知设置」入口，侧载更容易被登记
        let standard: UNAuthorizationOptions = [.alert, .sound, .badge, .providesAppNotificationSettings]
        if let outcome = await request(options: standard) {
            return outcome
        }
        if let outcome = await request(options: standard.union(.provisional)) {
            return outcome
        }
        // 再试一次最简选项，尽量让系统把 App 写进设置列表
        if let outcome = await request(options: [.alert, .providesAppNotificationSettings]) {
            return outcome
        }

        UIApplication.shared.registerForRemoteNotifications()

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
            UIApplication.shared.registerForRemoteNotifications()
            if granted {
                return options.contains(.provisional) ? .provisional : .granted
            }
            let status = await center.notificationSettings().authorizationStatus
            if status == .denied || status == .notDetermined { return .deniedNeedsSettings }
            return .deniedNeedsSettings
        } catch {
            let ns = error as NSError
            // UNErrorCode.notificationsNotAllowed = 1：侧载常见
            if ns.domain == "UNErrorDomain", ns.code == 1 {
                return nil
            }
            return .failed(error.localizedDescription)
        }
    }

    /// 打开「设置 › 玻璃课表」本 App 页（侧载时通知开关通常在这里，而不是通知总列表）。
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// 优先打开通知专用设置；不可用则退回本 App 设置页。
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
            return "还没有通知权限。请点「打开本 App 设置页」，在设置最底部的「玻璃课表 › 通知」里打开允许通知。"
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
            return "测试通知发送失败：\(error.localizedDescription)\n\n若持续失败，多半是侧载签名未带上通知能力，请用 Sideloadly 重新签名安装（不要用 Live Container）。"
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

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            openSettingsFor notification: UNNotification?) {
        // 系统「App 通知设置」按钮会回调这里；界面已在设置里，无需额外跳转。
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
