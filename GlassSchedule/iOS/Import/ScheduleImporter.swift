import Foundation

enum ParseEngine {
    case appleIntelligence, rules, calendar, mixed

    var label: String {
        switch self {
        case .appleIntelligence: "Apple 智能识别"
        case .rules: "本地规则识别"
        case .calendar: "日历文件导入"
        case .mixed: "智能 + 规则联合识别"
        }
    }

    var symbol: String {
        switch self {
        case .appleIntelligence: "apple.intelligence"
        case .rules: "text.viewfinder"
        case .calendar: "calendar"
        case .mixed: "sparkles"
        }
    }
}

struct ImportOutcome {
    var drafts: [CourseDraft]
    var engine: ParseEngine
}

enum ScheduleImporter {
    static func parse(_ document: ExtractedDocument) async -> ImportOutcome {
        let slots = SharedSettings.periodSlots
        if !document.icsCourses.isEmpty {
            return ImportOutcome(drafts: document.icsCourses, engine: .calendar)
        }

        let layout = TextExtractor.layoutDescription(document.items)
        let rowsText = Set(document.items.map(\.page)).sorted()
            .flatMap { page in LayoutRows.group(document.items.filter { $0.page == page }) }
            .map { $0.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
        let plain = [document.plainText, rowsText].filter { !$0.isEmpty }.joined(separator: "\n")
        let aiInput = [layout, document.items.isEmpty ? document.plainText : ""].filter { !$0.isEmpty }.joined(separator: "\n")

        let ruleDrafts = ruleBasedDrafts(items: document.items, plain: plain, slots: slots)

        var aiDrafts: [CourseDraft] = []
        if SharedSettings.useAppleIntelligence && AIScheduleExtractor.isAvailable && !aiInput.isEmpty {
            do {
                aiDrafts = try await AIScheduleExtractor.extract(from: aiInput, slots: slots)
            } catch {
                print("Apple 智能识别失败，改用本地规则：\(error)")
            }
        }

        if !aiDrafts.isEmpty && !ruleDrafts.isEmpty {
            let merged = merge(primary: aiDrafts, secondary: ruleDrafts)
            return ImportOutcome(drafts: merged, engine: .mixed)
        }
        if !aiDrafts.isEmpty {
            return ImportOutcome(drafts: dedupe(aiDrafts), engine: .appleIntelligence)
        }
        return ImportOutcome(drafts: dedupe(ruleDrafts), engine: .rules)
    }

    private static func ruleBasedDrafts(items: [TextItem], plain: String, slots: [PeriodSlot]) -> [CourseDraft] {
        var drafts = GridHeuristicParser.parse(items, slots: slots)
        if drafts.count < 2 {
            let lineDrafts = LineHeuristicParser.parse(plain, slots: slots)
            drafts = merge(primary: drafts, secondary: lineDrafts)
        }
        return drafts
    }

    /// 以主结果为准，用次结果补教室、教师、周次、节次等空字段；并补上主结果漏掉的课。
    private static func merge(primary: [CourseDraft], secondary: [CourseDraft]) -> [CourseDraft] {
        var result = primary
        for index in result.indices {
            guard let match = secondary.first(where: { similar($0, result[index]) }) else { continue }
            if result[index].classroom.isEmpty { result[index].classroom = match.classroom }
            if result[index].teacher.isEmpty { result[index].teacher = match.teacher }
            if result[index].weeks.isEmpty { result[index].weeks = match.weeks }
            if result[index].startPeriod <= 0 { result[index].startPeriod = match.startPeriod }
            if result[index].endPeriod <= 0 { result[index].endPeriod = match.endPeriod }
            if result[index].endMinutes <= result[index].startMinutes {
                result[index].startMinutes = match.startMinutes
                result[index].endMinutes = match.endMinutes
            }
        }
        for draft in secondary where !result.contains(where: { similar($0, draft) }) {
            result.append(draft)
        }
        return dedupe(result).sorted { ($0.weekday, $0.startPeriod, $0.startMinutes) < ($1.weekday, $1.startPeriod, $1.startMinutes) }
    }

    private static func similar(_ a: CourseDraft, _ b: CourseDraft) -> Bool {
        guard a.weekday == b.weekday else { return false }
        if abs(a.startPeriod - b.startPeriod) <= 1 && a.startPeriod > 0 && b.startPeriod > 0 { return namesSimilar(a.name, b.name) }
        if abs(a.startMinutes - b.startMinutes) <= 20 && a.startMinutes > 0 && b.startMinutes > 0 { return namesSimilar(a.name, b.name) }
        return false
    }

    private static func namesSimilar(_ a: String, _ b: String) -> Bool {
        let left = a.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        let right = b.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        if left.isEmpty || right.isEmpty { return false }
        if left == right || left.contains(right) || right.contains(left) { return true }
        return left.prefix(2) == right.prefix(2) && abs(left.count - right.count) <= 4
    }

    private static func dedupe(_ drafts: [CourseDraft]) -> [CourseDraft] {
        var seen = Set<String>()
        return drafts.filter { seen.insert($0.dedupeKey).inserted }
    }
}
