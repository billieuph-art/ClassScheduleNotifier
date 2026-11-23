import SwiftUI

@main
struct ClassScheduleNotifierApp: App {
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var notificationScheduler = NotificationScheduler()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scheduleStore)
                .environmentObject(notificationScheduler)
                .task {
                    scheduleStore.load()
                    await notificationScheduler.requestAuthorization()
                    await notificationScheduler.scheduleAll(for: scheduleStore.courses)
                }
                .onChange(of: scheduleStore.courses) { _, courses in
                    scheduleStore.save()
                    Task { await notificationScheduler.scheduleAll(for: courses) }
                    WatchSyncService.shared.sendCourses(courses)
                }
        }
    }
}