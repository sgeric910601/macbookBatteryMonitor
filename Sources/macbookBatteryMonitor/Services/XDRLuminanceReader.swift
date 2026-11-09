import AppKit

@MainActor
enum XDRLuminanceReader {
    private typealias InfoReader = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    private typealias LinearReader = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private static var cached: (display: UInt32, uptime: Double, maximum: Double?)?

    private static let infoReader: InfoReader? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
              let symbol = dlsym(handle, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(symbol, to: InfoReader.self)
    }()

    private static let linearReader: LinearReader? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetLinearBrightness") else { return nil }
        return unsafeBitCast(symbol, to: LinearReader.self)
    }()

    static func estimatedNits(display: UInt32, gain: Double, headroom: Double) -> Int? {
        var linear: Float = 0
        guard let linearReader, linearReader(display, &linear) == 0 else { return nil }
        return XDRBrightnessPolicy.estimatedNits(sdrMaximum: maximumSDR(display),
            linearBrightness: Double(linear), gain: gain, headroom: headroom)
    }

    private static func maximumSDR(_ display: UInt32) -> Double? {
        let uptime = ProcessInfo.processInfo.systemUptime
        if let cached, cached.display == display, uptime - cached.uptime < 1 { return cached.maximum }
        let info = infoReader?(display)?.takeRetainedValue() as? [String: Any]
        let maximum = (info?["ReferencePeakSDRLuminance"] as? NSNumber)?.doubleValue
        cached = (display, uptime, maximum)
        return maximum
    }
}
