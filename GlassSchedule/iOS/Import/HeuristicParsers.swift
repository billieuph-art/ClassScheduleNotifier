import Foundation

/// 把 OCR 拆碎的格子文字粘回一句，例如：
/// `水利工` + `程造价` + `二@231` + `3` → `水利工程造价二@2313`
enum OCRTextJoiner {
    static func join(_ lines: [String]) -> String {
        var parts = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return "" }

        // 先把「@231」+「3」这种教室号断行拼上。
        var i = 0
        while i < parts.count - 1 {
            let a = parts[i], b = parts[i + 1]
            if shouldGlue(a, b) {
                parts[i] = a + b
                parts.remove(at: i + 1)
            } else {
                i += 1
            }
        }
        // 课表格子几乎都是窄列竖排中文，默认无空格拼接。
        return parts.joined()
    }

    private static func shouldGlue(_ a: String, _ b: String) -> Bool {
        if b.isEmpty { return false }
        if a.hasSuffix("@") { return true }
        if a.contains("@"), let last = a.last, last.isNumber, b.allSatisfy(\.isNumber) { return true }
        if let last = a.last, last.isNumber, b.allSatisfy(\.isNumber), b.count <= 3 { return true }
        // 中文被拆成「水利工」「程造价」
        if isIdeograph(a.last) && isIdeograph(b.first) { return true }
        if isIdeograph(a.last), let f = b.first, f.isLetter || f.isNumber || f == "@" { return true }
        return false
    }

    private static func isIdeograph(_ ch: Character?) -> Bool {
        guard let ch, let v = ch.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v)
    }
}

private enum Patterns {
    /// 超星 / 教务常见：课程名@教室号
    static let atRoom = try! NSRegularExpression(pattern: "^(.+?)@([A-Za-z0-9\\-－]{2,12})$")
    static let periodRange = try! NSRegularExpression(
        pattern: "(?:第\\s*)?(\\d{1,2})\\s*(?:[-－—~～至到,，]\\s*(\\d{1,2}))?\\s*节"
    )
    static let timeRange = try! NSRegularExpression(
        pattern: "(\\d{1,2}[:：]\\d{2})\\s*[-－—~～至到]\\s*(\\d{1,2}[:：]\\d{2})"
    )
    /// 周次：包含「1-16周 (单周)」「1-16周（双周）」整段，避免只吃掉「1-16周」丢掉单双周标记
    static let weeks = try! NSRegularExpression(
        pattern: "(?:第)?\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?(?:\\s*[,，、]\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?)*\\s*周\\s*(?:[\\(（]\\s*(?:单|双)\\s*周?\\s*[\\)）])?|(?:[\\[(（]\\s*)?(?:第)?\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?(?:\\s*[,，、]\\s*\\d{1,2}(?:\\s*[-－—~～至到]\\s*\\d{1,2})?)*\\s*[\\])）]\\s*(?:[\\(（]\\s*(?:单|双)\\s*周?\\s*[\\)）])?|(?:单|双)\\s*周"
    )
    /// 教室：教一楼 302 / 理教楼 A-201 / 教 A-101 / 机房 C-301 / 体育馆二楼
    static let room = try! NSRegularExpression(
        pattern: "(?:[东南西北]?[\\p{Han}]{0,8}?(?:楼|馆|教|室|区|院|中心|实验|机房|报告厅|阶梯)[\\p{Han}A-Za-z0-9\\-－—]*\\s*[A-Za-z]?\\-?\\d{2,5}[A-Za-z0-9\\-－—]*)|(?:体育馆(?:[一二三四东南北]楼)?)|(?:操场|田径场|游泳馆)|(?:\\b[A-Za-z]\\-?\\d{2,4}[A-Za-z]?\\b)|(?:\\b\\d{1,2}[-－—]\\d{3,4}\\b)|(?:教室[:：]?\\s*[\\p{Han}A-Za-z0-9\\-－—\\s]+\\d{2,5})"
    )
    static let buildingOnly = try! NSRegularExpression(
        pattern: "^[东南西北]?[\\p{Han}A-Za-z0-9]{0,10}?(?:楼|馆|教|室|区|院|中心)[\\p{Han}A-Za-z0-9\\-－—]*$"
    )
    static let buildingToken = try! NSRegularExpression(
        pattern: "[东南西北]?[\\p{Han}A-Za-z0-9]{0,10}?(?:楼|馆|教|室|区|院|中心)[\\p{Han}A-Za-z0-9\\-－—]*"
    )
    static let roomNumber = try! NSRegularExpression(pattern: "^\\d{2,5}[A-Za-z]?$")
    static let roomNumberToken = try! NSRegularExpression(pattern: "\\d{2,5}[A-Za-z]?")
    static let rowLabel = try! NSRegularExpression(
        pattern: "^\\s*(?:第\\s*)?(\\d{1,2})\\s*(?:[-－—~～]\\s*(\\d{1,2}))?\\s*节?\\s*$"
    )
    static let teacher = try! NSRegularExpression(
        pattern: "(?:教师|老师|授课)[:：]?\\s*([\\p{Han}]{2,8})|(?:[\\[【（(])\\s*([\\p{Han}]{2,4})(?:老师|教授)?\\s*[\\]】）)]"
    )
    static let teacherLoose = try! NSRegularExpression(pattern: "^(?:[\\p{Han}]{2,4}|辅导员)(?:老师|教授)?$")
    static let junkName = try! NSRegularExpression(
        pattern: "^(?:星期?[一二三四五六日天]|周[一二三四五六日天]|今天|明天|第?\\d+(?:[-－—]\\d+)?节|上午|下午|晚上|备注|课程|教室|教师|时间|节次|地点|节数|时间段|课程名|周次|—|-|－|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)$",
        options: [.caseInsensitive]
    )
    static let dateHeader = try! NSRegularExpression(pattern: "(\\d{1,2})[/.-](\\d{1,2})")

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

    init() {}

    init(lines: [String]) {
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "—" && $0 != "-" && $0 != "－" }
        guard !cleanedLines.isEmpty else { return }

        // 教务网格常见 4 行：课名 / 教师 / 教一楼 302 / 1-16周 (单周)
        if parseStructuredLines(cleanedLines) { return }

        // 回退：拼回整句再解析（超星窄列竖排）
        parseJoined(OCRTextJoiner.join(cleanedLines))
    }

    /// 按行分类解析；成功取出课名则返回 true。
    @discardableResult
    private mutating func parseStructuredLines(_ lines: [String]) -> Bool {
        let remain = lines
        var weekLines: [String] = []
        var roomLines: [String] = []
        var teacherLines: [String] = []
        var nameLines: [String] = []

        // 先抽出周次行 / 教室行 / 教师行，剩下的拼成课名
        for line in remain {
            if isWeekLine(line) {
                weekLines.append(line)
            } else if isRoomLine(line) {
                roomLines.append(line)
            } else if isTeacherLine(line) {
                teacherLines.append(line)
            } else {
                nameLines.append(line)
            }
        }

        // 「教一楼」+「302」被拆成两行时合并
        if roomLines.isEmpty {
            for i in 0..<(remain.count - 1) {
                if Patterns.firstMatch(Patterns.buildingOnly, in: remain[i]) != nil,
                   Patterns.firstMatch(Patterns.roomNumber, in: remain[i + 1]) != nil {
                    roomLines = ["\(remain[i]) \(remain[i + 1])"]
                    nameLines.removeAll { $0 == remain[i] || $0 == remain[i + 1] }
                    teacherLines.removeAll { $0 == remain[i] || $0 == remain[i + 1] }
                    break
                }
            }
        }

        if let weekText = weekLines.first {
            applyWeeks(from: weekText)
        }
        if let roomText = roomLines.first {
            classroom = normalizeRoom(roomText)
        }
        if let teacherText = teacherLines.first {
            teacher = teacherText.replacingOccurrences(of: "老师|教授", with: "", options: .regularExpression)
        }

        // 课名：优先非教师/非教室行；若分类过狠导致为空，用最长一行
        name = nameLines
            .filter { Patterns.firstMatch(Patterns.junkName, in: $0) == nil }
            .joined()
        if name.count < 2 {
            name = lines.max(by: { $0.count < $1.count }) ?? ""
        }
        name = name.replacingOccurrences(of: #"^[\[【\(（]+|[\]】\)）]+$"#, with: "", options: .regularExpression)

        // 仍缺字段时，对剩余拼接文本补抽
        if classroom.isEmpty || teacher.isEmpty || weeks.isEmpty || name.count < 2 {
            var leftover = lines.filter { line in
                line != classroom && line != teacher && !weekLines.contains(line) && !roomLines.contains(line)
            }
            if name.count >= 2 { leftover.removeAll { $0 == name || name.contains($0) } }
            let joined = OCRTextJoiner.join(leftover.isEmpty ? lines : leftover)
            if classroom.isEmpty || teacher.isEmpty || weeks.isEmpty {
                var tmp = CellFields()
                tmp.parseJoined(joined)
                if classroom.isEmpty { classroom = tmp.classroom }
                if teacher.isEmpty { teacher = tmp.teacher }
                if weeks.isEmpty { weeks = tmp.weeks }
                if periods == nil { periods = tmp.periods }
                if times == nil { times = tmp.times }
                if name.count < 2 { name = tmp.name }
            }
        }

        return name.count >= 2
    }

    private mutating func parseJoined(_ raw: String) {
        var text = raw
        if text.isEmpty { return }

        if let m = Patterns.firstMatch(Patterns.timeRange, in: text),
           let s = Patterns.string(m, group: 1, in: text).flatMap({ TimeFormat.minutes(from: $0) }),
           let e = Patterns.string(m, group: 2, in: text).flatMap({ TimeFormat.minutes(from: $0) }) {
            times = (s, e)
            text = (text as NSString).replacingCharacters(in: m.range, with: " ")
        }

        // 可能先后出现「1-16周」与「单周」；合并后再解析
        var weekSnippets: [String] = []
        while let m = Patterns.firstMatch(Patterns.weeks, in: text) {
            let snippet = Patterns.string(m, group: 0, in: text) ?? ""
            weekSnippets.append(snippet)
            text = (text as NSString).replacingCharacters(in: m.range, with: " ")
        }
        if !weekSnippets.isEmpty {
            applyWeeks(from: weekSnippets.joined(separator: " "))
        }

        if let m = Patterns.firstMatch(Patterns.periodRange, in: text),
           let s = Patterns.string(m, group: 1, in: text).flatMap({ Int($0) }) {
            let e = Patterns.string(m, group: 2, in: text).flatMap { Int($0) } ?? s
            periods = (s, max(s, e))
            text = (text as NSString).replacingCharacters(in: m.range, with: " ")
        }
        if let m = Patterns.firstMatch(Patterns.teacher, in: text) {
            teacher = Patterns.string(m, group: 1, in: text) ?? Patterns.string(m, group: 2, in: text) ?? ""
            text = (text as NSString).replacingCharacters(in: m.range, with: " ")
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let m = Patterns.firstMatch(Patterns.atRoom, in: text),
           let course = Patterns.string(m, group: 1, in: text),
           let room = Patterns.string(m, group: 2, in: text) {
            name = course
            classroom = room
        } else {
            if let m = Patterns.firstMatch(Patterns.room, in: text) {
                classroom = normalizeRoom(Patterns.string(m, group: 0, in: text) ?? "")
                text = (text as NSString).replacingCharacters(in: m.range, with: " ")
            }
            // 「教一楼302」粘连时上面已覆盖；「教一楼」与数字被空格拆开再拼
            if classroom.isEmpty, let m = Patterns.firstMatch(Patterns.buildingToken, in: text) {
                let building = Patterns.string(m, group: 0, in: text) ?? ""
                let rest = (text as NSString).replacingCharacters(in: m.range, with: " ")
                if let numMatch = Patterns.firstMatch(Patterns.roomNumberToken, in: rest),
                   let num = Patterns.string(numMatch, group: 0, in: rest) {
                    classroom = "\(building) \(num)"
                    text = (rest as NSString).replacingCharacters(in: numMatch.range, with: " ")
                }
            }

            var tokens = text.split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "/" || $0 == "·" })
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
                .filter { !$0.isEmpty }
            tokens.removeAll { Patterns.firstMatch(Patterns.junkName, in: $0) != nil || Int($0) != nil }

            if teacher.isEmpty {
                // 从后往前找教师名，避免把课名开头两字当成老师
                for index in tokens.indices.reversed() where Patterns.firstMatch(Patterns.teacherLoose, in: tokens[index]) != nil {
                    let candidate = tokens[index]
                    if candidate.count <= 4 {
                        teacher = candidate.replacingOccurrences(of: "老师|教授", with: "", options: .regularExpression)
                        tokens.remove(at: index)
                        break
                    }
                }
            }
            // 粘连串：…李明教一楼… 里抽出 2–3 字人名
            if teacher.isEmpty {
                let compact = tokens.joined()
                if let extracted = extractTrailingTeacher(from: compact) {
                    teacher = extracted.teacher
                    tokens = [extracted.remainder].filter { !$0.isEmpty }
                }
            }
            name = tokens.joined()
        }

        name = name.replacingOccurrences(of: #"^[\[【\(（]+|[\]】\)）]+$"#, with: "", options: .regularExpression)
        if name.contains("@") || name.hasPrefix("二@") || (name.first?.isNumber == true && name.contains("@")) {
            if classroom.isEmpty, let m = Patterns.firstMatch(Patterns.atRoom, in: name),
               let course = Patterns.string(m, group: 1, in: name),
               let room = Patterns.string(m, group: 2, in: name) {
                name = course
                classroom = room
            }
        }
        // 课名里误吞的教师名
        if teacher.isEmpty, let extracted = extractTrailingTeacher(from: name), extracted.remainder.count >= 2 {
            name = extracted.remainder
            teacher = extracted.teacher
        }
    }

    private mutating func applyWeeks(from snippet: String) {
        let isBareTeachingWeek = snippet.range(of: #"^第?\s*\d{1,2}\s*周$"#, options: .regularExpression) != nil
            && !snippet.contains("单") && !snippet.contains("双")
        guard !isBareTeachingWeek else { return }
        let parsed = WeeksParser.parse(snippet)
        if !parsed.isEmpty {
            weeks = parsed
        } else if snippet.contains("单") {
            weeks = Array(stride(from: 1, through: 20, by: 2))
        } else if snippet.contains("双") {
            weeks = Array(stride(from: 2, through: 20, by: 2))
        }
    }

    private func isWeekLine(_ line: String) -> Bool {
        line.contains("周") && (
            line.contains("单") || line.contains("双")
            || Patterns.firstMatch(Patterns.weeks, in: line) != nil
            || line.range(of: #"\d"#, options: .regularExpression) != nil
        )
    }

    private func isRoomLine(_ line: String) -> Bool {
        if Patterns.firstMatch(Patterns.room, in: line) != nil { return true }
        if line == "体育馆" || line == "操场" { return true }
        // 「教一楼 302」
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 2,
           Patterns.firstMatch(Patterns.buildingOnly, in: parts[0]) != nil,
           Patterns.firstMatch(Patterns.roomNumber, in: parts[1]) != nil {
            return true
        }
        return false
    }

    private func isTeacherLine(_ line: String) -> Bool {
        Patterns.firstMatch(Patterns.teacherLoose, in: line) != nil
            || Patterns.firstMatch(Patterns.teacher, in: line) != nil
    }

    private func normalizeRoom(_ raw: String) -> String {
        raw.replacingOccurrences(of: "教室[:：]?", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从「高等数学(上)李明」这类粘连串末尾抽出教师名。
    private func extractTrailingTeacher(from text: String) -> (remainder: String, teacher: String)? {
        let chars = Array(text)
        guard chars.count >= 4 else { return nil }
        for len in [3, 2] {
            guard chars.count > len else { continue }
            let suffix = String(chars.suffix(len))
            let prefix = String(chars.dropLast(len))
            guard Patterns.firstMatch(Patterns.teacherLoose, in: suffix) != nil else { continue }
            guard prefix.count >= 2 else { continue }
            // 前缀应像课名（含汉字且不只是姓）
            let han = prefix.filter { $0.unicodeScalars.first.map { (0x4E00...0x9FFF).contains($0.value) } == true }
            if han.count >= 2 { return (prefix, suffix) }
        }
        return nil
    }
}

/// 适用于“表头是星期、左侧是节次”的网格课程表截图（含超星「今天/周二 + 课程@教室」）。
enum GridHeuristicParser {
    static func parse(_ allItems: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        var drafts: [CourseDraft] = []
        for page in Set(allItems.map(\.page)).sorted() {
            drafts += parsePage(allItems.filter { $0.page == page }, slots: slots)
        }
        return mergeAdjacent(drafts, slots: slots)
    }

    private static func parsePage(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        guard !items.isEmpty else { return [] }

        let columns = detectWeekdayColumns(in: items)
        guard columns.count >= 2 else { return [] }
        let headerBottom = columns.values.map(\.bottom).max() ?? 0.08

        let centers = columns.values.map(\.x).sorted()
        let spacing = zip(centers, centers.dropFirst()).map { $1 - $0 }.min() ?? 0.12
        let leftBoundary = centers[0] - spacing * 0.55

        var rowCenters = detectPeriodRows(in: items, leftBoundary: leftBoundary, headerBottom: headerBottom)
        if rowCenters.count < 2 {
            rowCenters = guessedPeriodRows(from: items, leftBoundary: leftBoundary, headerBottom: headerBottom, slots: slots)
        }

        let cells = items.filter { $0.rect.minY >= headerBottom - 0.004 && $0.rect.midX >= leftBoundary }
        var byWeekday: [Int: [TextItem]] = [:]
        for item in cells {
            let weekday = columns.min { abs($0.value.x - item.rect.midX) < abs($1.value.x - item.rect.midX) }!.key
            guard abs(columns[weekday]!.x - item.rect.midX) < spacing * 0.55 else { continue }
            byWeekday[weekday, default: []].append(item)
        }

        var drafts: [CourseDraft] = []
        for (weekday, columnItems) in byWeekday {
            let columnBlocks = blocks(from: columnItems)
            for (blockIndex, block) in columnBlocks.enumerated() {
                let nextTop = blockIndex + 1 < columnBlocks.count ? columnBlocks[blockIndex + 1].map(\.rect.minY).min() : nil
                let fields = CellFields(lines: block.map(\.text))
                guard fields.name.count >= 2, Patterns.firstMatch(Patterns.junkName, in: fields.name) == nil else { continue }
                guard !ScheduleJunk.isDayOrHeader(fields.name) else { continue }
                // 拒绝把教室号当课名
                guard !fields.name.contains("@"), !(fields.name.count <= 6 && fields.name.hasPrefix("二")) else { continue }
                // 课名里不应主要是楼名（如「理教楼」）
                if fields.name.hasSuffix("楼") || fields.name.hasSuffix("馆"), fields.name.count <= 5 { continue }

                var draft = CourseDraft(name: fields.name, classroom: fields.classroom, teacher: fields.teacher,
                                        weekday: weekday, weeks: fields.weeks)
                if let p = fields.periods {
                    draft.startPeriod = p.0; draft.endPeriod = p.1
                } else if let p = periods(for: block, rowCenters: rowCenters, nextTop: nextTop) {
                    draft.startPeriod = p.0; draft.endPeriod = p.1
                }
                if let t = fields.times { draft.startMinutes = t.0; draft.endMinutes = t.1 }
                draft.complete(with: slots, preferPeriods: true)
                if draft.isValid { drafts.append(draft) }
            }
        }
        return drafts.sorted { ($0.weekday, $0.startPeriod) < ($1.weekday, $1.startPeriod) }
    }

    private struct Column {
        var x: CGFloat
        var bottom: CGFloat
    }

    private static func detectWeekdayColumns(in items: [TextItem]) -> [Int: Column] {
        var columns: [Int: Column] = [:]
        let headerItems = items.sorted { $0.rect.minY < $1.rect.minY }.prefix(max(20, items.count / 4))
        for item in headerItems {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard item.rect.midY < 0.28 else { continue }
            // 「今天 11/23」「周二 11/24」——日期推星期优先，避免「今天」按导入当天错位
            var weekday: Int?
            if let m = Patterns.firstMatch(Patterns.dateHeader, in: text),
               let month = Patterns.string(m, group: 1, in: text).flatMap(Int.init),
               let day = Patterns.string(m, group: 2, in: text).flatMap(Int.init) {
                weekday = weekdayFrom(month: month, day: day)
            }
            if weekday == nil {
                weekday = WeekdayName.detect(in: text, allowBare: true)
            }
            guard let weekday else { continue }
            let existing = columns[weekday]
            if existing == nil || abs(existing!.x - item.rect.midX) > 0.04 {
                columns[weekday] = Column(x: item.rect.midX, bottom: max(existing?.bottom ?? 0, item.rect.maxY))
            } else {
                columns[weekday] = Column(x: existing!.x, bottom: max(existing!.bottom, item.rect.maxY))
            }
        }
        if columns.count < 3 {
            // 回退：上半区聚类 x，从今天起连续映射
            let top = items.filter { $0.rect.midY < 0.22 }
            var xs: [CGFloat] = []
            for x in top.map(\.rect.midX).sorted() {
                if let last = xs.last, abs(last - x) < 0.045 { continue }
                xs.append(x)
            }
            let today = SemesterCalendar.weekday(of: .now)
            for (i, x) in xs.prefix(7).enumerated() {
                let day = ((today - 1 + i) % 7) + 1
                if columns[day] == nil {
                    columns[day] = Column(x: x, bottom: 0.1)
                }
            }
        }
        return columns
    }

    private static func weekdayFrom(month: Int, day: Int) -> Int? {
        let cal = SemesterCalendar.calendar
        var year = cal.component(.year, from: .now)
        // 跨年课表：若月份远大于当前月，可能是去年
        let currentMonth = cal.component(.month, from: .now)
        if month - currentMonth > 6 { year -= 1 }
        if currentMonth - month > 6 { year += 1 }
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return SemesterCalendar.weekday(of: date)
    }

    private static func detectPeriodRows(in items: [TextItem], leftBoundary: CGFloat, headerBottom: CGFloat) -> [Int: CGFloat] {
        var rowCenters: [Int: CGFloat] = [:]
        for item in items where item.rect.midX < leftBoundary && item.rect.minY > headerBottom - 0.02 {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let m = Patterns.firstMatch(Patterns.rowLabel, in: text),
               let period = Patterns.string(m, group: 1, in: text).flatMap({ Int($0) }),
               (1...20).contains(period), rowCenters[period] == nil {
                rowCenters[period] = item.rect.midY
            }
        }
        return rowCenters
    }

    private static func blocks(from items: [TextItem]) -> [[TextItem]] {
        let sorted = items.sorted { $0.rect.minY < $1.rect.minY }
        let heights = sorted.map(\.rect.height).sorted()
        let lineHeight = heights.dropFirst(heights.count / 3).first ?? 0.02
        var result: [[TextItem]] = []
        for item in sorted {
            // 同一格子内行距很近；不同课程块之间空隙更大
            if let last = result.last?.last, item.rect.minY - last.rect.maxY < max(lineHeight * 1.35, 0.014) {
                result[result.count - 1].append(item)
            } else {
                result.append([item])
            }
        }
        return result
    }

    private static func periods(for block: [TextItem], rowCenters: [Int: CGFloat], nextTop: CGFloat?) -> (Int, Int)? {
        guard !rowCenters.isEmpty else { return nil }
        let top = block.map(\.rect.minY).min() ?? 0
        let bottom = block.map(\.rect.maxY).max() ?? 0
        let tolerance: CGFloat = 0.014
        let covered = rowCenters.filter { $0.value >= top - tolerance && $0.value <= bottom + tolerance }.keys.sorted()
        if let first = covered.first, let last = covered.last {
            // 块已覆盖两节以上时不要再自动扩成更多
            if first == last, first % 2 == 1, let nextCenter = rowCenters[first + 1] {
                let rowHeight = abs(nextCenter - (rowCenters[first] ?? nextCenter))
                if nextTop.map({ $0 > nextCenter - rowHeight * 0.35 }) ?? true {
                    return (first, first + 1)
                }
            }
            return (first, last)
        }
        let mid = (top + bottom) / 2
        let nearest = rowCenters.min { abs($0.value - mid) < abs($1.value - mid) }!.key
        if nearest % 2 == 1, rowCenters[nearest + 1] != nil {
            return (nearest, nearest + 1)
        }
        return (nearest, nearest)
    }

    private static func guessedPeriodRows(from items: [TextItem], leftBoundary: CGFloat,
                                          headerBottom: CGFloat, slots: [PeriodSlot]) -> [Int: CGFloat] {
        let bodyItems = items.filter { $0.rect.minY > headerBottom }
        guard let top = bodyItems.map(\.rect.minY).min(), let bottom = bodyItems.map(\.rect.maxY).max(), bottom > top else {
            return [:]
        }
        let count = max(slots.count, 14)
        var result: [Int: CGFloat] = [:]
        for index in 1...count {
            let t = (CGFloat(index) - 0.5) / CGFloat(count)
            result[index] = top + (bottom - top) * t
        }
        return result
    }

    /// 同一天、同名同教室且节次相连时，只合并「被拆碎的同一大节」。
    /// 例如 OCR 把第 1、2 节拆成两条 → 合成 1-2；但超星里 1-2 与 3-4 是两格，保持分开，不合成 1-4。
    private static func mergeAdjacent(_ drafts: [CourseDraft], slots: [PeriodSlot]) -> [CourseDraft] {
        let sorted = drafts.sorted { ($0.weekday, $0.startPeriod, $0.startMinutes) < ($1.weekday, $1.startPeriod, $1.startMinutes) }
        var result: [CourseDraft] = []
        for draft in sorted {
            if var last = result.last,
               last.weekday == draft.weekday,
               last.name == draft.name,
               last.classroom == draft.classroom,
               draft.startPeriod == last.endPeriod + 1 {
                let lastSpan = last.endPeriod - last.startPeriod + 1
                let draftSpan = draft.endPeriod - draft.startPeriod + 1
                // 合并后总跨度不超过 2 节（一大节），避免把 1-2 与 3-4 粘成 1-4
                if lastSpan + draftSpan <= 2 {
                    last.endPeriod = draft.endPeriod
                    last.endMinutes = max(last.endMinutes, draft.endMinutes)
                    if last.weeks.isEmpty { last.weeks = draft.weeks }
                    last.complete(with: slots, preferPeriods: true)
                    result[result.count - 1] = last
                    continue
                }
            }
            result.append(draft)
        }
        return result
    }
}

enum LineHeuristicParser {
    static func parse(_ text: String, slots: [PeriodSlot]) -> [CourseDraft] {
        var drafts: [CourseDraft] = []
        var currentWeekday: Int?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // 「一、星期一」分区标题
            if let day = ListScheduleParserDay.detect(line) {
                currentWeekday = day
                continue
            }
            if ScheduleJunk.isDayOrHeader(line), WeekdayName.detect(in: line, allowBare: false) != nil {
                currentWeekday = WeekdayName.detect(in: line, allowBare: false)
                continue
            }

            let weekday = WeekdayName.detect(in: line, allowBare: false) ?? (line.contains("今天") ? SemesterCalendar.weekday(of: .now) : nil)
            // 空格分列：时间 课名 教师 教室 周次
            let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
            if tokens.count >= 3, let day = weekday ?? currentWeekday {
                if let draft = parseSpacedRow(tokens, day: day, slots: slots) {
                    drafts.append(draft)
                    continue
                }
            }

            var cleaned = line
            for prefix in ["星期", "礼拜", "周"] {
                for n in ["一", "二", "三", "四", "五", "六", "日", "天"] {
                    cleaned = cleaned.replacingOccurrences(of: prefix + n, with: " ")
                }
            }
            cleaned = cleaned.replacingOccurrences(of: "今天", with: " ")
            cleaned = cleaned.replacingOccurrences(of: "(?i)\\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*\\.?", with: " ",
                                                   options: .regularExpression)
            let fields = CellFields(lines: [cleaned])
            if weekday != nil && fields.name.count < 2 {
                currentWeekday = weekday
                continue
            }
            guard let day = weekday ?? currentWeekday, fields.name.count >= 2,
                  !ScheduleJunk.isDayOrHeader(fields.name),
                  fields.periods != nil || fields.times != nil else { continue }
            var draft = CourseDraft(name: fields.name, classroom: fields.classroom, teacher: fields.teacher,
                                    weekday: day, weeks: fields.weeks)
            if let p = fields.periods { draft.startPeriod = p.0; draft.endPeriod = p.1 }
            if let t = fields.times { draft.startMinutes = t.0; draft.endMinutes = t.1 }
            draft.complete(with: slots, preferPeriods: true)
            if draft.isValid { drafts.append(draft) }
        }
        return drafts
    }

    private static func parseSpacedRow(_ tokens: [String], day: Int, slots: [PeriodSlot]) -> CourseDraft? {
        var rest = tokens
        var time = ""
        if let i = rest.firstIndex(where: { $0.range(of: #"\d{1,2}[:：]\d{2}"#, options: .regularExpression) != nil }) {
            time = rest.remove(at: i)
        }
        var weeksText = ""
        if let i = rest.firstIndex(where: { $0.contains("周") }) {
            weeksText = rest.remove(at: i)
        }
        var classroom = ""
        if let i = rest.firstIndex(where: {
            $0.contains("楼") || $0.contains("馆") || $0.contains("机房")
                || $0.range(of: #"[A-Za-z]\-?\d{2,4}"#, options: .regularExpression) != nil
        }) {
            classroom = rest.remove(at: i)
            if i < rest.count, rest[i].range(of: #"^[A-Za-z]?\-?\d{2,4}$"#, options: .regularExpression) != nil {
                classroom += " " + rest.remove(at: i)
            }
        }
        var teacher = ""
        if let i = rest.firstIndex(where: {
            $0.hasSuffix("老师") || $0 == "辅导员" || $0.contains("教研室") || $0 == "体育组"
                || ($0.range(of: #"^[\p{Han}]{2,4}$"#, options: .regularExpression) != nil && $0.count <= 4
                    && !$0.contains("大学") && !$0.contains("数学") && !$0.contains("英语"))
        }) {
            teacher = rest.remove(at: i).replacingOccurrences(of: "老师", with: "")
        }
        let name = rest.joined()
        guard name.count >= 2, !ScheduleJunk.isDayOrHeader(name) else { return nil }
        var draft = CourseDraft(name: name, classroom: classroom, teacher: teacher, weekday: day,
                                weeks: WeeksParser.parse(weeksText))
        if let range = time.range(of: #"(\d{1,2})[:：](\d{2})\s*[-－—~～至到]\s*(\d{1,2})[:：](\d{2})"#, options: .regularExpression) {
            let nums = String(time[range]).split { !"0123456789".contains($0) }.compactMap { Int($0) }
            if nums.count >= 4 {
                draft.startMinutes = nums[0] * 60 + nums[1]
                draft.endMinutes = nums[2] * 60 + nums[3]
            }
        }
        draft.complete(with: slots, preferPeriods: false)
        return draft.isValid ? draft : nil
    }
}

/// 供 LineHeuristicParser 复用的日标题检测。
private enum ListScheduleParserDay {
    static func detect(_ text: String) -> Int? {
        if let m = text.range(of: #"[一二三四五六日天]、?\s*星期[一二三四五六日天]"#, options: .regularExpression) {
            return WeekdayName.detect(in: String(text[m]), allowBare: false)
        }
        if text.range(of: #"^[一二三四五六日天]、"#, options: .regularExpression) != nil {
            return WeekdayName.detect(in: "星期" + String(text.prefix(1)), allowBare: false)
        }
        return nil
    }
}

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
                draft.complete(with: slots, preferPeriods: false)
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
