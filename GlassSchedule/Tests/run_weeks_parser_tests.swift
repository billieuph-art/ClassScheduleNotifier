#!/usr/bin/env swift
import Foundation

// 与 WeeksParser.parse 同步的回归（Shared 模块逻辑副本，供 Linux/macOS 快测）

func parseWeeks(_ text: String) -> [Int] {
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let everyWeekOnly = raw.replacingOccurrences(of: #"[（()）\s]"#, with: "", options: .regularExpression)
    if everyWeekOnly == "每周" { return [] }

    var t = raw.replacingOccurrences(of: "，", with: ",")
        .replacingOccurrences(of: "、", with: ",")
        .replacingOccurrences(of: "—", with: "-")
        .replacingOccurrences(of: "–", with: "-")
        .replacingOccurrences(of: "~", with: "-")
        .replacingOccurrences(of: "至", with: "-")
    let hasEvery = t.contains("每周")
    let oddOnly = !hasEvery && t.contains("单")
    let evenOnly = !hasEvery && t.contains("双")
    t = t.replacingOccurrences(of: "[^0-9,\\-]", with: " ", options: .regularExpression)
    var weeks = Set<Int>()
    for token in t.split(whereSeparator: { $0 == "," || $0 == " " }) {
        let bounds = token.split(separator: "-").compactMap { Int($0) }
        if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] <= 30 {
            weeks.formUnion(bounds[0]...bounds[1])
        } else if bounds.count == 1, bounds[0] >= 1, bounds[0] <= 30 {
            weeks.insert(bounds[0])
        }
    }
    if oddOnly { weeks = weeks.filter { $0 % 2 == 1 } }
    if evenOnly { weeks = weeks.filter { $0 % 2 == 0 } }
    return weeks.sorted()
}

var failed = 0
func expect(_ cond: Bool, _ msg: String) {
    print(cond ? "PASS  \(msg)" : "FAIL  \(msg)")
    if !cond { failed += 1 }
}

expect(parseWeeks("1-16周") == Array(1...16), "1-16周")
expect(parseWeeks("第1-16周") == Array(1...16), "第1-16周")
expect(parseWeeks("1-16周（单周）") == Array(stride(from: 1, through: 16, by: 2)), "1-16单周")
expect(parseWeeks("1-16周（双周）") == Array(stride(from: 2, through: 16, by: 2)), "1-16双周")
expect(parseWeeks("第1-8周") == Array(1...8), "第1-8周")
expect(parseWeeks("第9-16周") == Array(9...16), "第9-16周")
expect(parseWeeks("第1-16周（每周）") == Array(1...16), "第1-16周（每周）不筛单双")
expect(parseWeeks("每周").isEmpty, "纯每周→空数组")
expect(parseWeeks("3,5,7周") == [3, 5, 7], "离散周次")
// 单双同时出现时奇偶过滤互相抵消 → 空（表示每周），绝不当课名
expect(parseWeeks("1-16周（双周）1-16周（单周）").isEmpty, "冲突单双周→空数组(每周)")

if failed == 0 {
    print("\nAll weeks parser regressions passed.")
    exit(0)
} else {
    print("\n\(failed) failure(s).")
    exit(1)
}
