import Foundation
import CoreGraphics

/// OCR 去重、重复拼接折叠、伪课名校验（纯逻辑，便于单测）。
enum OCRCleanup {
    /// 去掉几乎同位置、同内容的重复观测。
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

    /// 单元格内行去重：相同文字只留一次。
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

    /// 「高等数学（上）高等数学（上）高等数学（上）」→「高等数学（上）」
    static func collapseRepeatedPhrase(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4 else { return t }

        // 精确整段重复
        for len in 2...(t.count / 2) where t.count % len == 0 {
            let unit = String(t.prefix(len))
            let n = t.count / len
            if n >= 2, String(repeating: unit, count: n) == t {
                return unit
            }
        }

        // 前缀反复拼接：ABABAB / AAA
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

    /// 是否像多门课被水平拼进同一字段。
    static func looksLikeMergedCourses(_ name: String) -> Bool {
        let t = collapseRepeatedPhrase(name)
        if t.count < 10 { return false }
        // 多个书名号/括注课程后缀
        let parenPairs = t.filter { $0 == "（" || $0 == "(" }.count
        if parenPairs >= 2 { return true }
        // 多个典型课名关键词且总长很长
        let markers = ["大学", "高等", "线性", "程序", "思想", "中国", "形势", "离散", "数据", "概率", "体育", "英语", "物理", "数学"]
        let hits = markers.filter { t.contains($0) }.count
        if hits >= 3 && t.count >= 12 { return true }
        if hits >= 2 && t.count >= 16 { return true }
        return false
    }

    static func sanitizeCourseName(_ raw: String) -> String {
        var t = collapseRepeatedPhrase(raw)
        t = t.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        return t
    }

    /// 教室/周次/节次+教师等绝不能当课名。
    static func isBogusCourseName(_ raw: String) -> Bool {
        let t = collapseRepeatedPhrase(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if t.isEmpty { return true }
        if ScheduleJunk.isNonCourseText(t) { return true }
        if looksLikeMergedCourses(t) { return true }

        // 第1-2节… / 第 3-4 节王芳…
        if t.range(of: #"^第?\s*\d{1,2}\s*([-－—~～]\s*\d{1,2})?\s*节"#, options: .regularExpression) != nil {
            return true
        }
        // 纯周次堆叠
        if isWeekOnlyName(t) { return true }
        // 纯教室堆叠
        if isRoomOnlyName(t) { return true }
        // 纯教师名堆叠：李明李明 / 王芳陈伟孙丽
        if isTeacherStack(t) { return true }
        return false
    }

    static func isWeekOnlyName(_ t: String) -> Bool {
        var rest = t.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        // 反复剥周次片段
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
        // 教一楼302 / 理教楼A-201 / 体育馆
        if collapsed.range(of: #"^(?:[东南西北]?[\p{Han}]{0,8}?(?:楼|馆|教|室|区|院|中心|机房)[\p{Han}A-Za-z0-9\-－—]*\d{0,5}[A-Za-z0-9\-－—]*|体育馆|操场)$"#, options: .regularExpression) != nil {
            return true
        }
        // 重复教室
        if collapseRepeatedPhrase(collapsed) != collapsed {
            return isRoomOnlyName(collapseRepeatedPhrase(collapsed))
        }
        return false
    }

    static func isTeacherStack(_ t: String) -> Bool {
        let compact = t.replacingOccurrences(of: #"\s+|老师|教授"#, with: "", options: .regularExpression)
        // 全是 2–3 字人名重复/拼接，无课名关键词
        guard compact.count >= 4, compact.count <= 18 else { return false }
        if compact.range(of: #"^[\p{Han}]+$"#, options: .regularExpression) == nil { return false }
        let courseHints = ["大学", "高等", "数学", "英语", "物理", "体育", "程序", "线性", "思想", "中国", "形势", "数据", "概率", "离散", "计算", "创新", "实验"]
        if courseHints.contains(where: { compact.contains($0) }) { return false }
        // 李明李明
        if compact.count % 2 == 0 {
            let half = compact.count / 2
            if String(compact.prefix(half)) == String(compact.suffix(half)) { return true }
        }
        // 王芳陈伟孙丽 — 按 2 字切
        if compact.count % 2 == 0 {
            var i = compact.startIndex
            var ok = true
            while i < compact.endIndex {
                let j = compact.index(i, offsetBy: 2, limitedBy: compact.endIndex) ?? compact.endIndex
                if compact.distance(from: i, to: j) != 2 { ok = false; break }
                i = j
            }
            if ok, compact.count >= 6 { return true }
        }
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
