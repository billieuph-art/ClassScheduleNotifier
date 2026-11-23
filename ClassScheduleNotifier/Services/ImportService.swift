import Foundation

enum ImportService {
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

            result.append(Course(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: item["teacher"] ?? "",
                location: item["location"] ?? "",
                weekday: weekday,
                startTime: start,
                endTime: end,
                notes: item["notes"] ?? ""
            ))
        }
        return result
    }

    private static func parseCSVRow(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if quoted {
                    // CSV escaped quote: ""
                    field.append(character)
                }
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
        var errorDescription: String? {
            "CSV 表头必须包含 name、weekday、start、end；weekday 使用 1（周一）至 7（周日）。"
        }
    }
}