import Foundation
import Darwin

/// 解析 macOS APFS 檔案系統的 Copy-on-Write (CoW) 區塊克隆屬性。
/// 參考 Mole 的 cmd/analyze/clone_darwin.go 做法，透過 Darwin getattrlist 讀取
/// ATTR_CMNEXT_CLONEID 與 ATTR_CMNEXT_EXT_FLAGS，避免在計算磁碟佔用時重複計算克隆檔案。
public enum APFSCloneResolver {
    // 依據 macOS <sys/attr.h> 定義的常數
    private static let attrCmnextCloneID: UInt32 = 0x00000100
    private static let attrCmnextExtFlags: UInt32 = 0x00000200
    private static let efSharesAllBlocks: UInt64 = 0x00000040

    public struct CloneInfo: Equatable {
        public let cloneID: UInt64
        public let sharesAllBlocks: Bool
    }

    private struct AttrList {
        var bitmapCount: UInt16 = UInt16(ATTR_BIT_MAP_COUNT)
        var reserved: UInt16 = 0
        var commonAttr: UInt32 = 0
        var volAttr: UInt32 = 0
        var dirAttr: UInt32 = 0
        var fileAttr: UInt32 = 0
        var forkAttr: UInt32 = 0
    }

    /// 讀取檔案在 APFS 上的 Clone 資訊
    /// - Parameter path: 檔案的絕對路徑
    /// - Returns: 若該磁碟支援並成功讀取則回傳 CloneInfo，若不支援或無法讀取則回傳 nil
    public static func cloneInfo(for path: String) -> CloneInfo? {
        var list = AttrList()
        list.forkAttr = attrCmnextCloneID | attrCmnextExtFlags

        // 回應緩衝區：前 4 bytes 為長度 (UInt32)，接著 clone id (UInt64)，最後 extended flags (UInt64)
        // 總共需 4 + 8 + 8 = 20 bytes
        var buf = [UInt8](repeating: 0, count: 24)

        let result = path.withCString { cPath in
            getattrlist(cPath, &list, &buf, buf.count, UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED))
        }

        guard result == 0 else { return nil }

        let length = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        guard length >= 20 else { return nil }

        let cloneID = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt64.self) }
        let extFlags = buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: UInt64.self) }
        let sharesAll = (extFlags & efSharesAllBlocks) != 0

        return CloneInfo(cloneID: cloneID, sharesAllBlocks: sharesAll)
    }

    /// 判斷檔案是否為全區塊共享的 APFS 克隆檔（實體不佔新磁碟空間）
    public static func isSharedClone(at path: String) -> Bool {
        guard let info = cloneInfo(for: path) else { return false }
        return info.sharesAllBlocks
    }
}
