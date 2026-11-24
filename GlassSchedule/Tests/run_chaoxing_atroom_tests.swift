#!/usr/bin/env swift
import Foundation

/// 超星「课程@教室」粘合与尾号恢复回归。

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

func parseAtRoom(_ glued: String) -> (String, String)? {
    guard let at = glued.firstIndex(of: "@") else { return nil }
    let course = String(glued[..<at])
    var room = String(glued[glued.index(after: at)...])
    // 模拟：若房间后还有空白数字
    if let r = room.range(of: #"^([A-Za-z0-9\-－]+)"#, options: .regularExpression) {
        room = String(room[r])
    }
    guard course.count >= 2, room.count >= 1 else { return nil }
    return (course, room)
}

func roomsCompatible(_ a: String, _ b: String) -> Bool {
    if a == b || a.isEmpty || b.isEmpty { return true }
    return a.hasPrefix(b) || b.hasPrefix(a)
}

var failed = 0
func expect(_ c: Bool, _ m: String) {
    print(c ? "PASS  \(m)" : "FAIL  \(m)")
    if !c { failed += 1 }
}

expect(join(["水利工", "程造价", "二@231", "3"]) == "水利工程造价二@2313", "碎片拼成完整@教室")
expect(join(["水利造价软件应用@221", "2"]) == "水利造价软件应用@2212", "软件应用教室尾号")
expect(join(["招投标与合同管理@130", "6"]) == "招投标与合同管理@1306", "招投标教室")
expect(join(["建设工程项目管理@140", "3"]) == "建设工程项目管理@1403", "项目管理教室")

if let p = parseAtRoom(join(["水利工程造价二@231", "3"])) {
    expect(p.0 == "水利工程造价二" && p.1 == "2313", "解析课名与完整教室 2313")
} else {
    expect(false, "解析课名与完整教室 2313")
}

expect(roomsCompatible("231", "2313"), "教室前缀兼容")
expect(roomsCompatible("241", "2416"), "241/2416 兼容")
expect(!roomsCompatible("2313", "1216"), "不同教室不兼容")

// 裸数字不能当节次噪声过滤掉
func isCellPeriodNoise(_ line: String) -> Bool {
    if line.contains("节") { return true }
    return line.range(of: #"^\d{1,2}\s*[-－—~～]\s*\d{1,2}$"#, options: .regularExpression) != nil
}
expect(!isCellPeriodNoise("3"), "裸数字 3 不是节次噪声")
expect(!isCellPeriodNoise("2313"), "教室号不是节次噪声")
expect(isCellPeriodNoise("第1-2节") || isCellPeriodNoise("1-2"), "1-2 是节次")

if failed == 0 {
    print("\nAll chaoxing @room regressions passed.")
    exit(0)
} else {
    print("\n\(failed) failure(s).")
    exit(1)
}
