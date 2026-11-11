import AppKit
import ApplicationServices
import Observation

@MainActor @Observable
final class XDRBrightnessKeys {
    private(set) var status = "未連動"
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var sequence = XDRBrightnessKeySequence()
    private let adjust: (Bool) -> Bool

    init(adjust: @escaping (Bool) -> Bool) { self.adjust = adjust }

    func start() {
        guard AXIsProcessTrusted() else {
            if tap != nil { stop() }
            status = "亮度鍵需要輔助使用權限；滑桿仍可使用"
            return
        }
        if let tap, CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) { return }
        stop()
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(1 << 14), callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let owner = Unmanaged<XDRBrightnessKeys>.fromOpaque(info).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        owner.sequence = XDRBrightnessKeySequence()
                        if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return Unmanaged.passUnretained(event)
                    }
                    guard let key = NSEvent(cgEvent: event), key.type == .systemDefined, key.subtype.rawValue == 8 else {
                        return Unmanaged.passUnretained(event)
                    }
                    let code = (key.data1 >> 16) & 0xffff
                    guard code == 2 || code == 3 else { return Unmanaged.passUnretained(event) }
                    let state = (key.data1 >> 8) & 0xff
                    if state == 0xA {
                        let repeating = (key.data1 & 1) != 0
                        let shouldAdjust = owner.sequence.shouldAdjustDown(code: code, repeating: repeating)
                        let adjusted = shouldAdjust && owner.adjust(code == 2)
                        if owner.sequence.consumeDown(code: code, adjusted: adjusted, repeating: repeating) { return nil }
                    }
                    if state == 0xB, owner.sequence.consumeUp(code: code) { return nil }
                    return Unmanaged.passUnretained(event)
                }
            }, userInfo: pointer) else { status = "無法連動亮度鍵；請使用滑桿"; return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        status = "亮度鍵已連動；每格調整 5%"
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        sequence = XDRBrightnessKeySequence()
        status = "未連動"
    }

    static func nativeBrightness(_ display: CGDirectDisplayID?) -> Float? {
        guard let display, let reader = brightnessReader else { return nil }
        var brightness: Float = 0
        guard reader(display, &brightness) == 0, brightness.isFinite, (0...1).contains(brightness) else { return nil }
        return brightness
    }

    private typealias BrightnessReader = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private static let brightnessReader: BrightnessReader? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: BrightnessReader.self)
    }()
}
