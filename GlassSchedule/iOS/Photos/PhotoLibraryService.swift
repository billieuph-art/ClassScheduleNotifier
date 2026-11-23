import Photos
import UIKit
import UniformTypeIdentifiers

/// 在“照片”App 中维护“专业文件夹 › 课程·复习资料相簿”的结构。
enum PhotoLibraryService {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static func assets(from start: Date, to end: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d",
                                        start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    static func asset(id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    static func folder(named title: String) async throws -> PHCollectionList {
        let existing = PHCollectionList.fetchTopLevelUserCollections(with: nil)
        var found: PHCollectionList?
        existing.enumerateObjects { collection, _, stop in
            if let list = collection as? PHCollectionList, list.localizedTitle == title {
                found = list
                stop.pointee = true
            }
        }
        if let found { return found }

        let identifier = IdentifierBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: title)
            identifier.value = request.placeholderForCreatedCollectionList.localIdentifier
        }
        guard let list = PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [identifier.value], options: nil).firstObject else {
            throw CocoaError(.fileNoSuchFile)
        }
        return list
    }

    static func album(named title: String, in folder: PHCollectionList) async throws -> PHAssetCollection {
        var found: PHAssetCollection?
        PHCollection.fetchCollections(in: folder, options: nil).enumerateObjects { collection, _, stop in
            if let album = collection as? PHAssetCollection, album.localizedTitle == title {
                found = album
                stop.pointee = true
            }
        }
        if let found { return found }

        let identifier = IdentifierBox()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            let placeholder = request.placeholderForCreatedAssetCollection
            identifier.value = placeholder.localIdentifier
            PHCollectionListChangeRequest(for: folder)?.addChildCollections([placeholder] as NSArray)
        }
        guard let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier.value], options: nil).firstObject else {
            throw CocoaError(.fileNoSuchFile)
        }
        return album
    }

    static func add(_ assets: [PHAsset], to album: PHAssetCollection) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray)
        }
    }

    static func image(for asset: PHAsset, maxDimension: CGFloat) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let size = CGSize(width: maxDimension, height: maxDimension)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                continuation.resume(returning: image)
            }
        }
    }

    static func originalData(for asset: PHAsset) async -> (Data, String)? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                guard let data else { return continuation.resume(returning: nil) }
                let ext = uti.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"
                continuation.resume(returning: (data, ext))
            }
        }
    }
}

/// performChanges 的闭包是 @Sendable，不能直接修改外部 var。
private final class IdentifierBox: @unchecked Sendable {
    var value = ""
}

/// 把照片副本按“复习资料/专业/课程/”存到 App 的文稿目录，可在“文件”App 中浏览。
enum MaterialFileStore {
    static var rootURL: URL {
        URL.documentsDirectory.appendingPathComponent("复习资料", isDirectory: true)
    }

    static func directory(major: String, course: String) -> URL {
        rootURL.appendingPathComponent(sanitize(major), isDirectory: true)
            .appendingPathComponent(sanitize(course), isDirectory: true)
    }

    static func save(data: Data, ext: String, major: String, course: String, capturedAt: Date, periodText: String) throws -> String {
        let dir = directory(major: major, course: course)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        var url = dir.appendingPathComponent("\(formatter.string(from: capturedAt))_\(periodText).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(formatter.string(from: capturedAt))_\(periodText)_\(n).\(ext)")
            n += 1
        }
        try data.write(to: url)
        return String(url.path.dropFirst(URL.documentsDirectory.path.count + 1))
    }

    /// 每门课一个“AI 复习笔记.md”，追加每张照片的摘要。
    static func appendNote(major: String, course: String, capturedAt: Date, title: String, summary: String, keywords: [String]) {
        let url = directory(major: major, course: course).appendingPathComponent("AI 复习笔记.md")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var entry = "\n## \(title)（\(formatter.string(from: capturedAt))）\n\(summary)\n"
        if !keywords.isEmpty { entry += "\n关键词：" + keywords.joined(separator: "、") + "\n" }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(entry.utf8))
            try? handle.close()
        } else {
            try? Data(("# \(course) 复习笔记\n" + entry).utf8).write(to: url)
        }
    }

    private static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return (trimmed.isEmpty ? "未命名" : trimmed).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }
}
