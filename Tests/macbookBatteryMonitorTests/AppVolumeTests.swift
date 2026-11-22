import Foundation

struct AppVolumeTests {
    /// 100% 不擷取；調低、靜音才擷取；增益不超過 1
    func testGainAndTap() {
        XCTAssertTrue(!AppVolume.Setting().needsTap)
        XCTAssertEqual(AppVolume.Setting().gain, 1)
        XCTAssertTrue(AppVolume.Setting(volume: 0.5).needsTap)
        XCTAssertEqual(AppVolume.Setting(volume: 0.5).gain, 0.5)
        XCTAssertTrue(AppVolume.Setting(volume: 1, muted: true).needsTap)
        XCTAssertEqual(AppVolume.Setting(volume: 0.8, muted: true).gain, 0)
        XCTAssertEqual(AppVolume.Setting(volume: 3).gain, 1)
        XCTAssertEqual(AppVolume.Setting(volume: -1).gain, 0)
        XCTAssertEqual(AppVolume.Setting(volume: .nan).gain, 1)
    }

    /// Helper 程序對應回 App：要在「.」邊界上，取最長的
    func testOwnerOfHelper() {
        let apps: Set<String> = ["com.brave.Browser", "com.example.Chat", "com.example.Chat.Pro"]
        XCTAssertEqual(AppVolume.owner(ofProcessBundleID: "com.brave.Browser.helper.renderer", apps: apps), "com.brave.Browser")
        XCTAssertEqual(AppVolume.owner(ofProcessBundleID: "com.brave.Browser", apps: apps), "com.brave.Browser")
        XCTAssertEqual(AppVolume.owner(ofProcessBundleID: "com.example.Chat.Pro.helper", apps: apps), "com.example.Chat.Pro")
        XCTAssertNil(AppVolume.owner(ofProcessBundleID: "com.brave.BrowserBeta", apps: apps))
        XCTAssertNil(AppVolume.owner(ofProcessBundleID: "", apps: apps))
        // Safari 的聲音來自 WebKit 程序：Safari 開著才對應過去
        XCTAssertEqual(AppVolume.owner(ofProcessBundleID: "com.apple.WebKit.GPU", apps: apps.union(["com.apple.Safari"])), "com.apple.Safari")
        XCTAssertNil(AppVolume.owner(ofProcessBundleID: "com.apple.WebKit.GPU", apps: apps))
    }

    /// 背景 App 的 Helper 歸到它所屬的一般 App；本身就是一般 App 的不變；沒有上層的背景 App 照用自己
    func testResolveOwner() {
        let regular: Set<String> = ["com.brave.Browser", "com.apple.Music"]
        let apps = regular.union(["com.brave.Browser.helper", "com.example.MenuPlayer"])
        XCTAssertEqual(AppVolume.resolveOwner(pidOwner: "com.brave.Browser.helper", processBundleID: "com.brave.Browser.helper", apps: apps, regularApps: regular), "com.brave.Browser")
        XCTAssertEqual(AppVolume.resolveOwner(pidOwner: nil, processBundleID: "com.brave.Browser.helper", apps: apps, regularApps: regular), "com.brave.Browser")
        XCTAssertEqual(AppVolume.resolveOwner(pidOwner: "com.apple.Music", processBundleID: "com.apple.Music", apps: apps, regularApps: regular), "com.apple.Music")
        XCTAssertEqual(AppVolume.resolveOwner(pidOwner: "com.example.MenuPlayer", processBundleID: "com.example.MenuPlayer", apps: apps, regularApps: regular), "com.example.MenuPlayer")
        XCTAssertNil(AppVolume.resolveOwner(pidOwner: nil, processBundleID: "LINE.MediaService", apps: apps, regularApps: regular))
    }

    /// 讀回時最多 256 筆
    func testStoredLimit() {
        let many = Dictionary(uniqueKeysWithValues: (0..<400).map { ("app.\($0)", ["volume": 0.5] as [String: Any]) })
        XCTAssertEqual(AppVolume.settings(stored: many).count, AppVolume.maxStored)
    }

    /// 只存非預設值；讀回時略過壞掉的項目
    func testStoreAndRead() {
        let settings = ["a.b": AppVolume.Setting(volume: 0.3), "c.d": AppVolume.Setting(), "e.f": AppVolume.Setting(volume: 1, muted: true)]
        let stored = AppVolume.stored(settings)
        XCTAssertEqual(Set(stored.keys), ["a.b", "e.f"])
        let read = AppVolume.settings(stored: stored)
        XCTAssertEqual(read["a.b"], AppVolume.Setting(volume: 0.3))
        XCTAssertEqual(read["e.f"], AppVolume.Setting(volume: 1, muted: true))
        let broken: [String: Any] = ["x.y": "bad", "": ["volume": 0.5], "z.w": ["volume": 7.0, "muted": "yes"]]
        let fixed = AppVolume.settings(stored: broken)
        XCTAssertNil(fixed["x.y"])
        XCTAssertNil(fixed[""])
        // 7 被夾成 1、muted 型別錯當成 false → 預設值，不存
        XCTAssertNil(fixed["z.w"])
    }

    private func run(_ input: [Float], inCh: Int, outCh: Int, outSamples: Int, gain: Float, target: Float, ramp: Float = 1) -> ([Float], Float, Float) {
        var output = [Float](repeating: 9, count: outSamples)
        let result = input.withUnsafeBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                AppVolume.mix(input: inBuf.baseAddress!, inputChannels: inCh, inputSamples: input.count,
                              output: outBuf.baseAddress!, outputChannels: outCh, outputSamples: outSamples,
                              gain: gain, target: target, ramp: ramp)
            }
        }
        return (output, result.gain, result.peak)
    }

    /// 立體聲進、立體聲出乘上音量；單聲道出取平均；多聲道出重複最後一個聲道；多出來的輸出補 0
    func testMix() {
        let stereo: [Float] = [0.2, -0.4, 1.0, 0.0]
        let (same, gain, peak) = run(stereo, inCh: 2, outCh: 2, outSamples: 4, gain: 0.5, target: 0.5)
        XCTAssertEqual(same, [0.1, -0.2, 0.5, 0.0])
        XCTAssertEqual(gain, 0.5)
        XCTAssertEqual(peak, 1.0)
        let (mono, _, _) = run(stereo, inCh: 2, outCh: 1, outSamples: 2, gain: 1, target: 1)
        XCTAssertEqual(mono, [Float(-0.1), 0.5])
        let (wide, _, _) = run([0.2, 0.4], inCh: 2, outCh: 3, outSamples: 3, gain: 1, target: 1)
        XCTAssertEqual(wide, [0.2, 0.4, 0.4])
        let (padded, _, _) = run([0.2, 0.4], inCh: 2, outCh: 2, outSamples: 4, gain: 1, target: 1)
        XCTAssertEqual(padded, [0.2, 0.4, 0, 0])
        let (silentIn, _, silentPeak) = run([], inCh: 2, outCh: 2, outSamples: 2, gain: 1, target: 1)
        XCTAssertEqual(silentIn, [0, 0])
        XCTAssertEqual(silentPeak, 0)
    }

    /// 音量慢慢靠近目標，不會一下子跳過去
    func testRamp() {
        let (_, gain, _) = run([Float](repeating: 0.5, count: 20), inCh: 2, outCh: 2, outSamples: 20, gain: 1, target: 0, ramp: 0.1)
        XCTAssertTrue(gain > 0 && gain < 1)
        XCTAssertTrue(AppVolume.rampCoefficient(sampleRate: 48_000) > 0 && AppVolume.rampCoefficient(sampleRate: 48_000) < 0.01)
        XCTAssertEqual(AppVolume.rampCoefficient(sampleRate: 0), 1)
    }

    /// 暫停中的調整過的 App 留在清單上；沒在跑的 App 不列
    func testListed() {
        let list = AppVolume.listed(playing: ["b.player"], adjusted: ["a.music", "c.closed"], running: ["a.music", "b.player"])
        XCTAssertEqual(list.map(\.bundleID), ["a.music", "b.player"])
        XCTAssertEqual(list.map(\.isPlaying), [false, true])
        XCTAssertTrue(AppVolume.listed(playing: [], adjusted: [], running: ["a.music"]).isEmpty)
    }

    /// 沒出聲過或安靜滿 10 秒才拆；靜音的不拆
    func testIdle() {
        let now: TimeInterval = 1000
        XCTAssertTrue(AppVolume.isIdle(lastPlaying: nil, now: now, gain: 0.5))
        XCTAssertTrue(!AppVolume.isIdle(lastPlaying: now - 9.9, now: now, gain: 0.5))
        XCTAssertTrue(AppVolume.isIdle(lastPlaying: now - 10, now: now, gain: 0.5))
        XCTAssertTrue(!AppVolume.isIdle(lastPlaying: nil, now: now, gain: 0))
    }

    /// 第一次建立：等到收到聲音才接手、從 100% 開始；重建且舊的已接手：收到聲音或等 0.5 秒後接手、從目前設定開始；舊的還沒接手時當成第一次
    func testArmDecision() {
        XCTAssertEqual(AppVolume.armDecision(heardSound: false, oldArmed: false, waited: 10), .wait)
        XCTAssertEqual(AppVolume.armDecision(heardSound: true, oldArmed: false, waited: 0), .arm(fromFullVolume: true))
        XCTAssertEqual(AppVolume.armDecision(heardSound: true, oldArmed: true, waited: 0), .arm(fromFullVolume: false))
        XCTAssertEqual(AppVolume.armDecision(heardSound: false, oldArmed: true, waited: 0.2), .wait)
        XCTAssertEqual(AppVolume.armDecision(heardSound: false, oldArmed: true, waited: 0.6), .arm(fromFullVolume: false))
    }
}
