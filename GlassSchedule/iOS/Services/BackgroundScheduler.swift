import BackgroundTasks
import Foundation

enum BackgroundScheduler {
    static let refreshID = "com.example.glassschedule.refresh"
    static let photosID = "com.example.glassschedule.photos"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            let work = Task { @MainActor in
                await AppCoordinator.shared.refreshAll(classifyPhotos: false)
                scheduleRefresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: photosID, using: nil) { task in
            let work = Task { @MainActor in
                await PhotoClassifier.shared.classifyRecent(days: 3, requestAccessIfNeeded: false)
                schedulePhotos()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    @MainActor
    static func scheduleAll() {
        scheduleRefresh()
        schedulePhotos()
    }

    /// 尽量在下一节课开始前提醒时间点附近唤醒，用于自动开启实时活动和滚动更新提醒。
    @MainActor
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshID)
        let lead = TimeInterval(SharedSettings.reminderMinutes * 60)
        if let next = ScheduleQuery.current(courses: DataStore.shared.snapshots(), semesterStart: SharedSettings.semesterStart) {
            request.earliestBeginDate = max(Date.now.addingTimeInterval(60), next.start.addingTimeInterval(-lead - 120))
        } else {
            request.earliestBeginDate = Date.now.addingTimeInterval(6 * 3600)
        }
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func schedulePhotos() {
        guard SharedSettings.autoClassifyPhotos else { return }
        let request = BGProcessingTaskRequest(identifier: photosID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date.now.addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
