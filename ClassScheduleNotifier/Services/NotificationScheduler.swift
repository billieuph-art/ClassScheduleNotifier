import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler: ObservableObject {
    @Published private(set) var authorizationGranted = false
    private let center = UNUserNotificationCenter.current()
    private let leadTime: TimeInterval = 20 * 60

    func requestAuthorization() async {
        do {
            authorizationGranted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            authorizationGranted = false
            print("通知授权失败：\(error)")
        }
    }

    func scheduleAll(for courses: [Course]) async {
        center.removeAllPendingNotificationRequests()
        guard authorizationGranted else { return }

        // 每门课按星期重复提醒。系统待处理通知数量有限，避免超过 64 条。
        for course in courses.prefix(64) {
            schedule(course)
        }
    }

    func schedule(_ course: Course) {
        guard authorizationGranted else { return }
        let reminderDate = course.startTime.addingTimeInterval(-leadTime)
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        var triggerComponents = DateComponents()
        // Calendar weekday: Sunday = 1; app Weekday: Monday = 1.
        triggerComponents.weekday = course.weekday == .sunday ? 1 : course.weekday.rawValue + 1
        triggerComponents.hour = components.hour
        triggerComponents.minute = components.minute

        let content = UNMutableNotificationContent()
        content.title = "课程即将开始"
        content.body = "\(course.name) 将在 20 分钟后开始\(course.location.isEmpty ? "" : "，地点：\(course.location)")。"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "course-reminder-\(course.id.uuidString)",
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error { print("添加课程提醒失败：\(error)") }
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}