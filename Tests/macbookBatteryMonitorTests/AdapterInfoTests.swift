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
    print("Adapter metadata, negotiated specification, levels and backward decoding tests passed")
}
