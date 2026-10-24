# 視窗切換器（參考 alt-tab-macos）

狀態：已在本機實作並實機測試，尚未送出實作的 PR。分析對象是 alt-tab-macos v11.10.1（2026-10-23）。這份文件記錄做了什麼、為什麼這樣做、還沒做什麼。

## 授權與做法

alt-tab-macos 是 GPL-3.0。本專案沒有 LICENSE 檔，也不打算改成 GPL，所以：

- 只參考**功能與互動行為**，用本專案自己的架構重寫，不複製 alt-tab 的程式碼、圖片、文字與翻譯。
- 它的 Pro 授權機制（Keychain 授權碼、機器指紋、試用期排程、付款頁）完全不整合。本專案沒有付費層，下面所有功能都是內建、不需授權。
- 若之後想直接移植程式碼，必須先決定整個專案改用 GPL-3.0，這是另一個決策。

## 架構

| 層 | 檔案 | 責任 |
|---|---|---|
| 純邏輯（有單元測試） | `Model/WindowSwitching.swift` | 視窗模型、最近使用順序、篩選、快捷鍵、按鍵狀態機、幻影視窗判斷、版面計算 |
| 設定 | `Model/SwitcherSettings.swift` | 多組快捷鍵與共用設定，讀回時逐欄驗證 |
| 系統介面 | `Services/SkyLight.swift` | 以 dlsym 載入 SkyLight／CGS 私有函式，找不到就停用該功能 |
| 視窗追蹤 | `Services/WindowTracker.swift` | 每個 App 一個 AX 觀察者（標題、視窗元素、最近使用事件）；實際狀態每次按下快捷鍵時由 WindowServer 批次查詢 |
| 事件 | `Services/InputTap.swift` | 只攔按鍵的事件攔截，獨立執行緒，有看門狗 |
| 畫面 | `Services/WindowSwitcher.swift`、`WindowThumbnails.swift`、`WindowPreview.swift` | 不搶焦點的面板、縮圖擷取與快取、選到視窗的預覽 |
| 設定頁 | `UI/WindowSwitcherSettingsView.swift` | 「視窗切換」分頁 |

幾個從 alt-tab 的規格與實測得來的設計決定：

- **視窗清單來自 WindowServer，不靠 AX 掃描**：一次批次查詢 11–17 ms（6 個視窗實測）。AX 只用來取標題、判斷是否為一般視窗、執行視窗操作。
- **幻影視窗判斷**：視窗在畫面上（ordered-in）、縮小或所屬 App 隱藏就收；否則只有它位在「目前沒顯示的 Space」才收，背景分頁與 Electron `show:false` 的視窗因此不會出現。這些位元來自對照實際視窗狀態的逆向，每次 macOS 大版本要重新驗證。
- **最近使用順序只因真正的焦點事件移動**（App 啟用、AX 回報焦點／主視窗改變），不因輪詢移動。
- **沒有視窗的 App**（例如「音樂」按紅色叉叉）以佔位磚塊列出，選到時用 `NSWorkspace` 讓它重新開窗。
- **跨 Space 切換**用 `_SLPSSetFrontProcessWithOptions` 與合成事件記錄；同 Space 用 AX 的 raise。

## 功能狀態

| 功能 | 狀態 |
|---|---|
| 取代 Cmd+Tab，縮圖磚塊、最近使用順序 | 完成、實機測過 |
| 方向鍵、Tab、vim 鍵（H J K L）、滑鼠 hover 選取、放開即切換、快速輕按回上一個 | 完成、實機測過 |
| 視窗操作：W 關閉、M 縮小、F 全螢幕、H 隱藏、Q 結束 App，hover 的紅黃綠按鈕 | 完成、實機測過 |
| 所有 Space 的視窗與 Space 標籤、跨 Space 切換 | 完成；跨 Space 切換仍待更多實機驗證 |
| 篩選：Space、螢幕、最小化、隱藏、全螢幕、沒有視窗的 App；排序；每個 App 只列一個 | 完成 |
| 例外清單（Bundle ID，上限 200 筆，輸入驗證） | 完成 |
| 放開修飾鍵後保持開啟（Return 確認、Esc 取消、點外面取消） | 完成 |
| 樣式：縮圖／App 圖像／標題（alt-tab Pro 的外觀樣式） | 完成 |
| 自動調整大小（alt-tab Pro 的 Auto Size） | 完成 |
| 多組快捷鍵，最多 9 組，各自的樣式、大小、篩選（alt-tab Pro） | 完成；舊設定自動升級為第一組 |
| 預覽選到的視窗（在原位置顯示畫面） | 完成、實機測過 |
| 切換時更新縮圖開關（關閉後只用快取，不觸發系統的擷取提示） | 完成 |
| 淡入與選取框過渡動畫；系統「減少動態效果」時關閉 | 完成 |
| 無障礙：VoiceOver 描述與動作、選取播報、降低透明度 | 完成，待實機驗證 |
| 切換器顯示在滑鼠所在的螢幕 | 完成 |
| **搜尋**（alt-tab Pro） | 決定不做 |
| **觸控板手勢** | 決定不做（需要私有 MultitouchSupport） |
| **原生分頁各自成一項**（Terminal、Finder） | 決定不做：背景分頁不在任何視窗清單，alt-tab 靠暴力掃描 AX 元素編號，成本高又不穩；現在一個分頁群組顯示一項 |
| 設定匯入匯出、命令列介面、英文介面 | 未做 |
| 排序：最近建立 | 未做 |

與最初的計畫不同的地方：

- 原本的 Dock 懸停視窗清單與「點 Dock 隱藏 App」功能已移除（alt-tab 沒有這兩項，且是舊 WIP 才有）。
- 螢幕擷取改用私有的單張擷取（`CGSHWCaptureWindowList`），不用 ScreenCaptureKit 串流。

## 螢幕錄製與狀態列提示

縮圖與預覽需要「螢幕錄製」權限，擷取時 macOS 會在狀態列顯示「正在擷取你的畫面」。這是系統行為，App 不能控制。減少它的方式：

- 只在切換器真的顯示出來時才擷取，快速輕按不擷取。
- 「切換時更新視窗縮圖」關閉後只用快取。
- 樣式選「App 圖像」或「標題」完全不擷取；沒給權限時自動退成圖示與標題。

alt-tab 也有同樣的問題，它提供「在背景擷取視窗」開關處理。

## 風險

- **私有 API**：`_AXUIElementGetWindow`、SkyLight／CGS 與焦點事件記錄的位元組格式。本專案不上 App Store，可以用，但每次 macOS 大版本要重測；所有函式都以 dlsym 載入，找不到就降級，不會崩潰。回傳 `CGRect` 的函式必須以 `@convention(c)` 綁定，否則 Intel 上會崩潰。
- **事件攔截**：只在使用者開啟開關時建立，只攔按鍵，不記錄按鍵；被系統暫停時自動重新啟用。
- **權限**：輔助使用必要；螢幕錄製可選。本機簽章必須沿用穩定的開發憑證，否則每次重建都要重新授權。
- **資安**：視窗標題可能含敏感內容，不寫入日誌、不上傳；設定從 UserDefaults 讀回時逐欄驗證，例外清單的 Bundle ID 限制字元與長度。

## PR 切分

原本計畫拆成四個 PR。實作時發現各層互相依賴（設定模型、按鍵狀態機、版面與視圖是一起演進的），硬拆會產生編不過或測不過的中間狀態，所以改成**一個實作 PR**，審查時可依下面的順序閱讀：

1. 純邏輯與測試：`Model/WindowSwitching.swift`、`Model/SwitcherSettings.swift`、`Tests/`。
2. 系統介面與追蹤：`Services/SkyLight.swift`、`WindowTracker.swift`、`InputTap.swift`。
3. 畫面：`WindowSwitcher.swift`、`WindowThumbnails.swift`、`WindowPreview.swift`、`AccessibilityKit.swift`。
4. 設定頁與接線：`UI/WindowSwitcherSettingsView.swift`、`SettingsWindow.swift`、`AppSettings.swift`、`AppDelegate.swift`。

## 已決定

1. 只參考行為、自己重寫，不複製 alt-tab 程式碼。
2. 舊 WIP 只保留 `InputTap` 的概念，其餘依 alt-tab 的實際做法重做。
3. 螢幕錄製權限為可選。
4. 手勢、搜尋、原生分頁拆項不做。
