import AppIntents
import Foundation

/// 可以从 Siri、快捷指令（例如“每天 7:30 自动运行”的个人自动化）或小组件按钮触发，即使 App 在后台也能开启实时活动。
struct StartNextClassActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "开始下一节课的实时活动"
    static let description = IntentDescription("在锁屏和灵动岛显示下一节课的教室与倒计时。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let courses = DataStore.shared.snapshots()
        guard let next = ScheduleQuery.current(courses: courses, semesterStart: SharedSettings.semesterStart, horizon: 86_400) else {
            return .result(dialog: "接下来 24 小时内没有课")
        }
        LiveActivityManager.shared.start(next)
        return .result(dialog: "已开始：\(next.course.name)，\(next.course.classroom)")
    }
}

struct TodayClassesIntent: AppIntent {
    static let title: LocalizedStringResource = "今天有什么课"
    static let description = IntentDescription("列出今天的课程、教室和时间。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let list = ScheduleQuery.day(.now, courses: DataStore.shared.snapshots(), semesterStart: SharedSettings.semesterStart)
        guard !list.isEmpty else { return .result(value: "", dialog: "今天没有课，好好休息") }
        let text = list.map { "\($0.course.periodText) \($0.course.timeText) \($0.course.name) @\($0.course.classroom)" }
            .joined(separator: "\n")
        return .result(value: text, dialog: "今天有 \(list.count) 节课：\n\(text)")
    }
}

struct ClassifyPhotosIntent: AppIntent {
    static let title: LocalizedStringResource = "归类上课照片"
    static let description = IntentDescription("把最近上课期间拍摄的照片归类到对应课程的复习资料。")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await PhotoClassifier.shared.classifyRecent(days: 7, requestAccessIfNeeded: false)
        return .result(dialog: "\(PhotoClassifier.shared.lastSummary ?? "完成")")
    }
}

struct GlassScheduleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodayClassesIntent(),
                    phrases: ["\(.applicationName)今天有什么课", "用\(.applicationName)查看今天的课"],
                    shortTitle: "今天的课", systemImageName: "calendar")
        AppShortcut(intent: StartNextClassActivityIntent(),
                    phrases: ["用\(.applicationName)开始下一节课", "\(.applicationName)下一节课倒计时"],
                    shortTitle: "下一节课倒计时", systemImageName: "timer")
        AppShortcut(intent: ClassifyPhotosIntent(),
                    phrases: ["用\(.applicationName)整理上课照片"],
                    shortTitle: "整理上课照片", systemImageName: "photo.stack")
    }
}
