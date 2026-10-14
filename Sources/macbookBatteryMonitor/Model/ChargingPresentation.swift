import Foundation

/// 只穩定顯示狀態，不修改原始旗標、電流或功率。
struct ChargingPresentation {
    private var displayed: PowerState?
    private var fullLatched = false
    private var pending: (state: PowerState, since: TimeInterval)?
    private var lastLimit: Int?
    var hasReachedFull: Bool { fullLatched }

    mutating func state(_ snapshot: BatterySnapshot, uptime: TimeInterval) -> PowerState {
        let raw = Estimator.state(snapshot)
        guard snapshot.externalConnected else {
            self = ChargingPresentation()
            displayed = .discharging
            return .discharging
        }
        let limit = snapshot.chargeLimit?.limit
        if limit != lastLimit {
            self = ChargingPresentation()
            lastLimit = limit
        }
        var candidate = raw
        // 有系統充電上限時由上限判定，不套用 100% 滿電緩衝；但接電中的狀態變化一樣要確認 10 秒，
        // 否則充到上限附近時 macOS 反覆暫停／恢復充電，圖示會跟著跳
        if limit == nil {
            if snapshot.percent >= 100 || (snapshot.fullyCharged && snapshot.percent >= 98) {
                fullLatched = true; pending = nil; displayed = .full
                return .full
            }
            if fullLatched && snapshot.percent < 98 {
                fullLatched = false; pending = nil; displayed = raw
                return raw
            }
            candidate = fullLatched && !snapshot.chargingNow ? .full : raw
        }
        // 第一次讀取、實際插拔電源立即顯示；接電中的狀態變化才確認 10 秒。
        guard let previous = displayed, previous != .discharging else {
            displayed = candidate; pending = nil
            return candidate
        }
        guard candidate != previous else {
            pending = nil
            return previous
        }
        if let pending, pending.state == candidate,
           uptime - pending.since >= 10 {
            displayed = candidate
            self.pending = nil
            return candidate
        }
        if pending?.state != candidate { pending = (candidate, uptime) }
        return previous
    }
}

enum PowerFlowKind: String, Codable { case battery, adapter, charging, mixed }

/// 電量狀態與供電方向分開：沒在充電時的小幅電池補電不改變圖的拓樸。
struct PowerFlowPresentation {
    private var displayed: PowerFlowKind?
    private var pending: (kind: PowerFlowKind, since: TimeInterval)?

    /// holding：接著電源但沒在充電（滿電、到達上限、暫停），±2 W 內視為由變壓器直接供電
    static func rawKind(connected: Bool, watts: Double, holding: Bool) -> PowerFlowKind {
        guard connected else { return .battery }
        let threshold = holding ? 2.0 : 0.05
        if watts > threshold { return .charging }
        if watts < -threshold { return .mixed }
        return .adapter
    }

    mutating func kind(connected: Bool, watts: Double, holding: Bool, uptime: TimeInterval) -> PowerFlowKind {
        let candidate = Self.rawKind(connected: connected, watts: watts, holding: holding)
        guard holding, connected else {
            displayed = candidate; pending = nil
            return candidate
        }
        // 初次開啟或重新插電也先確認，避免第一筆功率差尖峰切換圖形。
        let previous = displayed == .battery ? .adapter : (displayed ?? .adapter)
        displayed = previous
        guard previous != candidate else {
            pending = nil
            return previous
        }
        // 方向明顯相反時不沿用舊圖，否則會把電池畫成負瓦數。
        // Intel 剛插電時電池先放電（電池一起供電），十幾秒後才開始充電，狀態還在確認時就會遇到
        if (previous == .mixed && watts > 5) || (previous == .charging && watts < -5) {
            displayed = candidate; pending = nil
            return candidate
        }
        if let pending, pending.kind == candidate, uptime - pending.since >= 10 {
            displayed = candidate; self.pending = nil
            return candidate
        }
        if pending?.kind != candidate { pending = (candidate, uptime) }
        return previous
    }
}

extension Estimates {
    var flowKind: PowerFlowKind {
        displayFlow ?? PowerFlowPresentation.rawKind(connected: state != .discharging, watts: batteryWatts,
                                                    holding: [.full, .limitReached, .pluggedIdle].contains(state) && !drainingOnAC)
    }
}
