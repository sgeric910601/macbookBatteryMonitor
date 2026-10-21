// 一鍵更新的簽章金鑰工具（Ed25519）。私鑰只存在登入鑰匙圈，不寫進專案、GitHub 或記錄；
// 只有 export 會把它寫進指定的資料夾，給 make-update-key.sh 放進加密的備份映像檔。
// 由 Scripts/make-update-key.sh 與 Scripts/sign-release.sh 編譯成 build/update-signing 後使用：
//   update-signing generate              建立金鑰並存進鑰匙圈（已經有就停下來），印出公鑰
//   update-signing public-key            印出公鑰（32 bytes 原始公鑰的 base64）
//   update-signing sign <檔案>            印出簽章（64 bytes 原始簽章的 base64，一行）
//   update-signing verify <檔案> <簽章檔> <公鑰>   驗證簽章，通過結束碼 0
//   update-signing export <資料夾>        把私鑰寫成 <資料夾>/update-signing-key.txt（備份用）
//   update-signing import <檔案>          從 export 的備份檔還原到鑰匙圈
import CryptoKit
import Foundation
import Security

let service = "macbookBatteryMonitor update signing"
let account = "ed25519"
let backupName = "update-signing-key.txt"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func storedKey() -> Curve25519.Signing.PrivateKey? {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else {
        if status == errSecItemNotFound { return nil }
        fail("讀不到鑰匙圈裡的更新簽章金鑰（錯誤 \(status)）")
    }
    guard let data = item as? Data, let raw = Data(base64Encoded: data), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("鑰匙圈裡的更新簽章金鑰格式不對")
    }
    return key
}

func store(_ key: Curve25519.Signing.PrivateKey) {
    let attributes: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        kSecAttrLabel as String: service,
        kSecAttrComment as String: "電池與系統監控的一鍵更新簽章私鑰（Ed25519）。遺失的話 App 無法再一鍵更新",
        kSecValueData as String: Data(key.rawRepresentation.base64EncodedString().utf8),
    ]
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else { fail("無法存進鑰匙圈（錯誤 \(status)）") }
}

func requireKey() -> Curve25519.Signing.PrivateKey {
    guard let key = storedKey() else { fail("鑰匙圈裡沒有更新簽章金鑰：先執行 Scripts/make-update-key.sh，或用備份 import") }
    return key
}

func read(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else { fail("讀不到 \(path)") }
    return data
}

let args = Array(CommandLine.arguments.dropFirst())
switch (args.first, args.count) {
case ("generate", 1):
    if storedKey() != nil { fail("鑰匙圈裡已經有更新簽章金鑰，不重新產生（換金鑰會讓舊版 App 無法驗證更新）") }
    let key = Curve25519.Signing.PrivateKey()
    store(key)
    print(key.publicKey.rawRepresentation.base64EncodedString())
case ("public-key", 1):
    print(requireKey().publicKey.rawRepresentation.base64EncodedString())
case ("sign", 2):
    let signature = try requireKey().signature(for: read(args[1]))
    print(signature.base64EncodedString())
case ("verify", 4):
    let text = String(decoding: read(args[2]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let signature = Data(base64Encoded: text), signature.count == 64,
          let raw = Data(base64Encoded: args[3]), raw.count == 32,
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
          publicKey.isValidSignature(signature, for: read(args[1])) else { fail("簽章驗證失敗") }
    print("簽章正確")
case ("export", 2):
    let key = requireKey()
    let file = URL(fileURLWithPath: args[1]).appendingPathComponent(backupName)
    let text = """
        # 電池與系統監控的一鍵更新簽章私鑰（Ed25519）。還原：build/update-signing import \(backupName)
        private \(key.rawRepresentation.base64EncodedString())
        public \(key.publicKey.rawRepresentation.base64EncodedString())

        """
    guard FileManager.default.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
        fail("無法寫入 \(file.path)")
    }
    print(file.path)
case ("import", 2):
    if storedKey() != nil { fail("鑰匙圈裡已經有更新簽章金鑰") }
    let line = String(decoding: read(args[1]), as: UTF8.self).split(separator: "\n").first { $0.hasPrefix("private ") }
    guard let encoded = line?.dropFirst("private ".count), let raw = Data(base64Encoded: String(encoded)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("備份檔格式不對") }
    store(key)
    print(key.publicKey.rawRepresentation.base64EncodedString())
default:
    fail("用法：update-signing generate | public-key | sign <檔案> | verify <檔案> <簽章檔> <公鑰> | export <資料夾> | import <檔案>")
}
