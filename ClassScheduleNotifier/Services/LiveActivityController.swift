import Foundation
import UserNotifications

public final class NotificationScheduler: ObservableObject {
    private let center = UNUserNotificationCenter.current()

    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func scheduleAll(for courses: [Course]) {
        center.removeAllPendingNotificationRequests()
        for course in courses {
            schedule(for: course)
        }
    }

    public func schedule(for course: Course) {
        let triggerDate = course.startTime.addingTimeInterval(-20 * 60)
        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "课程提醒"
        content.body = "\(course.name) 在 \(course.location) 开始，距离课程开始还有 20 分钟。"
        content.sound = .default
        content.badge = 1

        let dateComponents = Calendar.current.dateComponents([
            .year, .month, .day, .hour, .minute
        ], from: triggerDate)

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: "course-reminder-\(course.id.uuidString)", content: content, trigger: trigger)

        center.add(request)
    }

    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
