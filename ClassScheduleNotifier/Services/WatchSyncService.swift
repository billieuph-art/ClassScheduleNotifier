import Foundation
import Combine
import WatchConnectivity

final class WatchSyncService: NSObject, ObservableObject {
    static let shared = WatchSyncService()
    private var session: WCSession?

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let current = WCSession.default
        session = current
        current.delegate = self
        current.activate()
    }

    func sendCourses(_ courses: [Course]) {
        guard WCSession.isSupported(), let session else { return }
        let payload: [[String: Any]] = courses.map {
            [
                "id": $0.id.uuidString,
                "name": $0.name,
                "teacher": $0.teacher,
                "location": $0.location,
                "weekday": $0.weekday.rawValue,
                "start": $0.startTime.timeIntervalSince1970,
                "end": $0.endTime.timeIntervalSince1970
            ]
        }
        do {
            try session.updateApplicationContext(["courses": payload, "updatedAt": Date().timeIntervalSince1970])
        } catch {
            print("同步 Apple Watch 失败：\(error)")
        }
    }
}

extension WatchSyncService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error { print("WatchConnectivity 激活失败：\(error)") }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}