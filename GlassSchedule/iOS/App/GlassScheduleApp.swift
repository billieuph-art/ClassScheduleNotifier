import SwiftUI
import SwiftData

@main
struct GlassScheduleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        SharedSettings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(PhotoClassifier.shared)
        }
        .modelContainer(DataStore.shared.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await AppCoordinator.shared.refreshAll(classifyPhotos: SharedSettings.autoClassifyPhotos) }
            case .background:
                BackgroundScheduler.scheduleAll()
            default:
                break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SharedSettings.registerDefaults()
        NotificationScheduler.shared.configure()
        BackgroundScheduler.register()
        WatchSyncService.shared.activate()
        return true
    }
}

/// 每次课表或设置变化后统一刷新：提醒、实时活动、小组件、手表、照片归类。
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    func refreshAll(classifyPhotos: Bool = false) async {
        let courses = DataStore.shared.snapshots()
        let payload = SchedulePayload(courses: courses,
                                      semesterStart: SharedSettings.semesterStart,
                                      slots: SharedSettings.periodSlots)
        SharedSettings.payload = payload
        WidgetRefresher.reload()
        WatchSyncService.shared.push(payload)
        await NotificationScheduler.shared.reschedule(courses: courses)
        LiveActivityManager.shared.cleanupEnded()
        if SharedSettings.autoLiveActivity {
            LiveActivityManager.shared.startIfUpcoming(courses: courses)
        }
        if classifyPhotos {
            await PhotoClassifier.shared.classifyRecent(days: 14, requestAccessIfNeeded: false)
        }
    }
}
