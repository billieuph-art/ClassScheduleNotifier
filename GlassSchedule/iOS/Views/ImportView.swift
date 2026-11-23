import PhotosUI
import SwiftData
import SwiftUI

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var existing: [Course]

    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pastedText = ""
    @State private var showPaste = false

    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var outcome: ImportOutcome?
    @State private var drafts: [CourseDraft] = []
    @State private var major = SharedSettings.defaultMajor
    @State private var replaceExisting = false
    @State private var weekScope: ImportWeekScope = .everyWeek

    var body: some View {
        NavigationStack {
            Group {
                if outcome != nil {
                    previewList
                } else {
                    sourcePicker
                }
            }
            .background(GlassBackground())
            .navigationTitle(outcome == nil ? "导入课程表" : "确认课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark", role: .close) { dismiss() }
                }
                if outcome != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存", systemImage: "checkmark", role: .confirm) { save() }
                            .disabled(!drafts.contains { $0.isIncluded })
                    }
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: TextExtractor.supportedTypes) { result in
                if case .success(let url) = result {
                    run { try await TextExtractor.extract(fileAt: url) }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                run {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        throw ImportError.unreadable
                    }
                    return try await TextExtractor.extract(image: image)
                }
            }
            .alert("导入失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showPaste) { pasteSheet }
        }
    }

    // MARK: - 选择来源

    private var sourcePicker: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isProcessing {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text(processingTitle).font(.headline)
                        Text("所有识别均在本机完成，课表不会上传").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(30)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))
                }

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            sourceRow("photo.on.rectangle.angled", "从截图导入", "教务系统、App 里的课表截图")
                        }
                        Button { showFileImporter = true } label: {
                            sourceRow("doc.richtext", "从文件导入", "PDF、图片、ICS 日历、CSV、TXT、HTML")
                        }
                        Button { showPaste = true } label: {
                            sourceRow("doc.on.clipboard", "粘贴文字", "从网页或聊天里复制的课表文字")
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                VStack(alignment: .leading, spacing: 6) {
                    Label(intelligenceCaption, systemImage: AIScheduleExtractor.isAvailable ? "apple.intelligence" : "text.viewfinder")
                    Text("单双周课表：先导入单周截图并选「所有单周」，再导入双周截图选「所有双周」，并关闭「替换现有课表」。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
            .padding()
        }
    }

    private var processingTitle: String {
        if AIScheduleExtractor.isAvailable && SharedSettings.useAppleIntelligence {
            return "正在识别课程表…"
        }
        return "正在用本地规则识别课程表…"
    }

    private var intelligenceCaption: String {
        if AIScheduleExtractor.isAvailable {
            return "可用 Apple 智能辅助；超星网格也会优先用本地规则。"
        }
        return "此机型无 Apple 智能，将使用本机 Vision OCR + 本地规则识别（可正常导入截图）。"
    }

    private func sourceRow(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title2).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(18)
        .contentShape(.rect)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
    }

    private var pasteSheet: some View {
        NavigationStack {
            TextEditor(text: $pastedText)
                .padding()
                .navigationTitle("粘贴课表文字")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("识别", role: .confirm) {
                            showPaste = false
                            let text = pastedText
                            run { ExtractedDocument(plainText: text) }
                        }
                        .disabled(pastedText.isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 预览

    private var previewList: some View {
        List {
            Section {
                if let outcome {
                    Label("\(outcome.engine.label) · 识别到 \(drafts.count) 节课", systemImage: outcome.engine.symbol)
                    if let week = outcome.detectedTeachingWeek {
                        Label("截图显示第 \(week) 周", systemImage: "calendar")
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("专业（资料归档文件夹）", text: $major)

                Picker("这些课属于", selection: $weekScope) {
                    ForEach(ImportWeekScope.allCases) { scope in
                        Text(scope.title(detectedWeek: outcome?.detectedTeachingWeek)).tag(scope)
                    }
                }
                .onChange(of: weekScope) { _, newValue in
                    ScheduleImporter.applyWeekScope(newValue,
                                                    detectedWeek: outcome?.detectedTeachingWeek,
                                                    to: &drafts,
                                                    overwriteExplicit: true)
                }

                Toggle("替换现有课表（\(existing.count) 门）", isOn: $replaceExisting)
            } footer: {
                Text(weekScopeFooter)
            }

            ForEach(1...7, id: \.self) { day in
                if drafts.contains(where: { $0.weekday == day }) {
                    Section(WeekdayName.full(day)) {
                        ForEach($drafts) { $draft in
                            if draft.weekday == day {
                                DraftRow(draft: $draft)
                                    .swipeActions {
                                        Button("删除", systemImage: "trash", role: .destructive) {
                                            let id = draft.id
                                            drafts.removeAll { $0.id == id }
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            Section {
                Button("重新选择", systemImage: "arrow.counterclockwise") {
                    outcome = nil
                    drafts = []
                    photoItem = nil
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var weekScopeFooter: String {
        let week = outcome?.detectedTeachingWeek
        switch weekScope {
        case .screenshotWeek:
            if let week {
                return "只会写入第 \(week) 周，不会当成全学期每周都上。单双周不同时，请再导入另一周截图并选「所有单周/双周」，且关闭「替换」。"
            }
            return "未识别到截图周次时，请改选单周、双周或每周。"
        case .oddWeeks:
            return "适用于单周课表。保存时建议关闭「替换」，再导入双周截图合并。"
        case .evenWeeks:
            return "适用于双周课表。保存时建议关闭「替换」，与已有单周课合并。"
        case .everyWeek:
            return "周次留空表示每周都上。若截图只是某一周，请改选「仅第 N 周」或单/双周。"
        }
    }

    // MARK: - Actions

    private func run(_ extract: @escaping () async throws -> ExtractedDocument) {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                let document = try await extract()
                let result = await ScheduleImporter.parse(document)
                if result.drafts.isEmpty {
                    errorMessage = "没有识别出课程。可以尝试裁剪掉无关区域后重新截图，或手动添加。无 Apple 智能时也会用本地规则识别。"
                } else {
                    drafts = result.drafts.sorted { ($0.weekday, $0.startPeriod) < ($1.weekday, $1.startPeriod) }
                    outcome = result
                    weekScope = ImportWeekScope.defaultScope(detectedWeek: result.detectedTeachingWeek)
                    // 单周截图默认合并进现有课表，方便再导双周
                    replaceExisting = result.detectedTeachingWeek == nil && existing.isEmpty
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        let majorName = major.trimmingCharacters(in: .whitespaces)
        if replaceExisting {
            for course in existing { context.delete(course) }
            for draft in drafts where draft.isIncluded && draft.isValid {
                context.insert(draft.makeCourse(major: majorName))
            }
        } else {
            mergeIntoExisting(major: majorName)
        }
        try? context.save()
        if !majorName.isEmpty { SharedSettings.defaults.set(majorName, forKey: SharedSettings.Key.defaultMajor) }
        Task { await AppCoordinator.shared.refreshAll() }
        dismiss()
    }

    /// 合并导入：同名同学期同节次则合并周次；否则新增（支持单双周两套课）。
    private func mergeIntoExisting(major: String) {
        for draft in drafts where draft.isIncluded && draft.isValid {
            if let match = existing.first(where: {
                $0.name == draft.name
                    && $0.weekday == draft.weekday
                    && $0.startPeriod == draft.startPeriod
                    && $0.endPeriod == draft.endPeriod
                    && $0.classroom == draft.classroom
            }) {
                if draft.weeks.isEmpty {
                    match.weeks = []
                } else if match.weeks.isEmpty {
                    // 旧数据是「每周」；新导入有明确周次时，改为明确周次（避免继续污染全学期）
                    match.weeks = draft.weeks
                } else {
                    match.weeks = Array(Set(match.weeks + draft.weeks)).sorted()
                }
                if match.teacher.isEmpty { match.teacher = draft.teacher }
                if !major.isEmpty { match.major = major }
            } else {
                context.insert(draft.makeCourse(major: major))
            }
        }
    }
}

private struct DraftRow: View {
    @Binding var draft: CourseDraft
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    draft.isIncluded.toggle()
                } label: {
                    Image(systemName: draft.isIncluded ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(draft.isIncluded ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name).font(.headline)
                    Text("\(draft.periodText) · \(draft.timeText) · \(draft.classroom.isEmpty ? "教室未知" : draft.classroom)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(WeeksParser.format(draft.weeks)).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(expanded ? "完成" : "修改") { withAnimation { expanded.toggle() } }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            if expanded {
                TextField("课程名称", text: $draft.name)
                TextField("教室", text: $draft.classroom)
                TextField("教师", text: $draft.teacher)
                Picker("星期", selection: $draft.weekday) {
                    ForEach(1...7, id: \.self) { Text(WeekdayName.full($0)).tag($0) }
                }
                Stepper("开始：第\(draft.startPeriod)节", value: $draft.startPeriod, in: 1...16)
                    .onChange(of: draft.startPeriod) { _, _ in recomputeTimes() }
                Stepper("结束：第\(draft.endPeriod)节", value: $draft.endPeriod, in: draft.startPeriod...16)
                    .onChange(of: draft.endPeriod) { _, _ in recomputeTimes() }
                TextField("周次（如 13 或 1,3,5，留空为每周）", text: Binding(
                    get: { draft.weeks.isEmpty ? "" : WeeksParser.format(draft.weeks).replacingOccurrences(of: "周", with: "") },
                    set: { draft.weeks = WeeksParser.parse($0) }
                ))
            }
        }
        .opacity(draft.isIncluded ? 1 : 0.5)
    }

    private func recomputeTimes() {
        let slots = SharedSettings.periodSlots
        if draft.endPeriod < draft.startPeriod { draft.endPeriod = draft.startPeriod }
        if let s = PeriodTable.slot(draft.startPeriod, in: slots) { draft.startMinutes = s.startMinutes }
        if let e = PeriodTable.slot(draft.endPeriod, in: slots) { draft.endMinutes = e.endMinutes }
    }
}
