#!/usr/bin/env swift
import Foundation

// 与 OCRCleanup 同步的纯字符串回归。

func collapseRepeatedPhrase(_ raw: String) -> String {
    var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count >= 4 else { return t }
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

func looksLikePersonNameOnly(_ raw: String) -> Bool {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.range(of: #"^[\p{Han}]{2,3}$"#, options: .regularExpression) != nil else { return false }
    let hints = ["大学", "高等", "数学", "英语", "物理", "体育", "程序", "线性", "思想", "中国", "形势", "数据", "概率", "离散", "计算", "创新", "实验", "造价", "水利", "软件", "自习", "工程", "历史", "代数", "纲要"]
    return !hints.contains(where: { t.contains($0) })
}

func isBogusCourseName(_ raw: String) -> Bool {
    let t = collapseRepeatedPhrase(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    if t.isEmpty { return true }
    if looksLikeMergedCourses(t) { return true }
    if t.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil { return true }
    if t.filter({ $0 == "/" }).count >= 2 { return true }
    if t.range(of: #"^第?\s*\d{1,2}\s*([-－—~～]\s*\d{1,2})?\s*节"#, options: .regularExpression) != nil { return true }
    if isWeekOnlyName(t) { return true }
    if isRoomOnlyName(t) { return true }
    if looksLikePersonNameOnly(t) { return true }
    if t.count <= 2, !["体育", "自习"].contains(t) { return true }
    if t.contains("课程名") && (t.contains("教师") || t.contains("教室")) { return true }
    return false
}

var failed = 0
func expect(_ cond: Bool, _ message: String) {
    print(cond ? "PASS  \(message)" : "FAIL  \(message)")
    if !cond { failed += 1 }
}

expect(collapseRepeatedPhrase("高等数学（上）高等数学（上）高等数学（上）") == "高等数学（上）", "collapse 高等数学 x3")
expect(collapseRepeatedPhrase("教一楼302教一楼302") == "教一楼302", "collapse 教室 x2")
expect(collapseRepeatedPhrase("计算机楼 205 计算机楼 205") == "计算机楼 205", "collapse 空格教室")
expect(collapseRepeatedPhrase("水利工水利工") == "水利工", "collapse 水利工")
expect(collapseRepeatedPhrase("大学英语") == "大学英语", "collapse 不伤正常课名")

for name in [
    "第 1-2 节李明李明", "教一楼302教一楼302", "1-16周（双周）1-16周（单周）",
    "(每周)(每周)(每周)", "课程名教师教室", "王芳", "张健", "10", "11",
    "数11/2311/2411/2511/2611/2711/2811/29",
    "大学物理（上）大学英语（1）大学物理（上）线性代数",
] {
    expect(isBogusCourseName(name), "bogus: \(name)")
}

for name in ["高等数学（上）", "大学英语（I）", "程序设计基础（C语言）", "体育（乒乓球）", "线性代数", "中国近现代史纲要"] {
    expect(!isBogusCourseName(name), "valid: \(name)")
}

if failed == 0 {
    print("\nAll OCR cleanup regressions passed.")
    exit(0)
} else {
    print("\n\(failed) failure(s).")
    exit(1)
}
