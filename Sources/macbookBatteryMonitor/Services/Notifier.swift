import Foundation
import OSLog
import UserNotifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var lowFired = false
    /// 第一次評估只記錄狀態
    private var primed = false
    /// 這次接上電源後是否看過「充電中」
    private var sawChargingSincePlugged = false
    private var fullFired = false

    /// 點新版本通知時呼叫（打開設定的「更新」）
    var onOpenUpdate: (() -> Void)?
    /// 通知內容 userInfo 的 kind：點通知時用來分辨是哪一種
    nonisolated private static let kindKey = "kind"
    nonisolated private static let updateKind = "update"
    nonisolated private static let log = Logger(subsystem: "com.kuan.batterymonitor", category: "notifications")

    /// 沒打包成 .app（例如直接 swift run）時沒有 bundle id，通知中心會直接 crash
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// macOS 是否關閉了這個 App 的通知（關閉時所有提醒都不會出現，系統也不會再詢問）
    func checkBlocked(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let blocked = settings.authorizationStatus == .denied
            DispatchQueue.main.async {
                MainActor.assumeIsolatedCompat { completion(blocked) }
            }
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    /// 每次跨過門檻只通知一次，離開門檻一段距離後才會再通知
    func evaluate(_ s: BatterySnapshot, state: PowerState, settings: AppSettings) {
        let pct = s.percent
        // 接著電源但供電不足、電池仍在放電，也要提醒
        let drainingOnAC = state == .pluggedIdle && s.effectiveAmperage_mA < -50
        let draining = state == .discharging || drainingOnAC
        if !s.externalConnected { sawChargingSincePlugged = false }
        if state == .charging { sawChargingSincePlugged = true }

        // App 剛啟動時只記下目前狀態、不發通知，避免每次登入都跳「充電完成」
        if !primed {
            primed = true
            lowFired = draining && pct <= settings.lowThreshold
            fullFired = s.externalConnected && (pct >= settings.fullThreshold || state == .limitReached)
            return
        }

        if draining, pct <= settings.lowThreshold {
            if settings.lowAlertEnabled, !lowFired {
                let body = drainingOnAC ? "電量已低於 \(settings.lowThreshold)%，接著的電源供電不足，電池仍在放電。"
                    : "電量已低於 \(settings.lowThreshold)%，建議接上電源。"
                post(title: "電量偏低：\(pct)%", body: body)
            }
            lowFired = true
        } else if !draining || pct > settings.lowThreshold + 2 {
            lowFired = false
        }

        // 有系統充電上限時，充到上限就不會再往上，所以到上限也算充電完成
        let limit = s.chargeLimit?.limit
        let target = min(settings.fullThreshold, limit ?? 100)
        if s.externalConnected, pct >= settings.fullThreshold || state == .limitReached {
            // 接上電源後真的充過電才算「充電完成」；高於上限時插上電源不通知
            if settings.fullAlertEnabled, !fullFired, sawChargingSincePlugged {
                let body: String
                if state == .limitReached, let limit {
                    body = "已達充電上限 \(limit)%，電池暫停充電。"
                } else if settings.fullThreshold >= 100 {
                    body = "電池已充飽，可以拔掉電源。"
                } else {
                    body = "已充到 \(settings.fullThreshold)%，可以拔掉電源。"
                }
                post(title: "充電完成：\(pct)%", body: body)
            }
            fullFired = true
        } else if !s.externalConnected || pct < target - 5 {
            fullFired = false
        }
    }

    /// 周邊設備降到自己的門檻（是否通知、門檻由 PeripheralAlerts 判斷）
    func notifyPeripheralLow(_ device: PeripheralBattery, threshold: Int) {
        guard let level = device.lowest else { return }
        let detail = device.detailText.map { "（\($0)）" } ?? ""
        post(title: "\(device.name) 電量偏低：\(level)%", body: "已低於你設定的 \(threshold)%\(detail)，建議充電。")
    }

    /// 智慧充電：已在完成時間前充好，或照目前速度可能趕不上
    func notifyChargingPlan(_ event: ChargingPlanNotification, plan: ChargingPlan) {
        let time = plan.deadline.formatted(date: .omitted, time: .shortened)
        switch event {
        case .ready:
            // 完成目標就是原本的上限時沒有東西要還原
            let restore = plan.targetPercent == plan.restoreLimit ? "" : "拔掉電源後會還原原本的充電上限 \(plan.restoreLimit)%。"
            post(title: "已充到 \(plan.targetPercent)%", body: "智慧充電已在 \(time) 前完成。\(restore)")
        case .late:
            post(title: "智慧充電可能無法準時", body: "macOS 仍在充電，原定 \(time) 前充到 \(plan.targetPercent)%。")
        }
    }

    func notifyUpdate(_ release: ReleaseInfo, currentVersion: String) {
        post(title: "\(AppEdition.appName) 有新版本 v\(release.versionText)",
             body: "目前是 \(currentVersion)。點這則通知打開設定，按「一鍵更新」就能升級。",
             kind: Self.updateKind)
    }

    func sendTest() {
        post(title: AppEdition.appName, body: "通知功能正常 👍")
    }

    private func post(title: String, body: String, kind: String? = nil) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let kind { content.userInfo = [Self.kindKey: kind] }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Self.log.error("通知送出失敗：\(error.localizedDescription, privacy: .public)") }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kind = response.notification.request.content.userInfo[Self.kindKey] as? String
        let opensUpdate = kind == Self.updateKind && response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Self.log.notice("點了通知：kind=\(kind ?? "-", privacy: .public) action=\(response.actionIdentifier, privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolatedCompat {
                if opensUpdate { Notifier.shared.onOpenUpdate?() }
            }
            completionHandler()
        }
    }
}
