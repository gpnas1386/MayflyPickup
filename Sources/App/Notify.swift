import Foundation
import UserNotifications
import ActivityKit
import WidgetKit

enum Notifier {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, err in
            NSLog("[Mayfly] notify auth \(ok) \(err?.localizedDescription ?? "")")
        }
        let cat = UNNotificationCategory(identifier: "mayfly.arrival", actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }

    static func arrival(code: String, station: String, total: Int) {
        guard Pref.shared.notifyArrival else { return }
        let content = UNMutableNotificationContent()
        content.title = "驿站有 \(total) 个包裹待取"
        content.body = station.isEmpty ? "取件码 \(code)" : "\(station) · 取件码 \(code)"
        content.sound = .default
        content.categoryIdentifier = "mayfly.arrival"
        content.userInfo = ["code": code]
        let req = UNNotificationRequest(identifier: "mayfly.arrival.\(code)", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    static func test() {
        let content = UNMutableNotificationContent()
        content.title = "蜉蝣·取件通"
        content.body = "通知通道正常，有新包裹时人家会来叫你。"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "mayfly.test", content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }
}

enum LiveIsland {
    static var currentID: String?
    static var lastState: MayflyActivityAttributes.ContentState?

    static func sync(_ snap: Snapshot) {
        guard Pref.shared.liveIsland else { stop(); return }
        let pending = snap.pending
        guard let top = pending.first else { stop(); return }
        let state = MayflyActivityAttributes.ContentState(
            topCode: top.code, stationName: top.stationName, total: pending.count,
            speech: snap.whaleSpeech)

        if let id = currentID, let act = Activity<MayflyActivityAttributes>.activities.first(where: { $0.id == id }) {
            lastState = state
            Task { await act.update(state) }
            return
        }
        if let act = Activity<MayflyActivityAttributes>.activities.first {
            currentID = act.id
            lastState = state
            Task { await act.update(state) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = MayflyActivityAttributes(total: pending.count, stationHint: top.stationName)
        do {
            if #available(iOS 16.2, *) {
                let a = try Activity<MayflyActivityAttributes>.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600)),
                    pushType: nil)
                currentID = a.id
                lastState = state
            } else {
                let a = try Activity<MayflyActivityAttributes>.request(
                    attributes: attrs, contentState: state, pushType: nil)
                currentID = a.id
                lastState = state
            }
        } catch {
            NSLog("[Mayfly] live activity failed: \(error)")
        }
    }

    static func stop() {
        Task {
            for act in Activity<MayflyActivityAttributes>.activities {
                await act.end(dismissalPolicy: .immediate)
            }
        }
        currentID = nil
        lastState = nil
    }
}

enum WidgetRefresh {
    static func all() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
