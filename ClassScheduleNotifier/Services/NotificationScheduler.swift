import Foundation
import Combine
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
        for course in courses.prefix(64) { schedule(course) }
    }

    func schedule(_ course: Course) {
        guard authorizationGranted else { return }
        let reminderDate = course.startTime.addingTimeInterval(-leadTime)
        let time = Calendar.current.dateComponents([.hour, .minute], from: reminderDate)
        var components = DateComponents()
        components.weekday = course.weekday == .sunday ? 1 : course.weekday.rawValue + 1
        components.hour = time.hour
        components.minute = time.minute

        let content = UNMutableNotificationContent()
        content.title = "课程即将开始"
        content.body = "\(course.name) 将在 20 分钟后开始\(course.location.isEmpty ? "" : "，地点：\(course.location)")。"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
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