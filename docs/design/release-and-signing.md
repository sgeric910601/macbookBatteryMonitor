# 發布、一鍵更新與簽章

這份文件說明一個版本從 commit 到使用者 Mac 上的過程：兩個分支怎麼打包、Release 附哪些檔案、一鍵更新怎麼挑檔案和驗證，以及為什麼每個版本都用同一張憑證簽章。

## 兩個分支、一個 App

| 分支 | 系統 | 產出 |
|---|---|---|
| `main` | macOS 14 以上 | 通用版 `macbookBatteryMonitor.dmg`，Apple 晶片＋Intel |
| `legacy-macos12` | macOS 12 起 | 舊系統版本 `macbookBatteryMonitor-macOS12.dmg` |

- `legacy-macos12` 把 macOS 13／14 才有的寫法（Observation、Swift Charts、Grid、SMAppService 等）換成相容寫法，其他程式和 `main` 相同。每次發布前合併 `main`；在新系統上加 `--macos12-paths` 啟動，可以強制走 macOS 12 的寫法測試
- 兩邊的識別碼都是 `com.kuan.batterymonitor`，用同一張憑證簽，所以舊系統版本換成通用版時權限也保留
- `Info.plist` 的 `MBMEdition` 記錄是哪一種打包（`universal`、`legacy`，以及給舊版一鍵更新的 `battery`、`status`）。從 v1.6.x 更新上來時，App 用它保留原本的系統監控設定

## GitHub Actions（`.github/workflows/build.yml`）

- **每次推送與 PR**：跑 `Scripts/test-power.sh`，匯入簽章憑證，編譯通用版，檢查簽章（`codesign --verify --deep --strict`）、簽章身分與兩種架構，打包 DMG
- **發布**：推送到 `main` 時，如果 `Info.plist` 的版本 `v<版本>` 還沒有 Release（包括草稿），而且有 `.github/release-notes/v<版本>.md`，就測試、打包，在這個 commit 建立**草稿** Release。說明檔第一行是標題，第三行起是內容。所以版本號和說明檔要等確定發布時才一起 commit
- **發布一定要用固定的憑證**：匯入憑證的步驟帶 `MBM_SIGNING_REQUIRED=1`，沒有設定 Secrets 就停下來；每個打包好的 App 都用 `Scripts/check-signature.sh` 確認是「macbookBatteryMonitor Signing」簽的
- **簽署並正式發布**：草稿使用者與一鍵更新都看不到。發布者在自己的 Mac 上執行 `Scripts/sign-release.sh v<版本>` 才正式發布（見下面的「更新簽章」）
- `Info.plist` 帶 `MBMPrerelease`（例如 `beta.1`）時，tag 是 `v<版本>-beta.1`，標成預先發行版本，不會變成「最新版本」
- `legacy-macos12` 的版本號（含 Beta 序號）和這次發布相同時，才一起打包舊系統版本。所以要先推 `legacy-macos12`，再推 `main`
- 每一版附上：兩個 DMG、`…-<tag>-battery-macOS-arm64.zip`、`…-<tag>-status-macOS-arm64.zip`（給 v1.5.0～v1.6.2 與 v1.7.1 通用版的一鍵更新；內容和通用版相同，只有 `MBMEdition` 不同）、`SHA256SUMS.txt`。過渡版 v1.7.2 另附通用版與 macOS 12 版的 zip（給 v1.7.1）
- 檔名固定不帶版本號，`releases/latest/download/<檔名>` 永遠是最新版。不要改 DMG 檔名，也不要改 tag 格式（`vX.Y.Z`）：舊版的一鍵更新靠它們找檔案

## DMG（`Scripts/make-dmg.sh`）

- 只用系統內建的工具：`hdiutil` 建立與壓縮映像檔，Finder 的 AppleScript 排好拖曳安裝的視窗（Finder 不能用時照樣產生，只是用預設排列）
- 掛載與卸載先用 `diskutil image attach`／`diskutil eject`（macOS 27 起 hdiutil 的這些用法標為不建議使用）。macOS 13 只認單槓的選項、更舊的系統可能沒有這個指令，都會回報錯誤，這時改用 `hdiutil`
- 背景圖由 `Scripts/make-dmg-background.swift` 產生，寫著第一次打開被擋時怎麼「強制打開」
- 磁碟圖示是 App 圖示，只留 16～128 像素（約 32 KB）。要等 Finder 排好視窗後才放進去，否則排版時 Finder 會把它刪掉
- 打包完再掛載一次，檢查裡面 App 的簽章

## 一鍵更新（`Services/Updater.swift`）

1. **檢查**：讀 GitHub API 最近 20 個 Release。自動檢查在啟動後與之後每 6 小時看一次，距離上次檢查超過一天才連線；Beta 只在手動檢查時列出；沒有校驗檔或更新簽章的 Release 直接略過，不提示也不安裝
2. **挑檔案**：通用版依序找 DMG、通用版 zip、舊檔名的 zip。舊系統版本找 `macbookBatteryMonitor-macOS12.dmg`、再找它的 zip；系統已經是 macOS 14 以上時改裝通用版
3. **驗證校驗檔**：下載 `SHA256SUMS.txt` 與 `SHA256SUMS.sig`（一定要是 GitHub 的網址、回應 200、不超過 64 KB），用 App 內建的公鑰驗證簽章；缺任何一個或簽章不對就不安裝
4. **下載**：只從 `github.com` 與 `githubusercontent.com` 下載，用簽過的 `SHA256SUMS.txt` 核對
5. **取出**：DMG 唯讀、不顯示地掛載在暫存資料夾（掛載方式和 `make-dmg.sh` 相同），用 `ditto` 拷出 App；zip 用 `ditto -x -k` 解開
6. **驗證 App**：識別碼是 `com.kuan.batterymonitor`，版本號與 Beta 序號和 Release 的 tag 一致，`codesign --verify --deep --strict` 通過，而且 `codesign --verify -R` 符合 `Model/Update.swift` 的 `codeRequirement`（「macbookBatteryMonitor Signing」憑證簽的）
7. **換上**：App 結束後換上新版並重新開啟；換不過去就放回原本的版本。下載或驗證失敗、更新中途被中斷時，暫存檔會清掉

`--selftest-dmg <DMG>` 用同一段流程從本機的 DMG 取出 App 並驗證，不安裝；`--selftest-update` 用版本號改低的副本測試真正的下載與更新。

## 更新簽章（v1.7.5 起）

### 為什麼

憑證的私鑰在 GitHub Secrets 裡，Release 也是 GitHub Actions 打包的。只靠校驗檔與憑證的話，GitHub 帳號被盜的人可以上傳自己的 DMG 與校驗檔，甚至用 Actions 做出憑證簽的版本。所以另外加一把只在發布者 Mac 上的 Ed25519 金鑰：一鍵更新只接受這把金鑰簽過的 `SHA256SUMS.txt`。

### 格式

- `SHA256SUMS.sig`：一行 base64，是 64 bytes 的 Ed25519 原始簽章，簽的是 `SHA256SUMS.txt` 的原始位元組
- 公鑰：32 bytes 原始公鑰的 base64，寫在 `Model/Update.swift` 的 `updatePublicKeys`（陣列）。App 用 CryptoKit 的 `Curve25519.Signing.PublicKey` 驗證，macOS 12 起都有
- 用 openssl 驗證：`base64 -d SHA256SUMS.sig > sig.bin`，`openssl pkeyutl -verify -pubin -inkey pub.pem -rawin -in SHA256SUMS.txt -sigfile sig.bin`

### 金鑰

- `Scripts/make-update-key.sh` 建立一次：私鑰存在登入鑰匙圈（generic password，服務名稱「macbookBatteryMonitor update signing」），不寫進專案、GitHub、CI 或記錄
- 同一個腳本建立加密的備份映像檔（AES-256，密碼只有發布者知道），私鑰直接寫進加密的磁碟裡；備份放 iCloud Drive 與私人的備份 repo
- `Scripts/update-signing.swift` 是金鑰工具（產生、印出公鑰、簽署、驗證、匯出、匯入），編譯後用「macbookBatteryMonitor Signing」憑證簽，鑰匙圈才認得同一個工具，重新編譯不會一直詢問

### 發布時

`Scripts/sign-release.sh v<版本>`：
1. 確認鑰匙圈的金鑰是 App 信任的公鑰
2. 下載草稿的所有附檔，核對 `SHA256SUMS.txt`，每個附檔都要列在裡面
3. 打開每個 DMG 與 zip，用 `Scripts/check-signature.sh` 確認 App 是「macbookBatteryMonitor Signing」簽的，版本號與 Beta 序號和 tag 一致
4. 簽 `SHA256SUMS.txt`，用公鑰驗證一次，上傳 `SHA256SUMS.sig`
5. 草稿改成正式發布，正式版標成最新版本

### 過渡與限制

- v1.7.4 以前的一鍵更新不認得 `SHA256SUMS.sig`，照舊只核對校驗檔與簽章是否完好。v1.7.5 是第一個會驗證的版本，之後的每次更新都要有簽章
- **換金鑰**：先發一版 `updatePublicKeys` 同時有新舊兩把公鑰、用舊金鑰簽的版本，之後才改用新金鑰
- **金鑰與備份都遺失**：已經裝了 v1.7.5 以後版本的使用者無法再一鍵更新，只能手動下載一次帶新公鑰的版本
- 鎖定的憑證（`codeRequirement`）要換時也一樣：先發一版同時接受新舊兩個條件的 App

## 簽章

### 為什麼要固定的簽章

macOS 的「輔助使用」、藍牙等權限是用 App 的簽章身分（designated requirement）記住的。ad-hoc 簽章的身分就是程式碼的雜湊值，每次編譯都不同，所以 v1.7.3 以前每次更新，macOS 都把新版當成另一個 App：藍牙會再問一次，「輔助使用」的開關看起來還開著，卻對新版沒有作用。

v1.7.4 起每個版本都用同一張自簽的程式碼簽署憑證「macbookBatteryMonitor Signing」簽，簽章身分固定為：

```
identifier "com.kuan.batterymonitor" and certificate leaf = H"8a0f04d547969a353a94b2697263f1326370aec0"
```

新版本符合同一個身分，權限在一鍵更新與重新安裝後都會保留。這不是 Apple 的開發者簽章，也沒有公證：Gatekeeper 照樣擋下第一次打開的 App，使用者要到「系統設定 → 隱私權與安全性」按「強制打開」。

### 怎麼簽

- `Scripts/make-signing-cert.sh` 建立一次憑證：用系統內建的 LibreSSL 產生 RSA 2048、20 年有效、只能用於程式碼簽署的憑證，匯入登入鑰匙圈（私鑰只開放給 `codesign`），設定「信任用於程式碼簽署」。含私鑰的 `signing.p12`、隨機密碼與 base64 檔備份在專案外的資料夾（預設 `~/Documents/macbookBatteryMonitor-簽章`），絕對不能放進 Git
- `build.sh` 在鑰匙圈裡找得到被信任的這張憑證時用它簽（App 與管理員服務程式都是），找不到就用 ad-hoc，最後一行印出用了哪一種。`codesign` 只用被信任的憑證；憑證存在但沒被信任時，`security find-identity -v` 找不到它，`build.sh` 會改用 ad-hoc
- GitHub Actions 用 `Scripts/import-signing-cert.sh` 從 Secrets（`MBM_SIGNING_P12`、`MBM_SIGNING_PASSWORD`）把憑證匯入一個暫時的鑰匙圈，並在這台打包機器上信任它。沒有設定 Secrets 時（例如別人的 fork 開的 PR）什麼都不做，改用 ad-hoc

### 在使用者的 Mac 上

- 使用者的 Mac 不需要信任這張憑證。實測用一張沒被信任的自簽憑證簽的 App，`codesign --verify --deep --strict` 照樣通過、App 照常執行，所以 v1.5.0～v1.7.3 的一鍵更新（只做這一項簽章檢查）都能裝上新版；`spctl` 會拒絕，這和 ad-hoc 一樣
- 從 v1.7.3 以前更新上來時，簽章身分換了，權限要最後再允許一次；之後就不用
- 換了 App 圖示顏色時，App 最上層多一個自訂圖示檔，`--strict` 的檢查會回報有多餘的檔案；不加 `--strict` 的檢查與權限都不受影響

### 不能做的事

- **不要換憑證，也不要重新產生**：新憑證的簽章身分不同，所有使用者更新後都要再允許一次權限
- 備份遺失或憑證過期時只能換新的，發行說明要寫清楚，使用者要再允許一次
- 不要把 `signing.p12`、密碼或 base64 檔放進專案資料夾
