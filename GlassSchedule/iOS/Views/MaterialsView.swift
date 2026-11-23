import Photos
import SwiftData
import SwiftUI

struct MaterialsView: View {
    @Query(sort: [SortDescriptor(\Course.name)]) private var courses: [Course]
    @EnvironmentObject private var classifier: PhotoClassifier

    private var majors: [(String, [Course])] {
        Dictionary(grouping: courses) { $0.majorFolderName }
            .map { ($0.key, uniqueByName($0.value)) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    classifyCard
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                ForEach(majors, id: \.0) { major, list in
                    Section {
                        ForEach(list) { course in
                            NavigationLink {
                                CourseMaterialsView(courseName: course.name, major: major)
                            } label: {
                                HStack {
                                    Circle().fill(Color(hex: course.colorHex)).frame(width: 10, height: 10)
                                    Text("\(course.name) · 复习资料")
                                    Spacer()
                                    Text("\(materialCount(named: course.name))").foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Label(major, systemImage: "folder")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
            .navigationTitle("复习资料")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("在“文件”中打开", systemImage: "folder") { openFilesApp() }
                }
            }
        }
    }

    private var classifyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("自动归类上课照片", systemImage: "apple.intelligence").font(.headline)
            Text("按拍摄时间匹配课程，用 Apple 智能识别板书和 PPT，并在“照片”中按专业建文件夹、按课程建“复习资料”相簿。")
                .font(.subheadline).foregroundStyle(.secondary)
            if classifier.isRunning {
                ProgressView(value: classifier.progress) { Text(classifier.status).font(.caption) }
            } else if let summary = classifier.lastSummary {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("归类最近 7 天") {
                    Task { await classifier.classifyRecent(days: 7, requestAccessIfNeeded: true) }
                }
                .buttonStyle(.glassProminent)
                Button("整个学期") {
                    Task { await classifier.classifyRecent(days: 200, requestAccessIfNeeded: true) }
                }
                .buttonStyle(.glass)
            }
            .disabled(classifier.isRunning)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.vertical, 4)
    }

    /// 同一门课一周多次上课时只显示一次。
    private func uniqueByName(_ list: [Course]) -> [Course] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.name).inserted }
    }

    private func materialCount(named name: String) -> Int {
        courses.filter { $0.name == name }.reduce(0) { $0 + $1.materials.count }
    }

    private func openFilesApp() {
        try? FileManager.default.createDirectory(at: MaterialFileStore.rootURL, withIntermediateDirectories: true)
        if let url = URL(string: "shareddocuments://" + MaterialFileStore.rootURL.path) {
            UIApplication.shared.open(url)
        }
    }
}

struct CourseMaterialsView: View {
    let courseName: String
    let major: String

    @Query private var materials: [StudyMaterial]

    init(courseName: String, major: String) {
        self.courseName = courseName
        self.major = major
        _materials = Query(filter: #Predicate<StudyMaterial> { $0.course?.name == courseName },
                           sort: [SortDescriptor(\StudyMaterial.capturedAt, order: .reverse)])
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        ScrollView {
            if materials.isEmpty {
                ContentUnavailableView("暂无资料", systemImage: "photo.on.rectangle",
                                       description: Text("上课时拍下板书或 PPT，回到 App 后会自动归类到这里。"))
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(materials) { material in
                        NavigationLink {
                            MaterialDetailView(material: material)
                        } label: {
                            AssetThumbnail(localIdentifier: material.assetLocalIdentifier)
                                .frame(height: 104)
                                .clipShape(.rect(cornerRadius: 12))
                                .overlay(alignment: .bottomLeading) {
                                    Text("第\(material.week)周")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .glassEffect(.regular, in: .capsule)
                                        .padding(4)
                                }
                        }
                    }
                }
                .padding()
            }
        }
        .background(GlassBackground())
        .navigationTitle(courseName)
    }
}

struct MaterialDetailView: View {
    let material: StudyMaterial

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AssetThumbnail(localIdentifier: material.assetLocalIdentifier, targetSize: 1_400, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Text(material.title).font(.title3.bold())
                    Text(material.capturedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    if !material.summary.isEmpty { Text(material.summary) }
                    if !material.keywords.isEmpty {
                        HStack {
                            ForEach(material.keywords, id: \.self) { keyword in
                                Text(keyword).font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .glassEffect(.regular, in: .capsule)
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle("资料详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AssetThumbnail: View {
    let localIdentifier: String
    var targetSize: CGFloat = 300
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary).overlay { ProgressView() }
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: localIdentifier) {
            guard let asset = PhotoLibraryService.asset(id: localIdentifier) else { return }
            image = await PhotoLibraryService.image(for: asset, maxDimension: targetSize)
        }
    }
}
