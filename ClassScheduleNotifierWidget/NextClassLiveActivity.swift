import WidgetKit
import SwiftUI
import ActivityKit

// 与主 App 中的 NextClassAttributes 必须完全一致
struct NextClassAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var endTime: Date
        var startTime: Date
    }

    var courseName: String
    var room: String
    var teacher: String
}

struct NextClassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextClassAttributes.self) { context in
            // 锁屏 / 通知栏展开视图
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(.blue)
                    Text(context.attributes.courseName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.status)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.15))
                        .cornerRadius(8)
                }

                HStack {
                    if !context.attributes.room.isEmpty {
                        Label(context.attributes.room, systemImage: "mappin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !context.attributes.teacher.isEmpty {
                        Label(context.attributes.teacher, systemImage: "person")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // 系统自动倒计时
                Text(timerInterval: context.state.startTime...context.state.endTime, countsDown: false)
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding()
            .activityBackgroundTint(.blue.opacity(0.1))
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开状态
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.courseName, systemImage: "book")
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading) {
                        if !context.attributes.room.isEmpty {
                            Text(context.attributes.room)
                                .font(.subheadline)
                        }
                        Text(timerInterval: context.state.startTime...context.state.endTime, countsDown: true)
                            .font(.title3.monospacedDigit())
                    }
                }
            } compactLeading: {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(timerInterval: context.state.startTime...context.state.endTime, countsDown: true)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 40)
            } minimal: {
                Image(systemName: "book.closed")
            }
        }
    }
}

@main
struct ClassScheduleNotifierWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextClassLiveActivity()
    }
}
