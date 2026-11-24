import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 在 macOS CI / 本地 Swift 下可跑的 OCR 清洗回归用例。
/// 运行：`swift GlassSchedule/Tests/run_ocr_cleanup_tests.swift`
enum OCRCleanupTestCases {
    static let collapseCases: [(String, String)] = [
        ("高等数学（上）高等数学（上）高等数学（上）", "高等数学（上）"),
        ("教一楼 302教一楼 302", "教一楼 302"),
        ("李明李明", "李明"),
        ("大学英语", "大学英语"),
    ]

    static let bogusNames: [String] = [
        "第 1-2 节李明李明",
        "第1-2节李明李明",
        "教一楼 302教一楼 302",
        "1-16 周（双周）1-16 周（单周）",
        "(单周)1-16 周 1-16 周 1-16 周",
        "第 3-4 节王芳陈伟孙丽",
        "大学物理（上）大学英语（1）大学物理（上）线性代数",
        "中国近现代史线性代数思想道德与法治",
        "(每周)(每周)(每周)",
        "课程名教师教室",
        "王老师|教 A-102陈老师|机房 C-301",
    ]

    static let validNames: [String] = [
        "高等数学（上）",
        "大学英语（I）",
        "程序设计基础（C语言）",
        "体育（乒乓球）",
        "线性代数",
    ]
}
