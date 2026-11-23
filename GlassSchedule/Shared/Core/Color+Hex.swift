import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        if cleaned.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.35; g = 0.55; b = 0.95
        }
        self.init(red: r, green: g, blue: b)
    }
}

enum CoursePalette {
    static let colors = ["4F8EF7", "FF7A59", "34C759", "AF52DE", "FF9F0A", "30B0C7", "FF375F", "5E5CE6", "A2845E", "64D2FF"]

    /// 同名课程始终得到同一种颜色。
    static func color(for name: String) -> String {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(sum) % colors.count]
    }
}
