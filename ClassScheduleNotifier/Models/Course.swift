import Foundation

public enum Weekday: Int, Codable, CaseIterable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    public var title: String {
        switch self {
        case .monday: return "周一"
        case .tuesday: return "周二"
        case .wednesday: return "周三"
        case .thursday: return "周四"
        case .friday: return "周五"
        case .saturday: return "周六"
        case .sunday: return "周日"
        }
    }
}

public struct Course: Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let teacher: String
    public let location: String
    public let weekday: Weekday
    public let startTime: Date
    public let endTime: Date
    public let weeks: [Int] // 周数列表，例如 [1,2,3,...,16]
    public let isRecurring: Bool
    public let notes: String
    public let colorHex: String

    public init(
        id: UUID = UUID(),
        name: String,
        teacher: String = "",
        location: String = "",
        weekday: Weekday,
        startTime: Date,
        endTime: Date,
        weeks: [Int] = Array(1...20),
        isRecurring: Bool = true,
        notes: String = "",
        colorHex: String = "#5B8DEF"
    ) {
        self.id = id
        self.name = name
        self.teacher = teacher
        self.location = location
        self.weekday = weekday
        self.startTime = startTime
        self.endTime = endTime
        self.weeks = weeks.isEmpty ? Array(1...20) : weeks.sorted()
        self.isRecurring = isRecurring
        self.notes = notes
        self.colorHex = colorHex
    }

    public var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    public var weeksText: String {
        if weeks.count > 10 {
            return "\(weeks.first ?? 1)-\(weeks.last ?? 20)周"
        }
        return weeks.map(String.init).joined(separator: ",") + "周"
    }
}
