import SwiftUI

/// 彩色流动背景，让液态玻璃材质有可折射的内容。
struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) / 60 * 2 * .pi)
            let center = SIMD2<Float>(0.5 + 0.15 * sin(t), 0.5 + 0.15 * cos(t))
            let points: [SIMD2<Float>] = [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), center, SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
            ]
            MeshGradient(width: 3, height: 3, points: points, colors: colorScheme == .dark ? darkColors : lightColors)
        }
        .ignoresSafeArea()
    }

    private var lightColors: [Color] {
        [.init(hex: "C9E4FF"), .init(hex: "E3D7FF"), .init(hex: "FFE0EC"),
         .init(hex: "B8F1E0"), .init(hex: "F4F7FF"), .init(hex: "FFE9C7"),
         .init(hex: "D6E8FF"), .init(hex: "EAD9FF"), .init(hex: "CFF5FF")]
    }

    private var darkColors: [Color] {
        [.init(hex: "0B1A3A"), .init(hex: "24124A"), .init(hex: "3A0F2E"),
         .init(hex: "0D3B3A"), .init(hex: "111522"), .init(hex: "3A2A0D"),
         .init(hex: "0E2148"), .init(hex: "26164A"), .init(hex: "08333F")]
    }
}

struct CourseCard: View {
    let occurrence: ClassOccurrence
    var highlighted = false

    var body: some View {
        let course = occurrence.course
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(TimeFormat.string(course.startMinutes)).font(.headline.monospacedDigit())
                Text(TimeFormat.string(course.endMinutes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 56)

            Capsule().fill(Color(hex: course.colorHex)).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(course.name).font(.headline).lineLimit(1)
                HStack(spacing: 10) {
                    Label(course.classroom.isEmpty ? "未设置教室" : course.classroom, systemImage: "mappin.and.ellipse")
                    Label(course.periodText, systemImage: "number")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
            if occurrence.isOngoing() {
                Text("上课中").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(.regular.tint(.green.opacity(0.5)), in: .capsule)
            }
        }
        .padding(14)
        .glassEffect(highlighted ? .regular.tint(Color(hex: course.colorHex).opacity(0.35)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 22))
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
