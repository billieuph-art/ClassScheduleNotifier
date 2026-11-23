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
        let headers = parseCSVRow(rows[0]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let required = ["name", "weekday", "start", "end"]
        guard required.allSatisfy(headers.contains) else {
            throw ImportError.invalidHeader
        }

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

            let weeks = parseWeeks(item["weeks"] ?? "")
            result.append(Course(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: item["teacher"] ?? "",
                location: item["location"] ?? "",
                weekday: weekday,
                startTime: start,
                endTime: end,
                weeks: weeks,
                notes: item["notes"] ?? ""
            ))
        }
        return result
    }

    // MARK: - Image OCR Import
    static func parseImage(_ image: UIImage) async throws -> [Course] {
        guard let cgImage = image.cgImage else {
            throw ImportError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        return parseTextLines(lines)
    }

    // MARK: - Text Parsing (heuristic for Chinese course tables)
    static func parseTextLines(_ text: String) -> [Course] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var courses: [Course] = []
        var current: PartialCourse?

        for line in lines {
            if let weekday = detectWeekday(line) {
                // 新的一天开始，先保存上一个
                if let partial = current, partial.isValid {
                    courses.append(contentsOf: partial.buildCourses())
                }
                current = PartialCourse(weekday: weekday)
                continue
            }

            if current == nil {
                // 尝试从行内直接解析
                if let partial = tryParseCourseLine(line) {
                    courses.append(contentsOf: partial.buildCourses())
                }
                continue
            }

            // 累积信息
            if let timeRange = detectTimeRange(line) {
                current?.startTime = timeRange.0
                current?.endTime = timeRange.1
            } else if let weeks = detectWeeks(line) {
                current?.weeks = weeks
            } else if detectTeacher(line) != nil {
                current?.teacher = detectTeacher(line) ?? ""
            } else if detectLocation(line) != nil {
                current?.location = detectLocation(line) ?? ""
            } else if line.count >= 2 && !isMetadata(line) {
                // 课程名
                if current?.name.isEmpty == true {
                    current?.name = line
                } else {
                    current?.name += " " + line
                }
            }
        }

        if let partial = current, partial.isValid {
            courses.append(contentsOf: partial.buildCourses())
        }

        return courses
    }

    // MARK: - Helpers
    private struct PartialCourse {
        var name = ""
        var teacher = ""
        var location = ""
        var weekday: Weekday
        var startTime: Date?
        var endTime: Date?
        var weeks: [Int] = Array(1...16)

        var isValid: Bool {
            !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            startTime != nil && endTime != nil && (endTime ?? .distantPast) > (startTime ?? .distantFuture)
        }

        func buildCourses() -> [Course] {
            guard isValid, let start = startTime, let end = endTime else { return [] }
            return [Course(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: teacher,
                location: location,
                weekday: weekday,
                startTime: start,
                endTime: end,
                weeks: weeks
            )]
        }
    }

    private static func tryParseCourseLine(_ line: String) -> PartialCourse? {
        // 简单单行模式匹配，例如：高等数学 张三 1-16周 周一 08:00-09:40 A101
        var partial: PartialCourse?
        if let wd = detectWeekday(line) {
            partial = PartialCourse(weekday: wd)
            partial?.name = line.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
                .first ?? ""
        }
        return partial
    }

    private static func detectWeekday(_ text: String) -> Weekday? {
        let map: [String: Weekday] = [
            "周一": .monday, "星期一": .monday, "Mon": .monday,
            "周二": .tuesday, "星期二": .tuesday,
            "周三": .wednesday, "星期三": .wednesday,
            "周四": .thursday, "星期四": .thursday,
            "周五": .friday, "星期五": .friday,
            "周六": .saturday, "星期六": .saturday,
            "周日": .sunday, "星期日": .sunday, "周天": .sunday
        ]
        for (key, value) in map where text.contains(key) {
            return value
        }
        return nil
    }

    private static func detectTimeRange(_ text: String) -> (Date, Date)? {
        let patterns = [
            #"(\d{1,2})[:：](\d{2})\s*[-~－]\s*(\d{1,2})[:：](\d{2})"#,
            #"(\d{1,2})\s*[-~－]\s*(\d{1,2})\s*节"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                // 简化：假设第一节 8:00，每节 45 分钟 + 10 分钟课间
                if match.numberOfRanges >= 3 {
                    let startHour = Int((text as NSString).substring(with: match.range(at: 1))) ?? 8
                    let endHour = Int((text as NSString).substring(with: match.range(at: 3))) ?? startHour + 1
                    let start = Calendar.current.date(from: DateComponents(hour: startHour, minute: 0)) ?? Date()
                    let end = Calendar.current.date(from: DateComponents(hour: endHour, minute: 40)) ?? Date()
                    return (start, end)
                }
            }
        }
        return nil
    }

    private static func detectWeeks(_ text: String) -> [Int]? {
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*[-~－]\s*(\d+)\s*周"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            let start = Int((text as NSString).substring(with: match.range(at: 1))) ?? 1
            let end = Int((text as NSString).substring(with: match.range(at: 2))) ?? 16
            return Array(start...end)
        }
        if text.contains("周") {
            return Array(1...16)
        }
        return nil
    }

    private static func detectTeacher(_ text: String) -> String? {
        if text.contains("教师") || text.contains("老师") {
            return text.replacingOccurrences(of: "教师[:：]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "老师", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func detectLocation(_ text: String) -> String? {
        if text.range(of: #"[A-Za-z0-9]+号?"#, options: .regularExpression) != nil ||
           text.contains("教室") || text.contains("教学楼") {
            return text
        }
        return nil
    }

    private static func isMetadata(_ text: String) -> Bool {
        detectWeekday(text) != nil || detectTimeRange(text) != nil || detectWeeks(text) != nil ||
        detectTeacher(text) != nil || detectLocation(text) != nil
    }

    private static func parseWeeks(_ value: String) -> [Int] {
        if value.isEmpty { return Array(1...16) }
        // 简单支持 1-16 或 1,2,3
        if value.contains("-") {
            let parts = value.components(separatedBy: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 { return Array(parts[0]...parts[1]) }
        }
        return value.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
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
        formatter.timeZone = .current
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
