import AppKit

@MainActor
enum XDRLuminanceReader {
    private typealias InfoReader = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    private typealias LinearReader = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private struct Metadata {
        let sdrMaximum: Double?
        let peakHDR: Double?
    }
    private static var cached: (display: UInt32, uptime: Double, metadata: Metadata)?

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
        return XDRBrightnessPolicy.estimatedNits(sdrMaximum: metadata(display).sdrMaximum,
            linearBrightness: Double(linear), gain: gain, headroom: headroom)
    }

    static func maximumGain(display: UInt32, potentialHeadroom: Double) -> Double {
        let values = metadata(display)
        return XDRBrightnessPolicy.maximumGain(sdrMaximum: values.sdrMaximum,
            peakHDR: values.peakHDR, potentialHeadroom: potentialHeadroom)
    }

    static func targetNits(display: UInt32, potentialHeadroom: Double) -> Int? {
        let values = metadata(display)
        guard let sdr = values.sdrMaximum, let hdr = values.peakHDR,
              sdr.isFinite, sdr > 0, sdr <= 10_000,
              hdr.isFinite, hdr > 0, hdr <= 10_000 else { return nil }
        let maximum = maximumGain(display: display, potentialHeadroom: potentialHeadroom)
        return Int((sdr * maximum).rounded())
    }

    private static func metadata(_ display: UInt32) -> Metadata {
        let uptime = ProcessInfo.processInfo.systemUptime
        if let cached, cached.display == display, uptime - cached.uptime < 1 { return cached.metadata }
        let info = infoReader?(display)?.takeRetainedValue() as? [String: Any]
        let sdr = (info?["ReferencePeakSDRLuminance"] as? NSNumber)?.doubleValue
            ?? (info?["NonReferencePeakSDRLuminance"] as? NSNumber)?.doubleValue
        let hdr = (info?["NonReferencePeakHDRLuminance"] as? NSNumber)?.doubleValue
            ?? (info?["ReferencePeakHDRLuminance"] as? NSNumber)?.doubleValue
        let values = Metadata(sdrMaximum: sdr, peakHDR: hdr)
        cached = (display, uptime, values)
        return values
    }
}
