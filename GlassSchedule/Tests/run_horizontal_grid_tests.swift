#!/usr/bin/env swift
import Foundation

// 横向课表回归：星期在左侧按 Y 分行，节次在顶部按 X 分列。

struct DayAnchor {
    var day: Int
    var y: Double
    var x: Double
}

struct ColumnAnchor {
    var periodStart: Int
    var periodEnd: Int
    var x: Double
}

func isHorizontal(_ days: [DayAnchor]) -> Bool {
    guard days.count >= 2 else { return false }
    let xs = days.map(\.x), ys = days.map(\.y)
    return (ys.max()! - ys.min()!) >= 0.14 && (xs.max()! - xs.min()!) <= 0.22
}

func rowBounds(_ sorted: [DayAnchor]) -> [Int: ClosedRange<Double>] {
    var result: [Int: ClosedRange<Double>] = [:]
    for (i, day) in sorted.enumerated() {
        let previousGap = i > 0 ? day.y - sorted[i - 1].y
            : (sorted.count > 1 ? sorted[1].y - day.y : 0.12)
        let nextGap = i + 1 < sorted.count ? sorted[i + 1].y - day.y : previousGap
        let top = i == 0 ? max(0, day.y - previousGap * 0.48) : (sorted[i - 1].y + day.y) / 2
        let bottom = i + 1 == sorted.count ? min(1, day.y + nextGap * 0.48) : (day.y + sorted[i + 1].y) / 2
        result[day.day] = top...bottom
    }
    return result
}

func columnBounds(_ sorted: [ColumnAnchor]) -> [Int: ClosedRange<Double>] {
    var result: [Int: ClosedRange<Double>] = [:]
    for (i, col) in sorted.enumerated() {
        let left = i == 0 ? max(0, col.x - (sorted[1].x - col.x) * 0.48)
            : (sorted[i - 1].x + col.x) / 2
        let right = i == sorted.count - 1 ? min(1, col.x + (col.x - sorted[i - 1].x) * 0.48)
            : (col.x + sorted[i + 1].x) / 2
        result[col.periodStart] = left...right
    }
    return result
}

func owner(_ value: Double, _ bounds: [Int: ClosedRange<Double>]) -> Int? {
    bounds.first { $0.value.contains(value) }?.key
}

var failures = 0
func expect(_ condition: Bool, _ message: String) {
    print(condition ? "PASS  \(message)" : "FAIL  \(message)")
    if !condition { failures += 1 }
}

let days = [
    DayAnchor(day: 1, y: 0.18, x: 0.08),
    DayAnchor(day: 2, y: 0.34, x: 0.08),
    DayAnchor(day: 3, y: 0.50, x: 0.09),
    DayAnchor(day: 4, y: 0.66, x: 0.08),
    DayAnchor(day: 5, y: 0.82, x: 0.08),
]
let columns = [
    ColumnAnchor(periodStart: 1, periodEnd: 2, x: 0.28),
    ColumnAnchor(periodStart: 3, periodEnd: 4, x: 0.46),
    ColumnAnchor(periodStart: 5, periodEnd: 6, x: 0.64),
    ColumnAnchor(periodStart: 7, periodEnd: 8, x: 0.82),
]
expect(isHorizontal(days), "星期纵向分布应识别为横向课表")
let rows = rowBounds(days)
let cols = columnBounds(columns)

expect(owner(0.34, rows) == 2, "Y=0.34 必须归周二行")
expect(owner(0.50, rows) == 3, "Y=0.50 必须归周三行")
expect(owner(0.64, cols) == 5, "X=0.64 必须归第5-6节列")

// 交叉坐标决定唯一单元格：周二 × 第5-6节，不得串入周一/周三。
let targetDay = owner(0.34, rows)
let targetPeriod = owner(0.64, cols)
expect(targetDay == 2 && targetPeriod == 5, "周二第5-6节单元格定位正确")

// 同一格内课名、教师、教室、周次的 OCR 片段必须保留在同一行列坐标。
struct Fragment { var text: String; var x: Double; var y: Double }
let fragments = [
    Fragment(text: "高等数学（上）", x: 0.64, y: 0.335),
    Fragment(text: "张伟", x: 0.64, y: 0.350),
    Fragment(text: "教一楼", x: 0.64, y: 0.365),
    Fragment(text: "302", x: 0.64, y: 0.380),
    Fragment(text: "1-16周", x: 0.64, y: 0.395),
]
let cellFragments = fragments.filter {
    rows[2]!.contains($0.y) && cols[5]!.contains($0.x)
}
expect(cellFragments.count == 5, "课名/教师/楼栋/门牌/周次全部留在同一单元格")

// 星期在顶部横向排列时，不得误触发星期行解析。
let verticalDays = [
    DayAnchor(day: 1, y: 0.10, x: 0.20),
    DayAnchor(day: 2, y: 0.105, x: 0.34),
    DayAnchor(day: 3, y: 0.10, x: 0.48),
    DayAnchor(day: 4, y: 0.105, x: 0.62),
]
expect(!isHorizontal(verticalDays), "顶部星期列布局不得误判为星期行")

// 相邻行边界两侧必须归属不同星期。
expect(owner(rows[1]!.upperBound - 0.001, rows) == 2, "周二行内边界归周二")
expect(owner(rows[1]!.upperBound + 0.001, rows) == 3, "跨过行边界后归周三")

if failures == 0 {
    print("\nAll horizontal timetable spatial regressions passed.")
    exit(0)
} else {
    print("\n\(failures) failure(s).")
    exit(1)
}
