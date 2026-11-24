#!/usr/bin/env swift
import Foundation

/// 用户超星第13周截图回归：竖排「水利工/程造价/二@231/3」必须识别为完整课，
/// 且周一/周二/周三/周五各自独立，不得串列成「水利工水利工水利造」。

// MARK: - Joiner（与 OCRTextJoiner 同步）

func shouldGlue(_ a: String, _ b: String) -> Bool {
    if b.isEmpty { return false }
    if a.hasSuffix("@") { return true }
    if a.contains("@"), let last = a.last, last.isNumber, b.allSatisfy(\.isNumber) { return true }
    if let last = a.last, last.isNumber, b.allSatisfy(\.isNumber), b.count <= 3 { return true }
    let isHan: (Character?) -> Bool = { ch in
        guard let ch, let v = ch.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v)
    }
    if isHan(a.last) && isHan(b.first) { return true }
    if isHan(a.last), let f = b.first, f.isLetter || f.isNumber || f == "@" { return true }
    return false
}

func join(_ lines: [String]) -> String {
    var parts = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    var i = 0
    while i < parts.count - 1 {
        if shouldGlue(parts[i], parts[i + 1]) {
            parts[i] = parts[i] + parts[i + 1]
            parts.remove(at: i + 1)
        } else {
            i += 1
        }
    }
    return parts.joined()
}

func parseAtRoom(_ lines: [String]) -> (name: String, room: String)? {
    let glued = join(lines)
    guard let at = glued.firstIndex(of: "@") else { return nil }
    let name = String(glued[..<at])
    var room = String(glued[glued.index(after: at)...])
    if let r = room.range(of: #"^[A-Za-z0-9\-－]+"#, options: .regularExpression) {
        room = String(room[r])
    }
    guard name.count >= 2, room.count >= 3 else { return nil }
    return (name, room)
}

// MARK: - Column bounds

func columnBounds(_ sortedCols: [(day: Int, x: Double)]) -> [Int: ClosedRange<Double>] {
    var result: [Int: ClosedRange<Double>] = [:]
    for (i, col) in sortedCols.enumerated() {
        let left: Double
        let right: Double
        if i == 0 {
            let gap = i + 1 < sortedCols.count ? (sortedCols[i + 1].x - col.x) : 0.12
            left = col.x - gap * 0.48
            right = i + 1 < sortedCols.count ? (col.x + sortedCols[i + 1].x) / 2 : col.x + gap * 0.48
        } else if i == sortedCols.count - 1 {
            let gap = col.x - sortedCols[i - 1].x
            left = (sortedCols[i - 1].x + col.x) / 2
            right = col.x + gap * 0.48
        } else {
            left = (sortedCols[i - 1].x + col.x) / 2
            right = (col.x + sortedCols[i + 1].x) / 2
        }
        result[col.day] = left...right
    }
    return result
}

func owner(of x: Double, bounds: [Int: ClosedRange<Double>]) -> Int? {
    bounds.first { $0.value.contains(x) }?.key
}

// MARK: - Block split

struct FakeItem {
    var text: String
    var x: Double
    var y: Double
    var h: Double = 0.018
    var maxY: Double { y + h }
}

func chaoxingBlocks(_ items: [FakeItem]) -> [[FakeItem]] {
    let sorted = items.sorted { $0.y < $1.y }
    guard !sorted.isEmpty else { return [] }
    let lineHeight = sorted.map(\.h).sorted().dropFirst(sorted.count / 3).first ?? 0.018

    var clusters: [[FakeItem]] = []
    for item in sorted {
        if let last = clusters.last?.last, item.y - last.maxY < max(lineHeight * 1.85, 0.018) {
            clusters[clusters.count - 1].append(item)
        } else {
            clusters.append([item])
        }
    }

    var merged: [[FakeItem]] = []
    for cluster in clusters {
        let onlyDigits = cluster.allSatisfy { $0.text.allSatisfy(\.isNumber) } && cluster.map(\.text).joined().count <= 3
        if onlyDigits, !merged.isEmpty {
            merged[merged.count - 1].append(contentsOf: cluster)
        } else {
            merged.append(cluster)
        }
    }

    func isComplete(_ group: [FakeItem]) -> Bool {
        join(group.map(\.text)).range(of: #".+@[A-Za-z0-9\-－]{3,}"#, options: .regularExpression) != nil
    }

    var result: [[FakeItem]] = []
    for cluster in merged {
        var current: [FakeItem] = []
        for item in cluster {
            if !current.isEmpty, isComplete(current), !item.text.allSatisfy(\.isNumber) {
                result.append(current)
                current = [item]
            } else {
                current.append(item)
            }
        }
        if !current.isEmpty { result.append(current) }
    }
    return result
}

func roomsCompatible(_ a: String, _ b: String) -> Bool {
    if a == b || a.isEmpty || b.isEmpty { return true }
    return a.hasPrefix(b) || b.hasPrefix(a)
}

func mergeAdjacent(_ drafts: [(day: Int, name: String, room: String, start: Int, end: Int)])
    -> [(day: Int, name: String, room: String, start: Int, end: Int)] {
    let sorted = drafts.sorted { ($0.day, $0.start) < ($1.day, $1.start) }
    var result: [(day: Int, name: String, room: String, start: Int, end: Int)] = []
    for d in sorted {
        if var last = result.last,
           last.day == d.day, last.name == d.name, roomsCompatible(last.room, d.room),
           d.start == last.end + 1, d.end - last.start + 1 <= 4 {
            last.end = d.end
            if last.room.count < d.room.count { last.room = d.room }
            result[result.count - 1] = last
        } else {
            result.append(d)
        }
    }
    return result
}

// MARK: - Fixture: 超星第13周

var failed = 0
func expect(_ c: Bool, _ m: String) {
    print(c ? "PASS  \(m)" : "FAIL  \(m)")
    if !c { failed += 1 }
}

// 列中心（周一…周日）
let cols = [1, 2, 3, 4, 5, 6, 7].map { (day: $0, x: 0.14 + Double($0 - 1) * 0.12) }
let bounds = columnBounds(cols)

// 每格竖排四行，两格（1-2 / 3-4）同课叠放
func cellLines(day: Int, roomHead: String, roomTail: String, y0: Double) -> [FakeItem] {
    let x = cols.first { $0.day == day }!.x
    let texts = ["水利工", "程造价", "二@\(roomHead)", roomTail]
    return texts.enumerated().map { i, t in
        FakeItem(text: t, x: x, y: y0 + Double(i) * 0.022)
    }
}

var all: [FakeItem] = []
// 周一 @2313 两格
all += cellLines(day: 1, roomHead: "231", roomTail: "3", y0: 0.22)
all += cellLines(day: 1, roomHead: "231", roomTail: "3", y0: 0.34)
// 周二 @1216
all += cellLines(day: 2, roomHead: "121", roomTail: "6", y0: 0.22)
all += cellLines(day: 2, roomHead: "121", roomTail: "6", y0: 0.34)
// 周三 @2209
all += cellLines(day: 3, roomHead: "220", roomTail: "9", y0: 0.22)
all += cellLines(day: 3, roomHead: "220", roomTail: "9", y0: 0.34)
// 周五 软件应用 @2212 一格（3-4）
let friX = cols.first { $0.day == 5 }!.x
all += [
    FakeItem(text: "水利造", x: friX, y: 0.34),
    FakeItem(text: "价软件", x: friX, y: 0.362),
    FakeItem(text: "应用@2", x: friX, y: 0.384),
    FakeItem(text: "212", x: friX, y: 0.406),
]

// 1) 单格粘合
expect(join(["水利工", "程造价", "二@231", "3"]) == "水利工程造价二@2313", "周一格子粘合")
expect(join(["水利工", "程造价", "二@121", "6"]) == "水利工程造价二@1216", "周二格子粘合")
expect(join(["水利造", "价软件", "应用@2", "212"]) == "水利造价软件应用@2212", "周五格子粘合")

// 2) 列归属不得串列
for item in all {
    let day = owner(of: item.x, bounds: bounds)
    let expected = cols.min(by: { abs($0.x - item.x) < abs($1.x - item.x) })!.day
    expect(day == expected, "列归属 \(item.text)@x=\(item.x) → \(day ?? -1) 期望 \(expected)")
}

// 3) 按列切块 + 解析 + 合并相邻同课
var drafts: [(day: Int, name: String, room: String, start: Int, end: Int)] = []
for day in 1...7 {
    let colItems = all.filter { owner(of: $0.x, bounds: bounds) == day }
    let blocks = chaoxingBlocks(colItems)
    for (idx, block) in blocks.enumerated() {
        guard let parsed = parseAtRoom(block.map(\.text)) else {
            expect(false, "星期\(day) 块\(idx) 应能解析@教室: \(block.map(\.text))")
            continue
        }
        // 简化节次：第一块 1-2，第二块 3-4
        let start = idx == 0 ? 1 : 3
        let end = idx == 0 ? 2 : 4
        // 周五只有一块在 3-4
        if day == 5 {
            drafts.append((5, parsed.name, parsed.room, 3, 4))
        } else {
            drafts.append((day, parsed.name, parsed.room, start, end))
        }
    }
}

let merged = mergeAdjacent(drafts)

func find(_ day: Int) -> [(String, String, Int, Int)] {
    merged.filter { $0.day == day }.map { ($0.name, $0.room, $0.start, $0.end) }
}

let mon = find(1)
expect(mon.count == 1, "周一应 1 门（两格合并）实际 \(mon.count)")
if let m = mon.first {
    expect(m.0 == "水利工程造价二" && m.1 == "2313" && m.2 == 1 && m.3 == 4, "周一 1-4 @2313 → \(m)")
}

let tue = find(2)
expect(tue.count == 1, "周二应 1 门 实际 \(tue.count)")
if let t = tue.first {
    expect(t.0 == "水利工程造价二" && t.1 == "1216" && t.2 == 1 && t.3 == 4, "周二 1-4 @1216 → \(t)")
}

let wed = find(3)
expect(wed.count == 1, "周三应 1 门 实际 \(wed.count)")
if let w = wed.first {
    expect(w.0 == "水利工程造价二" && w.1 == "2209" && w.2 == 1 && w.3 == 4, "周三 1-4 @2209 → \(w)")
}

let fri = find(5)
expect(fri.count == 1, "周五应 1 门 实际 \(fri.count)")
if let f = fri.first {
    expect(f.0 == "水利造价软件应用" && f.1 == "2212" && f.2 == 3 && f.3 == 4, "周五 3-4 @2212 → \(f)")
}

// 4) 禁止确认页曾出现的脏名
let dirty = ["水利工", "程造价", "水利工水利工水利造", "程造价程造价软件", "程造价软件"]
for name in merged.map(\.name) {
    expect(!dirty.contains(name), "不得出现脏课名: \(name)")
}
expect(merged.allSatisfy { $0.room.count >= 4 }, "教室号至少 4 位")

// 5) 模拟串列：若错误把周二字塞进周一，join 会重复——检测应失败于解析策略
let leaked = join(["水利工", "程造价", "二@231", "3", "水利工", "程造价", "二@121", "6"])
expect(leaked.contains("水利工程造价二@2313"), "即使串列也能看到完整@教室前缀")
// 多 @ 应被切成两门
let multi = chaoxingBlocks([
    FakeItem(text: "水利工", x: 0.14, y: 0.22),
    FakeItem(text: "程造价", x: 0.14, y: 0.24),
    FakeItem(text: "二@231", x: 0.14, y: 0.26),
    FakeItem(text: "3", x: 0.14, y: 0.28),
    FakeItem(text: "水利工", x: 0.14, y: 0.34),
    FakeItem(text: "程造价", x: 0.14, y: 0.36),
    FakeItem(text: "二@121", x: 0.14, y: 0.38),
    FakeItem(text: "6", x: 0.14, y: 0.40),
])
expect(multi.count == 2, "同列两门@教室应切成 2 块 实际 \(multi.count)")
if multi.count == 2 {
    expect(parseAtRoom(multi[0].map(\.text))?.room == "2313", "第一块教室 2313")
    expect(parseAtRoom(multi[1].map(\.text))?.room == "1216", "第二块教室 1216")
}

if failed == 0 {
    print("\nAll chaoxing week13 fixture regressions passed.")
    exit(0)
} else {
    print("\n\(failed) failure(s).")
    exit(1)
}
