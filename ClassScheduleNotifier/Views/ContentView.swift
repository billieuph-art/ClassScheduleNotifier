import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

public final class WatchSyncService: NSObject, ObservableObject {
    #if canImport(WatchConnectivity)
    private let session: WCSession?
    #endif

    public override init() {
        #if canImport(WatchConnectivity)
        self.session = WCSession.default
        super.init()
        self.session?.delegate = self
        self.session?.activate()
        #else
        super.init()
        #endif
    }

    public func sendNextCourse(_ course: Course) {
        #if canImport(WatchConnectivity)
        guard let session, session.isReachable else { return }
        let payload: [String: Any] = [
            "courseName": course.name,
            "location": course.location,
            "startTime": course.startTime.timeIntervalSince1970,
            "teacher": course.teacher
        ]
        session.sendMessage(payload, replyHandler: nil)
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchSyncService: WCSessionDelegate {
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    public func sessionDidBecomeInactive(_ session: WCSession) {}
    public func sessionDidDeactivate(_ session: WCSession) {}
}
#endif
