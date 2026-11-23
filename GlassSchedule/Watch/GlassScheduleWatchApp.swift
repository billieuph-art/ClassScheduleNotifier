import SwiftUI
import WatchConnectivity

@main
struct GlassScheduleWatchApp: App {
    @StateObject private var store = WatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView().environmentObject(store)
        }
    }
}

/// 接收 iPhone 通过 WatchConnectivity 发来的课表，并缓存在手表本地，离线也能查看。
final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchStore()

    @Published private(set) var payload: SchedulePayload?

    private let cacheKey = "schedulePayload"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey) {
            payload = try? JSONDecoder().decode(SchedulePayload.self, from: data)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data,
              let decoded = try? JSONDecoder().decode(SchedulePayload.self, from: data) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        DispatchQueue.main.async { self.payload = decoded }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty { apply(session.receivedApplicationContext) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let payload = store.payload, !payload.courses.isEmpty {
                    let today = ScheduleQuery.day(context.date, courses: payload.courses, semesterStart: payload.semesterStart)
                    let tomorrow = ScheduleQuery.day(context.date.addingTimeInterval(86_400), courses: payload.courses,
                                                     semesterStart: payload.semesterStart)
                    let next = ScheduleQuery.current(courses: payload.courses, semesterStart: payload.semesterStart, now: context.date)
                    List {
                        if let next {
                            WatchNextCard(occurrence: next, now: context.date)
                                .listRowBackground(Color.clear)
                        }
                        Section(today.isEmpty ? "今天没有课" : "今天") {
                            ForEach(today) { WatchCourseRow(occurrence: $0, now: context.date) }
                        }
                        if !tomorrow.isEmpty {
                            Section("明天") {
                                ForEach(tomorrow) { WatchCourseRow(occurrence: $0, now: context.date) }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("暂无课表", systemImage: "iphone.and.arrow.forward",
                                           description: Text("请在 iPhone 上的玻璃课表中导入课程"))
                }
            }
            .navigationTitle("课表")
        }
    }
}

struct WatchNextCard: View {
    let occurrence: ClassOccurrence
    let now: Date

    var body: some View {
        let course = occurrence.course
        let ongoing = occurrence.isOngoing(at: now)
        VStack(alignment: .leading, spacing: 4) {
            Text(ongoing ? "正在上课" : "下一节").font(.caption2.bold()).foregroundStyle(Color(hex: course.colorHex))
            Text(course.name).font(.headline).lineLimit(2)
            Text(course.classroom.isEmpty ? course.periodText : "\(course.classroom) · \(course.periodText)")
                .font(.caption2).foregroundStyle(.secondary)
            if ongoing {
                Text("距下课 \(occurrence.end, style: .timer)").font(.caption.monospacedDigit())
            } else {
                Text(occurrence.start, style: .relative).font(.caption.monospacedDigit())
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color(hex: course.colorHex).opacity(0.35)), in: .rect(cornerRadius: 16))
    }
}

struct WatchCourseRow: View {
    let occurrence: ClassOccurrence
    let now: Date

    var body: some View {
        let course = occurrence.course
        HStack(spacing: 8) {
            Capsule().fill(Color(hex: course.colorHex)).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(course.name).font(.footnote.bold()).lineLimit(1)
                Text("\(TimeFormat.string(course.startMinutes)) · \(course.classroom)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .opacity(occurrence.end < now ? 0.45 : 1)
    }
}
