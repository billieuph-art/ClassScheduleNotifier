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
            .map { row in
                if row.count >= 3 { return row.map(\.text).joined(separator: " ") }
                return OCRTextJoiner.join(row.map(\.text))
            }
            .joined(separator: "\n")
        let plain = [document.plainText, rowsText].filter { !$0.isEmpty }.joined(separator: "\n")
        let aiInput = [layout, document.items.isEmpty ? document.plainText : ""].filter { !$0.isEmpty }.joined(separator: "\n")

        let detectedWeek = TeachingWeekDetector.currentWeek(in: plain)
        if let week = detectedWeek,
           let start = SemesterCalendar.semesterStart(forTeachingWeek: week) {
            let shown = SemesterCalendar.weekNumber(of: .now, semesterStart: SharedSettings.semesterStart)
            if shown != week { SharedSettings.semesterStart = start }
        }

        let ruleDrafts = ruleBasedDrafts(items: document.items, plain: plain, slots: slots)
        let ruleScore = quality(ruleDrafts)
        // 课程数和教室字段完整，不代表整张课表已识别完整。
        // 至少覆盖 3 个不同星期且识别到 4 条课程，才允许跳过 AI 复核；
        // 否则像超星课表只识别出周一、周三两条时，会被错误地当成完整网格。
        let ruleWeekdayCoverage = Set(ruleDrafts.map(\\.weekday)).count
        let strongGrid = ruleDrafts.count >= 4 && ruleWeekdayCoverage >= 3
            && ruleScore >= 12
            && ruleDrafts.filter { !$0.classroom.isEmpty }.count >= max(2, (ruleDrafts.count + 1) / 2)

        var aiDrafts: [CourseDraft] = []
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

        var scoped = drafts.filter(isAcceptableDraft)
        let scope = ImportWeekScope.defaultScope(detectedWeek: detectedWeek,
                                                 hasPerCourseWeeks: scoped.contains { !$0.weeks.isEmpty })
        applyWeekScope(scope, detectedWeek: detectedWeek, to: &scoped)
        return ImportOutcome(drafts: scoped, engine: engine, detectedTeachingWeek: detectedWeek)
    }

    /// 把周次范围写回草稿。
    static func applyWeekScope(_ scope: ImportWeekScope, detectedWeek: Int?, to drafts: inout [CourseDraft],
                               overwriteExplicit: Bool = false) {
        if scope == .autoDetected { return }
        let weeks = scope.weeks(detectedWeek: detectedWeek)
        for index in drafts.indices {
            if !overwriteExplicit, !drafts[index].weeks.isEmpty { continue }
            drafts[index].weeks = weeks
        }
    }

    private static func ruleBasedDrafts(items: [TextItem], plain: String, slots: [PeriodSlot]) -> [CourseDraft] {
        // 四种版式并行：星期列网格、星期行网格、列表、时间轴；分别解析后按质量选优。
        let horizontal = HorizontalGridParser.parse(items, slots: slots)
        let list = ListScheduleParser.parse(items, slots: slots)
        let grid = GridHeuristicParser.parse(items, slots: slots)
        let timeline = TimelineScheduleParser.parse(items, slots: slots)
        let lines = LineHeuristicParser.parse(plain, slots: slots)

        let candidates = [
            ("horizontal", horizontal),
            ("list", list),
            ("grid", grid),
            ("timeline", timeline),
            ("lines", lines),
        ]
        let ranked = candidates
            .map { pair -> (String, [CourseDraft], Int) in
                let clean = dedupe(pair.1.filter(isAcceptableDraft))
                var score = quality(clean)
                let atRoomCount = clean.filter {
                    !$0.classroom.isEmpty
                        && $0.classroom.range(of: #"\d{3,}"#, options: .regularExpression) != nil
                        && $0.name.count >= 4
                }.count

                if pair.0 == "lines" {
                    let withPeriod = clean.filter { $0.startPeriod > 0 }.count
                    score = withPeriod * 3
                    if withPeriod < 3 { score = min(score, 2) }
                }
                if pair.0 == "horizontal", clean.count >= 2 {
                    score += 14
                    score += clean.filter { $0.startPeriod > 0 || $0.endMinutes > $0.startMinutes }.count * 2
                    score += clean.filter { !$0.classroom.isEmpty }.count * 2
                }
                if pair.0 == "grid" {
                    if clean.count >= 2 {
                        score += clean.filter { !$0.classroom.isEmpty }.count * 3
                        score += clean.filter { $0.startPeriod > 0 }.count * 2
                        score += 12
                    }
                    if atRoomCount >= 2 { score += 40 }
                }
                if pair.0 == "list", clean.count >= 3 {
                    score += clean.filter { $0.startPeriod > 0 || $0.endMinutes > $0.startMinutes }.count * 2
                    score += 10
                    if atRoomCount > 0 { score -= 20 }
                }
                if pair.0 == "timeline", clean.count >= 3 { score += 10 }
                return (pair.0, clean, score)
            }
            .sorted { $0.2 > $1.2 }

        guard let best = ranked.first, best.2 > 0, !best.1.isEmpty else {
            return dedupe((horizontal + list + grid + timeline).filter(isAcceptableDraft))
        }

        var drafts = best.1
        let bestIsSpatialGrid = best.0 == "horizontal"
            || (best.0 == "grid" && best.1.filter {
                !$0.classroom.isEmpty && $0.name.count >= 4
            }.count >= 2)
        // 完整网格结果不再与其他版式合并，避免跨列残片污染课名。
        if !bestIsSpatialGrid,
           let second = ranked.dropFirst().first,
           second.0 != "lines", best.0 != "lines",
           second.2 >= best.2 / 2, !second.1.isEmpty {
            drafts = merge(primary: drafts, secondary: second.1, fillWeeks: true)
        }
        return drafts.filter(isAcceptableDraft)
    }

    private static func isAcceptableDraft(_ draft: CourseDraft) -> Bool {
        guard !draft.name.isEmpty, draft.isValid else { return false }
        guard !ScheduleJunk.isNonCourseText(draft.name) else { return false }
        guard !OCRCleanup.isBogusCourseName(draft.name) else { return false }
        guard !OCRCleanup.looksLikePersonNameOnly(draft.name) else { return false }
        return true
    }

    /// 分数越高表示课名越完整、教室越像真的、节次与时间一致。
    private static func quality(_ drafts: [CourseDraft]) -> Int {
        drafts.reduce(0) { score, draft in
            var s = 0
            if ScheduleJunk.isNonCourseText(draft.name) || OCRCleanup.isBogusCourseName(draft.name) { return score - 40 }
            if OCRCleanup.looksLikePersonNameOnly(draft.name) { return score - 40 }
            if draft.name.count >= 4 { s += 3 }
            if draft.name.count >= 6 { s += 3 }
            if draft.name.count >= 8 { s += 2 }
            if !draft.classroom.isEmpty { s += 4 }
            if draft.classroom.range(of: #"\d{2,5}|[A-Za-z]\-?\d{2,4}"#, options: .regularExpression) != nil { s += 4 }
            if !draft.teacher.isEmpty, draft.teacher != draft.name { s += 4 }
            if !draft.weeks.isEmpty { s += 2 }
            if draft.name.contains("@") { s -= 8 }
            if draft.name.count <= 3 { s -= 8 }
            if draft.startPeriod <= 0 { s -= 6 }
            if draft.name.count <= 4 && draft.classroom.isEmpty { s -= 6 }
            if draft.name.contains("楼") || draft.name.contains("馆") { s -= 6 }
            if draft.startPeriod >= 1, draft.endPeriod >= draft.startPeriod { s += 4 }
            if draft.endMinutes > draft.startMinutes { s += 2 }
            if let mapped = PeriodTable.periods(startMinutes: draft.startMinutes, endMinutes: draft.endMinutes, in: SharedSettings.periodSlots),
               mapped.0 == draft.startPeriod, mapped.1 == draft.endPeriod { s += 3 }
            return score + max(0, s)
        }
    }

    private static func merge(primary: [CourseDraft], secondary: [CourseDraft], fillWeeks: Bool) -> [CourseDraft] {
        var result = primary
        for index in result.indices {
            guard let match = secondary.first(where: { similar($0, result[index]) }) else { continue }
            if result[index].classroom.isEmpty { result[index].classroom = match.classroom }
            if result[index].teacher.isEmpty { result[index].teacher = match.teacher }
            if fillWeeks, result[index].weeks.isEmpty, !match.weeks.isEmpty { result[index].weeks = match.weeks }
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
        let left = a.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
        let right = b.replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
        if left.isEmpty || right.isEmpty { return false }
        if left == right || left.contains(right) || right.contains(left) { return true }
        return left.prefix(2) == right.prefix(2) && abs(left.count - right.count) <= 6
    }

    private static func dedupe(_ drafts: [CourseDraft]) -> [CourseDraft] {
        var seen = Set<String>()
        return drafts.filter { seen.insert($0.dedupeKey).inserted }
    }
}
