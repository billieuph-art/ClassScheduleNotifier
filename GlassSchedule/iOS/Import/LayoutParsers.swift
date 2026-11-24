import Foundation
import CoreGraphics

/// 列表式课表：「一、星期一」分区 + 时间段/课程名/教师/教室/周次 横排表。
enum ListScheduleParser {
    static func parse(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        guard !items.isEmpty else { return [] }
        var drafts: [CourseDraft] = []
        for page in Set(items.map(\.page)).sorted() {
            drafts += parsePage(items.filter { $0.page == page }, slots: slots)
        }
        return drafts
    }

    private static func parsePage(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        let rows = LayoutRows.group(items)
        var currentDay: Int?
        var drafts: [CourseDraft] = []
        var columnHints: ColumnHints?

        for row in rows {
            let texts = row.map(\.text)
            let joined = texts.joined(separator: " ")
            if let day = dayHeader(in: joined) {
                currentDay = day
                continue
            }
            if columnHints == nil, looksLikeColumnHeader(texts) {
                columnHints = ColumnHints.detect(from: row)
                continue
            }
            guard let day = currentDay else { continue }
            if looksLikeColumnHeader(texts) { continue }
            if joined.contains("休息") || joined.contains("无课程") { continue }

            if let draft = parseDataRow(row, day: day, hints: columnHints, slots: slots) {
                drafts.append(draft)
            }
        }
        return drafts
    }

    private static func dayHeader(in text: String) -> Int? {
        // 「一、星期一」「二、星期二」「日、星期日」「周一」
        if let m = text.range(of: #"[一二三四五六日天]、?\s*星期[一二三四五六日天]"#, options: .regularExpression) {
            return WeekdayName.detect(in: String(text[m]), allowBare: false)
        }
        if text.range(of: #"^[一二三四五六日天]、"#, options: .regularExpression) != nil {
            return WeekdayName.detect(in: "星期" + String(text.prefix(1)), allowBare: false)
        }
        return WeekdayName.detect(in: text, allowBare: false)
    }

    private static func looksLikeColumnHeader(_ texts: [String]) -> Bool {
        let blob = texts.joined()
        let keys = ["时间", "课程", "教师", "教室", "周次", "地点", "节次"]
        return keys.filter { blob.contains($0) }.count >= 2
    }

    private static func parseDataRow(_ row: [TextItem], day: Int, hints: ColumnHints?, slots: [PeriodSlot]) -> CourseDraft? {
        let sorted = row.sorted { $0.rect.minX < $1.rect.minX }
        var timeText = ""
        var name = ""
        var teacher = ""
        var classroom = ""
        var weeksText = ""

        if let hints, hints.isReliable {
            for item in sorted {
                switch hints.column(for: item.rect.midX) {
                case .time: timeText += (timeText.isEmpty ? "" : " ") + item.text
                case .name: name += item.text
                case .teacher: teacher += item.text
                case .room: classroom += (classroom.isEmpty ? "" : " ") + item.text
                case .weeks: weeksText += (weeksText.isEmpty ? "" : " ") + item.text
                case .unknown: break
                }
            }
        }

        // 无可靠表头时：按「时间 → 课名 → 教师 → 教室 → 周次」启发式拆分
        if name.count < 2 {
            let fields = splitRowHeuristically(sorted.map(\.text))
            if timeText.isEmpty { timeText = fields.time }
            if name.isEmpty { name = fields.name }
            if teacher.isEmpty { teacher = fields.teacher }
            if classroom.isEmpty { classroom = fields.classroom }
            if weeksText.isEmpty { weeksText = fields.weeks }
        }

        name = sanitizeCourseName(name)
        teacher = sanitizeTeacher(teacher)
        classroom = sanitizeClassroom(classroom)
        guard name.count >= 2, !ScheduleJunk.isDayOrHeader(name) else { return nil }

        var draft = CourseDraft(name: name, classroom: classroom, teacher: teacher, weekday: day,
                                weeks: WeeksParser.parse(weeksText))
        if let (s, e) = parseTimeRange(timeText) {
            draft.startMinutes = s
            draft.endMinutes = e
        }
        draft.complete(with: slots, preferPeriods: false)
        return draft.isValid ? draft : nil
    }

    private static func splitRowHeuristically(_ parts: [String]) -> (time: String, name: String, teacher: String, classroom: String, weeks: String) {
        var time = "", name = "", teacher = "", classroom = "", weeks = ""
        var rest = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let idx = rest.firstIndex(where: { parseTimeRange($0) != nil }) {
            time = rest.remove(at: idx)
        }
        if let idx = rest.firstIndex(where: { $0.contains("周") && ($0.contains("单") || $0.contains("双") || $0.range(of: #"\d"#, options: .regularExpression) != nil) }) {
            weeks = rest.remove(at: idx)
        }
        // 教室：含楼/馆/机房 或字母门牌
        if let idx = rest.firstIndex(where: { isClassroomToken($0) }) {
            classroom = rest.remove(at: idx)
            // 下一段若是门牌号则合并
            if idx < rest.count, rest[idx].range(of: #"^[A-Za-z]?\-?\d{2,4}$"#, options: .regularExpression) != nil {
                classroom += " " + rest.remove(at: idx)
            }
        }
        // 教师：2–4 字或「xx老师」「辅导员」「体育教研室」
        if let idx = rest.firstIndex(where: { isTeacherToken($0) }) {
            teacher = rest.remove(at: idx)
        }
        name = rest.joined()
        // 若课名仍粘着教师：高等数学（上）张伟
        if teacher.isEmpty, let split = peelTeacher(from: name) {
            name = split.name
            teacher = split.teacher
        }
        return (time, name, teacher, classroom, weeks)
    }

    private static func isClassroomToken(_ t: String) -> Bool {
        t.contains("楼") || t.contains("馆") || t.contains("机房") || t.contains("教室")
            || t.range(of: #"[A-Za-z]\-?\d{2,4}"#, options: .regularExpression) != nil
            || t.range(of: #"^\d{3,4}$"#, options: .regularExpression) != nil
    }

    private static func isTeacherToken(_ t: String) -> Bool {
        if t.hasSuffix("老师") || t.hasSuffix("教授") || t == "辅导员" || t.contains("教研室") || t == "体育组" || t == "指导教师组" {
            return true
        }
        return t.range(of: #"^[\p{Han}]{2,4}$"#, options: .regularExpression) != nil
            && !t.contains("大学") && !t.contains("数学") && !t.contains("英语") && !t.contains("物理")
            && !t.contains("体育") && !t.contains("程序") && !t.contains("线性") && !t.contains("形势")
    }

    private static func peelTeacher(from name: String) -> (name: String, teacher: String)? {
        let chars = Array(name)
        for len in [4, 3, 2] {
            guard chars.count > len + 1 else { continue }
            let suffix = String(chars.suffix(len))
            let prefix = String(chars.dropLast(len))
            guard isTeacherToken(suffix), prefix.count >= 2 else { continue }
            if prefix.contains("（") && !prefix.contains("）") { continue }
            if prefix.contains("(") && !prefix.contains(")") { continue }
            return (prefix, suffix)
        }
        return nil
    }

    private static func parseTimeRange(_ text: String) -> (Int, Int)? {
        guard let m = text.range(of: #"(\d{1,2})[:：](\d{2})\s*[-－—~～至到]\s*(\d{1,2})[:：](\d{2})"#, options: .regularExpression) else {
            return nil
        }
        let s = String(text[m])
        let nums = s.split { !"0123456789".contains($0) }.compactMap { Int($0) }
        guard nums.count >= 4 else { return nil }
        return (nums[0] * 60 + nums[1], nums[2] * 60 + nums[3])
    }

    private static func sanitizeCourseName(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: #"^[一二三四五六日天]、"#, with: "", options: .regularExpression)
        return t
    }

    private static func sanitizeTeacher(_ raw: String) -> String {
        raw.replacingOccurrences(of: "老师|教授", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeClassroom(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ColumnHints {
        enum Kind { case time, name, teacher, room, weeks, unknown }
        var centers: [(Kind, CGFloat)]
        var isReliable: Bool { centers.count >= 3 }

        static func detect(from row: [TextItem]) -> ColumnHints {
            var centers: [(Kind, CGFloat)] = []
            for item in row {
                let t = item.text
                let kind: Kind
                if t.contains("时间") || t.contains("节次") { kind = .time }
                else if t.contains("课程") || t.contains("课名") { kind = .name }
                else if t.contains("教师") || t.contains("老师") { kind = .teacher }
                else if t.contains("教室") || t.contains("地点") { kind = .room }
                else if t.contains("周次") || t == "周" { kind = .weeks }
                else { continue }
                centers.append((kind, item.rect.midX))
            }
            return ColumnHints(centers: centers)
        }

        func column(for x: CGFloat) -> Kind {
            guard let best = centers.min(by: { abs($0.1 - x) < abs($1.1 - x) }) else { return .unknown }
            return best.0
        }
    }
}

/// 时间轴课表：左侧星期，上方 08:00–20:00，课块内「课名 / 教师 | 教室 / (周次)」。
enum TimelineScheduleParser {
    static func parse(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        guard items.count >= 8 else { return [] }
        // 需要能找到多个星期标签 + 多个时刻刻度
        let dayLabels = items.compactMap { item -> (Int, TextItem)? in
            let t = item.text.trimmingCharacters(in: .whitespaces)
            guard let day = WeekdayName.detect(in: t, allowBare: false) ?? bareDayBox(t) else { return nil }
            // 时间轴里星期通常在左侧
            guard item.rect.midX < 0.22 else { return nil }
            return (day, item)
        }
        let timeTicks = items.compactMap { item -> (Int, CGFloat)? in
            guard let m = item.text.range(of: #"^(\d{1,2})[:：](\d{2})$"#, options: .regularExpression) else { return nil }
            let parts = String(item.text[m]).split { !"0123456789".contains($0) }.compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            return (parts[0] * 60 + parts[1], item.rect.midX)
        }
        guard dayLabels.count >= 3, timeTicks.count >= 3 else { return [] }

        let dayBands = bandDays(dayLabels.map { ($0.0, $0.1.rect.midY) })
        let axis = fitTimeAxis(timeTicks)
        var drafts: [CourseDraft] = []

        // 课名候选：不含纯时间、不含单独星期
        let candidates = items.filter { item in
            let t = item.text.trimmingCharacters(in: .whitespaces)
            guard t.count >= 2 else { return false }
            if ScheduleJunk.isDayOrHeader(t) { return false }
            if t.range(of: #"^\d{1,2}[:：]\d{2}$"#, options: .regularExpression) != nil { return false }
            if item.rect.midX < 0.18 { return false }
            return true
        }

        // 按垂直聚集成「课块」
        let blocks = clusterBlocks(candidates)
        for block in blocks {
            guard let day = nearestDay(for: block.map(\.rect.midY).reduce(0, +) / CGFloat(block.count), bands: dayBands) else { continue }
            let texts = block.sorted { $0.rect.minY < $1.rect.minY }.map(\.text)
            let parsed = parseBlockTexts(texts)
            guard parsed.name.count >= 2, !ScheduleJunk.isDayOrHeader(parsed.name) else { continue }

            let midX = block.map(\.rect.midX).reduce(0, +) / CGFloat(block.count)
            let width = (block.map(\.rect.maxX).max() ?? midX) - (block.map(\.rect.minX).min() ?? midX)
            let startMin = axis.minutes(at: midX - width * 0.35)
            let endMin = axis.minutes(at: midX + width * 0.35)

            var draft = CourseDraft(name: parsed.name, classroom: parsed.classroom, teacher: parsed.teacher,
                                    weekday: day, weeks: parsed.weeks)
            if endMin > startMin + 20 {
                draft.startMinutes = startMin
                draft.endMinutes = endMin
            }
            draft.complete(with: slots, preferPeriods: false)
            if draft.isValid { drafts.append(draft) }
        }
        return drafts
    }

    private static func bareDayBox(_ t: String) -> Int? {
        // 黑底白字小方块里只有「周一」或「周日」
        WeekdayName.detect(in: t, allowBare: false)
    }

    private static func bandDays(_ points: [(Int, CGFloat)]) -> [(Int, ClosedRange<CGFloat>)] {
        let sorted = points.sorted { $0.1 < $1.1 }
        var bands: [(Int, ClosedRange<CGFloat>)] = []
        for (i, p) in sorted.enumerated() {
            let prev = i > 0 ? (sorted[i - 1].1 + p.1) / 2 : max(0, p.1 - 0.06)
            let next = i + 1 < sorted.count ? (p.1 + sorted[i + 1].1) / 2 : min(1, p.1 + 0.06)
            bands.append((p.0, prev...next))
        }
        return bands
    }

    private static func nearestDay(for y: CGFloat, bands: [(Int, ClosedRange<CGFloat>)]) -> Int? {
        bands.first { $0.1.contains(y) }?.0
    }

    private struct TimeAxis {
        var samples: [(minutes: Int, x: CGFloat)]
        func minutes(at x: CGFloat) -> Int {
            let sorted = samples.sorted { $0.x < $1.x }
            guard let first = sorted.first, let last = sorted.last, last.x > first.x else {
                return 8 * 60 + Int(max(0, min(1, x)) * 12 * 60)
            }
            if x <= first.x { return first.minutes }
            if x >= last.x { return last.minutes }
            for i in 0..<(sorted.count - 1) {
                let a = sorted[i], b = sorted[i + 1]
                if x >= a.x && x <= b.x {
                    let t = (x - a.x) / (b.x - a.x)
                    return Int(Double(a.minutes) + Double(b.minutes - a.minutes) * Double(t))
                }
            }
            return first.minutes
        }
    }

    private static func fitTimeAxis(_ ticks: [(Int, CGFloat)]) -> TimeAxis {
        TimeAxis(samples: ticks.map { (minutes: $0.0, x: $0.1) })
    }

    private static func clusterBlocks(_ items: [TextItem]) -> [[TextItem]] {
        let sorted = items.sorted { $0.rect.minY < $1.rect.minY || ($0.rect.minY == $1.rect.minY && $0.rect.minX < $1.rect.minX) }
        var blocks: [[TextItem]] = []
        for item in sorted {
            if let last = blocks.last,
               let seed = last.first,
               abs(item.rect.midY - seed.rect.midY) < 0.045,
               abs(item.rect.midX - seed.rect.midX) < 0.12 {
                blocks[blocks.count - 1].append(item)
            } else {
                var matched: Int?
                for i in blocks.indices.reversed() {
                    let block = blocks[i]
                    let midY = block.map(\.rect.midY).reduce(0, +) / CGFloat(max(block.count, 1))
                    let midX = block.map(\.rect.midX).reduce(0, +) / CGFloat(max(block.count, 1))
                    if abs(item.rect.midY - midY) < 0.04 && abs(item.rect.midX - midX) < 0.1 {
                        matched = i
                        break
                    }
                }
                if let matched {
                    blocks[matched].append(item)
                } else {
                    blocks.append([item])
                }
            }
        }
        return blocks.filter { $0.count >= 1 }
    }

    private static func parseBlockTexts(_ texts: [String]) -> (name: String, teacher: String, classroom: String, weeks: [Int]) {
        var name = "", teacher = "", classroom = "", weeks: [Int] = []
        for (i, raw) in texts.enumerated() {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("(") || t.hasPrefix("（") || t.contains("每周") || (t.contains("周") && t.range(of: #"\d"#, options: .regularExpression) != nil) {
                weeks = WeeksParser.parse(t)
                continue
            }
            if t.contains("|") {
                let parts = t.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    teacher = parts[0].replacingOccurrences(of: "老师", with: "")
                    classroom = parts[1...].joined(separator: " ")
                }
                continue
            }
            if i == 0 {
                name = t
            } else if teacher.isEmpty && (t.hasSuffix("老师") || t.range(of: #"^[\p{Han}]{2,4}$"#, options: .regularExpression) != nil) {
                teacher = t.replacingOccurrences(of: "老师", with: "")
            } else if classroom.isEmpty {
                classroom = t
            }
        }
        return (name, teacher, classroom, weeks)
    }
}

enum ScheduleJunk {
    static func isDayOrHeader(_ name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let lowered = t.lowercased()
        let english = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                       "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        if english.contains(lowered) { return true }
        if WeekdayName.detect(in: t, allowBare: false) != nil && t.count <= 6 { return true }
        if t.range(of: #"^[一二三四五六日天]、?\s*星期"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^第?\d{1,2}([-－—~～]\d{1,2})?节$"#, options: .regularExpression) != nil { return true }
        if t.range(of: #"^\d{1,2}[:：]\d{2}([-－—~～]\d{1,2}[:：]\d{2})?$"#, options: .regularExpression) != nil { return true }
        let headers = ["时间段", "课程名", "教师", "教室", "周次", "本学期课程安排", "课程表", "周课程时间轴"]
        if headers.contains(t) { return true }
        return false
    }
}
