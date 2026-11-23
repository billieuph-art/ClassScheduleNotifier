import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var notifications: NotificationScheduler
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("通知") {
                    HStack {
                        Text("通知权限")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }

                    Button("开启通知权限") {
                        Task {
                            await notifications.requestAuthorization()
                            if notifications.authorizationStatus == .denied {
                                notifications.openSystemSettings()
                            }
                        }
                    }
                    .disabled(notifications.authorizationStatus == .authorized)
                }

                Section("实时活动") {
                    Text("Live Activities 需要在系统设置中允许。课程开始前会自动展示在灵动岛和锁屏。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("导入说明") {
                    Text("图片导入使用本机 Vision OCR 识别中文课表截图，会尽量提取课程名、教师、教室、周数和时间。识别结果建议手动核对。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await notifications.refreshStatus()
            }
        }
    }

    private var statusText: String {
        switch notifications.authorizationStatus {
        case .authorized: return "已开启"
        case .denied: return "已拒绝"
        case .notDetermined: return "未请求"
        case .provisional: return "临时"
        case .ephemeral: return "临时"
        @unknown default: return "未知"
        }
    }
}
