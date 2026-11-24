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
        startPeriod == endPeriod ? "第\(startPeriod)节" : "第\(startPeriod)-\(endPeriod)节"
    }

    var timeText: String {
        "\(TimeFormat.string(startMinutes))–\(TimeFormat.string(endMinutes))"
    }

    /// - Parameter preferPeriods: 网格课表以节次为准重算时间；列表/ICS 以时间反推节次。
    mutating func complete(with slots: [PeriodSlot], preferPeriods: Bool = true) {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        classroom = classroom.trimmingCharacters(in: .whitespacesAndNewlines)
        teacher = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if !hasPeriods || abs(periods.0 - startPeriod) > 0 {
                // 节次与时间不一致时，以时间映射的节次为准（并回写标准作息）
                if let s = PeriodTable.slot(periods.0, in: slots), let e = PeriodTable.slot(periods.1, in: slots) {
                    startMinutes = s.startMinutes
                    endMinutes = e.endMinutes
                }
            }
        } else if hasPeriods,
                  let s = PeriodTable.slot(startPeriod, in: slots), let e = PeriodTable.slot(endPeriod, in: slots) {
            startMinutes = s.startMinutes
            endMinutes = e.endMinutes
        } else if !hasTime && !hasPeriods {
            startPeriod = 1; endPeriod = 2
            startMinutes = slots.first?.startMinutes ?? 480
            endMinutes = PeriodTable.slot(2, in: slots)?.endMinutes ?? 575
        }
    }

    var isValid: Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2, endMinutes > startMinutes else { return false }
        if ScheduleJunk.isNonCourseText(cleaned) { return false }
        let junk = ["上午", "下午", "晚上", "备注", "课程", "教室", "教师", "时间", "节次", "地点", "节数", "今天", "时间段", "课程名", "周次", "每周"]
        if junk.contains(cleaned) { return false }
        if cleaned.contains("@") { return false }
        if cleaned.hasPrefix("周") && cleaned.count <= 3 { return false }
        if cleaned.hasPrefix("星期") && cleaned.count <= 4 { return false }
        // 纯教室号 / 纯时间
        if cleaned.range(of: #"^\d{3,5}$"#, options: .regularExpression) != nil { return false }
        if cleaned.range(of: #"^[一二三四五六日天]?@?\d{3,5}$"#, options: .regularExpression) != nil { return false }
        if cleaned.range(of: #"^\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil { return false }
        return true
    }

    func makeCourse(major: String) -> Course {
        Course(name: name, classroom: classroom, teacher: teacher, major: major, weekday: weekday,
               startPeriod: startPeriod, endPeriod: endPeriod, startMinutes: startMinutes, endMinutes: endMinutes,
               weeks: weeks)
    }

    var dedupeKey: String { "\(name)|\(weekday)|\(startPeriod)|\(endPeriod)|\(classroom)" }
}
