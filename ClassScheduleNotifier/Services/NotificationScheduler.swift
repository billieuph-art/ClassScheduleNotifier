import Foundation

public enum ImportService {
    public static func parseCSV(_ csvText: String) -> [Course] {
        let lines = csvText.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        var courses: [Course] = []
        let header = lines[0].components(separatedBy: ",")

        for row in lines.dropFirst() {
            let values = row.components(separatedBy: ",")
            guard values.count >= 6 else { continue }

            let dictionary = Dictionary(uniqueKeysWithValues: zip(header, values))
            guard let name = dictionary["name"],
                  let location = dictionary["location"],
                  let weekdayRaw = dictionary["weekday"],
                  let weekday = Weekday(rawValue: Int(weekdayRaw) ?? 1),
                  let startText = dictionary["start"],
                  let endText = dictionary["end"] else { continue }

            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let start = formatter.date(from: startText) ?? Date()
            let end = formatter.date(from: endText) ?? Date()

            let baseDate = Date()
            let calendar = Calendar(identifier: .gregorian)
            let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: baseDate)
            var targetComponents = DateComponents(year: startComponents.year, month: startComponents.month, day: startComponents.day, hour: calendar.component(.hour, from: start), minute: calendar.component(.minute, from: start))
            targetComponents.weekday = weekday.rawValue
            targetComponents.second = 0

            let mappedStartDate = calendar.date(from: targetComponents) ?? baseDate
            let mappedEndDate = mappedStartDate.addingTimeInterval(max(end.timeIntervalSince(start), 60 * 30))

            let course = Course(
                name: name,
                teacher: dictionary["teacher"] ?? "",
                location: location,
                weekday: weekday,
                startTime: mappedStartDate,
                endTime: mappedEndDate,
                notes: dictionary["notes"] ?? ""
            )
            courses.append(course)
        }

        return courses
    }

    public static func parseICS(_ icsText: String) -> [Course] {
        var courses: [Course] = []
        let lines = icsText.components(separatedBy: .newlines)

        var current: [String: String] = [:]
        for line in lines {
            if line.hasPrefix("BEGIN:VEVENT") {
                current.removeAll(keepingCapacity: true)
            } else if line.hasPrefix("END:VEVENT") {
                if let summary = current["SUMMARY"],
                   let start = current["DTSTART"],
                   let end = current["DTEND"],
                   let location = current["LOCATION"] {
                    let startDate = parseICSDate(start)
                    let endDate = parseICSDate(end)
                    let weekday = weekdayFromDate(startDate)
                    let course = Course(name: summary, teacher: "", location: location, weekday: weekday, startTime: startDate, endTime: endDate)
                    courses.append(course)
                }
            } else {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let key = String(parts[0])
                let value = String(parts[1])
                current[key] = value
            }
        }

        return courses
    }

    private static func parseICSDate(_ raw: String) -> Date {
        let trimmed = raw.replacingOccurrences(of: "T", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMddHHmmssZ"

        if let parsed = formatter.date(from: trimmed + "Z") {
            return parsed
        }

        formatter.dateFormat = "yyyyMMdd"
        if let parsed = formatter.date(from: trimmed) {
            return parsed
        }

        return Date()
    }

    private static func weekdayFromDate(_ date: Date) -> Weekday {
        let calendar = Calendar(identifier: .gregorian)
        let value = calendar.component(.weekday, from: date)
        return Weekday(rawValue: value) ?? .monday
    }
}
