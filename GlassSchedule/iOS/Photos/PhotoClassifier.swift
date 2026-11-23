import Foundation
import Photos
import SwiftData

/// 按“拍摄时间落在某节课的上课时间内”把照片归类到该课程的复习资料。
@MainActor
final class PhotoClassifier: ObservableObject {
    static let shared = PhotoClassifier()
    private static let skippedKey = "skippedPhotoAssets"

    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status = ""
    @Published private(set) var lastSummary: String?

    func classifyRecent(days: Int, requestAccessIfNeeded: Bool) async {
        let now = Date.now
        let start = max(SharedSettings.semesterStart, now.addingTimeInterval(-Double(days) * 86_400))
        await classify(from: start, to: now, requestAccessIfNeeded: requestAccessIfNeeded)
    }

    func classify(from start: Date, to end: Date, requestAccessIfNeeded: Bool) async {
        guard !isRunning else { return }
        if !PhotoLibraryService.hasAccess {
            guard requestAccessIfNeeded, await PhotoLibraryService.requestAccess() else {
                status = "未获得照片访问权限"
                return
            }
        }

        isRunning = true
        progress = 0
        status = "正在查找上课期间拍摄的照片…"
        defer { isRunning = false }

        let store = DataStore.shared
        let courses = store.courses()
        let byID = Dictionary(uniqueKeysWithValues: courses.map { ($0.id, $0) })
        var skippedIDs = Set(SharedSettings.defaults.stringArray(forKey: Self.skippedKey) ?? [])
        let known = Set(((try? store.context.fetch(FetchDescriptor<StudyMaterial>())) ?? []).map(\.assetLocalIdentifier))
            .union(skippedIDs)
        let tolerance = TimeInterval(SharedSettings.photoToleranceMinutes * 60)
        let occurrences = ScheduleQuery.occurrences(of: courses.map(\.snapshot), from: start, to: end,
                                                    semesterStart: SharedSettings.semesterStart)
            .filter { $0.start <= end }

        var added = 0
        var skipped = 0
        var albumCache: [UUID: PHAssetCollection] = [:]

        for (index, occurrence) in occurrences.enumerated() {
            if Task.isCancelled { break }
            progress = Double(index) / Double(max(occurrences.count, 1))
            guard let course = byID[occurrence.course.id] else { continue }

            let candidates = PhotoLibraryService.assets(from: occurrence.start.addingTimeInterval(-tolerance),
                                                         to: occurrence.end.addingTimeInterval(tolerance))
                .filter { !known.contains($0.localIdentifier) }
            guard !candidates.isEmpty else { continue }
            status = "正在分析「\(course.name)」第\(occurrence.week)周的 \(candidates.count) 张照片…"

            var accepted: [PHAsset] = []
            for asset in candidates {
                guard let image = await PhotoLibraryService.image(for: asset, maxDimension: 1_600) else { continue }
                let analysis = await MaterialAnalyzer.analyze(image: image, courseName: course.name)
                if SharedSettings.onlyStudyPhotos && !analysis.isStudyMaterial {
                    skipped += 1
                    skippedIDs.insert(asset.localIdentifier)
                    continue
                }
                let capturedAt = asset.creationDate ?? occurrence.start
                var relativePath: String?
                if SharedSettings.exportToFiles, let file = await PhotoLibraryService.originalData(for: asset) {
                    relativePath = try? MaterialFileStore.save(data: file.0, ext: file.1, major: course.majorFolderName,
                                                               course: course.name, capturedAt: capturedAt,
                                                               periodText: occurrence.course.periodText)
                    MaterialFileStore.appendNote(major: course.majorFolderName, course: course.name, capturedAt: capturedAt,
                                                 title: analysis.title, summary: analysis.summary, keywords: analysis.keywords)
                }
                let material = StudyMaterial(assetLocalIdentifier: asset.localIdentifier, capturedAt: capturedAt,
                                             week: occurrence.week, relativeFilePath: relativePath,
                                             title: analysis.title, summary: analysis.summary,
                                             keywords: analysis.keywords, course: course)
                store.context.insert(material)
                accepted.append(asset)
            }

            if !accepted.isEmpty {
                do {
                    let album: PHAssetCollection
                    if let cached = albumCache[course.id] {
                        album = cached
                    } else {
                        let folder = try await PhotoLibraryService.folder(named: course.majorFolderName)
                        album = try await PhotoLibraryService.album(named: "\(course.name) · 复习资料", in: folder)
                        albumCache[course.id] = album
                    }
                    try await PhotoLibraryService.add(accepted, to: album)
                } catch {
                    print("写入相簿失败：\(error)")
                }
                added += accepted.count
                store.save()
            }
        }

        SharedSettings.defaults.set(Array(skippedIDs.suffix(5_000)), forKey: Self.skippedKey)
        progress = 1
        status = ""
        lastSummary = added == 0 && skipped == 0
            ? "没有发现新的上课照片"
            : "新归类 \(added) 张照片" + (skipped > 0 ? "，跳过 \(skipped) 张非学习资料" : "")
    }
}
