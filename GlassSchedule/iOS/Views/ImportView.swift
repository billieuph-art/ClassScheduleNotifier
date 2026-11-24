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
    @State private var showSaveReviewAlert = false

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
                        Button("保存", systemImage: "checkmark", role: .confirm) { requestSave() }
                            .disabled(!drafts.contains { $0.isIncluded && $0.isValid })
                    }
                }
            }
            .alert("仍有待确认课程", isPresented: $showSaveReviewAlert) {
                Button("继续保存", role: .destructive) { save() }
                Button("回去检查", role: .cancel) {}
            } message: {
                Text("勾选的课程里仍有「待确认」项（字段不全或课名可疑）。未点保存前不会写入课表；建议先修改或取消勾选。")
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

                Label(intelligenceCaption, systemImage: AIScheduleExtractor.isAvailable ? "apple.intelligence" : "text.viewfinder")
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

                Picker("周次归属", selection: $weekScope) {
                    ForEach(ImportWeekScope.allCases) { scope in
                        Text(scope.title(detectedWeek: outcome?.detectedTeachingWeek)).tag(scope)
                    }
                }
                .onChange(of: weekScope) { _, newValue in
                    // 自动识别：不覆盖格子结果；手动选项：整表统一改写
                    if let original = outcome?.drafts, newValue == .autoDetected {
                        drafts = original.sorted { ($0.weekday, $0.startPeriod) < ($1.weekday, $1.startPeriod) }
                    } else {
                        ScheduleImporter.applyWeekScope(newValue,
                                                        detectedWeek: outcome?.detectedTeachingWeek,
                                                        to: &drafts,
                                                        overwriteExplicit: true)
                    }
                }

                Toggle("替换现有课表（\(existing.count) 门）", isOn: $replaceExisting)
            } footer: {
                Text(weekScopeFooter)
            }

            if !reviewHints.isEmpty {
                Section {
                    ForEach(reviewHints, id: \.self) { hint in
                        Label(hint, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("请核对")
                }
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

    private var reviewHints: [String] {
        var hints: [String] = []
        let included = drafts.filter(\.isIncluded)
        let suspicious = included.filter {
            OCRCleanup.looksLikeMergedCourses($0.name) || OCRCleanup.isBogusCourseName($0.name)
        }
        if !suspicious.isEmpty {
            hints.append("有 \(suspicious.count) 门课名疑似识别拼接错误，请点「修改」检查或取消勾选。")
        }
        let missing = included.filter { $0.classroom.isEmpty || $0.teacher.isEmpty }.count
        if missing > 0 {
            hints.append("有 \(missing) 门课教室或教师为空，保存前建议补全。")
        }
        // 同学期同学段冲突仅提示，不自动删除（可能是单双周两套课）
        var seen: [String: Int] = [:]
        for d in included where d.startPeriod > 0 {
            let key = "\(d.weekday)-\(d.startPeriod)-\(d.endPeriod)"
            seen[key, default: 0] += 1
        }
        let conflicts = seen.values.filter { $0 > 1 }.count
        if conflicts > 0 {
            hints.append("有 \(conflicts) 个时段存在多门课，若非单双周两套请核对。")
        }
        return hints
    }

    private var weekScopeFooter: String {
        let week = outcome?.detectedTeachingWeek
        switch weekScope {
        case .autoDetected:
            return "默认保留截图里每门课自己的周次（含「单周」「双周」）。若识别有误，可改选手动选项整表覆盖，或点「修改」逐门调整。"
        case .screenshotWeek:
            if let week {
                return "所有课只会写入第 \(week) 周。"
            }
            return "未识别到截图周次时，请改选自动识别、单周、双周或每周。"
        case .oddWeeks:
            return "把当前列表里全部课程改成单周（1、3、5…）。"
        case .evenWeeks:
            return "把当前列表里全部课程改成双周（2、4、6…）。"
        case .everyWeek:
            return "周次留空表示每周都上。"
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
                    var prepared = result.drafts
                    for i in prepared.indices { prepared[i].applyImportSafety() }
                    drafts = prepared.sorted { ($0.weekday, $0.startPeriod) < ($1.weekday, $1.startPeriod) }
                    outcome = result
                    weekScope = ImportWeekScope.defaultScope(detectedWeek: result.detectedTeachingWeek,
                                                             hasPerCourseWeeks: result.drafts.contains { !$0.weeks.isEmpty })
                    // 已有课表时默认合并，避免冲掉另一半单/双周
                    replaceExisting = existing.isEmpty
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestSave() {
        let risky = drafts.contains { $0.isIncluded && $0.isValid && $0.needsReview }
        if risky {
            showSaveReviewAlert = true
        } else {
            save()
        }
    }

    private func save() {
        // 关闭/取消不会走到这里；仅确认保存才写入
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
                    HStack(spacing: 6) {
                        Text(draft.name).font(.headline)
                        if draft.needsReview {
                            Text(draft.classroom.isEmpty && draft.teacher.isEmpty ? "缺教室/教师" : "待确认")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("\(draft.periodText) · \(draft.timeText) · \(draft.classroom.isEmpty ? "教室未知" : draft.classroom)"
                         + (draft.teacher.isEmpty ? "" : " · \(draft.teacher)"))
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
