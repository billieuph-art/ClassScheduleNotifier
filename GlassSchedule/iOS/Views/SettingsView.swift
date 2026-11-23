import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var courses: [Course]

    @AppStorage(SharedSettings.Key.semesterStart, store: SharedSettings.defaults) private var semesterStartRaw: Double = 0
    @AppStorage(SharedSettings.Key.reminderMinutes, store: SharedSettings.defaults) private var reminderMinutes = 20
    @AppStorage(SharedSettings.Key.autoLiveActivity, store: SharedSettings.defaults) private var autoLiveActivity = true
    @AppStorage(SharedSettings.Key.autoClassifyPhotos, store: SharedSettings.defaults) private var autoClassifyPhotos = true
    @AppStorage(SharedSettings.Key.photoToleranceMinutes, store: SharedSettings.defaults) private var tolerance = 10
    @AppStorage(SharedSettings.Key.onlyStudyPhotos, store: SharedSettings.defaults) private var onlyStudyPhotos = true
    @AppStorage(SharedSettings.Key.useAppleIntelligence, store: SharedSettings.defaults) private var useAI = true
    @AppStorage(SharedSettings.Key.exportToFiles, store: SharedSettings.defaults) private var exportToFiles = true
    @AppStorage(SharedSettings.Key.showWeekend, store: SharedSettings.defaults) private var showWeekend = false

    @State private var confirmClear = false
    @State private var notificationStatus = "检查中…"
    @State private var permissionAlert: String?
    @State private var openSettingsAfterAlert = false
    @State private var liveActivityAlert: String?

    private var semesterStart: Binding<Date> {
        Binding(get: { Date(timeIntervalSinceReferenceDate: semesterStartRaw) },
                set: { semesterStartRaw = $0.timeIntervalSinceReferenceDate })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("学期") {
                    DatePicker("第 1 周周一", selection: semesterStart, displayedComponents: .date)
                    NavigationLink("作息时间（每节课的时间）") { PeriodTableEditor() }
                    Toggle("课表显示周末", isOn: $showWeekend)
                }

                Section {
                    Stepper("上课前 \(reminderMinutes) 分钟提醒", value: $reminderMinutes, in: 5...120, step: 5)
                    LabeledContent("通知权限", value: notificationStatus)
                    Button("开启通知权限") {
                        Task { await handleNotificationPermission() }
                    }
                    Button("打开系统通知设置") {
                        NotificationScheduler.shared.openNotificationSettings()
                    }
                    Button("发送测试通知（5秒后）") {
                        Task {
                            permissionAlert = await NotificationScheduler.shared.scheduleTestNotification()
                            openSettingsAfterAlert = false
                        }
                    }
                    Toggle("自动开启实时活动", isOn: $autoLiveActivity)
                    LabeledContent("实时活动", value: LiveActivityManager.shared.statusText)
                    Button("立即开启下一节课实时活动") {
                        Task {
                            let result = await LiveActivityManager.shared.startNext(courses: DataStore.shared.snapshots())
                            liveActivityAlert = result.message
                        }
                    }
                } header: {
                    Text("提醒与实时活动")
                } footer: {
                    Text("侧载安装时系统经常不弹通知授权框（会报 UNError 1）。请点「打开系统通知设置」，在「通知 › 玻璃课表」里打开「允许通知」，再回来发测试通知。实时活动需保留 Widget 扩展。")
                }

                Section {
                    Toggle("自动归类上课照片", isOn: $autoClassifyPhotos)
                    Stepper("前后容差 \(tolerance) 分钟", value: $tolerance, in: 0...30, step: 5)
                    Toggle("只归类学习资料（板书、PPT 等）", isOn: $onlyStudyPhotos)
                    Toggle("同时保存到“文件”App", isOn: $exportToFiles)
                } header: {
                    Text("复习资料")
                } footer: {
                    Text("照片会被加入“照片”App 中「专业」文件夹下的「课程 · 复习资料」相簿；副本保存在“文件 > 我的 iPhone > 玻璃课表 > 复习资料 > 专业 > 课程”。")
                }

                Section {
                    Toggle("使用 Apple 智能", isOn: $useAI)
                    LabeledContent("状态", value: AIScheduleExtractor.availabilityDescription)
                } header: {
                    Text("Apple 智能")
                } footer: {
                    Text("课表识别会同时使用 Apple 智能与本地规则，互相补全课程名、教室、教师、节次和周次。")
                }

                Section {
                    Button("清空全部课程", role: .destructive) { confirmClear = true }
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle("设置")
            .task { await refreshNotificationStatus() }
            .onChange(of: reminderMinutes) { _, _ in Task { await refresh() } }
            .onChange(of: semesterStartRaw) { _, _ in Task { await refresh() } }
            .confirmationDialog("确定清空全部 \(courses.count) 门课程？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    for course in courses { context.delete(course) }
                    try? context.save()
                    Task { await refresh() }
                }
            }
            .alert("通知权限", isPresented: Binding(get: { permissionAlert != nil }, set: { if !$0 { permissionAlert = nil } })) {
                if openSettingsAfterAlert {
                    Button("去通知设置") { NotificationScheduler.shared.openNotificationSettings() }
                    Button("取消", role: .cancel) {}
                } else {
                    Button("好", role: .cancel) {}
                }
            } message: {
                Text(permissionAlert ?? "")
            }
            .alert("实时活动", isPresented: Binding(get: { liveActivityAlert != nil }, set: { if !$0 { liveActivityAlert = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(liveActivityAlert ?? "")
            }
        }
    }

    private func refresh() async {
        await AppCoordinator.shared.refreshAll()
        await refreshNotificationStatus()
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationScheduler.shared.authorizationStatusText
    }

    private func handleNotificationPermission() async {
        let outcome = await NotificationScheduler.shared.ensurePermission()
        openSettingsAfterAlert = outcome.shouldOpenSettings
        permissionAlert = outcome.message
        await refreshNotificationStatus()
        if outcome == .granted || outcome == .provisional {
            await AppCoordinator.shared.refreshAll()
        } else if outcome.shouldOpenSettings {
            // 侧载环境几乎总会走到这里：稍延迟后自动跳转系统通知设置，避免只看到错误。
            try? await Task.sleep(for: .milliseconds(400))
            NotificationScheduler.shared.openNotificationSettings()
        }
    }
}

struct PeriodTableEditor: View {
    @State private var slots = SharedSettings.periodSlots

    var body: some View {
        Form {
            ForEach($slots) { $slot in
                Section("第 \(slot.index) 节") {
                    DatePicker("上课", selection: binding(for: $slot.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("下课", selection: binding(for: $slot.endMinutes), displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Button("增加一节") {
                    let last = slots.last
                    let start = (last?.endMinutes ?? 470) + 10
                    slots.append(PeriodSlot(index: slots.count + 1, startMinutes: start, endMinutes: start + 45))
                }
                if slots.count > 1 {
                    Button("删除最后一节", role: .destructive) { slots.removeLast() }
                }
                Button("恢复默认") { slots = PeriodTable.defaultSlots }
            }
            Section {
                Button("按新作息更新所有课程时间") { applyToCourses() }
            } footer: {
                Text("根据每门课的节次重新计算上下课时间。")
            }
        }
        .navigationTitle("作息时间")
        .onChange(of: slots) { _, newValue in
            SharedSettings.periodSlots = newValue
            Task { await AppCoordinator.shared.refreshAll() }
        }
    }

    private func applyToCourses() {
        for course in DataStore.shared.courses() {
            if let s = PeriodTable.slot(course.startPeriod, in: slots) { course.startMinutes = s.startMinutes }
            if let e = PeriodTable.slot(course.endPeriod, in: slots) { course.endMinutes = e.endMinutes }
        }
        DataStore.shared.save()
        Task { await AppCoordinator.shared.refreshAll() }
    }

    private func binding(for minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { SemesterCalendar.date(on: .now, minutes: minutes.wrappedValue) },
            set: {
                let c = SemesterCalendar.calendar.dateComponents([.hour, .minute], from: $0)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
