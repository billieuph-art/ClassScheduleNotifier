import Foundation

enum AppGroup {
    static let id = "group.com.example.glassschedule"
}

/// 所有设置都放在 App Group 的 UserDefaults 中，主 App 与小组件共享。
enum SharedSettings {
    static let defaults: UserDefaults = UserDefaults(suiteName: AppGroup.id) ?? .standard

    enum Key {
        static let semesterStart = "semesterStart"
        static let reminderMinutes = "reminderMinutes"
        static let autoLiveActivity = "autoLiveActivity"
        static let autoClassifyPhotos = "autoClassifyPhotos"
        static let photoToleranceMinutes = "photoToleranceMinutes"
        static let onlyStudyPhotos = "onlyStudyPhotos"
        static let useAppleIntelligence = "useAppleIntelligence"
        static let exportToFiles = "exportToFiles"
        static let defaultMajor = "defaultMajor"
        static let periodSlots = "periodSlots"
        static let payload = "schedulePayload"
        static let showWeekend = "showWeekend"
    }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.semesterStart: defaultSemesterStart().timeIntervalSinceReferenceDate,
            Key.reminderMinutes: 30,
            Key.autoLiveActivity: true,
            Key.autoClassifyPhotos: true,
            Key.photoToleranceMinutes: 10,
            Key.onlyStudyPhotos: true,
            Key.useAppleIntelligence: true,
            Key.exportToFiles: true,
            Key.defaultMajor: "我的专业",
            Key.showWeekend: false,
        ])
    }

    static var semesterStart: Date {
        get { Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Key.semesterStart)) }
        set { defaults.set(newValue.timeIntervalSinceReferenceDate, forKey: Key.semesterStart) }
    }

    static var reminderMinutes: Int { max(1, defaults.integer(forKey: Key.reminderMinutes)) }
    static var autoLiveActivity: Bool { defaults.bool(forKey: Key.autoLiveActivity) }
    static var autoClassifyPhotos: Bool { defaults.bool(forKey: Key.autoClassifyPhotos) }
    static var photoToleranceMinutes: Int { defaults.integer(forKey: Key.photoToleranceMinutes) }
    static var onlyStudyPhotos: Bool { defaults.bool(forKey: Key.onlyStudyPhotos) }
    static var useAppleIntelligence: Bool { defaults.bool(forKey: Key.useAppleIntelligence) }
    static var exportToFiles: Bool { defaults.bool(forKey: Key.exportToFiles) }
    static var defaultMajor: String { defaults.string(forKey: Key.defaultMajor) ?? "我的专业" }

    static var periodSlots: [PeriodSlot] {
        get {
            guard let data = defaults.data(forKey: Key.periodSlots),
                  let slots = try? JSONDecoder().decode([PeriodSlot].self, from: data), !slots.isEmpty
            else { return PeriodTable.defaultSlots }
            return slots
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.periodSlots) }
    }

    static var payload: SchedulePayload? {
        get {
            guard let data = defaults.data(forKey: Key.payload) else { return nil }
            return try? JSONDecoder().decode(SchedulePayload.self, from: data)
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.payload) }
    }

    /// 默认开学日期：春季学期 2 月底，秋季学期 9 月初。
    static func defaultSemesterStart(now: Date = .now) -> Date {
        let cal = SemesterCalendar.calendar
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        var comps = DateComponents(year: year, month: 9, day: 1)
        if month < 2 { comps = DateComponents(year: year - 1, month: 9, day: 1) }
        else if month < 8 { comps = DateComponents(year: year, month: 2, day: 24) }
        return cal.date(from: comps) ?? now
    }
}
