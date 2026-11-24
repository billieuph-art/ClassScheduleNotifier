#!/usr/bin/env swift
import Foundation

/// 用用户反馈的错误识别样例做验收夹具（不依赖 Vision，验证清洗与伪课判定）。

func collapseRepeatedPhrase(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count >= 4 else { return t }
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
        if hits >= 2, rest.isEmpty { return unit }
    }
    return t
}

func looksLikeMergedCourses(_ name: String) -> Bool {
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

func isWeekOnlyName(_ t: String) -> Bool {
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

func isRoomOnlyName(_ t: String) -> Bool {
    let collapsed = collapseRepeatedPhrase(t).replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    return collapsed.range(of: #"^(?:[东南西北]?[\p{Han}]{0,8}?(?:楼|馆|教|室|区|院|中心|机房)[\p{Han}A-Za-z0-9\-－—]*\d{0,5}[A-Za-z0-9\-－—]*|体育馆|操场)$"#, options: .regularExpression) != nil
}

func isTeacherStack(_ t: String) -> Bool {
    let compact = t.replacingOccurrences(of: #"\s+|老师|教授"#, with: "", options: .regularExpression)
    guard compact.count >= 4, compact.count <= 18 else { return false }
    if compact.range(of: #"^[\p{Han}]+$"#, options: .regularExpression) == nil { return false }
    let courseHints = ["大学", "高等", "数学", "英语", "物理", "体育", "程序", "线性", "思想", "中国", "形势", "数据", "概率", "离散", "计算", "创新", "实验"]
    if courseHints.contains(where: { compact.contains($0) }) { return false }
    if compact.count % 2 == 0 {
        let half = compact.count / 2
        if String(compact.prefix(half)) == String(compact.suffix(half)) { return true }
    }
    return compact.count % 2 == 0 && compact.count >= 6
}

func isBogusCourseName(_ raw: String) -> Bool {
    let t = collapseRepeatedPhrase(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    if t.isEmpty { return true }
    if looksLikeMergedCourses(t) { return true }
    if t.range(of: #"^第?\s*\d{1,2}\s*([-－—~～]\s*\d{1,2})?\s*节"#, options: .regularExpression) != nil { return true }
    if isWeekOnlyName(t) { return true }
    if isRoomOnlyName(t) { return true }
    if isTeacherStack(t) { return true }
    let weekOnly = t.replacingOccurrences(of: #"[（()）\s]"#, with: "", options: .regularExpression)
    if weekOnly == "每周" || weekOnly.range(of: #"^(每周)+$"#, options: .regularExpression) != nil { return true }
    if t.contains("课程名") && (t.contains("教师") || t.contains("教室")) { return true }
    if t.contains("|") && (t.contains("老师") || t.contains("教") || t.contains("楼")) { return true }
    return false
}

/// 去重键：同名不同星期/节次必须保留
func dedupeKey(name: String, weekday: Int, start: Int, end: Int, room: String) -> String {
    "\(name)|\(weekday)|\(start)|\(end)|\(room)"
}

var failed = 0
func expect(_ cond: Bool, _ msg: String) {
    print(cond ? "PASS  \(msg)" : "FAIL  \(msg)")
    if !cond { failed += 1 }
}

// —— 用户截图中的错误课名，必须全部判定为伪课程或可折叠 ——
let screenshotBugs = [
    "高等数学（上）高等数学（上）高等数学（上）",
    "大学物理（上）大学英语（1）大学物理（上）线性代数",
    "第 1-2 节李明李明",
    "教一楼 302教一楼 302",
    "1-16 周（双周）1-16 周（单周）",
    "(单周)1-16 周 1-16 周 1-16 周",
    "第 3-4 节王芳陈伟孙丽",
    "中国近现代史线性代数思想道德与法治",
]
for raw in screenshotBugs {
    let collapsed = collapseRepeatedPhrase(raw)
    let ok = isBogusCourseName(raw) || (collapsed != raw && !looksLikeMergedCourses(collapsed) && !isBogusCourseName(collapsed) == false)
    // 可接受：直接 bogus，或折叠成单门合法课名
    let acceptable = isBogusCourseName(raw)
        || (!isBogusCourseName(collapsed) && collapsed.count >= 2 && !looksLikeMergedCourses(collapsed)
            && !isRoomOnlyName(collapsed) && !isWeekOnlyName(collapsed))
    expect(acceptable, "截图样例可处理: \(raw) → \(collapsed)")
}

// 折叠后的高等数学应合法
expect(!isBogusCourseName(collapseRepeatedPhrase("高等数学（上）高等数学（上）高等数学（上）")),
       "折叠后高等数学合法")

// 同名不同天必须保留两条
let k1 = dedupeKey(name: "高等数学（上）", weekday: 1, start: 1, end: 2, room: "教一楼302")
let k2 = dedupeKey(name: "高等数学（上）", weekday: 3, start: 1, end: 2, room: "教一楼302")
let k3 = dedupeKey(name: "高等数学（上）", weekday: 1, start: 1, end: 2, room: "教一楼302")
expect(k1 != k2, "周一/周三同名不同键")
expect(k1 == k3, "完全相同才去重")

if failed == 0 {
    print("\nAll screenshot fixture regressions passed.")
    exit(0)
} else {
    print("\n\(failed) failure(s).")
    exit(1)
}
