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
    print("Adapter metadata, negotiated specification and backward decoding tests passed")
}
