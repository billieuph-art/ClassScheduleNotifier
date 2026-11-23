import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ScheduleStore
    @EnvironmentObject private var notifications: NotificationScheduler
    @State private var showingEditor = false
    @State private var showingImporter = false
    @State private var importError: String?

    private var todayCourses: [Course] {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let appWeekday = weekday == 1 ? 7 : weekday - 1
        return store.courses
            .filter { $0.weekday.rawValue == appWeekday }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            Group {
                if todayCourses.isEmpty {
                    ContentUnavailableView(
                        "今天没有课程",
                        systemImage: "calendar",
                        description: Text("可以手动添加课程，或导入学校课表。")
                    )
                } else {
                    List {
                        Section("今天 · \(Date.now.formatted(date: .abbreviated, time: .omitted))") {
                            ForEach(todayCourses) { course in
                                CourseRow(course: course)
                            }
                            .onDelete { offsets in
                                let ids = offsets.map { todayCourses[$0].id }
                                store.courses.removeAll { ids.contains($0.id) }
                                store.save()
                                Task { await notifications.scheduleAll(for: store.courses) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("我的课表")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("导入 CSV 文件", systemImage: "doc.text") { showingImporter = true }
                        Button("重新生成提醒", systemImage: "bell.badge") {
                            Task { await notifications.scheduleAll(for: store.courses) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加课程")
                }
            }
            .sheet(isPresented: $showingEditor) {
                CourseEditorView { course in
                    store.add(course)
                    Task { await notifications.scheduleAll(for: store.courses) }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                do {
                    guard let url = try result.get().first else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let imported = try ImportService.parseCSV(text)
                    guard !imported.isEmpty else {
                        importError = "没有识别到课程。请检查 CSV 表头和内容。"
                        return
                    }
                    store.courses.append(contentsOf: imported)
                    store.save()
                    Task { await notifications.scheduleAll(for: store.courses) }
                } catch {
                    importError = error.localizedDescription
                }
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .task {
                await notifications.requestAuthorization()
                await notifications.scheduleAll(for: store.courses)
            }
        }
    }
}