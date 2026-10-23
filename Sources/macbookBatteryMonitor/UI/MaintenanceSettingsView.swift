import SwiftUI
import AppKit

/// 設定視窗專屬：「清理與系統維護」分頁
/// 完整整合 Mole 的深度快取掃描、孤立殘留清理、過期安裝檔檢測、Top 大型檔案排行與系統修復
struct MaintenanceSettingsView: View {
    @State private var scanResult: DiskCleanerService.ScanResult?
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var statusMessage: String?
    @State private var expandedCategories: Set<DiskCleanerService.CategoryType> = [.developer, .installers]
    @State private var showLargeFiles = true

    private let service = DiskCleanerService()

    private var totalBytes: UInt64 {
        scanResult?.totalCleanableBytes ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - 1. 總覽與快速動作儀表板
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            CardTitle("儲存空間深度清理", systemImage: "sparkles")
                            Text("掃描開發者衍生快取、已解除安裝應用的孤立殘留與過期大型安裝包。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isScanning || isCleaning {
                            ProgressView()
                                .controlSize(.small)
                        } else if totalBytes > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(ByteFormat.size(totalBytes))
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                Text("可釋放空間")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let msg = statusMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(msg)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        .padding(.vertical, 2)
                    }

                    HStack(spacing: 10) {
                        Button {
                            cleanAll()
                        } label: {
                            Label(totalBytes > 0 ? "一鍵釋放全部 (\(ByteFormat.size(totalBytes)))" : "深度掃描可清理項目", systemImage: "trash.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(isScanning || isCleaning)

                        Button {
                            startScan()
                        } label: {
                            Label("重新完整掃描", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isScanning || isCleaning)
                    }
                }
            }

            // MARK: - 2. 分類明細卡片清單
            if let result = scanResult {
                ForEach(DiskCleanerService.CategoryType.allCases) { cat in
                    let items = result.itemsByCategory[cat] ?? []
                    let catBytes = items.reduce(0) { $0 + $1.sizeBytes }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(cat.rawValue, systemImage: cat.icon)
                                    .font(.headline)
                                Spacer()
                                Text(catBytes > 0 ? ByteFormat.size(catBytes) : "無快取殘留")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(catBytes > 0 ? .primary : .secondary)

                                if catBytes > 0 {
                                    Button("清理此項") {
                                        cleanCategory(items)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(isCleaning)
                                }

                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedCategories.contains(cat) {
                                            expandedCategories.remove(cat)
                                        } else {
                                            expandedCategories.insert(cat)
                                        }
                                    }
                                } label: {
                                    Image(systemName: expandedCategories.contains(cat) ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            if expandedCategories.contains(cat) {
                                Divider()
                                if items.isEmpty {
                                    Text("未發現可清理項目，系統非常乾淨。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 2)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(items) { item in
                                            HStack(alignment: .top) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(item.name)
                                                        .font(.system(size: 11, weight: .medium))
                                                    Text(item.path)
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                }
                                                Spacer()
                                                Text(ByteFormat.size(item.sizeBytes))
                                                    .font(.system(size: 11, design: .rounded))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // MARK: - 3. Top 大型檔案探查器
                if !result.largeFiles.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                CardTitle("Top 大型檔案探查器", systemImage: "externaldrive.badge.exclamationmark")
                                Spacer()
                                Button {
                                    withAnimation { showLargeFiles.toggle() }
                                } label: {
                                    Image(systemName: showLargeFiles ? "chevron.up" : "chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Text("顯示 Downloads、Movies、Documents 中單一體積最大之檔案，方便手動搬移或刪除。")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if showLargeFiles {
                                Divider()
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(result.largeFiles) { file in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(file.name)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .lineLimit(1)
                                                Text(file.path)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            Spacer()
                                            Text(file.formattedSize)
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.secondary)

                                            Button {
                                                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
                                            } label: {
                                                Image(systemName: "folder")
                                                    .font(.system(size: 11))
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                            .help("在 Finder 中顯示")
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // MARK: - 4. 系統與記憶體無痛最佳化專區
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle("系統與記憶體無痛最佳化", systemImage: "wrench.and.screwdriver")
                    Text("調用 macOS 原生自帶二進位維護工具，修復網路解析延遲、縮圖快取與釋放不活躍記憶體。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            executeMaintenance("DNS 快取", action: SystemMaintenanceService.flushDNS)
                        } label: {
                            Label("刷新 DNS 快取", systemImage: "network")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button {
                            executeMaintenance("QuickLook 縮圖", action: SystemMaintenanceService.rebuildQuickLookCache)
                        } label: {
                            Label("修復縮圖預覽", systemImage: "eye")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)

                        Button {
                            executeMaintenance("記憶體快取", action: SystemMaintenanceService.purgeMemory)
                        } label: {
                            Label("釋放記憶體", systemImage: "memorychip")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
            }
        }
        .onAppear {
            startScan()
        }
    }

    // MARK: - 操作邏輯
    private func startScan() {
        isScanning = true
        statusMessage = "正在進行全盤深度掃描與 APFS 克隆分析..."
        DispatchQueue.global(qos: .utility).async {
            let res = service.performDeepScan()
            DispatchQueue.main.async {
                self.scanResult = res
                self.isScanning = false
                self.statusMessage = res.totalCleanableBytes > 0 ? "掃描完成，發現 \(res.formattedTotal) 可清理空間" : "掃描完成，系統非常乾淨！"
            }
        }
    }

    private func cleanAll() {
        guard let res = scanResult, res.totalCleanableBytes > 0 else {
            startScan()
            return
        }
        isCleaning = true
        statusMessage = "正在進行守護檢查與安全釋放..."
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: UInt64 = 0
            for items in res.itemsByCategory.values {
                let results = service.cleanCategory(items)
                freed += results.reduce(0) { $0 + $1.freedBytes }
            }
            let updated = service.performDeepScan()
            DispatchQueue.main.async {
                self.scanResult = updated
                self.isCleaning = false
                self.statusMessage = "🎉 已成功安全釋放 \(ByteFormat.size(freed)) 空間！"
            }
        }
    }

    private func cleanCategory(_ items: [DiskCleanerService.CleanableItem]) {
        isCleaning = true
        statusMessage = "正在清理選定類別..."
        DispatchQueue.global(qos: .userInitiated).async {
            let results = service.cleanCategory(items)
            let freed = results.reduce(0) { $0 + $1.freedBytes }
            let updated = service.performDeepScan()
            DispatchQueue.main.async {
                self.scanResult = updated
                self.isCleaning = false
                self.statusMessage = "已釋放 \(ByteFormat.size(freed))"
            }
        }
    }

    private func executeMaintenance(_ name: String, action: @escaping () -> SystemMaintenanceService.MaintenanceOutcome) {
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = action()
            DispatchQueue.main.async {
                self.statusMessage = outcome.success ? "\(name)已完成最佳化" : "\(name)執行結果：\(outcome.details)"
            }
        }
    }
}
