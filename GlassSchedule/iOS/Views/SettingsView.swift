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
                    Toggle("自动开启实时活动", isOn: $autoLiveActivity)
                    Button("开启通知权限") { Task { await NotificationScheduler.shared.requestAuthorization(); await refresh() } }
                } header: {
                    Text("提醒与实时活动")
                } footer: {
                    Text("提醒到达时点按“在灵动岛显示倒计时”即可开启实时活动；也可在“快捷指令”中创建自动化运行“开始下一节课的实时活动”，做到完全自动。")
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
                    Text("课表识别和照片摘要都由端侧模型完成，数据不会离开你的设备。")
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
            .onChange(of: reminderMinutes) { _, _ in Task { await refresh() } }
            .onChange(of: semesterStartRaw) { _, _ in Task { await refresh() } }
            .confirmationDialog("确定清空全部 \(courses.count) 门课程？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    for course in courses { context.delete(course) }
                    try? context.save()
                    Task { await refresh() }
                }
            }
        }
    }

    private func refresh() async {
        await AppCoordinator.shared.refreshAll()
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
