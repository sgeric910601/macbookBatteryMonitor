# 電池與系統監控 macbookBatteryMonitor

macOS 選單列的電池與系統資訊 App。MacBook 上選單列直接顯示電量，點開就能看到剩餘時間、健康度、電力流向（可展開到各硬體的耗電）、可直接拖動調整的充電上限、歷史曲線、耗電排行，以及藍牙鍵盤、滑鼠、耳機等周邊設備的電量；桌上型 Mac（Mac mini、iMac、Mac Studio 等）改為顯示系統耗電。另外可以開啟 CPU／GPU（含風扇與溫度）、記憶體、磁碟（含外接磁碟）、網路的系統監控模組。

- **一個 App 適用所有 Mac**（v1.7.0 起）：Apple 晶片與 Intel、MacBook 與桌上型 Mac 都用同一個下載檔，自動判斷要顯示電池還是系統耗電
- **系統監控可開可關**：第一次啟動時選「只看電池」或「電池＋系統監控」，之後在設定 → 系統監控隨時切換；關閉時四個模組都不取樣，和以前的電池版一樣省電
- **充電上限滑桿**：在面板電量下方的資訊卡最上方直接拖動調整 macOS 的充電上限（80–100%），與系統設定裡的充電上限是同一個設定、兩邊同步；不需要管理員權限（v1.6.0 起）
- **不另外控制充電**：除了你親手拖動的充電上限滑桿（等於在系統設定裡調整），不會更動任何充電設定，實際停在上限由 macOS 控制；預設不需要管理員權限，只有選用的「管理員 CPU 取樣」開啟時才要授權
- **每秒更新**：選單列與面板上的資訊預設每 1 秒刷新一次，可在設定改成每 2、5、10 秒；面板關閉時 CPU 約 0.2%（只看電池）、約 1%（四個系統監控模組全開），不會阻止系統睡眠
- **省電模式**：想更省電可在設定開啟，電力流向改用靜態圖示、更新頻率至少每 2 秒，不必為了省電改用有 bug 的舊版
- **自己選顯示項目**：電力流向細項（螢幕背光、晶片、CPU／GPU／ANE）與詳細資訊欄位可以個別隱藏；機型讀不到的 ANE、螢幕背光會自動隱藏
- **一鍵更新**：有新版本時在設定按一下就下載、驗證並換上新版（v1.5.0 起）；發現新版本時會發通知，可以關閉
- **不需要 Xcode**：只要 Command Line Tools 就能編譯

## 下載

到 [Releases](https://github.com/sgeric910601/macbookBatteryMonitor/releases) 下載 `macbookBatteryMonitor-<版本>-macOS-universal.zip`（v1.7.0 起）。Apple 晶片與 Intel 的 MacBook、桌上型 Mac 都用這一個；需求是 macOS 14 以上（2018 年以後的 Intel Mac 也可以）。

macOS 12 或 13 的 Mac（例如 2015～2017 年的 MacBook，或用 OpenCore Legacy Patcher 升級的舊 Mac）請改下載 `macbookBatteryMonitor-<版本>-macOS12.zip`（舊系統版本，v1.7.0 起）：功能和通用版相同，同樣支援 Apple 晶片與 Intel；系統升級到 macOS 14 以後，一鍵更新會自動換成通用版。

Release 裡另外兩個 `…-battery-macOS-arm64.zip`、`…-status-macOS-arm64.zip` 是給 v1.5.0～v1.6.1 一鍵更新用的舊檔名，內容和通用版相同，不需要下載。

| | 只看電池 | 電池＋系統監控 |
|---|---|---|
| 怎麼選 | 第一次啟動時選擇，之後在設定 → 系統監控關閉 | 第一次啟動時選擇，之後在設定 → 系統監控開啟 |
| 電池資訊（桌上型 Mac 為系統耗電）、電力流向、充電上限、通知 | ✓ | ✓ |
| CPU／GPU、記憶體、磁碟、網路模組 | — | ✓（選單列各一個圖示，可個別開關；含風扇與溫度、外接磁碟） |
| 周邊設備電量與各自的低電量通知 | ✓ | ✓ |
| 更新頻率（1／2／5／10 秒）、省電模式（靜態電力流向） | ✓ | ✓ |
| 一鍵更新與新版本通知、App 圖示換色 | ✓ | ✓ |
| 面板關閉時 CPU | 約 0.2% | 約 1%（四個模組全開） |
| 面板關閉時 CPU，省電模式 | 約 0.15% | 約 0.5%（四個模組全開） |

App 名稱是「電池與系統監控」（英文系統顯示 Battery & System Monitor），App 資料夾是 `macbookBatteryMonitor.app`。從 v1.6.1 以前升級時不會詢問：原本的電池版維持只看電池，系統監控版維持開著系統監控。只看到電池圖示、沒有 CPU 等圖示時，先到設定 → 系統監控確認總開關有沒有開；有瀏海的 MacBook 選單列放不下時，macOS 也會把多出來的圖示藏在瀏海後面，可以關掉用不到的模組。

### 只看電池

![只看電池：選單列電池圖示與電池面板](docs/screenshots/edition-battery.png)

### 電池＋系統監控

![電池＋系統監控：選單列的 CPU／GPU、記憶體、磁碟、網路圖示與各模組面板，含風扇與溫度、外接磁碟](docs/screenshots/edition-status.png)

### 桌上型 Mac

沒有電池的 Mac（Mac mini、iMac、Mac Studio、Mac Pro）選單列顯示電腦圖示與系統耗電瓦數，面板顯示系統耗電與近 3 分鐘平均、耗電細項（晶片運算、CPU／GPU／ANE、其他）、耗電歷史、耗電排行與周邊設備；設定頁不顯示電池相關的通知與充電上限。

![桌上型 Mac：選單列的系統耗電與耗電細項面板](docs/screenshots/desktop.png)

### Intel Mac

v1.7.0 起支援 Intel Mac（macOS 14 以上，大約是 2018 年以後的機型），在 2018 Mac mini（Intel Core i5-8500B、macOS 15）實測：

- **溫度**：CPU 用各核心的 SMC 溫度鍵（`TC1C` 起；沒有的核心回報 -127 會被過濾），讀不到時改用 PECI／die／proximity（`TCXC`、`TC0F`、`TC0P`）；內顯 `TCGC`、獨立顯卡 `TG0D`／`TG0P`；SSD `TH0a`／`TH0b`；MacBook 電池 `TB0T` 系列
- **CPU／內顯功耗**：SMC 的 `PCPC`／`PCPG`（有號 8.7 定點數），不需要管理員密碼，所以 Intel 不顯示「管理員 CPU 取樣」
- **GPU 記憶體**：Intel 內顯讀 `inUseSysMemoryBytes`，負載時偶爾出現的溢位值（超過實體記憶體）會丟掉
- Intel MacBook 的電池功能目前還沒有在實機上驗證
- 只能裝到 macOS 12、13 的 Mac 用舊系統版本（`…-macOS12.zip`）

### 周邊設備

面板下方的「周邊設備」分頁列出連線中的藍牙鍵盤、滑鼠、觸控板與耳機電量（AirPods 等會分別列出左耳、右耳與充電盒）。每個設備右邊的鈴鐺可以各自設定低電量通知：不通知，或低於 10%、15%、20%、30%、50% 時通知（預設 20%）。

![周邊設備：AirPods、鍵盤、滑鼠的電量與通知設定](docs/screenshots/peripherals.png)

### 更新頻率與省電模式

設定 → 更新頻率與省電。兩個版本都有：

- **更新頻率**：每秒（預設）、每 2 秒、每 5 秒、每 10 秒，電池、系統監控模組、耗電排行與 App 排行都依這個間隔取樣；越慢越省電
- **省電模式**：電力流向改用靜態圖示與箭頭（v1.0.0 的畫法），硬體細項的流帶也不播放動畫，更新頻率至少每 2 秒。可以勾選「只在使用電池時啟用」（v1.7.0 起）：接上電源時自動恢復一般模式，拔掉電源再進入省電

![省電模式：靜態電力流向](docs/screenshots/power-saving.png)

> 截圖為示範數據。CPU 數據為 M1 MacBook Air 實測。

### 舊版本（有已知 bug，不建議使用）

舊版本仍保留在 Releases，但都有下表的 bug，最新版已全部修正。v1.5.0 起有一鍵更新，之後不必再手動下載。想省電的話，請用最新版、把系統監控關掉（只看電池）並開啟省電模式或調慢更新頻率，不要改用舊版。

| 已知 bug | v1.0.0 | v1.1.0 | v1.2.1 | v1.2.2 | v1.3.0 | v1.4.1 |
|---|---|---|---|---|---|---|
| 接著電源時，電池晶片的「充電中」旗標停在舊值：上方顯示「暫停充電」，流向圖卻畫出充電瓦數，狀態圖示在充電上限附近反覆跳動 | 有 | 有 | 有 | 有 | 有 | — |
| 有充電上限時，右上角是充到上限的時間、詳細資訊的系統預估卻是充到 100%，兩個時間不同 | 有 | 有 | 有 | 有 | 有 | — |
| 流向圖中間的系統耗電慢變壓器一秒，充到上限附近電池功率有約 ±4 W 的雜訊 | — | — | 有 | 有 | 有 | — |
| 接著電源但電池仍在放電時（充電器瓦數不足或負載太重），不顯示剩餘時間，**低電量提醒也不會響** | 有 | 有 | 有 | 有 | — | — |
| 每次登入都跳出一次「充電完成」通知 | 有 | 有 | 有 | 有 | — | — |
| 把「最佳化電池充電」的暫停誤認為充電上限，沒設上限也顯示 80% | 有 | 有 | 有 | 有 | — | — |
| 開機自啟動可能同時啟動兩個 App，出現兩個圖示、兩份通知 | 有 | 有 | 有 | 有 | — | — |
| 電量歷史檔讀取失敗時被空檔覆蓋，歷史紀錄全部消失 | 有 | 有 | 有 | 有 | — | — |
| 面板開著時插拔電源，背景取樣與主執行緒同時讀寫快取，可能閃退 | — | — | 有 | 有 | — | — |
| `top` 被強制結束後，CPU 一個核心跑滿、耗電排行卡住 | — | — | — | 有 | — | — |
| 電力流向的圓角裁切在版面尺寸過小時觸發繪圖斷言，極少數情況下閃退 | — | 有 | 有 | 有 | — | — |
| 插拔電源後約 1 分鐘內，電力流向與功率數字錯誤 | 有 | 有 | — | — | — | — |
| 放電到充電上限時，電力流向誤畫成變壓器在供電 | 有 | 有 | — | — | — | — |
| 面板開著時動畫每次更新都整個重建，較耗電 | — | 有 | — | — | — | — |
| 換了 App 圖示顏色後，Finder 已開著的視窗與 LaunchServices 仍顯示舊圖示 | — | — | — | — | — | 有 |

| 版本 | 介面 | 下載 |
|---|---|---|
| v1.6.0 | 充電上限滑桿（沒有已知 bug，可直接一鍵更新到最新版） | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.6.0) |
| v1.5.3 | 外接磁碟、風扇與溫度（沒有已知 bug，可直接一鍵更新到最新版） | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.5.3) |
| v1.5.0 | 一鍵更新（沒有已知 bug，可直接一鍵更新到最新版） | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.5.0) |
| v1.4.1 | 新 App 圖示，可換背景色 | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.4.1) |
| v1.4.0 | 周邊設備、可調更新頻率與顯示項目（沒有已知 bug，但沒有一鍵更新） | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.4.0) |
| v1.3.0 | 電池版／系統監控版、省電模式 | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.3.0) |
| v1.2.2 | 每秒更新、可展開硬體細項 | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.2.2) |
| v1.2.1 | 選單列每 30 秒更新、可展開硬體細項 | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.2.1) |
| v1.1.0 | 動畫 Sankey 流向圖，選單列每 30 秒更新 | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.1.0) |
| v1.0.0 | 靜態圖示與箭頭，選單列每 30 秒更新 | [Release](https://github.com/sgeric910601/macbookBatteryMonitor/releases/tag/v1.0.0) |

## 安裝

需求：macOS 14 以上；Apple 晶片或 Intel 的 MacBook、桌上型 Mac 都可以（通用版）。macOS 12、13 請用舊系統版本（`…-macOS12.zip`），安裝方式相同。

1. 從 Releases 下載 `macbookBatteryMonitor-<版本>-macOS-universal.zip`，解壓縮
2. 把 App（Finder 顯示「電池監控」或「電池與系統監控」，檔名都是 `macbookBatteryMonitor.app`）拖到「應用程式」資料夾
3. 第一次打開時 macOS 會擋下來（App 沒有 Apple 開發者簽章）。任選一種方式放行：
   - 到「系統設定 → 隱私權與安全性」，在下方找到這個 App，按「強制打開」
   - 或在終端機執行：
     ```bash
     xattr -dr com.apple.quarantine /Applications/macbookBatteryMonitor.app
     ```
4. 第一次啟動會詢問要「只看電池」還是「電池＋系統監控」（桌上型 Mac 是「只看耗電」／「耗電＋系統監控」）、詢問通知權限，並自動加入開機自啟動（可在設定關閉）

已經在用 v1.5.0 以後的版本：到設定 → 更新按「一鍵更新」即可升級，不必重新下載。

要只看電池或開啟系統監控，到設定 → 系統監控切換即可，不用重新下載。設定頁最下方會顯示 App 名稱與版本號。

## 功能

**選單列**（設定 → 選單列 → 顯示方式）
- 圖示 + 百分比、只有圖示、只有百分比、圖示 + 剩餘時間
- 圖示內百分比 + 剩餘時間（v1.2 起）：電量顯示在電池圖示裡，右側是剩餘／充滿時間；沒有時間資料顯示「—」，滿電、接電未充電、到達上限時分別顯示「已充飽」、「接電」、「已達上限」
- 充電中顯示閃電、接電未充電顯示插頭、低電量變紅

**面板**
- 電量、充放電狀態、剩餘時間／充滿時間（有充電上限時顯示充到上限的時間）
- 充電上限滑桿（v1.6.0 起）：在預估可用時間／電源狀態／充電預估卡片的最上方（v1.6.1 起與卡片合併），80–100% 每 5% 一格（級距由系統提供），放開滑桿才寫入，寫入後讀回確認系統已套用，沒套用會顯示提示；在系統設定改的也會即時同步。主面板上的上限數值只顯示在滑桿上，下方卡片與詳細資訊不再重複（設定頁的「充電上限」仍會顯示）。系統不支援調整充電上限的 Mac 不顯示滑桿
- 預估用到 0% 與**用到 10%** 的時間：系統預估 + 依近 3 分鐘平均耗電推算
- 已使用電池多久（這次拔掉電源後）
- 電力流向：變壓器、系統、電池之間的瓦數
- 系統細項（v1.2 起）：展開成螢幕背光、晶片運算、其他（估算）；點晶片再展開 CPU／GPU／ANE（沒有 ANE 通道的機型不顯示 ANE；沒有背光感測器的機型不顯示螢幕背光，「其他」改為包含螢幕）。每一項都可以在設定 → 顯示項目隱藏
- 詳細資訊：電池電壓、電池電流、電池功率、系統耗電、系統預估、電池溫度、健康度、循環次數、容量（mAh）、變壓器（額定瓦數）、變壓器即時電壓與電流、充電上限（有充電上限滑桿的 Mac 只顯示在滑桿上，不重複列出）；每個欄位都可以在設定 → 顯示項目隱藏
- 電量歷史圖表（1 小時／24 小時／7 天，第一次啟動會用 `pmset` 紀錄回填過去幾天）
- 耗電排行：前 5 名 App，同一個 App 的子程序會合併，依更新頻率更新
- 周邊設備：連線中的藍牙鍵盤、滑鼠、觸控板與耳機電量，每 60 秒更新，每個設備可以各自設定低電量通知

**系統監控模組**（設定 → 系統監控：總開關加上四個模組各自的開關）
- CPU／GPU：選單列顯示 CPU 與 GPU 使用率；面板有使用者／系統比例、最近 2 分鐘曲線、各核心（效能核心、節能核心）、GPU 記憶體、平均負載、CPU 使用率最高的 App，以及「風扇與溫度」：風扇轉速與佔最高轉速的比例（沒有風扇的機型不顯示）、CPU／GPU／SoC／電池／儲存裝置溫度（讀不到的項目不顯示）
- 記憶體：選單列顯示使用率（記憶體壓力升高時變橘、變紅）；面板有 App 記憶體、系統保留、已壓縮、檔案快取、可用的組成，以及最近 2 分鐘曲線、Swap、使用記憶體最多的 App
- 磁碟：選單列顯示開機磁碟的已使用比例；面板列出開機磁碟與目前掛載的外接磁碟（USB、Thunderbolt、SD 卡，不含映像檔與網路磁碟），每顆都有已使用／可用容量、檔案系統、連線類型、SMART 健康狀態、讀寫速度與曲線、累計讀寫
- 網路：選單列顯示上傳與下載速度；面板有目前的網路介面（Wi-Fi、乙太網路）與 IP、速度曲線、開機以來的累計流量
- 同一個 App 的子程序（例如瀏覽器分頁）會合併到 App 名下

**其他**
- macOS 的充電上限（系統設定 → 電池）：可在面板直接調整；顯示已達上限、充到上限的時間、高於上限時降到上限的時間；用電池時也讀得到目前的設定
- 低電量／充電完成通知（門檻可調；到達系統充電上限也會通知）；接著電源但電池仍在放電時，低電量提醒照樣會響。macOS 關閉了這個 App 的通知時（例如第一次詢問時按了不允許，之後系統不會再問），設定頁的「通知」會提醒，並可直接打開系統設定的通知頁
- 周邊設備低電量通知：每個設備降到自己的門檻時通知一次，充電回到門檻以上才會再通知
- 更新頻率可選 1／2／5／10 秒；省電模式改用靜態電力流向
- 滿電或到達充電上限、接著電源時，狀態與流向不會反覆跳動（見下方「電力總覽與硬體功耗」）
- 管理員 CPU 取樣（選用）：CPU 能量計數不更新的機型，可改用 `powermetrics` 取得 CPU 功耗
- App 圖示可換背景色：薄荷綠（內建）、暖杏色、深夜藍、天空藍（見下方說明）
- 一鍵更新：設定 → 更新，有新版本時按一下就下載、驗證並換上新版；自動檢查發現新版本時發一則通知，每個版本只通知一次，可在設定 → 更新關閉（見下方說明）
- 開機自動啟動

## 使用方式

- **左鍵**點選單列圖示：打開面板
- **右鍵**：打開面板、設定、結束
- **電力流向**（v1.2 起）：點「系統」展開硬體細項，點「晶片運算」再展開 CPU／GPU／ANE
- **系統監控模組**（開啟時）：左鍵打開該模組的面板，右鍵打開設定或結束；按住 ⌘ 可以拖曳調整圖示在選單列的順序
- **周邊設備**：面板下方切到「周邊設備」分頁；點設備右邊的鈴鐺設定低電量通知，右下角的箭頭可以立即更新
- **充電上限**：拖動電量下方資訊卡最上方的滑桿，放開後就套用到 macOS 的充電上限；拖到 100% 等於不限制
- **更新**：有新版本時會收到通知、面板底部也會出現「有新版本」；點通知或這個按鈕都會打開設定 → 更新，按「一鍵更新」
- **設定**：選單列顯示方式、App 圖示顏色、一鍵更新、顯示項目（電力流向細項與詳細資訊欄位）、更新頻率與省電模式、系統監控總開關與各模組開關、管理員 CPU 取樣（Apple 晶片）、通知門檻與新版本通知、開機自啟動；設定頁的「充電上限」顯示目前的系統設定，也可以跳到系統設定修改

## App 圖示

圖示是一隻仰躺在無線充電墊上的布偶貓（照片去背）。設定 → App 圖示可以換背景色：薄荷綠（內建）、暖杏色、深夜藍、天空藍。

![App 圖示的四種背景色](docs/screenshots/app-icons.png)

- 換的是「應用程式」資料夾、Finder、Launchpad、Spotlight 裡看到的圖示，等同在「取得資訊」裡貼上自訂圖示；通知與系統設定的登入項目用的是內建圖示，仍是薄荷綠
- 換成薄荷綠以外的顏色時，App 最上層會多一個自訂圖示檔，`codesign --verify --strict` 會回報有多餘的檔案；App 照常執行，換回薄荷綠就會移除
- 用新版覆蓋 App 後自訂圖示會消失，App 啟動時會自動套回你選的顏色

## 一鍵更新

設定 → 更新可以檢查 GitHub 上的新版本，有新版時按「一鍵更新」：

1. 下載通用版的 zip（Apple 晶片與 Intel 都能用；舊版 Release 沒有通用版時改用舊檔名的 zip），只從 `github.com` 與 `githubusercontent.com` 下載
2. 驗證：比對 Release 附的 `SHA256SUMS.txt`（加入一鍵更新之後的每個 Release 都有），並確認 App 的識別碼、版本號與簽章
3. App 結束後換上新版並重新開啟；換不過去會放回原本的版本。設定、電量歷史與自訂的 App 圖示顏色都會保留；下載或驗證失敗、或更新中途被中斷時，暫存檔會清掉

「自動檢查更新」預設開啟：啟動後與之後每 6 小時看一次，距離上次檢查超過一天才會連到 `api.github.com` 查最新版本，只提示、不會自動安裝。所以一直開著 App 的話，新版發布後大約 1 天內會發現。

「有新版本時通知」預設開啟：自動檢查發現新版本時發一則 macOS 通知，每個版本只通知一次（手動按「檢查更新」看到的版本不會再通知），點通知會打開設定並捲到「更新」。不想收到可在設定 → 更新關閉；關閉自動檢查更新時也不會通知，但面板底部仍會在手動檢查到新版本時顯示「有新版本」。App 不在可寫入的位置（例如由系統管理員安裝）時無法一鍵更新，會提示到 GitHub 手動下載。

v1.4.1 以前的版本沒有這個功能，要先手動下載一次新版。

## 管理員 CPU 取樣（選用，預設關閉）

部分機型（例如下表的 M1、M2 Pro）的 CPU 能量計數不更新，晶片細項的 CPU 只能顯示 0 W。需要 CPU 功耗時，可以在設定 → CPU 功耗打開「管理員 CPU 取樣」，改用系統內建的 `powermetrics` 讀取。不需要的話維持關閉即可，App 完全不會安裝或連線任何服務。

- **開啟**：只有在設定裡親手打開時才會跳出 macOS 的管理員授權視窗，安裝一個只讀取 CPU 功耗的系統服務；不儲存密碼、不修改 sudoers。授權取消或失敗時選項會自動關回去，開 App 或開機時不會跳出密碼視窗
- **取樣**：只在主面板開著時連線，間隔與其他資訊相同（依更新頻率）。關閉面板、進入設定頁、睡眠或結束 App 就斷線，`powermetrics` 立即停止，之後完全不通訊；服務閒置 30 秒後自行結束，不常駐，下次打開面板時由系統再啟動
- **關閉**：關掉選項就停止並移除服務（不需要密碼）。只有親手關掉選項才會移除；開 App 時不會去動系統裡的服務。選項開著但服務版本與 App 不符時，會移除舊服務並關回選項，需要時再開一次授權
- **耗電**：只有主面板開著時 `powermetrics` 才會執行。M1 MacBook Air 實測，面板開著時服務與 `powermetrics` 合計另佔 CPU 約 1%（省電模式約 0.3%）；面板關閉時與沒開這個選項相同
- **安全**：服務只接受安裝時那位使用者的連線，只能開始／停止固定參數的 `powermetrics`（間隔只能是 1、2、5、10 秒）或移除自己，不接受任意指令、路徑或 PID
- **位置**：服務程式在 `/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu/`，啟動設定在 `/Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist`

等待授權、尚未取得資料或資料逾時時不顯示舊值；系統功耗與 CPU 的取樣時間窗只是近似同步。

## 電力總覽與硬體功耗（v1.2 起）

面板主頁依更新頻率（預設每秒）取樣，關閉面板、進入設定頁或睡眠時停止取樣。讀取不需要管理員權限（CPU 改用 `powermetrics` 的選用功能除外）。

**接著電源時的穩定顯示**

- **是否在充電**：電池晶片回報的「充電中」旗標會停在舊值（實測 M1 在約 14 W 充入電池、電量持續上升時，仍有十幾秒回報「未充電、電流 0」），所以有 SMC 即時功率時以功率為準：充入 3 W 以上算充電、0.5 W 以下算沒在充，中間才看晶片旗標。到達充電上限後要晶片旗標與功率都同意才算充電（多一層保險，避免感測器配對不到時的雜訊）
- **狀態確認 10 秒**：接著電源時，充電中／已達上限／未充電之間的切換要持續 10 秒才更新，避免 macOS 在上限附近反覆暫停、恢復充電時圖示跟著跳；實際拔除或重新接上電源立即更新
- **滿電緩衝**（沒有設定系統充電上限時）：畫面優先維持「已充飽」，短暫降到 99%／98% 仍保留滿電狀態，低於 98% 恢復一般判定
- **流向圖跟著狀態**：接著電源但沒在充電（滿電、到達上限、暫停）時，電池功率在 ±2 W 內顯示由變壓器直接供電，流向變化持續 10 秒才切換；滿電時「電力流向」標題列會顯示即時帶正負號的電池功率。供電不足或電量高於上限、電池正在放電時照實畫出電池一起供電，剩餘時間與低電量提醒不受影響
- **預估時間一致**：有充電上限時，右上角與詳細資訊的「系統預估」都是充到上限的時間

**電力總覽**（變壓器、系統、電池）

- **變壓器輸入**讀 SMC `PDTR`，**系統耗電**讀 SMC `PSTR`
- **電池功率**用「變壓器輸入 − 系統耗電」推算，所以三個數字一定對得起來。實測兩個感測器都每秒更新一次，但 `PSTR` 比 `PDTR` 慢一次更新（`PSTR` 幾乎等於 1 秒前的 `PDTR`，平均差 0.01 W），同時讀的兩個值直接相減會有約 ±4 W 的雜訊、系統耗電也會看起來慢變壓器一秒；所以系統耗電配對 1 秒前讀到的變壓器輸入。更新頻率慢於每秒時，在每次更新前 1 秒先讀一次變壓器輸入（只多一次 SMC 讀取），電池閒置時誤差由約 4 W 降到 0.00 W。SMC 的 `PPBR` 在部分機型上與實際充放電功率不符（例如 M1 MacBook Air 充電約 13 W 時只讀到 1～2 W），所以完全不使用；缺少 `PDTR` 或 `PSTR` 時，改用 IORegistry 電壓 × 電流備援，不會把缺少的輸入當成 0 W
- 剛拔電時 `PDTR` 可能殘留舊值，只在系統確認接電時才計入輸入
- macOS 放電到充電上限時會暫停變壓器供電，此時仍視為接電，顯示「已達充電上限」
- SMC 數值即時更新，不會像電池晶片（IORegistry）那樣插拔後延遲約一分鐘；電流由電池功率與電壓換算，數值不加約等於符號。第一頁依更新頻率重新讀取輸入與系統功率，並同步重新計算電池分流。插拔通知後會在 1、3、6 秒各重讀一次

**硬體細項**

- **系統總功耗**：優先讀取 SMC `PSTR`，不可用時退回 IORegistry 的 `SystemLoad`
- **螢幕背光**：讀取 SMC 感測器（`PDBR`／`PBwo`）。沒有這兩個 key 的機型（例如 M1 MacBook Air）不顯示背光，背光改算在「其他（含螢幕）」裡；M2 Pro 等有感測器的機型照常顯示
- **CPU／GPU／ANE**：IOReport Energy Model 的能量差除以實際取樣時間；首次取樣只建立基準。Energy Model 沒有 ANE 通道的機型不顯示 ANE，也不把它算成缺值
- **其他（估算）**：總功耗扣掉背光與已取得的晶片功耗後的差值（沒有背光感測器時不扣背光）；缺晶片細項時改標示「未分類（估算）」，裡面也包含缺少的項目
- 晶片合計只涵蓋取得的 CPU、GPU、ANE，不代表完整 SoC 功耗，也不含外接螢幕
- 每一項都可以在設定 → 顯示項目隱藏；隱藏「晶片運算」後就不能再展開 CPU／GPU／ANE

IOReport 是系統私有介面，可用性依晶片與 macOS 版本而異。機型本身沒有的項目自動隱藏，暫時讀不到的項目顯示「—」：

| 機型 | 系統總功耗 | 背光 | GPU | CPU | ANE |
|---|---|---|---|---|---|
| M2 Pro | ✓ | ✓ | ✓ | 顯示 0 W（通道未持續更新）；開啟管理員 CPU 取樣可讀到 | 閒置時 0 W |
| M1 MacBook Air | ✓ | 沒有感測器，自動隱藏（算在「其他（含螢幕）」） | ✓ | 顯示 0 W（通道未持續更新）；開啟管理員 CPU 取樣可讀到 | 沒有通道，自動隱藏 |

## 更新頻率與省電設計

所有即時資訊預設每 1 秒更新（可改成 2／5／10 秒；省電模式至少 2 秒），但每次只做必要的讀取。M1 MacBook Air 實測：

| 情況 | 每秒更新 | 省電模式（每 2 秒） |
|---|---|---|
| 面板關閉，只看電池（系統監控總開關關閉） | 約 0.2% | 約 0.15% |
| 面板關閉，四個系統監控模組全開 | 約 1% | 約 0.5% |
| 打開電池面板（耗電排行分頁） | 約 4%，`top` 另佔約 6% | 約 2%，`top` 另佔約 3% |
| 打開 CPU 或記憶體模組面板 | 約 3%，`top` 另佔約 6% | 約 2%，`top` 另佔約 3% |

`top` 只在耗電排行分頁或 CPU／記憶體面板開著時執行，切到其他分頁或關閉面板就停止；面板停在詳細資訊或電量歷史時沒有 `top` 的負擔。

- 面板關著時依更新頻率更新選單列需要的資料（電量、狀態、功率、剩餘時間）；插拔電源另由系統通知立即更新
- 選單列圖示只有在數字、時間或狀態改變時才重畫
- SMC 每個 key 的格式查過一次就記住，之後每個數值只需一次 SMC 呼叫；每秒只讀 `PDTR`、`PSTR` 兩個值，不讀 `PPBR`
- 變壓器規格接上電源後每 30 秒查一次（額定瓦數不會每秒改變）；充電上限檔案用 `stat()` 確認修改時間，變了才重新解析；系統的充電上限設定只在啟動、打開面板與系統通知有變更時讀取，不每秒查詢
- 面板每次打開才建立，關閉就連同視窗整個釋放，背景沒有任何畫面在更新
- 硬體細項與 SMC 溫度只在面板開著時讀；選用的管理員 CPU 取樣也只在主面板開著時連線，關閉面板就斷線，服務閒置後自行結束
- 耗電排行只在面板開著且停在該分頁時，持續跑一個 `top` 依更新頻率輸出；切換分頁或關閉面板就停止；`top` 意外結束時會停止監聽，不會空轉
- 流向動畫由 Core Animation 合成（不逐幀更新 SwiftUI），只在面板開著且該線路有供電時播放；支援「減少動態效果」；省電模式改用靜態圖示，完全不播放動畫
- 更新頻率與省電模式改變時，所有計時器與 `top` 的取樣間隔立即跟著改，不必重開 App
- 系統監控只取樣有開啟的模組；總開關關閉時完全不建立模組的圖示與計時器；選單列圖示寬度固定，換數字時不會讓整條選單列重新排版
- 磁碟容量每秒用 `statfs()` 讀（幾微秒），系統可清出的空間（查一次約 12 毫秒）每 5 分鐘校正一次；網路只查目前使用中的介面
- 外接磁碟清單每秒用 `getfsstat(MNT_NOWAIT)` 讀（不會被離線的網路磁碟卡住），是否為外接只在第一次看到時問 DiskArbitration；各磁碟讀寫計數的位置找到一次就記住，之後每秒只讀一個屬性
- SMART 健康狀態要啟動 `diskutil`，還可能喚醒休眠中的外接硬碟，所以只在磁碟面板開著時查，每顆最多 10 分鐘一次
- 風扇與溫度只在 CPU 面板開著時於背景每 2 秒讀一次（一次約 28 毫秒），選單列平常不讀
- CPU 與記憶體的 App 排行只在該模組面板開著時，持續跑一個 `top` 依更新頻率輸出；關閉面板就停止
- 周邊設備電量變化很慢，每 60 秒查一次：鍵盤、滑鼠、觸控板讀 IORegistry（很快）；耳機要跑 `system_profiler`（約 0.1～0.3 秒），所以背景更新時只有連著藍牙音訊裝置才查，打開周邊設備分頁時才查所有藍牙設備
- 不是即時讀數的資料不必每秒查：電量歷史每分鐘記一筆（每 15 分鐘寫一次檔，睡眠前和結束時也會存）；健康度每 6 小時查一次（`system_profiler` 每次約需 0.5 秒，健康度以週為單位變化）

## 資料來源

| 項目 | 來源 |
|---|---|
| 電量、電壓、原始電流、容量、循環次數 | IORegistry `AppleSmartBattery` |
| 外部輸入、系統功耗、背光 | SMC（唯讀，`PDTR`、`PSTR`、`PDBR`／`PBwo`）；桌上型 Mac 只讀 `PSTR`（整機耗電） |
| 變壓器即時電壓、電流 | SMC（唯讀，`VD0R`、`ID0R`，與 `PDTR` 同一次讀取、一起配對）；沒有時用 IORegistry `PowerTelemetryData` 的 `SystemCurrentIn` |
| 電池功率 | 由「外部輸入 − 系統功耗」推算；缺少任一路時改用 IORegistry 電壓 × 電流（不使用 `PPBR`） |
| CPU／GPU／ANE 功耗 | Apple 晶片：IOReport Energy Model 的能量差與實際取樣時間，管理員模式的 CPU 改用 `powermetrics`；Intel：SMC `PCPC`／`PCPG`（唯讀） |
| 系統預估時間 | IOKit Power Sources |
| 是否在充電 | SMC 即時電池功率為主，數值模糊時看 IOKit Power Sources／IORegistry 的充電旗標 |
| 健康度（最大容量）、電池狀況 | `system_profiler SPPowerDataType` |
| 電池溫度（詳細資訊） | SMC（唯讀，`TB0T`～`TB2T`） |
| 耗電排行 | `top -o power` |
| 歷史回填、拔電時間 | `pmset -g log` |
| 充電上限（設定值、滑桿調整） | macOS 的充電上限服務（PowerUI 的 `PowerUISmartChargeClient`，系統設定的電池頁也是用它）；變更通知 `com.apple.powerui.mclstatuschanged`。不需要管理員權限 |
| 充電上限（目前生效中） | `/Library/Preferences/com.apple.powerd.charging.plist`（唯讀；只在接電時存在）；讀不到系統設定值的 Mac 會記住上次接電時讀到的值 |
| CPU 使用率、各核心 | `host_processor_info` 的累計 tick 差值；核心類型來自 `hw.perflevel0／1` |
| 平均負載 | `getloadavg` |
| GPU 使用率、GPU 記憶體 | IORegistry `IOAccelerator` 的 `PerformanceStatistics`（Intel 內顯的記憶體是 `inUseSysMemoryBytes`） |
| 記憶體組成、壓力、Swap | `host_statistics64`、`kern.memorystatus_vm_pressure_level`、`vm.swapusage` |
| 磁碟容量 | `statfs()`，加上定期校正的系統可清出空間（與 Finder 一致） |
| 磁碟讀寫 | IORegistry `IOBlockStorageDriver` 的累計讀寫位元組（每顆磁碟各自從分割區往上找到對應的驅動） |
| 外接磁碟清單、連線類型 | `getfsstat`、DiskArbitration（`DeviceInternal`、`DeviceProtocol`） |
| 磁碟健康狀態 | `diskutil info -plist` 的 `SMARTStatus`（多數 USB 外接盒不回報，顯示「此裝置不支援」） |
| 風扇轉速 | SMC（唯讀，`F<n>Ac`、`F<n>Mn`、`F<n>Mx`） |
| CPU 面板的溫度（CPU／GPU／SoC／電池／儲存） | IOHIDEventSystem 溫度感測器（以 `dlsym` 取得的私有介面，不存在時不顯示）；HID 沒有各核心感測器的 M2 系列改讀 SMC 核心溫度鍵，核心叢集休眠時的假值會沿用最近一次有效值最多 120 秒。實測 M1 MacBook Air 可由 HID 讀到 CPU、GPU、SoC、電池與儲存溫度。Intel 沒有 HID 溫度感測器，改讀 SMC 的核心（`TC1C` 起）、PECI／die／proximity、內顯 `TCGC`、SSD `TH0a`／`TH0b`、電池 `TB0T` 等鍵 |
| 網路速度與累計流量 | `sysctl` 的 64 位元介面計數器（`NET_RT_IFLIST2`），只查目前使用中的介面 |
| 網路介面與 IP | `SCDynamicStore`（預設路由介面）、`getifaddrs` |
| CPU／記憶體 App 排行 | `top -o cpu`、`top -o mem` |
| 新版本資訊（一鍵更新） | GitHub API `releases/latest`，每天最多一次；下載檔以 Release 的 `SHA256SUMS.txt` 驗證 |
| 周邊設備電量（鍵盤、滑鼠、觸控板） | IORegistry 中帶 `BatteryPercent` 的服務 |
| 周邊設備電量（耳機左右耳、充電盒） | `system_profiler SPBluetoothDataType`；是否連著藍牙耳機由 CoreAudio 的裝置清單判斷 |

## 資料存放位置

- 歷史紀錄：`~/Library/Application Support/BatteryMonitor/history.json`（保留 7 天）
- 設定：`com.kuan.batterymonitor`（UserDefaults）
- 管理員 CPU 取樣的服務（只在開啟該選項時存在）：`/Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu/`、`/Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist`

## 解除安裝

1. 在 App 設定裡關閉「管理員 CPU 取樣」（有開過的話，會移除系統服務）與「開機時自動啟動」，然後結束 App
2. 刪除 `/Applications/macbookBatteryMonitor.app`
3. 如果先刪了 App、系統服務還留著，在終端機執行：
   ```bash
   sudo launchctl bootout system/com.kuan.batterymonitor.cpu
   sudo rm -f /Library/LaunchDaemons/com.kuan.batterymonitor.cpu.plist
   sudo rm -rf /Library/PrivilegedHelperTools/com.kuan.batterymonitor.cpu
   ```
4. （選擇性）清除資料：
   ```bash
   rm -rf ~/Library/Application\ Support/BatteryMonitor
   defaults delete com.kuan.batterymonitor
   ```

## 從原始碼編譯

只需要 Command Line Tools（`xcode-select --install`），不需要 Xcode。

```bash
git clone https://github.com/sgeric910601/macbookBatteryMonitor.git
cd macbookBatteryMonitor
git checkout v1.6.1          # 或其他版本的 tag，不指定就是最新的開發版
./build.sh                   # 通用版（Apple 晶片＋Intel）：產生 build/macbookBatteryMonitor.app
./build.sh install           # 並安裝到 /Applications 啟動
```

## 開發

```bash
Scripts/test-power.sh    # 換算、供電狀態切換、接電穩定顯示、生命週期、動畫、系統監控、外接磁碟、溫度、CPU 服務協定、周邊設備、一鍵更新與充電上限滑桿測試（Command Line Tools 可執行）
```

除錯用參數：

```bash
APP=/Applications/macbookBatteryMonitor.app/Contents/MacOS/macbookBatteryMonitor
$APP --dump              # 目前讀到的資料印成 JSON
$APP --dump-hardware     # 每秒輸出硬體功耗，共五筆 JSON
$APP --snapshot <資料夾>  # 在螢幕外把面板各分頁畫成 PNG
$APP --selftest-panel    # 自動開面板 20 秒再關，量測耗電用
$APP --selftest-hardware # 展開晶片、切換設定頁，確認取樣會停止與恢復，並印出 CPU 讀值（含管理員 CPU 取樣狀態）
$APP --dump-monitors     # 系統監控模組的讀數（間隔 1 秒取樣兩次）印成 JSON
$APP --dump-sensors 10   # 每秒印一份溫度感測器與風扇的表格（原始值、保留舊值後的值），共 10 次
$APP --dump-peripherals  # 讀一次周邊設備電量（含所有藍牙設備）並印出耗時
$APP --notification-status # 印出這個 App 的通知權限（收不到通知時先查這個）
$APP --selftest-monitors # 依序打開 CPU、記憶體模組面板各 10 秒再關，量測耗電用
$APP --selftest-update   # 檢查 GitHub 上的新版本，有就直接一鍵更新（測試時把副本的版本號改低）
$APP --screenshots <資料夾> # 用示範數據畫出兩個版本、省電模式與周邊設備的介紹圖（docs/screenshots）
```

舊系統版本（macOS 12 起）在 `legacy-macos12` 分支：把 macOS 13／14 才有的寫法（Observation、Swift Charts、Grid、SMAppService 等）換成相容寫法，其他程式與主分支相同。在較新的系統上加 `--macos12-paths` 啟動，可以強制走 macOS 12 的寫法測試。發布時，`legacy-macos12` 分支的版本號和這次發布相同，GitHub Actions 才會一起打包 `…-macOS12.zip`。

`build.sh` 會一次編出 Apple 晶片與 Intel 兩種架構（通用版）；只裝 Command Line Tools、無法一次編兩種架構時，自動改編這台電腦的架構。

發布時 GitHub Actions 會用同一份程式碼打包三個 zip：給大家下載的通用版（`MBMEdition=universal`），以及給 v1.5.0～v1.6.1 一鍵更新用的舊檔名 `battery`／`status` zip（內容相同，只有 `MBMEdition` 不同，用來決定從舊版升級時系統監控預設開或關）。

`build.sh` 也會把管理員 CPU 取樣用的服務程式（`CPUPowerHelper`）放進 App 的 `Contents/Library/Helpers/`；只有使用者開啟該選項時才會安裝到系統。

App 圖示由 `Scripts/make-icon.swift` 產生：貓咪是 `Resources/icon-cat.png`（照片去背），充電墊、波紋與背景用程式畫出來。

```bash
swiftc -O Scripts/make-icon.swift -o build/make-icon
build/make-icon Resources/AppIcon.icns                                  # 內建的薄荷綠圖示
for bg in peach night sky; do build/make-icon --bg $bg --size 512 --preview Resources/AppIcons/icon-$bg.png; done
```

只裝 Command Line Tools 時沒有 SwiftUI 的 macro 外掛，所以程式裡不用 `@State`，介面狀態集中在 `PanelState`。

## 致謝

- [@melvin0kuo](https://github.com/melvin0kuo)：動畫電力流向、分層硬體功耗、功率感測備援、選單列圖示內百分比、滿電穩定顯示與管理員 CPU 取樣（#1、#2、#4～#7）
- [@liaw-boy](https://github.com/liaw-boy)：外接磁碟、風扇與溫度、1x 螢幕的選單列圖示對齊、充電上限滑桿併入資訊卡的版面構想（#8～#10）
