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
                    Button("开启 / 重新检查通知权限") {
                        Task { await handleNotificationPermission() }
                    }
                    Button("打开本 App 设置页") {
                        NotificationScheduler.shared.openAppSettings()
                    }
                    Button("打开通知设置") {
                        NotificationScheduler.shared.openNotificationSettings()
                    }
                    Button("发送测试通知（5秒后）") {
                        Task {
                            permissionAlert = await NotificationScheduler.shared.scheduleTestNotification()
                            openSettingsAfterAlert = permissionAlert?.contains("系统设置") == true
                                || permissionAlert?.contains("没有通知权限") == true
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
                    Text("侧载常见：系统不弹授权框，且「设置 › 通知」列表里暂时找不到本 App。请先点「开启 / 重新检查」，再点「打开本 App 设置页」——在设置主页滑到最底部找到「Classio」，打开里面的「通知」。Sideloadly 安装时不要用 Live Container，并保留 Widget 扩展。")
                }

                Section {
                    Toggle("自动归类上课照片", isOn: $autoClassifyPhotos)
                    Stepper("前后容差 \(tolerance) 分钟", value: $tolerance, in: 0...30, step: 5)
                    Toggle("只归类学习资料（板书、PPT 等）", isOn: $onlyStudyPhotos)
                    Toggle("同时保存到“文件”App", isOn: $exportToFiles)
                } header: {
                    Text("复习资料")
                } footer: {
                    Text("照片会被加入“照片”App 中「专业」文件夹下的「课程 · 复习资料」相簿；副本保存在“文件 > 我的 iPhone > Classio > 复习资料 > 专业 > 课程”。")
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
                    Button("打开本 App 设置页") { NotificationScheduler.shared.openAppSettings() }
                    Button("打开通知设置") { NotificationScheduler.shared.openNotificationSettings() }
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
            // 侧载时通知总列表常没有本 App，优先跳到「设置 › Classio」本页。
            try? await Task.sleep(for: .milliseconds(400))
            NotificationScheduler.shared.openAppSettings()
        }
    }
}

struct PeriodTableEditor: View {
    @State private var slots = SharedSettings.periodSlots
    @State private var durationMinutes = SharedSettings.periodDurationMinutes
    @State private var breakMinutes = SharedSettings.periodBreakMinutes
    @State private var firstStartMinutes: Int = SharedSettings.periodSlots.first?.startMinutes ?? 8 * 60
    @State private var autoCascade = true
    @State private var suppressCascade = false

    var body: some View {
        Form {
            Section {
                Stepper("每节课时长 \(durationMinutes) 分钟", value: $durationMinutes, in: 5...120, step: 5)
                Stepper("课间休息 \(breakMinutes) 分钟", value: $breakMinutes, in: 0...60, step: 5)
                DatePicker("第一节上课", selection: binding(for: $firstStartMinutes), displayedComponents: .hourAndMinute)
                Toggle("改完后自动重排后面所有节", isOn: $autoCascade)
                Button("按以上规则重新生成全部作息") { applyCascade(updateCourses: true) }
            } header: {
                Text("批量设置")
            } footer: {
                Text("例：第一节 08:50、时长 40、课间 10 → ①08:50–09:30 ②09:40–10:20 ③10:30–11:10 ④11:20–12:00。重排后会同步更新已有课程的上下课时间。")
            }

            if slots.count >= 4 {
                Section("预览（前 4 节）") {
                    ForEach(slots.prefix(4)) { slot in
                        LabeledContent("第 \(slot.index) 节",
                                       value: "\(TimeFormat.string(slot.startMinutes))–\(TimeFormat.string(slot.endMinutes))")
                    }
                }
            }

            ForEach($slots) { $slot in
                Section("第 \(slot.index) 节 · \(TimeFormat.string(slot.startMinutes))–\(TimeFormat.string(slot.endMinutes))") {
                    DatePicker("上课", selection: binding(for: $slot.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("下课", selection: binding(for: $slot.endMinutes), displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Button("增加一节") {
                    let last = slots.last
                    let start = (last?.endMinutes ?? firstStartMinutes) + breakMinutes
                    slots.append(PeriodSlot(index: slots.count + 1, startMinutes: start, endMinutes: start + durationMinutes))
                }
                if slots.count > 1 {
                    Button("删除最后一节", role: .destructive) { slots.removeLast() }
                }
                Button("恢复默认") {
                    suppressCascade = true
                    slots = PeriodTable.defaultSlots
                    firstStartMinutes = slots.first?.startMinutes ?? 8 * 60
                    durationMinutes = 45
                    breakMinutes = 10
                    suppressCascade = false
                }
            }
            Section {
                Button("按新作息更新所有课程时间") { applyToCourses() }
            } footer: {
                Text("根据每门课的节次重新计算上下课时间。")
            }
        }
        .navigationTitle("作息时间")
        .onChange(of: durationMinutes) { _, newValue in
            SharedSettings.periodDurationMinutes = newValue
            if autoCascade { applyCascade(updateCourses: true) }
        }
        .onChange(of: breakMinutes) { _, newValue in
            SharedSettings.periodBreakMinutes = newValue
            if autoCascade { applyCascade(updateCourses: true) }
        }
        .onChange(of: firstStartMinutes) { _, _ in
            if autoCascade { applyCascade(updateCourses: true) }
        }
        .onChange(of: slots) { _, newValue in
            guard !suppressCascade else { return }
            SharedSettings.periodSlots = newValue
            Task { await AppCoordinator.shared.refreshAll() }
        }
        .onAppear {
            // 若当前作息把课间算进了课时（如下课时间=下一节上课），按批量参数纠正一次
            if slotsLookMergedWithBreak() {
                applyCascade(updateCourses: true)
            }
        }
    }

    /// 检测「08:50–09:40、09:40–10:30」这种把课间吃进课时的错误作息。
    private func slotsLookMergedWithBreak() -> Bool {
        guard slots.count >= 2, breakMinutes > 0 else { return false }
        var suspicious = 0
        for index in 0..<(slots.count - 1) {
            let current = slots[index]
            let next = slots[index + 1]
            let duration = current.endMinutes - current.startMinutes
            if current.endMinutes == next.startMinutes, duration == durationMinutes + breakMinutes {
                suspicious += 1
            }
        }
        return suspicious >= 2
    }

    private func applyCascade(updateCourses: Bool) {
        suppressCascade = true
        let count = max(slots.count, 1)
        slots = PeriodTable.cascade(count: count,
                                    firstStartMinutes: firstStartMinutes,
                                    durationMinutes: durationMinutes,
                                    breakMinutes: breakMinutes)
        SharedSettings.periodDurationMinutes = durationMinutes
        SharedSettings.periodBreakMinutes = breakMinutes
        SharedSettings.periodSlots = slots
        suppressCascade = false
        if updateCourses { applyToCourses() }
        else { Task { await AppCoordinator.shared.refreshAll() } }
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
