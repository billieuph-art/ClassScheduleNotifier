import Foundation

/// 一节课在作息表里的时间段，例如第 1 节 08:00–08:45。
struct PeriodSlot: Codable, Hashable, Identifiable {
    var index: Int
    var startMinutes: Int
    var endMinutes: Int
    var id: Int { index }
}

enum PeriodTable {
    static let defaultSlots: [PeriodSlot] = [
        ("08:00", "08:45"), ("08:55", "09:40"), ("10:00", "10:45"), ("10:55", "11:40"),
        ("14:00", "14:45"), ("14:55", "15:40"), ("16:00", "16:45"), ("16:55", "17:40"),
        ("19:00", "19:45"), ("19:55", "20:40"), ("20:50", "21:35"), ("21:45", "22:30"),
    ].enumerated().map { offset, pair in
        PeriodSlot(index: offset + 1,
                   startMinutes: TimeFormat.minutes(from: pair.0) ?? 0,
                   endMinutes: TimeFormat.minutes(from: pair.1) ?? 0)
    }

    static func slot(_ period: Int, in slots: [PeriodSlot]) -> PeriodSlot? {
        slots.first { $0.index == period }
    }

    /// 把开始/结束时间映射回最接近的节次。
    static func periods(startMinutes: Int, endMinutes: Int, in slots: [PeriodSlot]) -> (Int, Int)? {
        guard !slots.isEmpty else { return nil }
        let start = slots.min { abs($0.startMinutes - startMinutes) < abs($1.startMinutes - startMinutes) }!
        let end = slots.min { abs($0.endMinutes - endMinutes) < abs($1.endMinutes - endMinutes) }!
        return (start.index, max(start.index, end.index))
    }
}

enum TimeFormat {
    static func string(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 支持 "8:00"、"08：00"、"0800" 等写法。
    static func minutes(from text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "：", with: ":").trimmingCharacters(in: .whitespaces)
        let parts = cleaned.split(separator: ":")
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) {
            return h * 60 + m
        }
        if cleaned.count == 4, let value = Int(cleaned), value / 100 < 24, value % 100 < 60 {
            return (value / 100) * 60 + value % 100
        }
        return nil
    }
}

enum WeekdayName {
    private static let names = ["一", "二", "三", "四", "五", "六", "日"]

    static func short(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "?" }
        return names[weekday - 1]
    }

    static func full(_ weekday: Int) -> String { "周" + short(weekday) }

    /// 从文本中识别星期：周一 / 星期一 / 礼拜一 / Mon / Monday。
    /// `allowBare` 用于表格表头，允许单独的「一」「二」…「日」。
    static func detect(in text: String, allowBare: Bool = false) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        for (i, n) in names.enumerated() {
            for prefix in ["周", "星期", "礼拜"] where trimmed.contains(prefix + n) { return i + 1 }
        }
        if trimmed.contains("周天") || trimmed.contains("星期天") { return 7 }
        let english = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        for (i, e) in english.enumerated() where lowered.range(of: "\\b\(e)", options: .regularExpression) != nil {
            return i + 1
        }
        if allowBare {
            if trimmed == "天" { return 7 }
            if let index = names.firstIndex(of: trimmed) { return index + 1 }
        }
        return nil
    }
}

/// 跨设备（iPhone / 小组件 / Apple Watch）传递的轻量课程数据。
struct CourseSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var classroom: String
    var teacher: String
    var major: String
    /// 1 = 周一 … 7 = 周日
    var weekday: Int
    var startPeriod: Int
    var endPeriod: Int
    var startMinutes: Int
    var endMinutes: Int
    /// 上课周次；为空表示每周都上。
    var weeks: [Int]
    var colorHex: String

    var periodText: String {
        startPeriod == endPeriod ? "第\(startPeriod)节" : "第\(startPeriod)-\(endPeriod)节"
    }

    var timeText: String {
        "\(TimeFormat.string(startMinutes))–\(TimeFormat.string(endMinutes))"
    }

    func occurs(inWeek week: Int) -> Bool {
        weeks.isEmpty || weeks.contains(week)
    }
}

struct ClassOccurrence: Identifiable, Hashable {
    var course: CourseSnapshot
    var start: Date
    var end: Date
    var week: Int
    var id: String { "\(course.id.uuidString)-\(Int(start.timeIntervalSince1970))" }

    func isOngoing(at date: Date = .now) -> Bool { start <= date && date < end }
}

enum SemesterCalendar {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "zh_CN")
        c.timeZone = .current
        return c
    }

    static func weekday(of date: Date) -> Int {
        let w = calendar.component(.weekday, from: date)
        return w == 1 ? 7 : w - 1
    }

    /// 教学周：开学当周为第 1 周。
    static func weekNumber(of date: Date, semesterStart: Date) -> Int {
        let cal = calendar
        let firstMonday = cal.dateInterval(of: .weekOfYear, for: semesterStart)?.start ?? cal.startOfDay(for: semesterStart)
        let days = cal.dateComponents([.day], from: firstMonday, to: cal.startOfDay(for: date)).day ?? 0
        return Int(floor(Double(days) / 7.0)) + 1
    }

    static func date(on day: Date, minutes: Int) -> Date {
        let start = calendar.startOfDay(for: day)
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

enum ScheduleQuery {
    static func occurrences(of courses: [CourseSnapshot], from: Date, to: Date, semesterStart: Date) -> [ClassOccurrence] {
        let cal = SemesterCalendar.calendar
        var result: [ClassOccurrence] = []
        var day = cal.startOfDay(for: from)
        while day <= to {
            let weekday = SemesterCalendar.weekday(of: day)
            let week = SemesterCalendar.weekNumber(of: day, semesterStart: semesterStart)
            if week >= 1 {
                for course in courses where course.weekday == weekday && course.occurs(inWeek: week) {
                    let start = SemesterCalendar.date(on: day, minutes: course.startMinutes)
                    let end = SemesterCalendar.date(on: day, minutes: course.endMinutes)
                    if end >= from && start <= to {
                        result.append(ClassOccurrence(course: course, start: start, end: end, week: week))
                    }
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.sorted { $0.start < $1.start }
    }

    static func day(_ date: Date, courses: [CourseSnapshot], semesterStart: Date) -> [ClassOccurrence] {
        let cal = SemesterCalendar.calendar
        let start = cal.startOfDay(for: date)
        let end = start.addingTimeInterval(86_399)
        return occurrences(of: courses, from: start, to: end, semesterStart: semesterStart)
    }

    /// 正在上的课，或之后最近的一节课。
    static func current(courses: [CourseSnapshot], semesterStart: Date, now: Date = .now, horizon: TimeInterval = 7 * 86_400) -> ClassOccurrence? {
        occurrences(of: courses, from: now, to: now.addingTimeInterval(horizon), semesterStart: semesterStart)
            .first { $0.end > now }
    }
}

enum WeeksParser {
    /// 解析 "1-16周"、"1-8,10-16"、"1-16(单)"、"3,5,7周" 等写法；无法识别时返回空数组（表示每周）。
    static func parse(_ text: String) -> [Int] {
        var t = text.replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "~", with: "-")
            .replacingOccurrences(of: "至", with: "-")
        let oddOnly = t.contains("单")
        let evenOnly = t.contains("双")
        t = t.replacingOccurrences(of: "[^0-9,\\-]", with: " ", options: .regularExpression)
        var weeks = Set<Int>()
        for token in t.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let bounds = token.split(separator: "-").compactMap { Int($0) }
            if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] <= 30 {
                weeks.formUnion(bounds[0]...bounds[1])
            } else if bounds.count == 1, bounds[0] >= 1, bounds[0] <= 30 {
                weeks.insert(bounds[0])
            }
        }
        if oddOnly { weeks = weeks.filter { $0 % 2 == 1 } }
        if evenOnly { weeks = weeks.filter { $0 % 2 == 0 } }
        return weeks.sorted()
    }

    static func format(_ weeks: [Int]) -> String {
        guard !weeks.isEmpty else { return "每周" }
        var ranges: [String] = []
        var start = weeks[0], prev = weeks[0]
        for w in weeks.dropFirst() + [Int.max] {
            if w == prev + 1 { prev = w; continue }
            ranges.append(start == prev ? "\(start)" : "\(start)-\(prev)")
            start = w; prev = w
        }
        return ranges.joined(separator: ",") + "周"
    }
}

/// iPhone 发给 Apple Watch / 小组件的完整数据包。
struct SchedulePayload: Codable {
    var courses: [CourseSnapshot]
    var semesterStart: Date
    var slots: [PeriodSlot]
}
