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
    你是中国大学课程表识别助手。输入是截图 OCR，文字常被拆成碎片，并带坐标 [x=… y=…]。
    表格：表头可能是「周一…周日」或「今天 11/23」「周二 11/24」；左侧是节数或「第1-2节」。同一列(x)同一天，同一片垂直色块同一门课。
    三种常见版式（必须按列/行分开，禁止把相邻列粘成一串）：
    1) 超星网格：课程名@教室号，如「水利工程造价二@2313」。
    2) 教务网格多行格：课名 / 教师 / 教一楼 302 / 1-16周 (单周)。
    3) 列表横排：时间段 | 课程名 | 教师 | 教室 | 周次。例如「08:00-09:40 高等数学（上） 张伟 理教楼 A-201 1-16周」——name=高等数学（上），teacher=张伟，classroom=理教楼 A-201。
    4) 时间轴：课块内「课名」「教师 | 教室」「(每周)」，时间由横向位置估计。
    禁止把「星期一/Thursday」等表头当成课程。教室保留完整门牌（A-201、302）。
    字段：
    - name：完整课程名，不要教师、不要教室、不要@、不要周次。禁止残片课名，禁止把楼名/人名当课名。
    - classroom：完整地点，如「教一楼 302」「外语楼 105」「体育馆」。楼名与门牌号都要保留。
    - teacher：如「李明」「王芳」；没有就空字符串。不要把教师名写进 name。
    - weekday：1=周一…7=周日。
    - startPeriod/endPeriod：色块覆盖的节次。
    - startTime/endTime：没有具体钟点就留空。
    - weeks：原样保留格子周次，如「1-16周 (单周)」「1-16周（双周）」「1-8周」。有单/双周标记必须写入 weeks 字段。格子没有周次则留空。
    只输出真实课程，不要把表头、日期、空单元格编成课。
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
                draft.complete(with: slots, preferPeriods: true)
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
