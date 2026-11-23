import Foundation
import FoundationModels
import UIKit

@Generable
struct MaterialInsight {
    @Guide(description: "这张照片是否是学习资料，例如板书、PPT 投影、讲义、书本、笔记、习题")
    var isStudyMaterial: Bool
    @Guide(description: "不超过 12 个字的标题，概括照片里的知识点")
    var title: String
    @Guide(description: "一两句话的复习要点摘要")
    var summary: String
    @Guide(description: "最多 5 个知识点关键词")
    var keywords: [String]
}

struct MaterialAnalysis {
    var isStudyMaterial: Bool
    var title: String
    var summary: String
    var keywords: [String]
}

/// 先用 Vision 在端侧读出照片里的文字，再交给 Apple 智能判断是否为学习资料并生成复习摘要。
enum MaterialAnalyzer {
    static func analyze(image: UIImage, courseName: String) async -> MaterialAnalysis {
        var text = ""
        if let cg = image.normalizedCGImage(), let items = try? await TextExtractor.recognize(cg, page: 0) {
            text = LayoutRows.group(items).map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n")
        }
        let hasText = text.count >= 8

        guard SharedSettings.useAppleIntelligence, AIScheduleExtractor.isAvailable, hasText else {
            return MaterialAnalysis(isStudyMaterial: hasText, title: courseName, summary: String(text.prefix(80)), keywords: [])
        }

        do {
            let session = LanguageModelSession(instructions: """
            你是学习助理。根据一张照片中识别出的文字，判断它是不是课堂学习资料，并为复习生成标题、摘要和关键词。
            如果文字明显与学习无关（例如聊天截图、菜单、风景照里的招牌），isStudyMaterial 为 false。
            """)
            let prompt = "课程：\(courseName)\n照片中的文字：\n\(text.prefix(1_500))"
            let insight = try await session.respond(to: prompt, generating: MaterialInsight.self).content
            return MaterialAnalysis(isStudyMaterial: insight.isStudyMaterial, title: insight.title,
                                    summary: insight.summary, keywords: Array(insight.keywords.prefix(5)))
        } catch {
            return MaterialAnalysis(isStudyMaterial: hasText, title: courseName, summary: String(text.prefix(80)), keywords: [])
        }
    }
}
