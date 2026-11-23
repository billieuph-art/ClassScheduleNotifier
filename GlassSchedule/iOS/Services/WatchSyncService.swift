import Foundation
import WatchConnectivity
import WidgetKit

final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private var pendingPayload: SchedulePayload?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ payload: SchedulePayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingPayload = payload
            return
        }
        guard session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try session.updateApplicationContext(["payload": data])
        } catch {
            print("同步到 Apple Watch 失败：\(error)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated, let payload = pendingPayload {
            pendingPayload = nil
            push(payload)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

enum WidgetRefresher {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
