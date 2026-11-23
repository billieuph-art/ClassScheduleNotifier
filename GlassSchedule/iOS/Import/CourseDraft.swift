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

    /// 只有节次就按作息表补时间，只有时间就反推节次。
    mutating func complete(with slots: [PeriodSlot]) {
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        classroom = classroom.trimmingCharacters(in: .whitespacesAndNewlines)
        teacher = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        weekday = min(max(weekday, 1), 7)
        let hasTime = endMinutes > startMinutes
        let hasPeriods = startPeriod > 0
        if hasPeriods && endPeriod < startPeriod { endPeriod = startPeriod }
        if hasPeriods && !hasTime,
           let s = PeriodTable.slot(startPeriod, in: slots), let e = PeriodTable.slot(endPeriod, in: slots) {
            startMinutes = s.startMinutes
            endMinutes = e.endMinutes
        } else if hasTime && !hasPeriods,
                  let periods = PeriodTable.periods(startMinutes: startMinutes, endMinutes: endMinutes, in: slots) {
            startPeriod = periods.0
            endPeriod = periods.1
        } else if !hasTime && !hasPeriods {
            startPeriod = 1; endPeriod = 2
            startMinutes = slots.first?.startMinutes ?? 480
            endMinutes = PeriodTable.slot(2, in: slots)?.endMinutes ?? 575
        }
    }

    var isValid: Bool { !name.isEmpty && endMinutes > startMinutes }

    func makeCourse(major: String) -> Course {
        Course(name: name, classroom: classroom, teacher: teacher, major: major, weekday: weekday,
               startPeriod: startPeriod, endPeriod: endPeriod, startMinutes: startMinutes, endMinutes: endMinutes,
               weeks: weeks)
    }

    var dedupeKey: String { "\(name)|\(weekday)|\(startPeriod)|\(startMinutes)" }
}
