#!/usr/bin/env swift
import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#else
struct CGFloat {}
#endif

// 网格列边界：相邻列中点分割，确保跨列文字不会落入同一单元格。

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

var failed = 0
func expect(_ cond: Bool, _ msg: String) {
    print(cond ? "PASS  \(msg)" : "FAIL  \(msg)")
    if !cond { failed += 1 }
}

// 模拟图三：周一…周五列中心
let cols = [(1, 0.20), (2, 0.32), (3, 0.44), (4, 0.56), (5, 0.68)].map { (day: $0.0, x: $0.1) }
let bounds = columnBounds(cols)

// 各列正中的课名应归属正确
expect(owner(of: 0.20, bounds: bounds) == 1, "周一中心归周一")
expect(owner(of: 0.32, bounds: bounds) == 2, "周二中心归周二")
expect(owner(of: 0.44, bounds: bounds) == 3, "周三中心归周三")

// 跨列中点不应同时属于两列（边界半开由 ClosedRange 一端独占）
let mid12 = (0.20 + 0.32) / 2
let o1 = owner(of: mid12 - 0.001, bounds: bounds)
let o2 = owner(of: mid12 + 0.001, bounds: bounds)
expect(o1 == 1 && o2 == 2, "列边界左右分属不同天")

// 模拟：周一高等数学、周三高等数学 不应进同一集合
var monday: [String] = []
var wednesday: [String] = []
for item in [(0.20, "高等数学（上）"), (0.44, "高等数学（上）"), (0.32, "大学物理（上）")] {
    switch owner(of: item.0, bounds: bounds) {
    case 1: monday.append(item.1)
    case 3: wednesday.append(item.1)
    default: break
    }
}
expect(monday == ["高等数学（上）"], "周一只有一门高等数学")
expect(wednesday == ["高等数学（上）"], "周三单独一门高等数学")
expect(!monday.contains("大学物理（上）"), "物理不串进周一")

if failed == 0 {
    print("\nAll grid spatial regressions passed.")
    exit(0)
} else {
    print("\n\(failed) failure(s).")
    exit(1)
}
