import Foundation
import CoreGraphics

/// OCR 去重、重复拼接折叠、伪课名校验（纯逻辑，便于单测）。
enum OCRCleanup {
    /// 课名续接词：OCR 常把「中国近现代史」与「纲要」拆开，后者不是教师。
    static let courseContinuations: Set<String> = [
        "纲要", "基础", "原理", "概论", "导论", "教程", "实务", "设计", "分析", "统计",
        "法治", "政策", "英语", "数学", "物理", "化学", "历史", "体育", "造价", "工程",
        "软件", "实践", "实训", "听说", "综合", "实验", "上", "下", "中", "I", "II", "III",
        "（上）", "(上)", "（下）", "(下)", "（综）", "（实验）",
    ]

    static func dedupeItems(_ items: [TextItem], iouThreshold: CGFloat = 0.45) -> [TextItem] {
        var result: [TextItem] = []
        for item in items.sorted(by: { $0.rect.area > $1.rect.area }) {
            let t = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let duplicate = result.contains { existing in
                existing.page == item.page
                    && existing.text == item.text
                    && (iou(existing.rect, item.rect) >= iouThreshold
                        || (abs(existing.rect.midX - item.rect.midX) < 0.02
                            && abs(existing.rect.midY - item.rect.midY) < 0.02))
            }
            if !duplicate { result.append(item) }
        }
        return result.sorted { $0.rect.minY < $1.rect.minY || ($0.rect.minY == $1.rect.minY && $0.rect.minX < $1.rect.minX) }
    }

    static func dedupeLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in lines {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if seen.insert(t).inserted { result.append(t) }
        }
        return result
    }

    /// 「高等数学（上）×3」或「计算机楼 205 计算机楼 205」→ 单份。
    static func collapseRepeatedPhrase(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4 else { return t }

        // 「A A」空格分隔的整段重复
        let spaced = t.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if spaced.count >= 2, spaced.count % 2 == 0 {
            let half = spaced.count / 2
            let a = spaced.prefix(half).joined(separator: " ")
            let b = spaced.suffix(half).joined(separator: " ")
            if a == b, a.count >= 2 { return a }
        }

        for len in 2...(t.count / 2) where t.count % len == 0 {
            let unit = String(t.prefix(len))
            let n = t.count / len
            if n >= 2, String(repeating: unit, count: n) == t { return unit }
        }

        for len in stride(from: min(t.count / 2, 24), through: 2, by: -1) {
            let unit = String(t.prefix(len))
            guard unit.count >= 2 else { continue }
            var rest = t
            var hits = 0
            while rest.hasPrefix(unit) {
                rest = String(rest.dropFirst(unit.count))
                hits += 1
            }
            if hits >= 2, rest.isEmpty || isWeekOrRoomFragment(rest) {
                return unit
            }
        }
        return t
    }

    static func looksLikeMergedCourses(_ name: String) -> Bool {
        let t = collapseRepeatedPhrase(name)
        if t.count < 10 { return false }
        let parenPairs = t.filter { $0 == "（" || $0 == "(" }.count
        if parenPairs >= 2 { return true }
        let markers = ["大学", "高等", "线性", "程序", "思想", "中国", "形势", "离散", "数据", "概率", "体育", "英语", "物理", "数学"]
        let hits = markers.filter { t.contains($0) }.count
        if hits >= 3 && t.count >= 12 { return true }
        if hits >= 2 && t.count >= 16 { return true }
        return false
    }

    static func sanitizeCourseName(_ raw: String) -> String {
        var t = collapseRepeatedPhrase(raw)
        // 去掉「1水利工」「3水利工」这类节次数字前缀
        t = t.replacingOccurrences(of: #"^\d{1,2}(?=[\p{Han}])"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return t
    }

    static func sanitizeClassroom(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = collapseRepeatedPhrase(t)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // 再压一次「计算机楼 205 计算机楼 205」
        t = collapseRepeatedPhrase(t)
        return t
    }

    static func sanitizeTeacher(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        t = collapseRepeatedPhrase(t)
        if courseContinuations.contains(t) { return "" }
        let stripped = t.replacingOccurrences(of: "老师|教授", with: "", options: .regularExpression)
        if stripped.count >= 2 { return stripped }
        return t
    }

    /// 像人名、不像课名（王芳 / 张健 / 李明）。
    static func looksLikePersonNameOnly(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "老师|教授", with: "", options: .regularExpression)
        guard t.range(of: #"^[\p{Han}]{2,3}$"#, options: .regularExpression) != nil else { return false }
        if courseContinuations.contains(t) { return false }
        let courseHints = ["大学", "高等", "数学", "英语", "物理", "体育", "程序", "线性", "思想", "中国",
                           "形势", "数据", "概率", "离散", "计算", "创新", "实验", "造价", "水利",
                           "软件", "自习", "课程", "工程", "历史", "道德", "法治", "代数"]
        if courseHints.contains(where: { t.contains($0) }) { return false }
        return true
    }

    /// 明确是教师/角色行（不是课名续接）。
    static func isClearTeacherLabel(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("老师") || t.hasSuffix("教授") { return true }
        if t == "辅导员" || t == "体育组" || t == "指导教师组" || t.contains("教研室") { return true }
        return false
    }

    static func isBogusCourseName(_ raw: String) -> Bool {
        let t = collapseRepeatedPhrase(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if t.isEmpty { return true }
        if ScheduleJunk.isNonCourseText(t) { return true }
        if looksLikeMergedCourses(t) { return true }

        // 纯数字 / 节次序号
        if t.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil { return true }
        // 日期垃圾：11/2311/24… 或大量斜杠数字
        if t.filter({ $0 == "/" }).count >= 2 { return true }
        if t.range(of: #"\d{1,2}/\d{2}"#, options: .regularExpression) != nil, t.count <= 40 {
            let digits = t.filter(\.isNumber).count
            if digits >= 6 { return true }
        }
        // 几乎全是数字和斜杠
        let nonNoise = t.filter { !$0.isNumber && $0 != "/" && $0 != "-" && !$0.isWhitespace }
        if nonNoise.count <= 1, t.count >= 4 { return true }

        if t.range(of: #"^第?\s*\d{1,2}\s*([-－—~～]\s*\d{1,2})?\s*节"#, options: .regularExpression) != nil {
            return true
        }
        if isWeekOnlyName(t) { return true }
        if isRoomOnlyName(t) { return true }
        if isTeacherStack(t) { return true }
        // 纯人名绝不能当课名
        if looksLikePersonNameOnly(t) { return true }
        // 过短残片（程造价 可保留 3 字以上含「造/学/课」等；纯 2 字且无课名提示则拒）
        if t.count <= 2, !["体育", "自习"].contains(t) { return true }
        return false
    }

    static func isWeekOnlyName(_ t: String) -> Bool {
        var rest = t.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let pattern = #"(?:[\(（]?\s*(?:单|双|每)?\s*周\s*[\)）]?|(?:第)?\d{1,2}(?:\s*[-－—~～至到]\s*\d{1,2})?\s*周(?:\s*[\(（]\s*(?:单|双)\s*周?\s*[\)）])?)"#
        var guardCount = 0
        while guardCount < 8, let r = rest.range(of: pattern, options: .regularExpression) {
            rest.removeSubrange(r)
            guardCount += 1
        }
        rest = rest.replacingOccurrences(of: #"[（()）\s\-－—]"#, with: "", options: .regularExpression)
        return rest.isEmpty
    }

    static func isRoomOnlyName(_ t: String) -> Bool {
        let collapsed = collapseRepeatedPhrase(t).replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        if collapsed.range(of: #"^(?:[东南西北]?[\p{Han}]{0,8}?(?:楼|馆|教|室|区|院|中心|机房)[\p{Han}A-Za-z0-9\-－—]*\d{0,5}[A-Za-z0-9\-－—]*|体育馆|操场)$"#, options: .regularExpression) != nil {
            return true
        }
        if collapseRepeatedPhrase(collapsed) != collapsed {
            return isRoomOnlyName(collapseRepeatedPhrase(collapsed))
        }
        return false
    }

    static func isTeacherStack(_ t: String) -> Bool {
        let compact = t.replacingOccurrences(of: #"\s+|老师|教授"#, with: "", options: .regularExpression)
        guard compact.count >= 4, compact.count <= 18 else { return false }
        if compact.range(of: #"^[\p{Han}]+$"#, options: .regularExpression) == nil { return false }
        let courseHints = ["大学", "高等", "数学", "英语", "物理", "体育", "程序", "线性", "思想", "中国", "形势", "数据", "概率", "离散", "计算", "创新", "实验"]
        if courseHints.contains(where: { compact.contains($0) }) { return false }
        if compact.count % 2 == 0 {
            let half = compact.count / 2
            if String(compact.prefix(half)) == String(compact.suffix(half)) { return true }
        }
        if compact.count % 2 == 0, compact.count >= 6 { return true }
        return false
    }

    private static func isWeekOrRoomFragment(_ t: String) -> Bool {
        isWeekOnlyName(t) || isRoomOnlyName(t) || t.isEmpty
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let u = a.area + b.area - inter.area
        guard u > 0 else { return 0 }
        return inter.area / u
    }
}

private extension CGRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}
