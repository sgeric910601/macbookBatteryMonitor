# WindowServer 介面的出處

這份文件列出 `Services/SkyLight.swift`、`Model/WindowSwitching.swift`（`ServerWindowRecord`、`ServerWindowBits`、`WindowCandidacy`）與 `Services/WindowTracker.swift` 快照流程裡，每一個私有符號、常數、結構欄位與作法的來源。

## 為什麼有這份文件

視窗切換器第一版（commit 3fbe460）的 WindowServer 查詢與視窗篩選，跟 alt-tab-macos（GPL-3.0）的對應程式碼在常數名稱、數值、結構欄位與查詢流程上幾乎一樣。本專案以「保留所有權利」的條款（見根目錄 LICENSE）散布執行檔，不能成為 GPL 作品的衍生作品，所以這幾個部分已經獨立重寫：

- 重寫時沒有讀、搜尋或憑記憶重現 alt-tab-macos 的原始碼；舊版的這幾段實作只看了其他檔案會呼叫的公開介面。
- 來源只用三種：Apple 的公開 SDK 標頭、MIT 授權的 [yabai](https://github.com/koekeishiya/yabai)，以及在本機寫的一次性探測程式。
- 能用公開 API 的就改用公開 API；名稱、結構、註解都是新寫的。
- 舊版為了 Intel 上回傳 `CGRect` 的私有函式所做的特殊綁定已經不需要：新版的視窗位置改用公開的 `kCGWindowBounds`，沒有任何私有函式以傳回值回傳結構。

yabai 的引用以 master 分支 commit `dd845723416f5fe92af49fad5ebab00369e07edd`（2026-06-14）為準，授權為 MIT（Copyright (c) 2019 Åsmund Vikane）。本專案只引用函式名稱、參數型別與數值這些關於 macOS 的事實，並以本機探測確認；程式碼是自己寫的。早期版本曾依 yabai 的 `make_key_window` 組出 0xf8 位元組的事件記錄讓視窗成為作用中，後來已整段移除。實測只呼叫 `_SLPSSetFrontProcessWithOptions` 不會切 Space，所以改成再啟用 App，由 macOS 切到它有視窗的 Space（系統設定「切換到應用程式時，切換到有其打開視窗的空間」，預設開啟），等目標出現在畫面上後用「輔助使用」的 `kAXRaiseAction` 讓它成為作用中。

## 探測方式

在本機（macOS 27.0.1，Apple Silicon）寫了一次性的 Swift 程式（不在 repo 裡）：自己開 6 個視窗，依序做縮到 Dock、`orderOut`、透明度設 0、設成子視窗、隱藏整個 App、切成全螢幕，每一步都透過下面列的函式讀出 WindowServer 的值。另一支探測程式在不建立視窗的情況下，對照系統上所有視窗的公開資料與私有資料（只統計數量，不輸出標題）。改寫後的 `SkyLight.swift` 也用同樣的情境跑過一次，結果與下表一致。

## 私有符號

全部以 `dlsym` 在第一次用到時載入；找不到就記錄一筆並停用依賴它的功能，不會崩潰。

| 符號 | 用途 | 宣告出處 | 用法出處 |
|---|---|---|---|
| `SLSMainConnectionID` | 取得 WindowServer 連線 | yabai `src/misc/extern.h` | 同左 |
| `SLSCopyManagedDisplaySpaces` | 每個螢幕的 Space 清單 | yabai `src/misc/extern.h` | 字典鍵 `Display Identifier`、`Spaces`、`id64` 見 yabai `src/display.c`；本機探測確認 |
| `SLSManagedDisplayGetCurrentSpace` | 每個螢幕目前顯示的 Space | yabai `src/misc/extern.h` | yabai `src/display.c`。探測：回傳正在顯示的 Space，切成全螢幕後變成那個全螢幕 Space |
| `SLSSpaceGetType` | 判斷全螢幕 Space | yabai `src/misc/extern.h` | yabai `src/space.c` 的 `space_is_fullscreen`：回傳 4。探測：視窗切成全螢幕後所在 Space 的類型是 4，一般 Space 是 0 |
| `SLSCopyWindowsWithOptionsAndTags` | 列出指定 Space 上的視窗編號 | yabai `src/misc/extern.h` | 選項 `0x7` 取自 yabai `src/space.c` `space_window_list_for_connection` 的 `include_minimized` 分支。探測：縮到 Dock、`orderOut`、隱藏 App 的視窗都在 `0x7` 清單裡 |
| `SLSCopySpacesForWindows` | 視窗所在的 Space | yabai `src/misc/extern.h` | 選擇子 `0x7` 取自 yabai `src/window.c` |
| `SLSWindowQueryWindows`、`SLSWindowQueryResultCopyWindows`、`SLSWindowIteratorAdvance` | 批次查詢視窗資料 | yabai `src/misc/extern.h` | yabai `src/space.c`；兩個回傳值都要釋放（yabai 以 `CFRelease` 釋放） |
| `SLSWindowIteratorGetWindowID`、`SLSWindowIteratorGetParentID` | 視窗編號、父視窗編號 | yabai `src/misc/extern.h` | 探測：`addChildWindow` 之後子視窗的父視窗編號是主視窗，其他視窗是 0 |
| `SLSWindowIteratorGetAttributes`、`SLSWindowIteratorGetTags` | 原始旗標，見下一節 | yabai `src/misc/extern.h` | 位元意義見下一節 |
| `SLSHWCaptureWindowList` | 單一視窗截圖 | yabai `src/misc/extern.h` | 選項 `(1 << 11) \| (1 << 8)` 與回傳陣列要釋放，取自 yabai `src/window_manager.c` 擷取視窗代理圖的地方。探測：能取得自己視窗的 2 倍解析度圖 |
| `_SLPSSetFrontProcessWithOptions` | 把行程帶到前面並指定視窗；實測單獨用不會切 Space，切 Space 靠再啟用 App | yabai `src/misc/extern.h` | 模式 `0x200`（`kCPSUserGenerated`）見 yabai `src/window_manager.h` 與 `window_manager_focus_window_*` |
| `_AXUIElementGetWindow` | 「輔助使用」視窗物件對應的視窗編號 | yabai `src/misc/extern.h` | 改成以 `dlsym(RTLD_DEFAULT)` 載入；找不到時所有 AX 視窗都視為沒有編號（標題與 AX 操作停用，切換仍可走 WindowServer） |

## 公開 API

| API | 用途 | 出處 |
|---|---|---|
| `CGWindowListCopyWindowInfo(.optionAll)` 的 `kCGWindowOwnerPID`、`kCGWindowLayer`、`kCGWindowAlpha`、`kCGWindowBounds`、`kCGWindowName`、`kCGWindowIsOnscreen` | 視窗擁有者、層級、透明度、位置、名稱 | `CoreGraphics/CGWindow.h`。探測：54 個候選視窗都查得到；位置與 `SLSGetWindowBounds` 完全相同、層級與 `SLSWindowIteratorGetLevel` 相同、透明度與 `SLSGetWindowAlpha` 相同，所以這三個私有函式不再使用 |
| `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` | 畫面上的視窗由前到後的順序 | `CGWindow.h` 註明這個選項的結果「由前到後」 |
| `GetProcessForPID` | 由 pid 取得 `ProcessSerialNumber` | `HIServices/Processes.h`（公開但已淘汰；Swift 不匯入 10.9 以前淘汰的函式，所以用 `dlsym(RTLD_DEFAULT)`） |
| `RTLD_DEFAULT` = `(void *)-2` | 在所有已載入映像檔中找符號 | `usr/include/dlfcn.h` |

## 原始旗標的位元（`ServerWindowBits`）

| 名稱 | 值 | 來源 | 探測結果 |
|---|---|---|---|
| `attributeOrdered` | attributes 的 `1 << 1` | yabai `src/space.c` 以 `attributes & 0x2` 判斷可列出的視窗 | 一般視窗 attributes 為 `0x3`；縮到 Dock、`orderOut`、隱藏 App 後變 `0x1`。在別的 Space 的視窗仍是 `0x3`（意思是「已排進它的 Space」，不是「現在看得到」） |
| `tagMinimized` | tags 的 `1 << 60` | yabai `src/space.c` 的 `include_minimized` 分支（`tags & 0x1000000000000000`） | 只有縮到 Dock 的那個視窗出現第 60 位元，還原前一直存在 |
| `tagHiddenByApp` | tags 的 `1 << 39` | 本機探測（yabai 沒有用到） | 隱藏 App 時，當下排在畫面上的視窗出現第 39 位元；已經 `orderOut` 的視窗、縮到 Dock 的視窗、子視窗都沒有。所以不能改用 `NSRunningApplication.isHidden`，否則隱藏 App 的幻影視窗也會被列出 |

本機探測時 Space 類型、選項值與上表都符合 yabai 的用法；第 39 位元只有本機實測一個來源，每次 macOS 大版本更新要重新確認。

## 視窗篩選（`WindowCandidacy`）

篩選規則是本專案自己的行為規格，由 `Tests/.../WindowSwitchingTests.swift` 的 `testWindowAdmission` 定義：編號 0、有父視窗、層級不是 0 或太小的不是切換對象；透明度 0 是幻影；已排進 Space、縮到 Dock 或跟著 App 隱藏的列出；其他的只有整個待在目前看不到的 Space 才列出，否則是幻影（背景分頁、Electron 的 `show:false`）。
