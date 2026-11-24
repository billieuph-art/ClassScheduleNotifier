import Foundation
import CoreGraphics

/// 处理「星期在左侧、节次/时间在顶部」的横向课表。
/// 与 GridHeuristicParser 的星期列模式分离，避免用列边界解释行式布局。
enum HorizontalGridParser {
    private struct DayRow {
        var weekday: Int
        var y: CGFloat
        var band: ClosedRange<CGFloat>
    }

    private struct Column {
        var x: CGFloat
        var band: ClosedRange<CGFloat>
        var periods: (Int, Int)?
        var times: (Int, Int)?
    }

    static func parse(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        var result: [CourseDraft] = []
        for page in Set(items.map(\.page)).sorted() {
            let pageItems = OCRCleanup.dedupeItems(items.filter { $0.page == page })
            result += parsePage(pageItems, slots: slots)
        }
        return deduplicate(result)
    }

    private static func parsePage(_ items: [TextItem], slots: [PeriodSlot]) -> [CourseDraft] {
        guard items.count >= 4 else { return [] }
        let dayItems = items.compactMap { item -> (Int, TextItem)? in
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 10 else { return nil }
            let day = WeekdayName.detect(in: text, allowBare: false)
                ?? (text.count == 1 ? WeekdayName.detect(in: text, allowBare: true) : nil)
            guard let day else { return nil }
            return (day, item)
        }
        guard dayItems.count >= 2 else { return [] }

        let sortedDayY = dayItems.map { $0.1.rect.midY }.sorted()
        let ySpread = (sortedDayY.last ?? 0) - (sortedDayY.first ?? 0)
        let xSpread = (dayItems.map { $0.1.rect.midX }.max() ?? 0)
            - (dayItems.map { $0.1.rect.midX }.min() ?? 0)
        // 纵向星期列通常同一水平线；只有星期标签沿 Y 轴分散时才判定为横向布局。
        guard ySpread >= 0.14, xSpread <= 0.22 else { return [] }

        let anchors = collapseDayAnchors(dayItems)
        guard anchors.count >= 2 else { return [] }
        let rows = makeDayRows(anchors)
        guard rows.count >= 2 else { return [] }

        let headerBottom = rows.map { $0.band.lowerBound }.min() ?? 0
        let bodyItems = items.filter { item in
            !isDayLabel(item.text)
                && parsePeriodRange(item.text) == nil
                && parseTimeRange(item.text) == nil
                && item.rect.midY >= headerBottom - 0.015
        }
        guard !bodyItems.isEmpty else { return [] }

        let columns = detectColumns(items: items, bodyItems: bodyItems, firstDayY: anchors.map(\.y).min() ?? 0,
                                    slots: slots)
        guard !columns.isEmpty else { return [] }

        var drafts: [CourseDraft] = []
        for row in rows {
            for column in columns {
                let cell = bodyItems.filter {
                    row.band.contains($0.rect.midY) && column.band.contains($0.rect.midX)
                }
                guard !cell.isEmpty,
                      let draft = parseCell(cell, weekday: row.weekday, column: column, slots: slots) else {
                    continue
                }
                drafts.append(draft)
            }
        }
        return deduplicate(drafts)
    }

    private static func collapseDayAnchors(_ items: [(Int, TextItem)]) -> [(weekday: Int, y: CGFloat, x: CGFloat)] {
        let sorted = items.sorted { $0.1.rect.midY < $1.1.rect.midY }
        var groups: [[(Int, TextItem)]] = []
        for entry in sorted {
            if let last = groups.last?.last,
               abs(last.1.rect.midY - entry.1.rect.midY) < 0.035 {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups.compactMap { group in
            guard let first = group.first else { return nil }
            // 同一行重复识别出星期标签时，只保留最可信的首个标签。
            let y = group.map { $0.1.rect.midY }.reduce(0, +) / CGFloat(group.count)
            let x = group.map { $0.1.rect.midX }.reduce(0, +) / CGFloat(group.count)
            return (first.0, y, x)
        }.sorted { $0.y < $1.y }
    }

    private static func makeDayRows(_ anchors: [(weekday: Int, y: CGFloat, x: CGFloat)]) -> [DayRow] {
        let sorted = anchors.sorted { $0.y < $1.y }
        return sorted.enumerated().map { index, anchor in
            let previousGap = index > 0 ? anchor.y - sorted[index - 1].y
                : (sorted.count > 1 ? sorted[1].y - anchor.y : 0.12)
            let nextGap = index + 1 < sorted.count ? sorted[index + 1].y - anchor.y : previousGap
            let top = index == 0 ? max(0, anchor.y - previousGap * 0.48)
                : (sorted[index - 1].y + anchor.y) / 2
            let bottom = index + 1 == sorted.count ? min(1, anchor.y + nextGap * 0.48)
                : (anchor.y + sorted[index + 1].y) / 2
            return DayRow(weekday: anchor.weekday, y: anchor.y, band: top...bottom)
        }
    }

    private static func detectColumns(items: [TextItem], bodyItems: [TextItem],
                                      firstDayY: CGFloat, slots: [PeriodSlot]) -> [Column] {
        // 优先识别位于星期行上方的节次/时间表头。
        var anchors: [(x: CGFloat, periods: (Int, Int)?, times: (Int, Int)?)] = []
        for item in items where item.rect.midY < firstDayY - 0.025 && item.rect.midX > 0.12 {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let period = parsePeriodRange(text) {
                anchors.append((item.rect.midX, period, nil))
            } else if let time = parseTimeRange(text) {
                let mapped = PeriodTable.periods(startMinutes: time.0, endMinutes: time.1, in: slots)
                anchors.append((item.rect.midX, mapped, time))
            }
        }
        anchors = mergeAnchors(anchors)
        if anchors.count >= 2 {
            let sorted = anchors.sorted { $0.x < $1.x }
            return sorted.enumerated().map { index, anchor in
                let left = index == 0 ? max(0, anchor.x - (sorted[1].x - anchor.x) * 0.48)
                    : (sorted[index - 1].x + anchor.x) / 2
                let right = index == sorted.count - 1
                    ? min(1, anchor.x + (anchor.x - sorted[index - 1].x) * 0.48)
                    : (anchor.x + sorted[index + 1].x) / 2
                return Column(x: anchor.x, band: left...right, periods: anchor.periods, times: anchor.times)
            }
        }

        // 无节次表头时，按课程文字的横向中心聚类；只定位课程所在列，不臆造节次。
        let centers = bodyItems.map { $0.rect.midX }.sorted()
        var clusters: [[CGFloat]] = []
        for center in centers {
            if let last = clusters.indices.last,
               abs(center - clusters[last].reduce(0, +) / CGFloat(clusters[last].count)) <= 0.085 {
                clusters[last].append(center)
            } else {
                clusters.append([center])
            }
        }
        let inferred = clusters.map { $0.reduce(0, +) / CGFloat($0.count) }.sorted()
        guard inferred.count >= 2 else { return [] }
        return inferred.enumerated().map { index, center in
            let left = index == 0 ? max(0, center - (inferred[1] - center) * 0.48)
                : (inferred[index - 1] + center) / 2
            let right = index == inferred.count - 1
                ? min(1, center + (center - inferred[index - 1]) * 0.48)
                : (center + inferred[index + 1]) / 2
            return Column(x: center, band: left...right, periods: nil, times: nil)
        }
    }

    private static func mergeAnchors(
        _ values: [(x: CGFloat, periods: (Int, Int)?, times: (Int, Int)?)]
    ) -> [(x: CGFloat, periods: (Int, Int)?, times: (Int, Int)?)] {
        let sorted = values.sorted { $0.x < $1.x }
        var result: [(x: CGFloat, periods: (Int, Int)?, times: (Int, Int)?)] = []
        for value in sorted {
            if let last = result.last, abs(last.x - value.x) < 0.035 {
                result[result.count - 1] = (
                    x: (last.x + value.x) / 2,
                    periods: last.periods ?? value.periods,
                    times: last.times ?? value.times
                )
            } else {
                result.append(value)
            }
        }
        return result
    }

    private static func parseCell(_ items: [TextItem], weekday: Int, column: Column,
                                  slots: [PeriodSlot]) -> CourseDraft? {
        let lines = OCRCleanup.dedupeLines(items.sorted {
            if abs($0.rect.midY - $1.rect.midY) > 0.006 { return $0.rect.midY < $1.rect.midY }
            return $0.rect.minX < $1.rect.minX
        }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !lines.isEmpty else { return nil }

        var weeks: [Int] = []
        var teacher = ""
        var classroom = ""
        var nameParts: [String] = []
        var time = column.times

        var skipNextRoomNumber = false
        for (lineIndex, raw) in lines.enumerated() {
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if skipNextRoomNumber {
                skipNextRoomNumber = false
                continue
            }
            guard !line.isEmpty, !isDayLabel(line) else { continue }

            // OCR 有时把「教一楼 302」拆成两个独立文本框。
            if isBuildingOnly(line), lineIndex + 1 < lines.count, isRoomNumber(lines[lineIndex + 1]) {
                if classroom.isEmpty { classroom = line + " " + lines[lineIndex + 1] }
                skipNextRoomNumber = true
                continue
            }
            if let range = parseTimeRange(line) {
                time = time ?? range
                continue
            }
            if line.contains("周") && (line.range(of: #"\d"#, options: .regularExpression) != nil
                || line.contains("单周") || line.contains("双周") || line.contains("每周")) {
                let parsed = WeeksParser.parse(line)
                if !parsed.isEmpty { weeks = parsed }
                continue
            }
            if isRoomNumber(line) {
                if classroom.isEmpty { classroom = line }
                continue
            }

            // 先从混合行中抽出教室，再处理剩余的课名/教师文字。
            if let room = extractClassroomFragment(from: line) {
                if classroom.isEmpty { classroom = room.value }
                line = (line as NSString).replacingCharacters(in: room.range, with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
            }

            if let split = splitInlineTeacher(line) {
                if !split.course.isEmpty { nameParts.append(split.course) }
                if teacher.isEmpty { teacher = split.teacher }
                continue
            }
            if line.hasSuffix("老师") || line.hasSuffix("教授") {
                let value = line.replacingOccurrences(of: #"(?:老师|教授)$"#, with: "", options: .regularExpression)
                if let split = peelTrailingTeacher(from: value) {
                    nameParts.append(split.name)
                    if teacher.isEmpty { teacher = split.teacher }
                } else if OCRCleanup.looksLikePersonNameOnly(value) || value.count == 1 {
                    if teacher.isEmpty { teacher = value }
                } else {
                    nameParts.append(value)
                }
                continue
            }
            if ScheduleJunk.isNonCourseText(line) { continue }
            if OCRCleanup.looksLikePersonNameOnly(line) {
                if teacher.isEmpty { teacher = line }
                continue
            }
            nameParts.append(line)
        }

        var name = OCRCleanup.sanitizeCourseName(OCRTextJoiner.join(nameParts))
        name = name.replacingOccurrences(of: #"@.+$"#, with: "", options: .regularExpression)
        if teacher.isEmpty, let split = peelTrailingTeacher(from: name) {
            name = split.name
            teacher = split.teacher
        }
        teacher = OCRCleanup.sanitizeTeacher(teacher)
        classroom = OCRCleanup.sanitizeClassroom(classroom)
        guard name.count >= 2, !OCRCleanup.isBogusCourseName(name),
              !ScheduleJunk.isNonCourseText(name) else { return nil }

        var draft = CourseDraft(name: name, classroom: classroom, teacher: teacher,
                                weekday: weekday, weeks: weeks)
        if let periods = column.periods {
            draft.startPeriod = periods.0
            draft.endPeriod = periods.1
        }
        if let time {
            draft.startMinutes = time.0
            draft.endMinutes = time.1
        }
        draft.complete(with: slots, preferPeriods: column.periods != nil)
        return draft.isValid ? draft : nil
    }

    private static func parsePeriodRange(_ text: String) -> (Int, Int)? {
        let pattern = #"^(?:第\s*)?(\d{1,2})\s*(?:[-－—~～至到]\s*(\d{1,2}))?\s*节?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let a = Range(match.range(at: 1), in: text),
              let start = Int(text[a]), (1...20).contains(start) else { return nil }
        let end: Int
        if match.range(at: 2).location != NSNotFound, let b = Range(match.range(at: 2), in: text) {
            end = Int(text[b]) ?? start
        } else {
            end = start
        }
        guard end >= start, end <= 20 else { return nil }
        return (start, end)
    }

    private static func parseTimeRange(_ text: String) -> (Int, Int)? {
        let pattern = #"(\d{1,2})[:：](\d{2})\s*[-－—~～至到]\s*(\d{1,2})[:：](\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 5 else { return nil }
        let values = (1...4).compactMap { index -> Int? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Int(text[range])
        }
        guard values.count == 4, values[0] < 24, values[2] < 24,
              values[1] < 60, values[3] < 60 else { return nil }
        let start = values[0] * 60 + values[1]
        let end = values[2] * 60 + values[3]
        return end > start ? (start, end) : nil
    }

    private static func extractClassroomFragment(from text: String) -> (value: String, range: NSRange)? {
        let pattern = #"(?:[东南西北]?[\p{Han}]{1,8}(?:楼|馆|机房|教室|实验室)[\p{Han}A-Za-z0-9\-－—]*\s*[A-Za-z]?\-?\d{2,5})|(?:\b[A-Za-z]\-?\d{2,4}\b)|(?:\b\d{3,5}室\b)|(?:体育馆|操场|田径场)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return (String(text[range]), match.range)
    }

    private static func splitInlineTeacher(_ text: String) -> (course: String, teacher: String)? {
        let pattern = #"^(.*?)(?:任课教师|教师|授课)[:：]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let courseRange = Range(match.range(at: 1), in: text),
              let teacherRange = Range(match.range(at: 2), in: text) else { return nil }
        return (
            String(text[courseRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(text[teacherRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func peelTrailingTeacher(from raw: String) -> (name: String, teacher: String)? {
        let characters = Array(raw)
        for length in [3, 2] where characters.count > length + 2 {
            let suffix = String(characters.suffix(length))
            let prefix = String(characters.dropLast(length))
            if OCRCleanup.looksLikePersonNameOnly(suffix), prefix.count >= 3 {
                return (prefix, suffix)
            }
        }
        return nil
    }

    private static func isBuildingOnly(_ text: String) -> Bool {
        text.range(of: #"^[东南西北]?[\p{Han}A-Za-z0-9]{1,10}(?:楼|馆|教|室|区|院|中心)$"#,
                   options: .regularExpression) != nil
    }

    private static func isRoomNumber(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z]?\-?\d{2,5}[A-Za-z]?$"#, options: .regularExpression) != nil
    }

    private static func isClassroom(_ text: String) -> Bool {
        text.range(of: #"(?:[东南西北]?[\p{Han}]{1,8}(?:楼|馆|机房|教室|实验室)[\p{Han}A-Za-z0-9\-－—]*\s*[A-Za-z]?\-?\d{2,5})|(?:\b[A-Za-z]\-?\d{2,4}\b)|(?:\b\d{3,5}室\b)|体育馆|操场|田径场"#,
                   options: .regularExpression) != nil
    }

    private static func isDayLabel(_ text: String) -> Bool {
        guard text.count <= 10 else { return false }
        return WeekdayName.detect(in: text, allowBare: false) != nil
            || (text.count == 1 && WeekdayName.detect(in: text, allowBare: true) != nil)
    }

    private static func deduplicate(_ drafts: [CourseDraft]) -> [CourseDraft] {
        var seen = Set<String>()
        return drafts.filter { seen.insert($0.dedupeKey).inserted }
            .sorted { ($0.weekday, $0.startPeriod, $0.startMinutes) < ($1.weekday, $1.startPeriod, $1.startMinutes) }
    }
}
