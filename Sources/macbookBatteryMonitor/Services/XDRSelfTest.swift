import AppKit

/// 獨立函式避免舊版 Swift 對大型泛型閉包進行整體型別推導。
@MainActor
func runXDRSelfTest() -> Bool {
    setvbuf(stdout, nil, _IOLBF, 0)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    let control = XDRBrightnessController.shared
    control.start()
    let cacheReady = Date().addingTimeInterval(0.4)
    while Date() < cacheReady { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    control.stop()
    control.reconcile()
    let stopped = control.completelyStopped
    let stoppedUntil = Date().addingTimeInterval(0.2)
    while Date() < stoppedUntil { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    let stayedStopped = control.completelyStopped
    print("Feature stop and late sampling: \(stopped && stayedStopped)")
    control.start()
    let restartedUntil = Date().addingTimeInterval(0.4)
    while Date() < restartedUntil { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    print("XDR supported: \(control.supported)")
    let id = control.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    let before = id.flatMap(XDRGammaSnapshot.capture)
    let automaticTest = CommandLine.arguments.contains("--xdr-auto")
    print("Automatic XDR: \(control.automaticActivation), maximum gain: \(control.maximumGain), peak target: \(control.targetNits ?? 0)")
    if !automaticTest {
        control.enable()
        let finish = Date().addingTimeInterval(4)
        while Date() < finish { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    }
    if CommandLine.arguments.contains("--xdr-visual"), control.enabled {
        control.setGain(control.maximumGain)
        let visualEnd = Date().addingTimeInterval(12)
        while Date() < visualEnd { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    }
    var activated = control.enabled && control.gain > 1 && control.renderingHealthy
    var keyChanges = 0
    if automaticTest || (CommandLine.arguments.contains("--xdr-keys") && control.enabled) {
        if !automaticTest { control.setGain(1) }
        var lastActive = control.enabled
        var lastGain = control.gain
        var lastNative = XDRBrightnessKeys.nativeBrightness(id)
        print("Brightness key test started for 35 seconds")
        let keyEnd = Date().addingTimeInterval(35)
        while Date() < keyEnd {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let native = XDRBrightnessKeys.nativeBrightness(id)
            if control.enabled && control.gain > 1 && control.renderingHealthy { activated = true }
            if control.gain != lastGain || native != lastNative || control.enabled != lastActive {
                if control.gain != lastGain { keyChanges += 1 }
                print("Key update: active=\(control.enabled), gain=\(control.gain), native=\(native ?? -1)")
                lastActive = control.enabled
                lastGain = control.gain
                lastNative = native
            }
        }
        print("Brightness key gain changes: \(keyChanges)")
    }
    if let id {
        let nits = XDRLuminanceReader.estimatedNits(display: id, gain: control.gain,
            headroom: Double(control.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1))
        print("Estimated nits: \(nits.map { String($0) } ?? "unavailable")")
    }
    print("Keys: \(control.keysStatus)")
    print("Rendering: \(control.renderingStatus)")
    print("EDR live: \(control.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 0), potential: \(control.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 0), native: \(XDRBrightnessKeys.nativeBrightness(id) ?? -1)")
    print("XDR enabled: \(control.enabled), gain: \(control.gain), status: \(control.status)")
    let boosted = id.flatMap(XDRGammaSnapshot.capture)
    print("Gamma peak before: \(before?.red.max() ?? -1), boosted: \(boosted?.red.max() ?? -1)")
    if let before, let boosted, before.red.count == boosted.red.count {
        let mid = before.red.count / 2
        print("Gamma midpoint before: \(before.red[mid]), boosted: \(boosted.red[mid])")
    }
    control.setGain(1)
    let unitGainReleased = !control.enabled && !control.renderingHealthy
    print("Unit gain released overlay: \(unitGainReleased)")
    let restored = control.disable()
    control.stop()
    print("XDR restored: \(restored)")
    guard let before, let after = id.flatMap(XDRGammaSnapshot.capture), before.red.count == after.red.count else { return false }
    let beforeChannels: [Float] = before.red + before.green + before.blue
    let afterChannels: [Float] = after.red + after.green + after.blue
    let differences: [Float] = zip(beforeChannels, afterChannels).map { abs($0.0 - $0.1) }
    let delta: Float = differences.max() ?? 1
    print("Gamma restoration max delta: \(delta)")
    print("Rendering lifecycle check only; physical brightness requires visual verification")
    return activated && stopped && stayedStopped && unitGainReleased && control.completelyStopped
        && restored && !control.enabled && delta < 0.005
        && (!(automaticTest || CommandLine.arguments.contains("--xdr-keys")) || keyChanges > 0)
}
