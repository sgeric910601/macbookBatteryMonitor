#!/bin/bash
# 把 App 包成拖曳安裝的 DMG：左邊 App、右邊「應用程式」捷徑，背景說明第一次打開被擋下時怎麼辦
#   Scripts/make-dmg.sh <App> <輸出的 .dmg>
# 排列圖示與背景要用 Finder（AppleScript）；Finder 不能用時（例如沒有允許終端機控制 Finder）
# 照樣產生 DMG，只是用 Finder 預設的排列。不需要安裝其他工具
set -euo pipefail

app="$1"
out="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
volume="電池與系統監控"
[[ -d "$app" ]] || { echo "找不到 $app" >&2; exit 1; }
[[ ! -d "/Volumes/$volume" ]] || { echo "已經有同名的磁碟 /Volumes/${volume}，請先退出" >&2; exit 1; }

work="$(mktemp -d)"
mounted=""     # 目前掛著的位置，結束或出錯時要卸載
mounted_by=""  # 掛載用的工具（diskutil 或 hdiutil），卸載時用同一套
cleanup() {
    [[ -n "$mounted" ]] && detach force >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

# 掛載、卸載先用 diskutil image attach／diskutil eject（macOS 27 起 hdiutil 的這些用法標為不建議使用，以後可能拿掉）；
# 舊系統（可能包括 GitHub Actions 的 macos-15）沒有這個指令，diskutil 回報不認得、結束碼非 0，改用原本的 hdiutil

# 從 diskutil 的 plist 輸出取出第一個 <key>$1</key> 的字串
plist_string() { sed -n "/<key>$1<\/key>/{n;s:.*<string>\(.*\)</string>.*:\1:p;q;}"; }

# 可寫入掛載在 /Volumes/磁碟名稱，Finder 才排得到圖示
attach_rw() {
    local plist dev
    if plist="$(diskutil image attach --plist "$1" 2>/dev/null)"; then
        mounted="$(plist_string mount-point <<<"$plist")"
        mounted_by=diskutil
        [[ "$mounted" != "/Volumes/$volume" ]] || return 0
        # 掛上了但讀不到位置或位置不對：退出整個映像檔，交給 hdiutil 再試一次
        dev="$(plist_string dev-entry <<<"$plist")"
        [[ -z "$dev" ]] || diskutil eject force "/dev/$dev" >/dev/null 2>&1 || true
    fi
    mounted_by=hdiutil
    mounted="$(hdiutil attach "$1" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*$' | head -n 1)"
}

# 唯讀掛載在指定的資料夾，不出現在 Finder 與桌面
attach_ro() {
    if diskutil image attach --readOnly --nobrowse --mountPoint "$2" "$1" >/dev/null 2>&1; then
        mounted_by=diskutil
    else
        mkdir -p "$2"
        hdiutil attach "$1" -readonly -nobrowse -noautoopen -mountpoint "$2" >/dev/null
        mounted_by=hdiutil
    fi
    mounted="$2"
}

# 卸載目前掛著的映像檔；參數是 force 時強制卸載
detach() {
    local force="${1:-}"
    case "$mounted_by" in
        diskutil) diskutil eject $force "$mounted" >/dev/null ;;
        hdiutil) hdiutil detach "$mounted" -quiet ${force:+-force} ;;
    esac
}

stage="$work/stage"
mkdir -p "$stage/.background"
ditto "$app" "$stage/macbookBatteryMonitor.app"
ln -s /Applications "$stage/應用程式"
cp "$root/Resources/DMG/background.tiff" "$stage/.background/background.tiff"

# 先做可寫入的映像檔，掛載後讓 Finder 排好圖示，再壓縮成唯讀的 DMG
size_mb=$(( $(du -sm "$stage" | cut -f1) + 20 ))
hdiutil create -quiet -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW -size "${size_mb}m" "$work/rw.dmg"
attach_rw "$work/rw.dmg"
[[ "$mounted" == "/Volumes/$volume" ]] || { echo "掛載位置不對：$mounted" >&2; exit 1; }

if osascript - "$volume" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            -- 視窗內容 540×380，加上標題列
            set bounds of container window to {200, 120, 740, 528}
            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 100
            set text size of viewOptions to 13
            set background picture of viewOptions to file ".background:background.tiff"
            set position of item "macbookBatteryMonitor.app" of container window to {140, 150}
            set position of item "應用程式" of container window to {400, 150}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT
then
    echo "已排好 DMG 視窗"
else
    echo "⚠️ Finder 無法排列圖示，改用預設排列" >&2
fi

rm -rf "$mounted/.fseventsd"
chmod -Rf go-w "$mounted" 2>/dev/null || true
sync
detach || detach force
mounted=""
rm -f "$out"
hdiutil convert "$work/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$out"

# 檢查：唯讀掛載後 App 還在、簽章完整
check="$work/check"
mkdir -p "$check"
attach_ro "$out" "$check"
codesign --verify --deep --strict "$check/macbookBatteryMonitor.app"
detach
mounted=""
echo "✅ 已產生 ${out}（$(du -h "$out" | cut -f1)）"
