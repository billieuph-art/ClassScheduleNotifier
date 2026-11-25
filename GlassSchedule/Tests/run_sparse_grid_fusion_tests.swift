#!/usr/bin/env swift
import Foundation

/// Regression for the importer policy: a sparse grid result must not suppress
/// independent weekday candidates from alternate parsers.

struct Draft: Equatable {
    var name: String
    var day: Int
    var start: Int
    var end: Int
    var room: String
}

func namesSimilar(_ a: String, _ b: String) -> Bool {
    let x = a.replacingOccurrences(of: #"\\s"#, with: "", options: .regularExpression)
    let y = b.replacingOccurrences(of: #"\\s"#, with: "", options: .regularExpression)
    return !x.isEmpty && !y.isEmpty && (x == y || x.contains(y) || y.contains(x))
}

func fuse(_ primary: [Draft], _ secondary: [Draft]) -> [Draft] {
    var result = primary
    for draft in secondary {
        if let index = result.firstIndex(where: {
            $0.day == draft.day && $0.start == draft.start && $0.end == draft.end
                && namesSimilar($0.name, draft.name)
        }) {
            if result[index].name.count < draft.name.count { result[index].name = draft.name }
            if result[index].room.isEmpty { result[index].room = draft.room }
        } else {
            result.append(draft)
        }
    }
    return result.sorted { ($0.day, $0.start) < ($1.day, $1.start) }
}

var failed = 0
func expect(_ value: Bool, _ message: String) {
    print(value ? "PASS  \\(message)" : "FAIL  \\(message)")
    if !value { failed += 1 }
}

let grid = [
    Draft(name: "水利工程造价二", day: 1, start: 3, end: 4, room: "2313"),
    Draft(name: "水利工程造价二", day: 3, start: 1, end: 4, room: "2209"),
]
let alternate = [
    Draft(name: "水利工程造价二", day: 1, start: 1, end: 2, room: "2313"),
    Draft(name: "水利工程造价二", day: 2, start: 1, end: 2, room: "1216"),
    Draft(name: "水利工程造价二", day: 2, start: 3, end: 4, room: "1216"),
    Draft(name: "水利造价软件应用", day: 5, start: 3, end: 4, room: "2212"),
]
let result = fuse(grid, alternate)
expect(result.contains { $0.day == 2 && $0.room == "1216" }, "保留周二候选")
expect(result.contains { $0.day == 5 && $0.room == "2212" }, "保留周五候选")
expect(result.contains { $0.day == 1 && $0.start == 1 && $0.end == 2 }, "补入周一前半段")
expect(result.contains { $0.day == 3 && $0.start == 1 && $0.end == 4 }, "保留周三原结果")

// 同教室、同时间但不同课名不能被误合并。
let conflict = fuse(
    [Draft(name: "课程甲", day: 2, start: 1, end: 2, room: "1201")],
    [Draft(name: "课程乙", day: 2, start: 1, end: 2, room: "1201")]
)
expect(conflict.count == 2, "同教室不同课程不能误合并")

if failed == 0 {
    print("\\nAll sparse-grid fusion regressions passed.")
    exit(0)
}
print("\\n\\(failed) failure(s).")
exit(1)
