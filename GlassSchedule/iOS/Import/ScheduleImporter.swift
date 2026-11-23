import Foundation

enum ParseEngine {
    case appleIntelligence, rules, calendar

    var label: String {
        switch self {
        case .appleIntelligence: "Apple 智能识别"
        case .rules: "本地规则识别"
        case .calendar: "日历文件导入"
        }
    }

    var symbol: String {
        switch self {
        case .appleIntelligence: "apple.intelligence"
        case .rules: "text.viewfinder"
        case .calendar: "calendar"
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
        let aiInput = [layout, document.items.isEmpty ? document.plainText : ""].filter { !$0.isEmpty }.joined(separator: "\n")

        if SharedSettings.useAppleIntelligence && AIScheduleExtractor.isAvailable {
            do {
                let drafts = try await AIScheduleExtractor.extract(from: aiInput, slots: slots)
                if !drafts.isEmpty { return ImportOutcome(drafts: drafts, engine: .appleIntelligence) }
            } catch {
                print("Apple 智能识别失败，改用本地规则：\(error)")
            }
        }

        var drafts = GridHeuristicParser.parse(document.items, slots: slots)
        if drafts.isEmpty {
            let rowsText = Set(document.items.map(\.page)).sorted()
                .flatMap { page in LayoutRows.group(document.items.filter { $0.page == page }) }
                .map { $0.map(\.text).joined(separator: " ") }
                .joined(separator: "\n")
            drafts = LineHeuristicParser.parse(document.plainText + "\n" + rowsText, slots: slots)
        }
        var seen = Set<String>()
        return ImportOutcome(drafts: drafts.filter { seen.insert($0.dedupeKey).inserted }, engine: .rules)
    }
}
