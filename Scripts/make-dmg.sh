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
[[ ! -d "/Volumes/$volume" ]] || { echo "已經有同名的磁碟 /Volumes/$volume，請先退出" >&2; exit 1; }

work="$(mktemp -d)"
mounted=""
cleanup() {
    [[ -n "$mounted" ]] && hdiutil detach "$mounted" -force >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

stage="$work/stage"
mkdir -p "$stage/.background"
ditto "$app" "$stage/macbookBatteryMonitor.app"
ln -s /Applications "$stage/應用程式"
cp "$root/Resources/DMG/background.tiff" "$stage/.background/background.tiff"

# 先做可寫入的映像檔，掛載後讓 Finder 排好圖示，再壓縮成唯讀的 DMG
size_mb=$(( $(du -sm "$stage" | cut -f1) + 20 ))
hdiutil create -quiet -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW -size "${size_mb}m" "$work/rw.dmg"
mounted="$(hdiutil attach "$work/rw.dmg" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*$' | head -n 1)"
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
hdiutil detach "$mounted" -quiet || hdiutil detach "$mounted" -force -quiet
mounted=""
rm -f "$out"
hdiutil convert "$work/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$out"

# 檢查：唯讀掛載後 App 還在、簽章完整
check="$work/check"
mkdir -p "$check"
hdiutil attach "$out" -readonly -nobrowse -noautoopen -mountpoint "$check" >/dev/null
mounted="$check"
codesign --verify --deep --strict "$check/macbookBatteryMonitor.app"
hdiutil detach "$check" -quiet
mounted=""
echo "✅ 已產生 $out（$(du -h "$out" | cut -f1)）"
