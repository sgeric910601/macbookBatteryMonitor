import Foundation
func runAdapterInfoTests() {
    let a = AdapterInfo.parse(["Name": "67W USB-C Power Adapter", "Manufacturer": "Apple Inc.", "Watts": 65, "AdapterVoltage": 20000, "Current": 3260, "SerialString": "demo"])
    precondition(a.name == "67W USB-C Power Adapter" && a.manufacturer == "Apple Inc.")
    precondition(a.specification == "20 V · 3.26 A")
    precondition(AdapterInfo.parse(["Name":"pd charger"]).name == nil)
    let absent = AdapterInfo.parse(["Watts": -1, "AdapterVoltage": 0, "Current": 0])
    precondition(absent.watts == nil && absent.specification == nil)
    let old = try! JSONDecoder().decode(AdapterInfo.self, from: Data("{\"watts\":30}".utf8))
    precondition(old.watts == 30 && old.manufacturer == nil)
    precondition(AdapterInfo.parse(["Name":"  ","Description":"pd charger"]).name == nil)
    precondition(AdapterInfo.connectionLabel(activeTypes: ["MagSafe 3"]) == "MagSafe 3")
    precondition(AdapterInfo.connectionLabel(activeTypes: ["USB-C"]) == "USB-C")
    precondition(AdapterInfo.connectionLabel(activeTypes: ["USB-C", "MagSafe 3"]) == nil)
    precondition(AdapterInfo.connectionLabel(activeTypes: []) == nil)
    precondition(AdapterInfo.connectionLabel(activeTypes: ["USB-C", "MagSafe 3"], chargerCount: 1) == "MagSafe 3")
    precondition(AdapterInfo.connectionLabel(activeTypes: ["USB-C", "MagSafe 3"], chargerCount: 2) == nil)
    // 支援檔位：依電壓排序、電流相同合併，壞資料略過
    let menu: [[String: Any]] = [
        ["Index": 4, "MaxVoltage": 20000, "MaxCurrent": 2250],
        ["Index": 0, "MaxVoltage": 5000, "MaxCurrent": 3000],
        ["Index": 1, "MaxVoltage": 9000, "MaxCurrent": 3000],
        ["Index": 2, "MaxVoltage": 0, "MaxCurrent": 3000],
        ["Index": 3, "MaxVoltage": 15000, "MaxCurrent": 3000],
    ]
    precondition(AdapterInfo.parse(["UsbHvcMenu": menu]).levelSummary == "5／9／15 V 3 A、20 V 2.25 A")
    precondition(AdapterInfo.parse(["UsbHvcMenu": [[String: Any]]()]).levels == nil)
    precondition(AdapterInfo.parse(["UsbHvcMenu": "bad"]).levelSummary == nil)
    // 經 MagSafe：每檔電流少一點，仍合併成整齊的兩組
    let magSafeMenu: [[String: Any]] = [5000: 2960, 9000: 2980, 12000: 2980, 15000: 2990, 20000: 3260].sorted { $0.key < $1.key }
        .map { ["MaxVoltage": $0.key, "MaxCurrent": $0.value] }
    precondition(AdapterInfo.parse(["UsbHvcMenu": magSafeMenu]).levelGroups == ["5／9／12／15 V 3 A", "20 V 3.25 A"])
    precondition(old.levels == nil)
    // 指紋：只看電壓電流（含 PPS），旗標位元不同（0x88／0x80）仍是同一顆
    let pdos140: [NSNumber] = [0x881912c, 0x2d12c, 0x3c12c, 0x4b12c, 0x641f4, NSNumber(value: Int32(bitPattern: 0xc9a43264))]
    let controllers: [[String: Any]] = [
        ["PortControllerMaxPower": 100000, "PortControllerPortPDO": pdos140 + [0, 0]],
        ["PortControllerMaxPower": 0, "PortControllerPortPDO": [NSNumber(value: 0x801912c)]],
    ]
    let port = AdapterInfo.powerPort(controllers)!
    precondition(port.index == 0 && port.pdos.count == 6)
    let fp140 = AdapterInfo.fingerprint(vendorID: 0x1A2B, productID: 0, pdos: port.pdos)
    precondition(fp140 == "1a2b:0000|5000x3000,9000x3000,12000x3000,15000x3000,20000x5000,pps21000")
    var reflagged = port.pdos; reflagged[0] = 0x801912c
    precondition(AdapterInfo.fingerprint(vendorID: 0x1A2B, productID: 0, pdos: reflagged) == fp140)
    let pps45: UInt32 = 0xC000_0000 | 110 << 17 | 50 << 8 | 81  // PPS 5–11 V 4.05 A
    let pdos45: [UInt32] = [0x801912c, 0x2d12c, 0x3c12c, 0x4b12c, 0x640e1, pps45]
    precondition(AdapterInfo.fingerprint(vendorID: 0, productID: 0, pdos: pdos45).hasSuffix("20000x2300,pps11000"))
    // 2.25 A 經 MagSafe 少 10～40 mA，進位後仍是同一個指紋
    var pdos45MagSafe = pdos45; pdos45MagSafe[4] = 0x640df  // 20 V 2.23 A
    precondition(AdapterInfo.fingerprint(vendorID: 0, productID: 0, pdos: pdos45MagSafe) == AdapterInfo.fingerprint(vendorID: 0, productID: 0, pdos: pdos45))
    precondition(AdapterInfo.fingerprint(vendorID: 0, productID: 0, pdos: pdos45) != fp140)
    // 兩個孔同時供電、沒有任何孔供電：看不出是哪一顆
    precondition(AdapterInfo.powerPort([controllers[0], controllers[0]]) == nil)
    precondition(AdapterInfo.powerPort([controllers[1]]) == nil)
    // 同一顆經 MagSafe：沒有廠商代碼、每檔電流少一點、PPS 電流 0，仍找得到 USB-C 時取的名稱
    let magSafe: [UInt32] = [0x8019128, 0x2d12a, 0x3c12a, 0x4b12b, 0x641f3, 0xc9a43000]
    let fpMagSafe = AdapterInfo.fingerprint(vendorID: 0, productID: 0, pdos: magSafe)
    precondition(fpMagSafe == "0000:0000|5000x3000,9000x3000,12000x3000,15000x3000,20000x5000,pps21000")
    precondition(AdapterInfo.savedName(for: fpMagSafe, in: [fp140: "A"]) == "A")
    precondition(AdapterInfo.savedName(for: fp140, in: [fpMagSafe: "A"]) == "A")
    let otherBrand = "1234:0000|" + fp140.split(separator: "|")[1]
    precondition(AdapterInfo.savedName(for: fpMagSafe, in: [fp140: "A", otherBrand: "B"]) == nil)  // 兩筆都符合：不猜
    precondition(AdapterInfo.savedName(for: otherBrand, in: [fp140: "A"]) == nil)  // 兩邊都有廠商代碼且不同
    precondition(AdapterInfo.savedName(for: fp140, in: [fp140: "A", fpMagSafe: "M"]) == "A")  // 完全相同優先
    precondition(AdapterInfo.savedEntry(for: fp140, in: [fpMagSafe: "A"])?.key == fpMagSafe)  // 改名要寫回借來的那筆
    // 兩顆都插著：落選的孔（LoserReason 5）也有功率，選沒落選的那個
    let loser: [String: Any] = ["PortControllerMaxPower": 29850, "PortControllerLoserReason": 5, "PortControllerPortPDO": pdos45.map { NSNumber(value: $0) }]
    precondition(AdapterInfo.powerPort([loser, controllers[0]])?.index == 1)
    precondition(AdapterInfo.powerPort([controllers[1], loser])?.index == 1)  // 只插一條時 LoserReason 也可能不是 0
    // 舊版指紋轉成新格式；新格式不變
    precondition(AdapterInfo.migratedFingerprint("1a2b:0000|5000x3000,9000x3000,12000x3000,15000x3000,20000x5000,pps5000-21000x5000") == fp140)
    precondition(AdapterInfo.migratedFingerprint("0000:0000|5000x3000,20000x2250,pps5000-11000x4050") == "0000:0000|5000x3000,20000x2300,pps11000")
    precondition(AdapterInfo.migratedFingerprint(fp140) == fp140)
    precondition(AdapterInfo.migratedFingerprint("壞資料") == "壞資料")
    precondition(AdapterInfo.migratedFingerprint("a|pps,ppsx") == "a|pps,ppsx")  // 壞掉的 pps 片段不當掉
    // 遷移撞鍵：新格式優先；兩筆都是舊格式時固定挑同一筆
    let migrated = AdapterInfo.migratedNames(["0000:0001|20000x3260": "舊1", "0000:0001|20000x3240": "舊2", "0000:0002|20000x3300": "新",
                                              "0000:0002|20000x3290": "舊", "0000:0003|5000x3000": "  "])
    precondition(migrated == ["0000:0001|20000x3300": "舊2", "0000:0002|20000x3300": "新"])
    // 設定檔匯入：壞鍵、非字串、空名稱都丟掉
    let imported = AdapterInfo.importedNames(["1a2b:0000|20000x5000": "書桌", "沒有分隔": "X", "a|b|c": "Y", "b|5000x3000": 3, "c|5000x3000": " "])
    precondition(imported == ["1a2b:0000|20000x5000": "書桌"])
    precondition(AdapterInfo.importedNames("不是字典").isEmpty)
    precondition(AdapterInfo.importedNames(Dictionary(uniqueKeysWithValues: (0..<150).map { (String(format: "%04x:0000|5000x3000", $0), "n") })).count == AdapterInfo.maxSavedChargers)
    // 超大數值、格式不對的鍵：匯入時丟掉、不當掉
    precondition(AdapterInfo.importedNames(["a|1x9223372036854775807": "x", "0000:0000|4000000000x4000000000,1x1": "y", "zz:0000|5000x3000": "z"]).isEmpty)
    precondition(AdapterInfo.describe(fingerprint: "0000:0000|4000000000x4000000000,1x1").hasPrefix("無廠商代碼"))
    precondition(AdapterInfo.isValidFingerprint(fp140) && AdapterInfo.isValidFingerprint("0000:0000|5000x3000,9000x2200,12000x1700,pps5900"))
    precondition(!AdapterInfo.isValidFingerprint("1a2b:0000|5000x") && !AdapterInfo.isValidFingerprint("1a2b|5000x3000"))
    // 設定頁說明
    precondition(AdapterInfo.vendorSummary([fp140, fp140]) == "廠商代碼 0x1A2B")
    precondition(AdapterInfo.vendorSummary([fp140, fpMagSafe]) == "廠商代碼 0x1A2B、無廠商代碼")
    precondition(AdapterInfo.describe(fingerprint: fp140) == "廠商代碼 0x1A2B · 最高 20 V 約 5 A")
    precondition(AdapterInfo.describe(fingerprint: "0000:0000|5000x3000,20000x2300,pps11000") == "無廠商代碼（MagSafe 或未回報） · 最高 20 V 約 2.3 A")
    precondition(AdapterInfo.describe(fingerprint: "1a2b:0000|5000x3000,12000x2500,15000x2000,20000x1500").hasSuffix("最高 20 V 約 1.5 A"))  // 瓦數相同取電壓高的
    // 名稱清理
    precondition(AdapterInfo.cleanName("  書桌\n140W\t ") == "書桌140W")
    precondition(AdapterInfo.cleanName("   ") == nil)
    precondition(AdapterInfo.cleanName("家\u{202E}👨\u{200D}👩") == "家👨\u{200D}👩")
    precondition(AdapterInfo.cleanName(String(repeating: "充", count: 50))?.count == AdapterInfo.maxNameLength)
    print("Adapter metadata, negotiated specification, levels, fingerprint and backward decoding tests passed")
}
