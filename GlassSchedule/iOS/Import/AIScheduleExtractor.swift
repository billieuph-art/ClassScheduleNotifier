import Foundation
import FoundationModels

@Generable
struct AICourse {
    @Guide(description: "课程名称，不要包含教室、教师、周次等信息")
    var name: String
    @Guide(description: "上课教室或地点，例如“教三-305”；未知则为空字符串")
    var classroom: String
    @Guide(description: "授课教师姓名；未知则为空字符串")
    var teacher: String
    @Guide(description: "星期几：1 表示周一，2 表示周二……7 表示周日")
    var weekday: Int
    @Guide(description: "开始节次，即第几节课开始，从 1 开始；未知为 0")
    var startPeriod: Int
    @Guide(description: "结束节次；只有一节课时与开始节次相同；未知为 0")
    var endPeriod: Int
    @Guide(description: "开始时间，24 小时制 HH:mm；未知则为空字符串")
    var startTime: String
    @Guide(description: "结束时间，24 小时制 HH:mm；未知则为空字符串")
    var endTime: String
    @Guide(description: "上课周次原文，例如“1-16周”“1-8,10-16周”“单周”；未知则为空字符串")
    var weeks: String
}

@Generable
struct AISchedule {
    @Guide(description: "课程表中出现的所有上课时段。同一门课一周上多次时，每次单独一条。")
    var courses: [AICourse]
}

/// 使用 Apple 智能的端侧大模型（Foundation Models 框架）把 OCR 文字整理成结构化课表。
enum AIScheduleExtractor {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static var availabilityDescription: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return "可用"
        case .unavailable(.deviceNotEligible):
            return "此设备不支持 Apple 智能"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "请在“设置 > Apple 智能与 Siri”中开启"
        case .unavailable(.modelNotReady):
            return "模型正在下载，请稍后再试"
        case .unavailable:
            return "暂不可用"
        }
    }

    private static let instructions = """
    你是中国大学课程表识别助手。输入是截图或 PDF 的 OCR 结果，每个文字片段带有归一化坐标 [x=… y=…]。
    常见表格：最上一行是星期（周一…周日，或「一」「二」），最左一列是节次（1、2、1-2、第1节）或时间（08:00）。
    同一列（x 接近）是同一天，同一行（y 接近）是同一节次。一个格子里多行通常依次是：课程名、教师、教室、周次。
    字段规则：
    - name：只要课程正式名称，去掉教师、教室、周次、节次。
    - classroom：如「教三-305」「理科楼B204」「3-201」「A301」。
    - teacher：教师姓名；没有就空字符串。
    - weekday：1=周一 … 7=周日。
    - startPeriod/endPeriod：节次；两节连上写成 1 和 2。
    - startTime/endTime：若 OCR 有具体时间就填 HH:mm，否则空字符串。
    - weeks：保留原文，如「1-16周」「1-8,10-16」「单周」。
    只输出课表里真实存在的上课时段，不要编造。表头、日期、校名、学期名不是课程。
    """

    static func extract(from text: String, slots: [PeriodSlot]) async throws -> [CourseDraft] {
        var drafts: [CourseDraft] = []
        let slotText = slots.map { "第\($0.index)节 \(TimeFormat.string($0.startMinutes))-\(TimeFormat.string($0.endMinutes))" }
            .joined(separator: "，")
        // 端侧模型上下文有限，长文档分段处理。
        for chunk in chunks(of: text, maxLength: 2_400) {
            try Task.checkCancellation()
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            参考作息时间：\(slotText)

            OCR 结果：
            \(chunk)
            """
            let response = try await session.respond(to: prompt, generating: AISchedule.self)
            for course in response.content.courses {
                var draft = CourseDraft(name: course.name, classroom: course.classroom, teacher: course.teacher,
                                        weekday: course.weekday, startPeriod: course.startPeriod, endPeriod: course.endPeriod,
                                        startMinutes: TimeFormat.minutes(from: course.startTime) ?? 0,
                                        endMinutes: TimeFormat.minutes(from: course.endTime) ?? 0,
                                        weeks: WeeksParser.parse(course.weeks))
                draft.complete(with: slots)
                if draft.isValid { drafts.append(draft) }
            }
        }
        var seen = Set<String>()
        return drafts.filter { seen.insert($0.dedupeKey).inserted }
    }

    /// 每段都带上前两行（通常是星期表头），否则后面的分段无法判断列对应星期几。
    private static func chunks(of text: String, maxLength: Int) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let header = lines.prefix(2).joined(separator: "\n") + "\n"
        var result: [String] = []
        var current = ""
        for line in lines {
            if current.count + line.count > maxLength, !current.isEmpty {
                result.append(current)
                current = header
            }
            current += line + "\n"
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
