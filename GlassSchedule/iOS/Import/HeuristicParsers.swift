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
    /// 超星 / 教务常见：课程名@教室号（教室可为 3–5 位，允许中间被 OCR 拆开后再拼）
    static let atRoom = try! NSRegularExpression(pattern: "(.+?)@([A-Za-z0-9\\-－]{1,12})")
    static let atRoomAnchored = try! NSRegularExpression(pattern: "^(.+?)@([A-Za-z0-9\\-－]{1,12})$")
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
        pattern: "^(?:星期?[一二三四五六日天]|周[一二三四五六日天]|今天|明天|第?\\d+(?:[-－—]\\d+)?节|上午|下午|晚上|备注|课程|教室|教师|时间|节次|地点|节数|时间段|课程名|周次|每周|(?:[\\(（]?每周[\\)）]?)+|课程名教师教室|时间段课程名教师教室周次|—|-|－|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)$",
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
        let cleanedLines = OCRCleanup.dedupeLines(
            lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0 != "—" && $0 != "-" && $0 != "－" }
        )
        guard !cleanedLines.isEmpty else { return }

        // 教务网格常见 4 行：课名 / 教师 / 教一楼 302 / 1-16周 (单周)
        if parseStructuredLines(cleanedLines) {
            name = OCRCleanup.sanitizeCourseName(name)
            if OCRCleanup.isBogusCourseName(name) { name = "" }
            return
        }

        // 回退：拼回整句再解析（超星窄列竖排）
        parseJoined(OCRTextJoiner.join(cleanedLines))
        name = OCRCleanup.sanitizeCourseName(name)
        if OCRCleanup.isBogusCourseName(name) { name = "" }
    }

    /// 按「课名 → 教师 → 教室 → 周次」行序解析；续接词并入课名，绝不把人名当课名。
    @discardableResult
    private mutating func parseStructuredLines(_ lines: [String]) -> Bool {
        var weekLines: [String] = []
        var roomParts: [String] = []
        var content: [String] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isWeekLine(line) {
                weekLines.append(line)
            } else if isRoomLine(line) {
                roomParts.append(line)
            } else if i + 1 < lines.count,
                      Patterns.firstMatch(Patterns.buildingOnly, in: line) != nil,
                      Patterns.firstMatch(Patterns.roomNumber, in: lines[i + 1]) != nil {
                roomParts.append("\(line) \(lines[i + 1])")
                i += 1
            } else if Patterns.firstMatch(Patterns.junkName, in: line) == nil {
                content.append(line)
            }
            i += 1
        }

        // 内容行：先拼课名（含续接词），再认教师
        var nameParts: [String] = []
        var teacherCandidate = ""
        for (idx, part) in content.enumerated() {
            if OCRCleanup.isClearTeacherLabel(part) {
                if teacherCandidate.isEmpty { teacherCandidate = part }
                continue
            }
            if OCRCleanup.courseContinuations.contains(part) || part.count == 1 {
                nameParts.append(part)
                continue
            }
            // 已有像样课名后，2–3 字人名 → 教师
            let assembled = nameParts.joined()
            if teacherCandidate.isEmpty,
               OCRCleanup.looksLikePersonNameOnly(part),
               assembled.count >= 4 {
                teacherCandidate = part
                continue
            }
            // 尚未有课名时，人名行先跳过（避免王芳当课名）；若整格只剩人名则最后丢弃
            if nameParts.isEmpty, OCRCleanup.looksLikePersonNameOnly(part), idx + 1 < content.count {
                // 后面还有内容时，暂存为人名，不写进课名
                if teacherCandidate.isEmpty { teacherCandidate = part }
                continue
            }
            nameParts.append(part)
        }

        name = OCRCleanup.sanitizeCourseName(nameParts.joined())
        if OCRCleanup.isBogusCourseName(name) || OCRCleanup.looksLikePersonNameOnly(name) {
            name = ""
        }

        if let weekText = weekLines.first { applyWeeks(from: weekText) }
        if let roomText = roomParts.first {
            classroom = OCRCleanup.sanitizeClassroom(normalizeRoom(roomText))
        }
        if !teacherCandidate.isEmpty {
            teacher = OCRCleanup.sanitizeTeacher(teacherCandidate)
        }
        // 教师与课名相同 → 清掉教师（自习时间）
        if !teacher.isEmpty, teacher == name { teacher = "" }

        // 补抽教室/周次（不覆盖已有课名）
        if classroom.isEmpty || weeks.isEmpty {
            let joined = OCRTextJoiner.join(lines)
            var tmp = CellFields()
            tmp.parseJoined(joined)
            if classroom.isEmpty { classroom = OCRCleanup.sanitizeClassroom(tmp.classroom) }
            if weeks.isEmpty { weeks = tmp.weeks }
            if periods == nil { periods = tmp.periods }
            if times == nil { times = tmp.times }
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

        if let m = Patterns.firstMatch(Patterns.atRoomAnchored, in: text)
            ?? Patterns.firstMatch(Patterns.atRoom, in: text),
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
        if line.contains("每周") { return true }
        let compact = line.replacingOccurrences(of: #"[（()）\s]"#, with: "", options: .regularExpression)
        if compact == "每周" || compact.range(of: #"^(每周)+$"#, options: .regularExpression) != nil { return true }
        return line.contains("周") && (
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
        if OCRCleanup.isClearTeacherLabel(line) { return true }
        if OCRCleanup.courseContinuations.contains(line) { return false }
        if OCRCleanup.looksLikePersonNameOnly(line) { return true }
        return Patterns.firstMatch(Patterns.teacher, in: line) != nil
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
            if OCRCleanup.courseContinuations.contains(suffix) { continue }
            guard OCRCleanup.looksLikePersonNameOnly(suffix) || OCRCleanup.isClearTeacherLabel(suffix) else { continue }
            guard prefix.count >= 2 else { continue }
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
            let cleaned = OCRCleanup.dedupeItems(allItems.filter { $0.page == page })
            drafts += parsePage(cleaned, slots: slots)
        }
        return mergeAdjacent(drafts, slots: slots)
    }

    private static func parsePage(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        guard !items.isEmpty else { return [] }

        let columns = detectWeekdayColumns(in: items)
        guard columns.count >= 2 else { return [] }
        let headerBottom = columns.values.map(\.bottom).max() ?? 0.08

        let sortedCols = columns.map { (day: $0.key, x: $0.value.x) }.sorted { $0.x < $1.x }
        let colBounds = columnBounds(sortedCols)
        let leftBoundary = colBounds.map(\.value.lowerBound).min() ?? (sortedCols[0].x - 0.06)

        // 超星课表特征：格子里是「课程@教室号」
        let atRoomHits = items.filter { $0.text.contains("@") }.count
        let blockDrafts = parseByColumnBlocks(items: items, columns: columns, colBounds: colBounds,
                                              headerBottom: headerBottom, leftBoundary: leftBoundary, slots: slots)

        // 同时尝试「整块聚类」与「节次行带」两种解析。超星课表经常把相邻
        // 1-2 / 3-4 节显示为两个紧贴的色块；仅按文字行距聚类可能把它们粘在一起，
        // 或因 OCR 框缺失而漏掉整列。带 @ 教室号时，行带解析也必须走专用拆分器。
        let detectedBands = detectPeriodBands(in: items, leftBoundary: leftBoundary, headerBottom: headerBottom)
        let bandDrafts = parseByBands(items: items, colBounds: colBounds, bands: detectedBands,
                                      headerBottom: headerBottom, slots: slots,
                                      allowAtRoom: atRoomHits >= 1)

        if atRoomHits >= 1 {
            let candidates = [blockDrafts, bandDrafts].filter { !$0.isEmpty }
            return candidates.max { candidateScore($0) < candidateScore($1) } ?? []
        }

        let bandScore = bandDrafts.filter { $0.canCommit || !$0.classroom.isEmpty }.count
        let blockScore = blockDrafts.filter { $0.canCommit || !$0.classroom.isEmpty }.count
        if blockScore > bandScore, !blockDrafts.isEmpty { return blockDrafts }
        if bandScore > 0, !bandDrafts.isEmpty { return bandDrafts }
        if !blockDrafts.isEmpty { return blockDrafts }

        let guessed = guessedPeriodBands(from: items, leftBoundary: leftBoundary, headerBottom: headerBottom, slots: slots)
        return parseByBands(items: items, colBounds: colBounds, bands: guessed,
                            headerBottom: headerBottom, slots: slots)
    }

    /// 优先保留覆盖星期更多、课程更多且教室/节次信息完整的候选解析。
    private static func candidateScore(_ drafts: [CourseDraft]) -> Int {
        let days = Set(drafts.map(\\.weekday)).count
        let rooms = drafts.filter { !$0.classroom.isEmpty }.count
        let periods = drafts.filter { $0.startPeriod > 0 && $0.endPeriod >= $0.startPeriod }.count
        return drafts.count * 10 + days * 8 + rooms * 2 + periods * 2
    }

    private static func parseByBands(items: [TextItem], colBounds: [Int: ClosedRange<CGFloat>],
                                     bands: [PeriodBand], headerBottom: CGFloat,
                                     slots: [PeriodSlot], allowAtRoom: Bool = false) -> [CourseDraft] {
        guard !bands.isEmpty else { return [] }
        var drafts: [CourseDraft] = []
        for (day, xRange) in colBounds {
            for band in bands {
                let cellItems = items.filter { item in
                    guard item.rect.minY >= headerBottom - 0.01 else { return false }
                    return xRange.contains(item.rect.midX) && band.yRange.contains(item.rect.midY)
                }
                guard let draft = draftFromCell(cellItems, day: day, periods: (band.startPeriod, band.endPeriod),
                                                slots: slots, allowAtRoom: allowAtRoom) else {
                    continue
                }
                drafts.append(draft)
            }
        }
        return drafts.sorted { ($0.weekday, $0.startPeriod) < ($1.weekday, $1.startPeriod) }
    }

    /// 超星窄列：同一星期列内按 Y 聚成课块，保留 课程@教室。
    private static func parseByColumnBlocks(items: [TextItem], columns: [Int: Column],
                                            colBounds: [Int: ClosedRange<CGFloat>],
                                            headerBottom: CGFloat, leftBoundary: CGFloat,
                                            slots: [PeriodSlot]) -> [CourseDraft] {
        let rowCenters = detectPeriodRowCenters(in: items, leftBoundary: leftBoundary, headerBottom: headerBottom)
        let sortedCols = columns.map { (day: $0.key, x: $0.value.x) }.sorted { $0.x < $1.x }
        let centers = sortedCols.map(\.x)
        let spacing = zip(centers, centers.dropFirst()).map { $1 - $0 }.min() ?? 0.12

        // 先严格按列中点边界归属，避免周一/周二窄列串字（「水利工」被粘两次）
        var byWeekday: [Int: [TextItem]] = [:]
        for item in items where item.rect.minY >= headerBottom - 0.004 && item.rect.midX >= leftBoundary - 0.02 {
            if let day = colBounds.first(where: { $0.value.contains(item.rect.midX) })?.key {
                byWeekday[day, default: []].append(item)
                continue
            }
            // 落在边界缝上的再就近，阈值收紧防止跨列
            guard let nearest = sortedCols.min(by: { abs($0.x - item.rect.midX) < abs($1.x - item.rect.midX) }) else {
                continue
            }
            if abs(nearest.x - item.rect.midX) > spacing * 0.42 { continue }
            byWeekday[nearest.day, default: []].append(item)
        }

        var drafts: [CourseDraft] = []
        for (day, columnItems) in byWeekday {
            let blocks = chaoxingVerticalBlocks(from: columnItems)
            for (blockIndex, block) in blocks.enumerated() {
                let nextTop = blockIndex + 1 < blocks.count ? blocks[blockIndex + 1].map(\.rect.minY).min() : nil
                let periods = periodsForBlock(block, rowCenters: rowCenters, nextTop: nextTop)
                guard let draft = draftFromCell(block, day: day, periods: periods, slots: slots, allowAtRoom: true) else {
                    continue
                }
                drafts.append(draft)
            }
        }
        return drafts.sorted { ($0.weekday, $0.startPeriod) < ($1.weekday, $1.startPeriod) }
    }

    private static func draftFromCell(_ cellItems: [TextItem], day: Int, periods: (Int, Int)?,
                                      slots: [PeriodSlot], allowAtRoom: Bool = false) -> CourseDraft? {
        guard !cellItems.isEmpty else { return nil }
        let rawLines = OCRCleanup.dedupeLines(cellItems.sorted { $0.rect.minY < $1.rect.minY }.map(\.text))
        // 超星：先粘合「@231」+「3」→「@2313」，绝不能把尾数当节次丢掉
        if allowAtRoom {
            return draftFromChaoxingCell(rawLines, day: day, periods: periods, slots: slots)
        }

        let contentLines = rawLines.filter { line in
            !isCellPeriodNoise(line)
                && line.range(of: #"^\d{1,2}[:：]\d{2}([-－—~～]\d{1,2}[:：]\d{2})?$"#, options: .regularExpression) == nil
                && line.range(of: #"^\d{1,2}/\d{1,2}$"#, options: .regularExpression) == nil
        }
        guard !contentLines.isEmpty else { return nil }

        var fields = CellFields(lines: contentLines)
        fields.name = OCRCleanup.sanitizeCourseName(fields.name)
        fields.classroom = OCRCleanup.sanitizeClassroom(fields.classroom)
        fields.teacher = OCRCleanup.sanitizeTeacher(fields.teacher)
        if fields.teacher == fields.name { fields.teacher = "" }

        guard fields.name.count >= 2 else { return nil }
        guard !OCRCleanup.isBogusCourseName(fields.name) else { return nil }
        guard Patterns.firstMatch(Patterns.junkName, in: fields.name) == nil else { return nil }
        if fields.name.contains("@") { return nil }

        var draft = CourseDraft(name: fields.name, classroom: fields.classroom, teacher: fields.teacher,
                                weekday: day, weeks: fields.weeks)
        if let p = fields.periods {
            draft.startPeriod = p.0; draft.endPeriod = p.1
        } else if let p = periods, p.0 > 0 {
            draft.startPeriod = p.0; draft.endPeriod = max(p.0, p.1)
        }
        if let t = fields.times { draft.startMinutes = t.0; draft.endMinutes = t.1 }
        draft.complete(with: slots, preferPeriods: true)
        return draft.isValid ? draft : nil
    }

    /// 单元格内的节次噪声：必须带「节」或「1-2」形式；裸数字「3」可能是教室号尾部，保留。
    private static func isCellPeriodNoise(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.contains("节") {
            return Patterns.firstMatch(Patterns.rowLabel, in: t) != nil
        }
        return t.range(of: #"^\d{1,2}\s*[-－—~～]\s*\d{1,2}$"#, options: .regularExpression) != nil
    }

    private static func draftFromChaoxingCell(_ rawLines: [String], day: Int, periods: (Int, Int)?,
                                              slots: [PeriodSlot]) -> CourseDraft? {
        // 去掉日期表头碎片，但保留纯数字（教室尾号）
        let lines = rawLines.filter { line in
            line.range(of: #"^\d{1,2}/\d{1,2}$"#, options: .regularExpression) == nil
                && !line.contains("今天")
                && Patterns.firstMatch(Patterns.junkName, in: line) == nil
        }
        guard !lines.isEmpty else { return nil }

        let glued = OCRTextJoiner.join(lines)
        var name = ""
        var classroom = ""

        if let m = Patterns.firstMatch(Patterns.atRoom, in: glued),
           let course = Patterns.string(m, group: 1, in: glued),
           let room = Patterns.string(m, group: 2, in: glued) {
            name = course
            classroom = room
            // 若 @ 后仍有落单数字被拼在尾巴外，再吸一次
            let after = (glued as NSString).replacingCharacters(in: m.range, with: " ")
            if let extra = after.range(of: #"^\s*(\d{1,3})\b"#, options: .regularExpression) {
                let digits = String(after[extra]).trimmingCharacters(in: .whitespaces)
                if classroom.count + digits.count <= 6 { classroom += digits }
            }
        } else {
            // 无 @：不收残片进确认页（「水利工」「程造价」曾因此污染周二）
            return nil
        }

        name = OCRCleanup.sanitizeCourseName(name)
            .replacingOccurrences(of: #"@.+$"#, with: "", options: .regularExpression)
        classroom = OCRCleanup.sanitizeClassroom(classroom)

        guard name.count >= 2 else { return nil }
        // 教室至少 3 位数字/字母，避免 @2 这类截断半成品
        guard classroom.range(of: #"[A-Za-z0-9\-－]{3,}"#, options: .regularExpression) != nil else { return nil }
        guard !OCRCleanup.isBogusCourseName(name) else { return nil }
        guard Patterns.firstMatch(Patterns.junkName, in: name) == nil else { return nil }

        var draft = CourseDraft(name: name, classroom: classroom, teacher: "", weekday: day, weeks: [])
        if let p = periods, p.0 > 0 {
            draft.startPeriod = p.0
            draft.endPeriod = max(p.0, p.1)
        }
        draft.complete(with: slots, preferPeriods: true)
        return draft.isValid ? draft : nil
    }

    /// 超星竖排：先按间距聚行，再在「课程@教室」完整后切开，防止 1-2/3-4 两格粘成乱码。
    private static func chaoxingVerticalBlocks(from items: [TextItem]) -> [[TextItem]] {
        let sorted = items.sorted { $0.rect.minY < $1.rect.minY }
        guard !sorted.isEmpty else { return [] }
        let heights = sorted.map(\.rect.height).sorted()
        let lineHeight = heights.dropFirst(max(0, heights.count / 3)).first ?? 0.02

        var clusters: [[TextItem]] = []
        for item in sorted {
            if let last = clusters.last?.last {
                let gap = item.rect.minY - last.rect.maxY
                // 同格内行距通常很小；两格之间空隙更大
                if gap < max(lineHeight * 1.85, 0.018) {
                    clusters[clusters.count - 1].append(item)
                    continue
                }
            }
            clusters.append([item])
        }

        // 过碎的纯数字行（教室尾号）并入上一簇
        var merged: [[TextItem]] = []
        for cluster in clusters {
            let texts = cluster.map(\.text)
            let onlyDigits = texts.allSatisfy { $0.trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber) }
                && texts.joined().count <= 3
            if onlyDigits, !merged.isEmpty {
                merged[merged.count - 1].append(contentsOf: cluster)
            } else {
                merged.append(cluster)
            }
        }

        // 一簇里若有多门「@教室」，按 @ 课程切开
        return merged.flatMap(splitMultipleAtRoomClusters)
    }

    private static func splitMultipleAtRoomClusters(_ items: [TextItem]) -> [[TextItem]] {
        let sorted = items.sorted { $0.rect.minY < $1.rect.minY }
        guard sorted.count >= 2 else { return [sorted] }

        var result: [[TextItem]] = []
        var current: [TextItem] = []

        func isComplete(_ group: [TextItem]) -> Bool {
            let glued = OCRTextJoiner.join(group.map(\.text))
            return glued.range(of: #".+@[A-Za-z0-9\-－]{3,}"#, options: .regularExpression) != nil
        }

        for item in sorted {
            let t = item.text.trimmingCharacters(in: .whitespaces)
            if !current.isEmpty, isComplete(current), !t.allSatisfy(\.isNumber) {
                // 上一门已完整，且本行不是教室尾号 → 新课
                result.append(current)
                current = [item]
            } else {
                current.append(item)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.filter { !$0.isEmpty }
    }

    private static func verticalBlocks(from items: [TextItem]) -> [[TextItem]] {
        let sorted = items.sorted { $0.rect.minY < $1.rect.minY }
        let heights = sorted.map(\.rect.height).sorted()
        let lineHeight = heights.dropFirst(heights.count / 3).first ?? 0.02
        var result: [[TextItem]] = []
        for item in sorted {
            if let last = result.last?.last, item.rect.minY - last.rect.maxY < max(lineHeight * 1.35, 0.014) {
                result[result.count - 1].append(item)
            } else {
                result.append([item])
            }
        }
        return result
    }

    private static func detectPeriodRowCenters(in items: [TextItem], leftBoundary: CGFloat, headerBottom: CGFloat) -> [Int: CGFloat] {
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

    private static func periodsForBlock(_ block: [TextItem], rowCenters: [Int: CGFloat], nextTop: CGFloat?) -> (Int, Int)? {
        guard !rowCenters.isEmpty else { return nil }
        let top = block.map(\.rect.minY).min() ?? 0
        let bottom = block.map(\.rect.maxY).max() ?? 0
        let tolerance: CGFloat = 0.014
        let covered = rowCenters.filter { $0.value >= top - tolerance && $0.value <= bottom + tolerance }.keys.sorted()
        if let first = covered.first, let last = covered.last {
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
        if nearest % 2 == 1, rowCenters[nearest + 1] != nil { return (nearest, nearest + 1) }
        return (nearest, nearest)
    }

    /// 相邻列中点为边界，禁止跨列吞字。
    private static func columnBounds(_ sortedCols: [(day: Int, x: CGFloat)]) -> [Int: ClosedRange<CGFloat>] {
        var result: [Int: ClosedRange<CGFloat>] = [:]
        for (i, col) in sortedCols.enumerated() {
            let left: CGFloat
            let right: CGFloat
            if i == 0 {
                let gap = i + 1 < sortedCols.count ? (sortedCols[i + 1].x - col.x) : 0.12
                left = col.x - gap * 0.48
                right = i + 1 < sortedCols.count ? (col.x + sortedCols[i + 1].x) / 2 : col.x + gap * 0.48
            } else if i == sortedCols.count - 1 {
                let gap = col.x - sortedCols[i - 1].x
                left = (sortedCols[i - 1].x + col.x) / 2
                right = col.x + gap * 0.48
            } else {
                left = (sortedCols[i - 1].x + col.x) / 2
                right = (col.x + sortedCols[i + 1].x) / 2
            }
            result[col.day] = left...right
        }
        return result
    }

    private struct PeriodBand {
        var startPeriod: Int
        var endPeriod: Int
        var yRange: ClosedRange<CGFloat>
    }

    private static func detectPeriodBands(in items: [TextItem], leftBoundary: CGFloat, headerBottom: CGFloat) -> [PeriodBand] {
        var labels: [(start: Int, end: Int, y: CGFloat)] = []
        for item in items where item.rect.midX < leftBoundary && item.rect.minY > headerBottom - 0.02 {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let m = Patterns.firstMatch(Patterns.rowLabel, in: text),
               let s = Patterns.string(m, group: 1, in: text).flatMap({ Int($0) }),
               (1...20).contains(s) {
                let e = Patterns.string(m, group: 2, in: text).flatMap { Int($0) } ?? (s % 2 == 1 ? s + 1 : s)
                labels.append((s, max(s, e), item.rect.midY))
            } else if let m = text.range(of: #"第\s*(\d{1,2})\s*[-－—~～]\s*(\d{1,2})\s*节"#, options: .regularExpression) {
                let nums = String(text[m]).split { !"0123456789".contains($0) }.compactMap { Int($0) }
                if nums.count >= 2 { labels.append((nums[0], nums[1], item.rect.midY)) }
            }
        }
        // 去重同节次
        var byStart: [Int: (Int, CGFloat)] = [:]
        for lab in labels {
            if byStart[lab.start] == nil { byStart[lab.start] = (lab.end, lab.y) }
        }
        let sorted = byStart.map { (start: $0.key, end: $0.value.0, y: $0.value.1) }.sorted { $0.y < $1.y }
        guard sorted.count >= 2 else { return [] }

        var bands: [PeriodBand] = []
        for (i, lab) in sorted.enumerated() {
            let top = i == 0 ? headerBottom : (sorted[i - 1].y + lab.y) / 2
            let bottom = i + 1 < sorted.count ? (lab.y + sorted[i + 1].y) / 2 : min(1, lab.y + (lab.y - top))
            bands.append(PeriodBand(startPeriod: lab.start, endPeriod: lab.end, yRange: top...bottom))
        }
        return bands
    }

    private static func guessedPeriodBands(from items: [TextItem], leftBoundary: CGFloat,
                                           headerBottom: CGFloat, slots: [PeriodSlot]) -> [PeriodBand] {
        let body = items.filter { $0.rect.minY > headerBottom && $0.rect.midX >= leftBoundary }
        guard let top = body.map(\.rect.minY).min(), let bottom = body.map(\.rect.maxY).max(), bottom > top else {
            return []
        }
        // 常见大节：1-2, 3-4, 5-6, 7-8, 9-10, 11-12
        let pairs = [(1, 2), (3, 4), (5, 6), (7, 8), (9, 10), (11, 12)]
        let count = pairs.count
        return pairs.enumerated().map { index, pair in
            let a = top + (bottom - top) * CGFloat(index) / CGFloat(count)
            let b = top + (bottom - top) * CGFloat(index + 1) / CGFloat(count)
            return PeriodBand(startPeriod: pair.0, endPeriod: pair.1, yRange: a...b)
        }
    }

    private struct Column {
        var x: CGFloat
        var bottom: CGFloat
    }

    private static func detectWeekdayColumns(in items: [TextItem]) -> [Int: Column] {
        var columns: [Int: Column] = [:]
        let headerItems = items.filter { $0.rect.midY < 0.28 }

        // 先收集纯日期碎片，供「今天」列就近对齐
        let datePins: [(x: CGFloat, weekday: Int, maxY: CGFloat)] = headerItems.compactMap { item in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let m = Patterns.firstMatch(Patterns.dateHeader, in: text),
                  let month = Patterns.string(m, group: 1, in: text).flatMap(Int.init),
                  let day = Patterns.string(m, group: 2, in: text).flatMap(Int.init),
                  let weekday = weekdayFrom(month: month, day: day) else { return nil }
            return (item.rect.midX, weekday, item.rect.maxY)
        }

        for item in headerItems {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var weekday: Int?
            if let m = Patterns.firstMatch(Patterns.dateHeader, in: text),
               let month = Patterns.string(m, group: 1, in: text).flatMap(Int.init),
               let day = Patterns.string(m, group: 2, in: text).flatMap(Int.init) {
                weekday = weekdayFrom(month: month, day: day)
            }
            if weekday == nil, text.contains("今天") {
                // 「今天」与「11/24」被拆成两段时，取最近日期钉
                if let pin = datePins.min(by: { abs($0.x - item.rect.midX) < abs($1.x - item.rect.midX) }),
                   abs(pin.x - item.rect.midX) < 0.1 {
                    weekday = pin.weekday
                } else {
                    weekday = SemesterCalendar.weekday(of: .now)
                }
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
        // 日期钉补列（仅有 11/24 无「周二」文字时）
        for pin in datePins where columns[pin.weekday] == nil {
            columns[pin.weekday] = Column(x: pin.x, bottom: pin.maxY)
        }
        if columns.count < 3 {
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

    /// 同一天、同名、教室兼容且节次相连时合并。
    /// 超星常见 1-2 与 3-4 两格同课 → 合成 1-4；教室「231」与「2313」视为同一间（取更长）。
    private static func mergeAdjacent(_ drafts: [CourseDraft], slots: [PeriodSlot]) -> [CourseDraft] {
        let sorted = drafts.sorted { ($0.weekday, $0.startPeriod, $0.startMinutes) < ($1.weekday, $1.startPeriod, $1.startMinutes) }
        var result: [CourseDraft] = []
        for draft in sorted {
            if var last = result.last,
               last.weekday == draft.weekday,
               last.name == draft.name,
               roomsCompatible(last.classroom, draft.classroom),
               draft.startPeriod == last.endPeriod + 1 {
                let mergedSpan = draft.endPeriod - last.startPeriod + 1
                // 超星一大段最多 4 节（两格）；普通课表一大节 2 节
                let limit = (last.classroom.contains(where: \.isNumber) || draft.classroom.contains(where: \.isNumber)) ? 4 : 2
                if mergedSpan <= limit {
                    last.endPeriod = draft.endPeriod
                    last.endMinutes = max(last.endMinutes, draft.endMinutes)
                    if last.classroom.count < draft.classroom.count { last.classroom = draft.classroom }
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

    private static func roomsCompatible(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.isEmpty || b.isEmpty { return true }
        let x = a.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let y = b.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return x == y || x.hasPrefix(y) || y.hasPrefix(x)
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
                  !ScheduleJunk.isNonCourseText(fields.name),
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
        guard name.count >= 2, !ScheduleJunk.isNonCourseText(name) else { return nil }
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
