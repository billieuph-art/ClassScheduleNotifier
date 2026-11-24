import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

/// OCR 得到的一段文字及其在页面中的位置（归一化坐标，原点在左上角）。
struct TextItem: Hashable {
    var text: String
    var rect: CGRect
    var page: Int
    /// Vision 候选置信度 0…1；旧路径或无置信度时为 1。
    var confidence: Float = 1
}

struct ExtractedDocument {
    var items: [TextItem] = []
    var plainText: String = ""
    var icsCourses: [CourseDraft] = []
}

enum ImportError: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取该文件"
        case .empty: "没有识别到任何文字，请换一张更清晰的截图"
        }
    }
}

enum TextExtractor {
    static let supportedTypes: [UTType] = [
        .pdf, .image, .png, .jpeg, .heic, .plainText, .commaSeparatedText, .html,
        UTType(filenameExtension: "ics") ?? .calendarEvent,
    ]

    static func extract(fileAt url: URL) async throws -> ExtractedDocument {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .pdf) {
            return try await extractPDF(url)
        }
        if type.conforms(to: .image) {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { throw ImportError.unreadable }
            return try await extract(image: image)
        }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
            ?? ""
        if url.pathExtension.lowercased() == "ics" {
            return ExtractedDocument(plainText: text, icsCourses: ICSParser.parse(text))
        }
        if type.conforms(to: .html) {
            return ExtractedDocument(plainText: stripHTML(text))
        }
        return ExtractedDocument(plainText: text)
    }

    static func extract(image: UIImage) async throws -> ExtractedDocument {
        guard let cgImage = image.normalizedCGImage() else { throw ImportError.unreadable }
        let items = try await recognize(cgImage, page: 0)
        guard !items.isEmpty else { throw ImportError.empty }
        return ExtractedDocument(items: items, plainText: "")
    }

    /// PDF 同时读取文字层，并把每页渲染成图片做 OCR 以保留表格布局（扫描版 PDF 也能识别）。
    private static func extractPDF(_ url: URL) async throws -> ExtractedDocument {
        guard let pdf = PDFDocument(url: url) else { throw ImportError.unreadable }
        var document = ExtractedDocument()
        var texts: [String] = []
        for index in 0..<min(pdf.pageCount, 6) {
            guard let page = pdf.page(at: index) else { continue }
            if let text = page.string, !text.isEmpty { texts.append(text) }
            let bounds = page.bounds(for: .mediaBox)
            let scale = max(1, 2400 / max(bounds.width, bounds.height))
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            if let cg = image.cgImage {
                document.items += try await recognize(cg, page: index)
            }
        }
        document.plainText = texts.joined(separator: "\n")
        if document.items.isEmpty && document.plainText.isEmpty { throw ImportError.empty }
        return document
    }

    static func recognize(_ cgImage: CGImage, page: Int) async throws -> [TextItem] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.Language(identifier: "zh-Hans"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: cgImage)
        let raw: [TextItem] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let confidence = candidate.confidence
            // 过低置信度易产生串字，丢掉
            if confidence < 0.35 { return nil }
            let box = observation.boundingBox.cgRect
            // Vision 的原点在左下角，转换为左上角便于按行排序。
            let rect = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            let text = candidate.string
                .replacingOccurrences(of: "：", with: ":")
                .applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? candidate.string
            return TextItem(text: text, rect: rect, page: page, confidence: confidence)
        }
        return OCRCleanup.dedupeItems(raw)
    }

    /// 把 OCR 结果按行排列并附上横坐标，方便大模型理解表格列（星期）与行（节次）。
    static func layoutDescription(_ items: [TextItem]) -> String {
        var lines: [String] = []
        for page in Set(items.map(\.page)).sorted() {
            let rows = LayoutRows.group(items.filter { $0.page == page })
            for row in rows {
                lines.append(row.map { "[x=\(String(format: "%.2f", $0.rect.midX)) y=\(String(format: "%.2f", $0.rect.midY))] \($0.text)" }
                    .joined(separator: "  "))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<br\\s*/?>|</(td|th|tr|p|div)>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

enum LayoutRows {
    static func group(_ items: [TextItem]) -> [[TextItem]] {
        let sorted = items.sorted { $0.rect.midY < $1.rect.midY }
        var rows: [[TextItem]] = []
        for item in sorted {
            if let last = rows.last?.last, abs(last.rect.midY - item.rect.midY) < max(0.006, item.rect.height * 0.5) {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }
}

extension UIImage {
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}
