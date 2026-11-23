import SwiftUI

struct CourseRow: View {
    let course: Course
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: course.colorHex))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(course.name)
                    .font(.headline)
                Text(course.timeRangeText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if !course.location.isEmpty {
                        Label(course.location, systemImage: "mappin.and.ellipse")
                    }
                    if !course.teacher.isEmpty {
                        Label(course.teacher, systemImage: "person")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            Button {
                Task {
                    await liveActivity.start(for: course)
                }
            } label: {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始实时活动")
        }
        .padding(.vertical, 5)
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0x5B8DEF
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
