import Foundation

private enum Patterns {
    static let periodRange = try! NSRegularExpression(pattern: "第?\\s*(\\d{1,2})\\s*(?:[-－~～至,，]\\s*(\\d{1,2}))?\\s*节")
    static let timeRange = try! NSRegularExpression(pattern: "(\\d{1,2}[:：]\\d{2})\\s*[-－~～至]\\s*(\\d{1,2}[:：]\\d{2})")
    static let weeks = try! NSRegularExpression(pattern: "[\\[(（]?\\s*\\d{1,2}(?:\\s*[-－~～]\\s*\\d{1,2})?(?:\\s*[,，]\\s*\\d{1,2}(?:\\s*[-－~～]\\s*\\d{1,2})?)*\\s*周?\\s*[\\(（]?[单双]?[\\)）]?\\s*周\\s*[\\])）]?")
    static let room = try! NSRegularExpression(pattern: "(?:[\\p{Han}A-Za-z0-9]*(?:楼|馆|教|室|区|中心|实验|机房|报告厅)[\\p{Han}A-Za-z0-9\\-－]*\\d+[\\p{Han}A-Za-z0-9\\-－]*)|(?:\\b[A-Za-z]{1,3}\\d?[-－]?\\d{3,4}\\b)")
    static let rowLabel = try! NSRegularExpression(pattern: "^\\s*第?\\s*(\\d{1,2})\\s*节?\\s*$")
    static let teacher = try! NSRegularExpression(pattern: "^(?:教师[:：]?)?\\s*[\\p{Han}]{2,4}(?:老师|教授)?$")

    static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func string(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
}

private struct CellFields {
    var name = ""
    var classroom = ""
    var teacher = ""
    var weeks: [Int] = []
    var periods: (Int, Int)?
    var times: (Int, Int)?

    init(lines: [String]) {
        var rest: [String] = []
        for raw in lines {
            var line = raw
            if let m = Patterns.firstMatch(Patterns.timeRange, in: line),
               let s = Patterns.string(m, group: 1, in: line).flatMap({ TimeFormat.minutes(from: $0) }),
               let e = Patterns.string(m, group: 2, in: line).flatMap({ TimeFormat.minutes(from: $0) }) {
                times = (s, e)
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            if let m = Patterns.firstMatch(Patterns.weeks, in: line) {
                weeks = WeeksParser.parse(Patterns.string(m, group: 0, in: line) ?? "")
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            if let m = Patterns.firstMatch(Patterns.periodRange, in: line),
               let s = Patterns.string(m, group: 1, in: line).flatMap({ Int($0) }) {
                let e = Patterns.string(m, group: 2, in: line).flatMap { Int($0) } ?? s
                periods = (s, max(s, e))
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            if classroom.isEmpty, let m = Patterns.firstMatch(Patterns.room, in: line) {
                classroom = Patterns.string(m, group: 0, in: line) ?? ""
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            let tokens = line.split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "/" })
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            rest += tokens
        }
        if let first = rest.first {
            name = first
            for candidate in rest.dropFirst() where teacher.isEmpty && Patterns.firstMatch(Patterns.teacher, in: candidate) != nil {
                teacher = candidate
            }
        }
    }
}

/// 适用于“表头是星期、左侧是节次”的网格课程表截图。
enum GridHeuristicParser {
    static func parse(_ allItems: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        var drafts: [CourseDraft] = []
        for page in Set(allItems.map(\.page)).sorted() {
            drafts += parsePage(allItems.filter { $0.page == page }, slots: slots)
        }
        return drafts
    }

    private static func parsePage(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        var columns: [Int: CGFloat] = [:]
        var headerBottom: CGFloat = 0
        for item in items.sorted(by: { $0.rect.minY < $1.rect.minY }) where item.text.count <= 8 {
            if let weekday = WeekdayName.detect(in: item.text), columns[weekday] == nil {
                columns[weekday] = item.rect.midX
                headerBottom = max(headerBottom, item.rect.maxY)
            }
        }
        guard columns.count >= 3 else { return [] }

        let centers = columns.values.sorted()
        let spacing = zip(centers, centers.dropFirst()).map { $1 - $0 }.min() ?? 0.12
        let leftBoundary = centers[0] - spacing * 0.6

        var rowCenters: [Int: CGFloat] = [:]
        for item in items where item.rect.midX < leftBoundary && item.rect.minY > headerBottom - 0.01 {
            if let m = Patterns.firstMatch(Patterns.rowLabel, in: item.text),
               let period = Patterns.string(m, group: 1, in: item.text).flatMap({ Int($0) }), rowCenters[period] == nil {
                rowCenters[period] = item.rect.midY
            }
        }

        let cells = items.filter { $0.rect.minY >= headerBottom - 0.002 && $0.rect.midX >= leftBoundary }
        var byWeekday: [Int: [TextItem]] = [:]
        for item in cells {
            let weekday = columns.min { abs($0.value - item.rect.midX) < abs($1.value - item.rect.midX) }!.key
            byWeekday[weekday, default: []].append(item)
        }

        var drafts: [CourseDraft] = []
        for (weekday, columnItems) in byWeekday {
            let columnBlocks = blocks(from: columnItems)
            for (blockIndex, block) in columnBlocks.enumerated() {
                let nextTop = blockIndex + 1 < columnBlocks.count ? columnBlocks[blockIndex + 1].map(\.rect.minY).min() : nil
                let fields = CellFields(lines: block.map(\.text))
                guard fields.name.count >= 2 else { continue }
                var draft = CourseDraft(name: fields.name, classroom: fields.classroom, teacher: fields.teacher,
                                        weekday: weekday, weeks: fields.weeks)
                if let p = fields.periods {
                    draft.startPeriod = p.0; draft.endPeriod = p.1
                } else if let p = periods(for: block, rowCenters: rowCenters, nextTop: nextTop) {
                    draft.startPeriod = p.0; draft.endPeriod = p.1
                }
                if let t = fields.times { draft.startMinutes = t.0; draft.endMinutes = t.1 }
                draft.complete(with: slots)
                if draft.isValid { drafts.append(draft) }
            }
        }
        return drafts.sorted { ($0.weekday, $0.startPeriod) < ($1.weekday, $1.startPeriod) }
    }

    /// 同一列中垂直距离很近的几行文字视为同一个格子。
    private static func blocks(from items: [TextItem]) -> [[TextItem]] {
        let sorted = items.sorted { $0.rect.minY < $1.rect.minY }
        let lineHeight = sorted.map(\.rect.height).sorted().dropFirst(sorted.count / 2).first ?? 0.02
        var result: [[TextItem]] = []
        for item in sorted {
            if let last = result.last?.last, item.rect.minY - last.rect.maxY < lineHeight * 0.9 {
                result[result.count - 1].append(item)
            } else {
                result.append([item])
            }
        }
        return result
    }

    /// 文字只覆盖到一行时，若下一行在同列中是空的，按大学常见的“两节连上”（1-2、3-4…）推断。
    private static func periods(for block: [TextItem], rowCenters: [Int: CGFloat], nextTop: CGFloat?) -> (Int, Int)? {
        guard let covered = coveredPeriods(for: block, rowCenters: rowCenters) else { return nil }
        let (first, last) = covered
        if first == last, first % 2 == 1, let nextCenter = rowCenters[first + 1] {
            let rowHeight = nextCenter - (rowCenters[first] ?? nextCenter)
            if nextTop.map({ $0 > nextCenter - rowHeight * 0.4 }) ?? true {
                return (first, first + 1)
            }
        }
        return (first, last)
    }

    private static func coveredPeriods(for block: [TextItem], rowCenters: [Int: CGFloat]) -> (Int, Int)? {
        guard !rowCenters.isEmpty else { return nil }
        let top = block.map(\.rect.minY).min() ?? 0
        let bottom = block.map(\.rect.maxY).max() ?? 0
        let tolerance: CGFloat = 0.01
        let covered = rowCenters.filter { $0.value >= top - tolerance && $0.value <= bottom + tolerance }.keys.sorted()
        if let first = covered.first, let last = covered.last { return (first, last) }
        let mid = (top + bottom) / 2
        let nearest = rowCenters.min { abs($0.value - mid) < abs($1.value - mid) }!.key
        return (nearest, nearest)
    }
}

/// 适用于列表形式的课表文字，例如“周一 第1-2节 高等数学 教三-305 1-16周”或 CSV。
enum LineHeuristicParser {
    static func parse(_ text: String, slots: [PeriodSlot]) -> [CourseDraft] {
        var drafts: [CourseDraft] = []
        var currentWeekday: Int?
        for rawLine in text.components(separatedBy: .newlines) {
            // CSV 的逗号换成空格，但保留周次里的逗号（如 1-8,10-16）。
            let line = rawLine.replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "(?<!\\d)[,，]|[,，](?!\\d)", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let weekday = WeekdayName.detect(in: line)
            var cleaned = line
            for prefix in ["星期", "礼拜", "周"] {
                for n in ["一", "二", "三", "四", "五", "六", "日", "天"] {
                    cleaned = cleaned.replacingOccurrences(of: prefix + n, with: " ")
                }
            }
            cleaned = cleaned.replacingOccurrences(of: "(?i)\\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\\.?", with: " ",
                                                   options: .regularExpression)
            let fields = CellFields(lines: [cleaned])
            if weekday != nil && fields.name.count < 2 {
                currentWeekday = weekday
                continue
            }
            guard let day = weekday ?? currentWeekday, fields.name.count >= 2,
                  fields.periods != nil || fields.times != nil else { continue }
            var draft = CourseDraft(name: fields.name, classroom: fields.classroom, teacher: fields.teacher,
                                    weekday: day, weeks: fields.weeks)
            if let p = fields.periods { draft.startPeriod = p.0; draft.endPeriod = p.1 }
            if let t = fields.times { draft.startMinutes = t.0; draft.endMinutes = t.1 }
            draft.complete(with: slots)
            if draft.isValid { drafts.append(draft) }
        }
        return drafts
    }
}

/// 解析教务系统导出的 .ics 日历文件。
enum ICSParser {
    static func parse(_ text: String) -> [CourseDraft] {
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "")
        let semesterStart = SharedSettings.semesterStart
        let slots = SharedSettings.periodSlots
        var merged: [String: CourseDraft] = [:]
        var order: [String] = []

        for block in unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            var fields: [String: String] = [:]
            for line in block.components(separatedBy: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].split(separator: ";").first.map(String.init) ?? ""
                fields[key] = String(line[line.index(after: colon)...])
            }
            guard let summary = fields["SUMMARY"], let start = date(fields["DTSTART"]), let end = date(fields["DTEND"]) else { continue }
            let cal = SemesterCalendar.calendar
            let startMinutes = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
            let endMinutes = cal.component(.hour, from: end) * 60 + cal.component(.minute, from: end)
            let weekday = SemesterCalendar.weekday(of: start)
            let firstWeek = SemesterCalendar.weekNumber(of: start, semesterStart: semesterStart)
            var weeks = [firstWeek]
            if let rrule = fields["RRULE"], rrule.contains("FREQ=WEEKLY") {
                let interval = value(of: "INTERVAL", in: rrule).flatMap { Int($0) } ?? 1
                var count = value(of: "COUNT", in: rrule).flatMap { Int($0) } ?? 1
                if let until = date(value(of: "UNTIL", in: rrule)) {
                    count = (cal.dateComponents([.day], from: start, to: until).day ?? 0) / (7 * interval) + 1
                }
                weeks = (0..<max(1, min(count, 30))).map { firstWeek + $0 * interval }
            }
            let unescape: (String) -> String = { $0.replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\n", with: " ") }
            let key = "\(summary)|\(weekday)|\(startMinutes)"
            if var existing = merged[key] {
                existing.weeks = Array(Set(existing.weeks + weeks)).sorted()
                merged[key] = existing
            } else {
                var draft = CourseDraft(name: unescape(summary), classroom: unescape(fields["LOCATION"] ?? ""),
                                        weekday: weekday, startMinutes: startMinutes, endMinutes: endMinutes,
                                        weeks: weeks.filter { $0 >= 1 })
                draft.complete(with: slots)
                merged[key] = draft
                order.append(key)
            }
        }
        return order.compactMap { merged[$0] }.filter(\.isValid)
    }

    private static func value(of key: String, in rrule: String) -> String? {
        rrule.split(separator: ";").first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let isUTC = string.hasSuffix("Z")
        formatter.timeZone = isUTC ? TimeZone(identifier: "UTC") : .current
        for format in ["yyyyMMdd'T'HHmmss'Z'", "yyyyMMdd'T'HHmmss", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let d = formatter.date(from: string) { return d }
        }
        return nil
    }
}
