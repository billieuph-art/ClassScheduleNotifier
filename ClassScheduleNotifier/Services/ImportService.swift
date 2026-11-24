import Foundation
import Vision
import UIKit

enum ImportService {
    // MARK: - CSV

    static func parseCSV(_ text: String) throws -> [Course] {
        let rows = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard rows.count > 1 else { return [] }
        let headers = parseCSVRow(rows[0]).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let required = ["name", "weekday", "start", "end"]
        guard required.allSatisfy(headers.contains) else { throw ImportError.invalidHeader }

        var result: [Course] = []
        for row in rows.dropFirst() {
            let values = parseCSVRow(row)
            guard values.count == headers.count else { continue }
            let item = Dictionary(uniqueKeysWithValues: zip(headers, values))
            guard
                let name = item["name"], !name.trimmingCharacters(in: .whitespaces).isEmpty,
                let weekdayValue = item["weekday"].flatMap(Int.init),
                let weekday = Weekday(rawValue: weekdayValue),
                let start = item["start"].flatMap(parseTime),
                let end = item["end"].flatMap(parseTime),
                end > start
            else { continue }

            result.append(Course(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: item["teacher"] ?? "",
                location: item["location"] ?? "",
                weekday: weekday,
                startTime: start,
                endTime: end,
                weeks: parseWeeks(item["weeks"] ?? ""),
                notes: item["notes"] ?? ""
            ))
        }
        return result
    }

    // MARK: - Spatial image OCR

    private struct OCRToken {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private struct DayAnchor {
        let weekday: Weekday
        let coordinate: CGFloat
    }

    private struct CellKey: Hashable {
        let weekday: Weekday
        let band: Int
    }

    private struct Cell {
        var tokens: [OCRToken] = []
        var coordinate: CGFloat
    }

    static func parseImage(_ image: UIImage) async throws -> [Course] {
        guard let cgImage = normalizedCGImage(from: image) else { throw ImportError.invalidImage }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.004

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        let tokens = (request.results ?? []).compactMap { observation -> OCRToken? in
            guard let text = observation.topCandidates(1).first?.string
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            let box = observation.boundingBox
            return OCRToken(
                text: normalizeOCRText(text),
                x: box.midX,
                y: 1 - box.midY,
                width: box.width,
                height: box.height
            )
        }

        guard tokens.count >= 3 else { return [] }
        return parseSpatialTokens(tokens)
    }

    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
        return normalized.cgImage
    }

    private static func parseSpatialTokens(_ tokens: [OCRToken]) -> [Course] {
        let anchors = tokens.compactMap { token -> (Weekday, CGFloat)? in
            guard let day = detectWeekday(token.text) else { return nil }
            return (day, 0)
        }
        guard anchors.count >= 2 else { return parseExplicitText(tokens) }

        let xs = anchors.indices.map { index in
            tokens.filter { detectWeekday($0.text) != nil }[index].x
        }
        let ys = tokens.filter { detectWeekday($0.text) != nil }.map(\.y)
        let xSpan = (xs.max() ?? 0) - (xs.min() ?? 0)
        let ySpan = (ys.max() ?? 0) - (ys.min() ?? 0)
        let weekdayAxisIsX = xSpan >= ySpan

        var dayAnchors: [DayAnchor] = []
        for token in tokens {
            guard let day = detectWeekday(token.text) else { continue }
            let coordinate = weekdayAxisIsX ? token.x : token.y
            if !dayAnchors.contains(where: { $0.weekday == day }) {
                dayAnchors.append(DayAnchor(weekday: day, coordinate: coordinate))
            }
        }
        guard dayAnchors.count >= 2 else { return parseExplicitText(tokens) }

        let ordered = dayAnchors.sorted { $0.coordinate < $1.coordinate }
        let otherCoordinate: (OCRToken) -> CGFloat = { weekdayAxisIsX ? $0.y : $0.x }
        let dayCoordinate: (OCRToken) -> CGFloat = { weekdayAxisIsX ? $0.x : $0.y }

        // Estimate timetable bands from all non-header text positions on the time axis.
        let candidateCoordinates = tokens
            .filter { detectWeekday($0.text) == nil }
            .map(otherCoordinate)
            .sorted()
        let bandCenters = clusterCoordinates(candidateCoordinates, tolerance: 0.035)
        guard !bandCenters.isEmpty else { return [] }

        var cells: [CellKey: Cell] = [:]
        var globalTimeLabels: [(CGFloat, (Date, Date))] = []

        for token in tokens where detectWeekday(token.text) == nil {
            let dayPosition = dayCoordinate(token)
            guard let nearestDay = ordered.min(by: {
                abs($0.coordinate - dayPosition) < abs($1.coordinate - dayPosition)
            }), abs(nearestDay.coordinate - dayPosition) <= 0.22 else { continue }

            let coordinate = otherCoordinate(token)
            guard let bandIndex = bandCenters.indices.min(by: {
                abs(bandCenters[$0] - coordinate) < abs(bandCenters[$1] - coordinate)
            }) else { continue }

            if let range = detectTimeRange(token.text) {
                globalTimeLabels.append((coordinate, range))
            }

            let key = CellKey(weekday: nearestDay.weekday, band: bandIndex)
            var cell = cells[key] ?? Cell(tokens: [], coordinate: bandCenters[bandIndex])
            cell.tokens.append(token)
            cells[key] = cell
        }

        var courses: [Course] = []
        for (key, cell) in cells {
            let text = cell.tokens.map(\.text).joined(separator: "\n")
            guard let name = extractCourseName(from: text) else { continue }

            let localTime = cell.tokens.compactMap { detectTimeRange($0.text) }.first
            let nearestGlobalTime = globalTimeLabels.min {
                abs($0.0 - cell.coordinate) < abs($1.0 - cell.coordinate)
            }?.1
            guard let time = localTime ?? nearestGlobalTime, time.1 > time.0 else { continue }

            let teacher = extractTeacher(from: text, courseName: name)
            let location = extractLocation(from: text)
            let weeks = detectWeeks(text) ?? Array(1...16)

            courses.append(Course(
                name: name,
                teacher: teacher,
                location: location,
                weekday: key.weekday,
                startTime: time.0,
                endTime: time.1,
                weeks: weeks
            ))
        }

        return deduplicate(courses).sorted {
            if $0.weekday.rawValue != $1.weekday.rawValue {
                return $0.weekday.rawValue < $1.weekday.rawValue
            }
            return $0.startTime < $1.startTime
        }
    }

    private static func clusterCoordinates(_ values: [CGFloat], tolerance: CGFloat) -> [CGFloat] {
        guard !values.isEmpty else { return [] }
        var groups: [[CGFloat]] = []
        for value in values {
            if let last = groups.indices.last,
               abs((groups[last].reduce(0, +) / CGFloat(groups[last].count)) - value) <= tolerance {
                groups[last].append(value)
            } else {
                groups.append([value])
            }
        }
        return groups.map { $0.reduce(0, +) / CGFloat($0.count) }
    }

    private static func parseExplicitText(_ tokens: [OCRToken]) -> [Course] {
        let text = tokens.sorted { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }
            .map(\.text).joined(separator: "\n")
        return parseTextLines(text)
    }

    // Kept as a conservative fallback for text-like timetable exports.
    static func parseTextLines(_ text: String) -> [Course] {
        let lines = text.components(separatedBy: .newlines)
            .map { normalizeOCRText($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var result: [Course] = []
        for line in lines {
            guard let day = detectWeekday(line),
                  let time = detectTimeRange(line),
                  let name = extractCourseName(from: line) else { continue }
            result.append(Course(
                name: name,
                teacher: extractTeacher(from: line, courseName: name),
                location: extractLocation(from: line),
                weekday: day,
                startTime: time.0,
                endTime: time.1,
                weeks: detectWeeks(line) ?? Array(1...16)
            ))
        }
        return result
    }

    // MARK: - Field extraction

    private static func normalizeOCRText(_ text: String) -> String {
        text.replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "－", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "～", with: "~")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func detectWeekday(_ text: String) -> Weekday? {
        let patterns: [(String, Weekday)] = [
            ("星期一|周一|礼拜一|Monday|Mon", .monday),
            ("星期二|周二|礼拜二|Tuesday|Tue", .tuesday),
            ("星期三|周三|礼拜三|Wednesday|Wed", .wednesday),
            ("星期四|周四|礼拜四|Thursday|Thu", .thursday),
            ("星期五|周五|礼拜五|Friday|Fri", .friday),
            ("星期六|周六|礼拜六|Saturday|Sat", .saturday),
            ("星期日|星期天|周日|周天|礼拜日|礼拜天|Sunday|Sun", .sunday)
        ]
        for (pattern, day) in patterns {
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return day
            }
        }
        return nil
    }

    private static func detectTimeRange(_ text: String) -> (Date, Date)? {
        let pattern = #"(?<!\d)(\d{1,2})\s*[:：.]\s*(\d{2})\s*[-~至到]\s*(\d{1,2})\s*[:：.]\s*(\d{2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 5 else { return nil }
        let values = (1...4).map { Int((text as NSString).substring(with: match.range(at: $0))) ?? -1 }
        guard values[0] < 24, values[2] < 24,
              values[1] < 60, values[3] < 60,
              values[0] >= 0, values[2] >= 0,
              values[1] >= 0, values[3] >= 0 else { return nil }
        let start = makeTime(hour: values[0], minute: values[1])
        let end = makeTime(hour: values[2], minute: values[3])
        guard end > start else { return nil }
        return (start, end)
    }

    private static func makeTime(hour: Int, minute: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        ) ?? Date(timeIntervalSince1970: 0)
    }

    private static func extractCourseName(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let candidates = lines.filter {
            detectWeekday($0) == nil && detectTimeRange($0) == nil &&
            detectWeeks($0) == nil && !isTeacherLabel($0) && !isLocation($0)
        }
        return candidates.first(where: { $0.count >= 2 && !isLikelyTeacherName($0) })?
            .trimmingCharacters(in: CharacterSet(charactersIn: "[](){}·,，;；"))
    }

    private static func extractTeacher(from text: String, courseName: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        for line in lines where isTeacherLabel(line) {
            return line.replacingOccurrences(
                of: ".*?(教师|任课教师|老师)[:：]?", with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let candidates = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                $0 != courseName && detectWeekday($0) == nil && detectTimeRange($0) == nil &&
                detectWeeks($0) == nil && !isLocation($0) && isLikelyTeacherName($0)
            }
        return candidates.first ?? ""
    }

    private static func extractLocation(from text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { isLocation($0) }) ?? ""
    }

    private static func isTeacherLabel(_ text: String) -> Bool {
        text.contains("教师") || text.contains("任课") || text.contains("老师")
    }

    private static func isLikelyTeacherName(_ text: String) -> Bool {
        text.range(of: #"^[\p{Han}]{2,4}$"#, options: .regularExpression) != nil
    }

    private static func isLocation(_ text: String) -> Bool {
        text.range(of: #"(教室|教学楼|实验楼|\d{1,3}[-楼栋层室]|[A-Z]{1,3}\d{2,4}|\d{2,4}室)"#,
                   options: .regularExpression) != nil
    }

    private static func detectWeeks(_ text: String) -> [Int]? {
        let pattern = #"(?:(\d{1,2})\s*[-~至]\s*(\d{1,2})\s*周|第?(\d{1,2})\s*周)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return nil }
        var weeks: [Int] = []
        for match in matches {
            if match.range(at: 1).location != NSNotFound,
               match.range(at: 2).location != NSNotFound {
                let start = Int((text as NSString).substring(with: match.range(at: 1))) ?? 1
                let end = Int((text as NSString).substring(with: match.range(at: 2))) ?? start
                if start > 0 && end >= start && end <= 30 { weeks.append(contentsOf: start...end) }
            } else if match.range(at: 3).location != NSNotFound {
                let week = Int((text as NSString).substring(with: match.range(at: 3))) ?? 0
                if (1...30).contains(week) { weeks.append(week) }
            }
        }
        return weeks.isEmpty ? nil : Array(Set(weeks)).sorted()
    }

    private static func deduplicate(_ courses: [Course]) -> [Course] {
        var seen = Set<String>()
        return courses.filter { course in
            let key = "\(course.weekday.rawValue)|\(course.name)|\(course.startTime.timeIntervalSince1970)|\(course.location)"
            return seen.insert(key).inserted
        }
    }

    // MARK: - CSV helpers

    private static func parseWeeks(_ value: String) -> [Int] {
        if value.isEmpty { return Array(1...16) }
        if value.contains("-") {
            let parts = value.components(separatedBy: "-")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2, parts[0] > 0, parts[1] >= parts[0] {
                return Array(parts[0]...parts[1])
            }
        }
        return value.components(separatedBy: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var iterator = line.makeIterator()
        while let character = iterator.next() {
            if character == "\"" {
                if quoted { field.append(character) }
                quoted.toggle()
            } else if character == "," && !quoted {
                fields.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields.map { $0.replacingOccurrences(of: "\"\"", with: "\"") }
    }

    private static func parseTime(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "H:mm"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    enum ImportError: LocalizedError {
        case invalidHeader
        case invalidImage
        var errorDescription: String? {
            switch self {
            case .invalidHeader: return "CSV 表头必须包含 name、weekday、start、end"
            case .invalidImage: return "无法读取图片"
            }
        }
    }
}
