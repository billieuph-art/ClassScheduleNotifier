import Foundation

private enum Patterns {
    static let periodRange = try! NSRegularExpression(
        pattern: "(?:第\\s*)?(\\d{1,2})\\s*(?:[-－—~～至到,，]\\s*(\\d{1,2}))?\\s*节"
    )
    static let periodPairOnly = try! NSRegularExpression(pattern: "^\\s*(\\d{1,2})\\s*[-－—~～]\\s*(\\d{1,2})\\s*$")
    static let timeRange = try! NSRegularExpression(
        pattern: "(\\d{1,2}[:：]\\d{2})\\s*[-－—~～至到]\\s*(\\d{1,2}[:：]\\d{2})"
    )
    /// 兼容「1-16周」「(1-16)」「1～16周」「第1-16周」「1-8,10-16周」「单周」「双周」。
    static let weeks = try! NSRegularExpression(
        pattern: "(?:第)?\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?(?:\\s*[,，、]\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?)*\\s*周|(?:[\\[(（]\\s*)?(?:第)?\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?(?:\\s*[,，、]\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?)*\\s*[\\])）]|(?:单|双)\\s*周"
    )
    static let room = try! NSRegularExpression(
        pattern: "(?:[东南西北]?[\\p{Han}A-Za-z0-9]{0,8}?(?:楼|馆|教|室|区|院|中心|实验|机房|报告厅|阶梯)[\\p{Han}A-Za-z0-9\\-－—]*\\d+[A-Za-z0-9\\-－—]*)|(?:\\b[A-Za-z]{1,3}\\d?[-－—]?\\d{2,4}[A-Za-z]?\\b)|(?:\\b\\d{1,2}[-－—]\\d{3,4}\\b)|(?:教室[:：]?\\s*[\\p{Han}A-Za-z0-9\\-－—]+)"
    )
    static let rowLabel = try! NSRegularExpression(
        pattern: "^\\s*(?:第\\s*)?(\\d{1,2})\\s*(?:[-－—~～]\\s*(\\d{1,2}))?\\s*节?\\s*$"
    )
    static let teacher = try! NSRegularExpression(
        pattern: "(?:教师|老师|授课)[:：]?\\s*([\\p{Han}]{2,8})|(?:[\\[【（(])\\s*([\\p{Han}]{2,4})(?:老师|教授)?\\s*[\\]】）)]"
    )
    /// 中文姓名多为 2–3 字；4 字更像「高等数学」这类课名，不能当教师。
    static let teacherLoose = try! NSRegularExpression(pattern: "^[\\p{Han}]{2,3}(?:老师|教授)?$")
    static let junkName = try! NSRegularExpression(
        pattern: "^(?:星期?[一二三四五六日天]|周[一二三四五六日天]|第?\\d+节|上午|下午|晚上|备注|课程|教室|教师|时间|节次|地点)$"
    )

    static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func string(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
            var line = raw.replacingOccurrences(of: "　", with: " ")
            if let m = Patterns.firstMatch(Patterns.timeRange, in: line),
               let s = Patterns.string(m, group: 1, in: line).flatMap({ TimeFormat.minutes(from: $0) }),
               let e = Patterns.string(m, group: 2, in: line).flatMap({ TimeFormat.minutes(from: $0) }) {
                times = (s, e)
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            if let m = Patterns.firstMatch(Patterns.weeks, in: line) {
                let snippet = Patterns.string(m, group: 0, in: line) ?? ""
                let parsed = WeeksParser.parse(snippet)
                if !parsed.isEmpty { weeks = parsed }
                else if snippet.contains("单") { weeks = stride(from: 1, through: 20, by: 2).map { $0 } }
                else if snippet.contains("双") { weeks = stride(from: 2, through: 20, by: 2).map { $0 } }
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            if let m = Patterns.firstMatch(Patterns.periodRange, in: line),
               let s = Patterns.string(m, group: 1, in: line).flatMap({ Int($0) }) {
                let e = Patterns.string(m, group: 2, in: line).flatMap { Int($0) } ?? s
                periods = (s, max(s, e))
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            if classroom.isEmpty, let m = Patterns.firstMatch(Patterns.room, in: line) {
                classroom = (Patterns.string(m, group: 0, in: line) ?? "")
                    .replacingOccurrences(of: "教室[:：]?", with: "", options: .regularExpression)
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            if teacher.isEmpty, let m = Patterns.firstMatch(Patterns.teacher, in: line) {
                teacher = Patterns.string(m, group: 1, in: line) ?? Patterns.string(m, group: 2, in: line) ?? ""
                line = (line as NSString).replacingCharacters(in: m.range, with: " ")
            }
            let tokens = line.split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "/" || $0 == "·" })
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            rest += tokens
        }

        rest.removeAll { Patterns.firstMatch(Patterns.junkName, in: $0) != nil || Int($0) != nil }
        // 先定课程名（通常是最长词），再从剩余短词里认教师，避免把「高等数学」误判成人名。
        if let best = rest.enumerated().max(by: { a, b in
            if a.element.count != b.element.count { return a.element.count < b.element.count }
            return a.offset > b.offset // 同长度时优先更靠前的词（课程名通常在前）
        }) {
            name = rest.remove(at: best.offset)
        }
        if teacher.isEmpty {
            for (index, candidate) in rest.enumerated() where Patterns.firstMatch(Patterns.teacherLoose, in: candidate) != nil {
                teacher = candidate.replacingOccurrences(of: "老师|教授", with: "", options: .regularExpression)
                rest.remove(at: index)
                break
            }
        }
        // 若教室仍空，再扫剩余 token。
        if classroom.isEmpty {
            for (index, candidate) in rest.enumerated() where Patterns.firstMatch(Patterns.room, in: candidate) != nil {
                classroom = candidate
                rest.remove(at: index)
                break
            }
        }
        name = name.replacingOccurrences(of: #"^[\[【\(（]+|[\]】\)）]+$"#, with: "", options: .regularExpression)
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
        guard !items.isEmpty else { return [] }
        let headerItems = items.sorted { $0.rect.minY < $1.rect.minY }.prefix(max(12, items.count / 5))
        var columns: [Int: CGFloat] = [:]
        var headerBottom: CGFloat = 0

        for item in headerItems {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 6, let weekday = WeekdayName.detect(in: text, allowBare: true) else { continue }
            // 表头通常在上半部分。
            guard item.rect.midY < 0.35 else { continue }
            if columns[weekday] == nil || abs(columns[weekday]! - item.rect.midX) > 0.04 {
                columns[weekday] = item.rect.midX
            }
            headerBottom = max(headerBottom, item.rect.maxY)
        }
        // 至少识别出 3 列；不够时按常见五列均分猜测。
        if columns.count < 3 {
            columns = guessedWeekdayColumns(from: items)
            headerBottom = items.map(\.rect.minY).sorted().prefix(8).last ?? 0.08
        }
        guard columns.count >= 3 else { return [] }

        let centers = columns.values.sorted()
        let spacing = zip(centers, centers.dropFirst()).map { $1 - $0 }.min() ?? 0.12
        let leftBoundary = centers[0] - spacing * 0.55

        var rowCenters: [Int: CGFloat] = [:]
        for item in items where item.rect.midX < leftBoundary && item.rect.minY > headerBottom - 0.02 {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let m = Patterns.firstMatch(Patterns.rowLabel, in: text),
               let period = Patterns.string(m, group: 1, in: text).flatMap({ Int($0) }),
               (1...16).contains(period), rowCenters[period] == nil {
                rowCenters[period] = item.rect.midY
                if let end = Patterns.string(m, group: 2, in: text).flatMap({ Int($0) }), end > period {
                    // 「1-2」这种合并行标签，用中间位置代表两节。
                    for p in period...end where rowCenters[p] == nil {
                        let t = CGFloat(p - period + 1) / CGFloat(end - period + 2)
                        rowCenters[p] = item.rect.midY + (item.rect.height * t)
                    }
                }
            }
        }
        // 左侧没有节次时，按时间列或均分行高推断。
        if rowCenters.count < 2 {
            rowCenters = guessedPeriodRows(from: items, leftBoundary: leftBoundary, headerBottom: headerBottom, slots: slots)
        }

        let cells = items.filter { $0.rect.minY >= headerBottom - 0.004 && $0.rect.midX >= leftBoundary }
        var byWeekday: [Int: [TextItem]] = [:]
        for item in cells {
            let weekday = columns.min { abs($0.value - item.rect.midX) < abs($1.value - item.rect.midX) }!.key
            // 离列中心太远的忽略，避免跨列串课。
            guard abs(columns[weekday]! - item.rect.midX) < spacing * 0.55 else { continue }
            byWeekday[weekday, default: []].append(item)
        }

        var drafts: [CourseDraft] = []
        for (weekday, columnItems) in byWeekday {
            let columnBlocks = blocks(from: columnItems)
            for (blockIndex, block) in columnBlocks.enumerated() {
                let nextTop = blockIndex + 1 < columnBlocks.count ? columnBlocks[blockIndex + 1].map(\.rect.minY).min() : nil
                let fields = CellFields(lines: block.map(\.text))
                guard fields.name.count >= 2, Patterns.firstMatch(Patterns.junkName, in: fields.name) == nil else { continue }
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
        let heights = sorted.map(\.rect.height).sorted()
        let lineHeight = heights.dropFirst(heights.count / 3).first ?? 0.02
        var result: [[TextItem]] = []
        for item in sorted {
            if let last = result.last?.last, item.rect.minY - last.rect.maxY < max(lineHeight * 1.15, 0.012) {
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
            if nextTop.map({ $0 > nextCenter - rowHeight * 0.35 }) ?? true {
                return (first, first + 1)
            }
        }
        return (first, last)
    }

    private static func coveredPeriods(for block: [TextItem], rowCenters: [Int: CGFloat]) -> (Int, Int)? {
        guard !rowCenters.isEmpty else { return nil }
        let top = block.map(\.rect.minY).min() ?? 0
        let bottom = block.map(\.rect.maxY).max() ?? 0
        let tolerance: CGFloat = 0.012
        let covered = rowCenters.filter { $0.value >= top - tolerance && $0.value <= bottom + tolerance }.keys.sorted()
        if let first = covered.first, let last = covered.last { return (first, last) }
        let mid = (top + bottom) / 2
        let nearest = rowCenters.min { abs($0.value - mid) < abs($1.value - mid) }!.key
        return (nearest, nearest)
    }

    private static func guessedWeekdayColumns(from items: [TextItem]) -> [Int: CGFloat] {
        let topBand = items.filter { $0.rect.midY < 0.28 }
        let xs = topBand.map(\.rect.midX).sorted()
        guard xs.count >= 3 else { return [:] }
        // 聚类相近的 x，取前 5 个作为周一到周五。
        var clusters: [CGFloat] = []
        for x in xs {
            if let last = clusters.last, abs(last - x) < 0.05 { continue }
            clusters.append(x)
        }
        let usable = Array(clusters.prefix(7))
        guard usable.count >= 3 else { return [:] }
        var result: [Int: CGFloat] = [:]
        for (index, x) in usable.enumerated() where index < 7 {
            result[index + 1] = x
        }
        return result
    }

    private static func guessedPeriodRows(from items: [TextItem], leftBoundary: CGFloat,
                                          headerBottom: CGFloat, slots: [PeriodSlot]) -> [Int: CGFloat] {
        let left = items.filter { $0.rect.midX < leftBoundary && $0.rect.minY > headerBottom }
        let times = left.compactMap { item -> (Int, CGFloat)? in
            guard let minutes = TimeFormat.minutes(from: item.text) else { return nil }
            return (minutes, item.rect.midY)
        }
        var result: [Int: CGFloat] = [:]
        if !times.isEmpty {
            for (minutes, y) in times {
                if let slot = slots.min(by: { abs($0.startMinutes - minutes) < abs($1.startMinutes - minutes) }) {
                    result[slot.index] = y
                }
            }
        }
        if result.count >= 2 { return result }
        // 最后手段：按作息节次数均分表格主体。
        let bodyItems = items.filter { $0.rect.minY > headerBottom }
        guard let top = bodyItems.map(\.rect.minY).min(), let bottom = bodyItems.map(\.rect.maxY).max(), bottom > top else {
            return result
        }
        let count = max(slots.count, 8)
        for index in 1...count {
            let t = CGFloat(index) / CGFloat(count + 1)
            result[index] = top + (bottom - top) * t
        }
        return result
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
            let weekday = WeekdayName.detect(in: line, allowBare: false)
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
