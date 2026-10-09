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
                .onAppear {
                    notificationScheduler.requestAuthorization()
                    scheduleStore.load()
                    notificationScheduler.scheduleAll(for: scheduleStore.courses)
                }
        }
    }
}
