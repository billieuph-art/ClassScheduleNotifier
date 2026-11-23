import SwiftUI

@main
struct ClassScheduleNotifierApp: App {
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var notificationScheduler = NotificationScheduler()
    @StateObject private var liveActivity = LiveActivityController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scheduleStore)
                .environmentObject(notificationScheduler)
                .environmentObject(liveActivity)
                .task {
                    scheduleStore.load()
                    await notificationScheduler.refreshStatus()
                    await notificationScheduler.scheduleAll(for: scheduleStore.courses)
                }
                .onChange(of: scheduleStore.courses) { _, courses in
                    scheduleStore.save()
                    Task { await notificationScheduler.scheduleAll(for: courses) }
                    WatchSyncService.shared.sendCourses(courses)
                    // 简单启动下一节课的 Live Activity（示例）
                    if let next = courses.sorted(by: { $0.startTime < $1.startTime }).first {
                        Task { await liveActivity.start(for: next) }
                    }
                }
        }
    }
}
