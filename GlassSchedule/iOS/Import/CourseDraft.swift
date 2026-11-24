import Foundation

/// 导入时识别出来、尚未保存的课程，用户可以在预览页修改或取消勾选。
struct CourseDraft: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var classroom: String = ""
    var teacher: String = ""
    var weekday: Int
    var startPeriod: Int = 0
    var endPeriod: Int = 0
    var startMinutes: Int = 0
    var endMinutes: Int = 0
    var weeks: [Int] = []
    var isIncluded = true

    var periodText: String {
        guard startPeriod > 0 else { return "节次未知" }
        return startPeriod == endPeriod ? "第\(startPeriod)节" : "第\(startPeriod)-\(endPeriod)节"
    }

    var timeText: String {
        guard endMinutes > startMinutes else { return "时间未知" }
        return "\(TimeFormat.string(startMinutes))–\(TimeFormat.string(endMinutes))"
    }

    /// 周次类型：空=每周；全奇数=单周；全偶数=双周；否则自定义区间。
    var weekKind: String {
        if weeks.isEmpty { return "每周" }
        let odd = weeks.allSatisfy { $0 % 2 == 1 }
        let even = weeks.allSatisfy { $0 % 2 == 0 }
        if odd { return "单周" }
        if even { return "双周" }
        return "自定义"
    }

    var weekStart: Int? { weeks.min() }
    var weekEnd: Int? { weeks.max() }

    /// - Parameter preferPeriods: 网格课表以节次为准重算时间；列表/ICS 以时间反推节次。
    mutating func complete(with slots: [PeriodSlot], preferPeriods: Bool = true) {
        name = OCRCleanup.sanitizeCourseName(name)
        classroom = OCRCleanup.sanitizeClassroom(classroom)
        teacher = OCRCleanup.sanitizeTeacher(teacher)
        // 再处理一次 name@room（AI / 碎片拼接后的残留）
        if let at = name.firstIndex(of: "@") {
            let room = String(name[name.index(after: at)...]).trimmingCharacters(in: .whitespaces)
            let course = String(name[..<at]).trimmingCharacters(in: .whitespaces)
            if !course.isEmpty, room.rangeOfCharacter(from: .decimalDigits) != nil {
                if classroom.isEmpty { classroom = room }
                name = course
            }
        }
        weekday = min(max(weekday, 1), 7)
        let hasTime = endMinutes > startMinutes
        let hasPeriods = startPeriod > 0
        if hasPeriods && endPeriod < startPeriod { endPeriod = startPeriod }

        if preferPeriods, hasPeriods,
           let s = PeriodTable.slot(startPeriod, in: slots), let e = PeriodTable.slot(endPeriod, in: slots) {
            startMinutes = s.startMinutes
            endMinutes = e.endMinutes
        } else if hasTime,
                  let periods = PeriodTable.periods(startMinutes: startMinutes, endMinutes: endMinutes, in: slots) {
            startPeriod = periods.0
            endPeriod = periods.1
            if let s = PeriodTable.slot(periods.0, in: slots), let e = PeriodTable.slot(periods.1, in: slots) {
                startMinutes = s.startMinutes
                endMinutes = e.endMinutes
            }
        } else if hasPeriods,
                  let s = PeriodTable.slot(startPeriod, in: slots), let e = PeriodTable.slot(endPeriod, in: slots) {
            startMinutes = s.startMinutes
            endMinutes = e.endMinutes
        }
        // 无节次且无时间时绝不臆造「第1-2节」，留给确认页标「待确认」
    }

    /// 课名合法即可进入确认页；无节次/时间的项用 needsReview + canCommit 约束保存。
    var isValid: Bool {
        let cleaned = OCRCleanup.sanitizeCourseName(name)
        guard cleaned.count >= 2 else { return false }
        if OCRCleanup.isBogusCourseName(cleaned) { return false }
        let junk = ["上午", "下午", "晚上", "备注", "课程", "教室", "教师", "时间", "节次", "地点", "节数", "今天", "时间段", "课程名", "周次", "每周"]
        if junk.contains(cleaned) { return false }
        if cleaned.contains("@") { return false }
        if cleaned.hasPrefix("周") && cleaned.count <= 3 { return false }
        if cleaned.hasPrefix("星期") && cleaned.count <= 4 { return false }
        if cleaned.range(of: #"^\d{3,5}$"#, options: .regularExpression) != nil { return false }
        if cleaned.range(of: #"^[一二三四五六日天]?@?\d{3,5}$"#, options: .regularExpression) != nil { return false }
        if cleaned.range(of: #"^\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil { return false }
        return true
    }

    /// 写入正式课表所需的最小时间信息。
    var canCommit: Bool {
        isValid && startPeriod > 0 && endPeriod >= startPeriod && endMinutes > startMinutes
    }

    /// 确认页提示：课名可疑、缺教室/教师、或缺节次时间。
    var needsReview: Bool {
        if OCRCleanup.looksLikeMergedCourses(name) || OCRCleanup.isBogusCourseName(name) { return true }
        if classroom.isEmpty && teacher.isEmpty { return true }
        if startPeriod <= 0 || endMinutes <= startMinutes { return true }
        return false
    }

    var reviewBadge: String {
        if OCRCleanup.looksLikeMergedCourses(name) || OCRCleanup.isBogusCourseName(name) { return "课名可疑" }
        if startPeriod <= 0 || endMinutes <= startMinutes { return "缺节次" }
        if classroom.isEmpty && teacher.isEmpty { return "缺教室/教师" }
        return "待确认"
    }

    /// 导入后：可疑或缺关键字段默认不勾选，防止静默写入。
    mutating func applyImportSafety() {
        name = OCRCleanup.sanitizeCourseName(name)
        if needsReview {
            isIncluded = false
        }
    }

    func makeCourse(major: String) -> Course {
        Course(name: name, classroom: classroom, teacher: teacher, major: major, weekday: weekday,
               startPeriod: startPeriod, endPeriod: endPeriod, startMinutes: startMinutes, endMinutes: endMinutes,
               weeks: weeks)
    }

    var dedupeKey: String { "\(name)|\(weekday)|\(startPeriod)|\(endPeriod)|\(classroom)" }
}
