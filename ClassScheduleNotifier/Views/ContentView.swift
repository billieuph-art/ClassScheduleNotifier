import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct ContentView: View {
    @EnvironmentObject private var store: ScheduleStore
    @EnvironmentObject private var notifications: NotificationScheduler
    @State private var showingEditor = false
    @State private var showingImporter = false
    @State private var showingSettings = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importError: String?
    @State private var isImporting = false

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
                        description: Text("可以手动添加课程，或导入学校课表截图。")
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
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("导入课表截图", systemImage: "photo")
                        }
                        Button("重新生成提醒", systemImage: "bell.badge") {
                            Task { await notifications.scheduleAll(for: store.courses) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("设置")

                        Button { showingEditor = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("添加课程")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                CourseEditorView { course in
                    store.add(course)
                    Task { await notifications.scheduleAll(for: store.courses) }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(notifications)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                Task { await handleFileImport(result) }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await handlePhotoImport(newItem) }
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("好", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
            .overlay {
                if isImporting {
                    ProgressView("正在识别课表...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
            .task {
                await notifications.refreshStatus()
                if notifications.authorizationStatus == .notDetermined {
                    await notifications.requestAuthorization()
                }
                await notifications.scheduleAll(for: store.courses)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
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
            await notifications.scheduleAll(for: store.courses)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func handlePhotoImport(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                importError = "无法读取图片"
                return
            }
            let imported = try await ImportService.parseImage(image)
            guard !imported.isEmpty else {
                importError = "没有从截图中识别到课程。请确保图片清晰，并包含课程名、时间、周数等信息。"
                return
            }
            store.courses.append(contentsOf: imported)
            store.save()
            await notifications.scheduleAll(for: store.courses)
        } catch {
            importError = error.localizedDescription
        }
        selectedPhoto = nil
    }
}
