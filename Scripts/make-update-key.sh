#!/bin/bash
# 建立一鍵更新的簽章金鑰（Ed25519，只需要執行一次），並做一份加密備份。
# App 只接受用這把金鑰簽過的 SHA256SUMS.txt（Release 附的 SHA256SUMS.sig），所以就算有人能上傳檔案到 GitHub，
# 沒有這把私鑰也做不出能一鍵更新的版本。私鑰只存在這台 Mac 的登入鑰匙圈，不進專案、GitHub 或記錄。
#   Scripts/make-update-key.sh
# 會做的事：
#   1. 編譯 Scripts/update-signing.swift（有「macbookBatteryMonitor Signing」憑證就用它簽，鑰匙圈才不會每次重新編譯都詢問）
#   2. 產生金鑰存進登入鑰匙圈，印出公鑰（要寫進 Sources/macbookBatteryMonitor/Model/Update.swift 的 updatePublicKeys）
#   3. 建立加密的備份映像檔 ~/Documents/macbookBatteryMonitor-更新金鑰備份.dmg：macOS 會請你設定密碼，
#      私鑰直接寫進加密的磁碟裡，不會以明文留在硬碟上；再複製一份到 iCloud Drive 的「macbookBatteryMonitor-簽章備份」
# 私鑰與備份都遺失的話，已經裝了驗證簽章版本的使用者就無法再一鍵更新，只能手動下載一次
set -euo pipefail
cd "$(dirname "$0")/.."

tool="build/update-signing"
backup="$HOME/Documents/macbookBatteryMonitor-更新金鑰備份.dmg"
icloud="$HOME/Library/Mobile Documents/com~apple~CloudDocs/macbookBatteryMonitor-簽章備份"
volume="mbm-update-key-backup"

if [[ -e "$backup" ]]; then
    echo "已經有 ${backup}，先移走再執行" >&2
    exit 1
fi
mkdir -p build
swiftc -O Scripts/update-signing.swift -o "$tool"
if security find-identity -v -p codesigning | grep -q '"macbookBatteryMonitor Signing"'; then
    codesign --force --sign "macbookBatteryMonitor Signing" --identifier com.kuan.batterymonitor.update-signing --timestamp=none "$tool"
fi

public="$("$tool" generate)"
echo "✅ 已建立更新簽章金鑰，存在登入鑰匙圈（「${volume}」以外不會有私鑰的檔案）"
echo "公鑰：${public}"

echo
echo "接下來建立加密備份：輸入兩次備份密碼（畫面不會顯示），請另外記在「密碼」App。"
hdiutil create -size 4m -fs HFS+ -encryption AES-256 -volname "$volume" -attach "$backup"
mount_point="/Volumes/${volume}"
if [[ ! -d "$mount_point" ]]; then
    echo "備份映像檔沒有掛載，請連點兩下 ${backup}、輸入密碼後再執行：${tool} export \"${mount_point}\"" >&2
    exit 1
fi
"$tool" export "$mount_point" >/dev/null
hdiutil detach "$mount_point" >/dev/null
echo "是否加密：$(hdiutil isencrypted "$backup" | tail -1)"
mkdir -p "$icloud"
cp "$backup" "$icloud/"
echo "✅ 備份：${backup}（另一份在 iCloud Drive 的「macbookBatteryMonitor-簽章備份」）"
echo
echo "還原到另一台 Mac：打開備份映像檔，執行 ${tool} import /Volumes/${volume}/update-signing-key.txt"
