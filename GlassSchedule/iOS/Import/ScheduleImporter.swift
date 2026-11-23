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
    /// 截图顶栏识别到的教学周，如「第13周」→ 13；没有则为 nil。
    var detectedTeachingWeek: Int? = nil
}

enum ScheduleImporter {
    static func parse(_ document: ExtractedDocument) async -> ImportOutcome {
        let slots = SharedSettings.periodSlots
        if !document.icsCourses.isEmpty {
            return ImportOutcome(drafts: document.icsCourses, engine: .calendar, detectedTeachingWeek: nil)
        }

        let layout = TextExtractor.layoutDescription(document.items)
        let rowsText = Set(document.items.map(\.page)).sorted()
            .flatMap { page in LayoutRows.group(document.items.filter { $0.page == page }) }
            // 行内无空格拼接，避免把「水利工 程造价」拆开
            .map { OCRTextJoiner.join($0.map(\.text)) }
            .joined(separator: "\n")
        let plain = [document.plainText, rowsText].filter { !$0.isEmpty }.joined(separator: "\n")
        let aiInput = [layout, document.items.isEmpty ? document.plainText : ""].filter { !$0.isEmpty }.joined(separator: "\n")

        let detectedWeek = TeachingWeekDetector.currentWeek(in: plain)
        // 顶栏「第13周 (本周)」→ 对齐学期第 1 周起点，避免周数显示偏差
        if let week = detectedWeek,
           let start = SemesterCalendar.semesterStart(forTeachingWeek: week) {
            let shown = SemesterCalendar.weekNumber(of: .now, semesterStart: SharedSettings.semesterStart)
            if shown != week {
                SharedSettings.semesterStart = start
            }
        }

        let ruleDrafts = ruleBasedDrafts(items: document.items, plain: plain, slots: slots)
        let ruleScore = quality(ruleDrafts)
        let strongGrid = ruleDrafts.count >= 2 && ruleScore >= 12
            && ruleDrafts.filter { !$0.classroom.isEmpty }.count >= max(1, ruleDrafts.count / 2)

        var aiDrafts: [CourseDraft] = []
        // 超星网格规则已经很完整时，跳过 AI，避免「程造价 / 编造周次」污染
        // 无 Apple 智能时仅走本地 Vision OCR + 规则，仍可识别网格课表
        if !strongGrid, SharedSettings.useAppleIntelligence && AIScheduleExtractor.isAvailable && !aiInput.isEmpty {
            do {
                aiDrafts = try await AIScheduleExtractor.extract(from: aiInput, slots: slots)
            } catch {
                print("Apple 智能识别失败，改用本地规则：\(error)")
            }
        }
        let aiScore = quality(aiDrafts)

        let drafts: [CourseDraft]
        let engine: ParseEngine
        if strongGrid || (ruleScore >= 8 && ruleScore >= aiScore) {
            if !aiDrafts.isEmpty, !strongGrid {
                drafts = merge(primary: ruleDrafts, secondary: aiDrafts, fillWeeks: false)
                engine = .mixed
            } else {
                drafts = dedupe(ruleDrafts)
                engine = .rules
            }
        } else if aiScore >= 8 && !aiDrafts.isEmpty {
            if !ruleDrafts.isEmpty {
                drafts = merge(primary: aiDrafts, secondary: ruleDrafts, fillWeeks: true)
                engine = .mixed
            } else {
                drafts = dedupe(aiDrafts)
                engine = .appleIntelligence
            }
        } else if !ruleDrafts.isEmpty {
            drafts = dedupe(ruleDrafts)
            engine = .rules
        } else {
            drafts = dedupe(aiDrafts)
            engine = .appleIntelligence
        }

        // 截图是「某一周」的课表时，默认只挂到该周，绝不当成全学期每周都上
        var scoped = drafts
        applyWeekScope(.defaultScope(detectedWeek: detectedWeek), detectedWeek: detectedWeek, to: &scoped)
        return ImportOutcome(drafts: scoped, engine: engine, detectedTeachingWeek: detectedWeek)
    }

    /// 把周次范围写回草稿。
    /// - overwriteExplicit: false 时保留格子里已写明的周次（如 1-8,10-16）；true 时按用户选择的单/双周覆盖。
    static func applyWeekScope(_ scope: ImportWeekScope, detectedWeek: Int?, to drafts: inout [CourseDraft],
                               overwriteExplicit: Bool = false) {
        let weeks = scope.weeks(detectedWeek: detectedWeek)
        for index in drafts.indices {
            if !overwriteExplicit, !drafts[index].weeks.isEmpty { continue }
            drafts[index].weeks = weeks
        }
    }

    private static func ruleBasedDrafts(items: [TextItem], plain: String, slots: [PeriodSlot]) -> [CourseDraft] {
        var drafts = GridHeuristicParser.parse(items, slots: slots)
        let lineDrafts = LineHeuristicParser.parse(plain, slots: slots)
        if drafts.isEmpty {
            drafts = lineDrafts
        } else if !lineDrafts.isEmpty {
            drafts = merge(primary: drafts, secondary: lineDrafts, fillWeeks: true)
        }
        return drafts
    }

    /// 分数越高表示课名越完整、教室越像真的、节次与时间一致。
    private static func quality(_ drafts: [CourseDraft]) -> Int {
        drafts.reduce(0) { score, draft in
            var s = 0
            if draft.name.count >= 4 { s += 3 }
            if draft.name.count >= 6 { s += 3 }
            if draft.name.count >= 8 { s += 2 }
            if !draft.classroom.isEmpty { s += 4 }
            if draft.classroom.range(of: #"^\d{3,5}$"#, options: .regularExpression) != nil { s += 2 }
            if draft.name.contains("@") { s -= 8 }
            if draft.name.count <= 3 { s -= 5 }
            // 残片课名（如「程造价」）大幅扣分
            if draft.name.count <= 4 && draft.classroom.isEmpty { s -= 4 }
            if draft.startPeriod >= 1, draft.endPeriod >= draft.startPeriod { s += 2 }
            if let mapped = PeriodTable.periods(startMinutes: draft.startMinutes, endMinutes: draft.endMinutes, in: SharedSettings.periodSlots),
               mapped.0 == draft.startPeriod, mapped.1 == draft.endPeriod {
                s += 3
            }
            return score + max(0, s)
        }
    }

    private static func merge(primary: [CourseDraft], secondary: [CourseDraft], fillWeeks: Bool) -> [CourseDraft] {
        var result = primary
        for index in result.indices {
            guard let match = secondary.first(where: { similar($0, result[index]) }) else { continue }
            if result[index].classroom.isEmpty { result[index].classroom = match.classroom }
            if result[index].teacher.isEmpty { result[index].teacher = match.teacher }
            // 网格课表格子常无周次；空 = 每周。不要用 AI 编造的 1-8,10-16 覆盖。
            if fillWeeks, result[index].weeks.isEmpty, !match.weeks.isEmpty {
                result[index].weeks = match.weeks
            }
            if result[index].name.count < match.name.count, !match.name.contains("@"), match.name.count >= 4 {
                result[index].name = match.name
            }
            if result[index].startPeriod <= 0 { result[index].startPeriod = match.startPeriod }
            if result[index].endPeriod <= 0 { result[index].endPeriod = match.endPeriod }
            if result[index].endMinutes <= result[index].startMinutes {
                result[index].startMinutes = match.startMinutes
                result[index].endMinutes = match.endMinutes
            }
            result[index].complete(with: SharedSettings.periodSlots, preferPeriods: true)
        }
        for draft in secondary where !result.contains(where: { similar($0, draft) }) {
            result.append(draft)
        }
        return dedupe(result).sorted { ($0.weekday, $0.startPeriod, $0.startMinutes) < ($1.weekday, $1.startPeriod, $1.startMinutes) }
    }

    private static func similar(_ a: CourseDraft, _ b: CourseDraft) -> Bool {
        guard a.weekday == b.weekday else { return false }
        let periodClose = a.startPeriod > 0 && b.startPeriod > 0 && abs(a.startPeriod - b.startPeriod) <= 2
        let timeClose = a.startMinutes > 0 && b.startMinutes > 0 && abs(a.startMinutes - b.startMinutes) <= 50
        guard periodClose || timeClose else { return false }
        return namesSimilar(a.name, b.name) || (!a.classroom.isEmpty && a.classroom == b.classroom)
    }

    private static func namesSimilar(_ a: String, _ b: String) -> Bool {
        let left = a.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        let right = b.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        if left.isEmpty || right.isEmpty { return false }
        if left == right || left.contains(right) || right.contains(left) { return true }
        return left.prefix(2) == right.prefix(2) && abs(left.count - right.count) <= 6
    }

    private static func dedupe(_ drafts: [CourseDraft]) -> [CourseDraft] {
        var seen = Set<String>()
        return drafts.filter { seen.insert($0.dedupeKey).inserted }
    }
}
