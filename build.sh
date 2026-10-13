#!/bin/bash
# 編譯並打包成 macbookBatteryMonitor.app（Apple 晶片與 Intel 通用）
#   ./build.sh                 → 通用版：系統監控是設定裡的開關，第一次啟動時詢問
#   ./build.sh install         → 編好後安裝到 /Applications 並啟動
#   ./build.sh battery|status  → 給 v1.6.1 以前的一鍵更新用的舊版別（內容相同，只有 MBMEdition 不同，
#                                從舊版升級時用來決定系統監控預設開或關）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="macbookBatteryMonitor"
APP="build/$APP_NAME.app"
# 舊系統版本分支（macOS 12 起）預設打包 legacy
EDITION="legacy"
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        legacy|universal|battery|status) EDITION="$arg" ;;
        install) INSTALL=1 ;;
        *) echo "用法：./build.sh [universal|battery|status] [install]" >&2; exit 1 ;;
    esac
done

# 通用版：同一個 App 同時支援 Apple 晶片與 Intel。
# 只裝 Command Line Tools 的舊版工具可能無法一次編兩種架構，這時改編這台電腦的架構
ARCH_FLAGS="--arch arm64 --arch x86_64"
if ! swift build -c release $ARCH_FLAGS; then
    echo "⚠️ 無法編成通用版，改編這台電腦的架構（$(uname -m)）" >&2
    ARCH_FLAGS=""
    swift build -c release
fi
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/Helpers"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$(dirname "$BIN")/CPUPowerHelper" "$APP/Contents/Library/Helpers/CPUPowerHelper"
codesign --force --sign - --timestamp=none "$APP/Contents/Library/Helpers/CPUPowerHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace MBMEdition -string "$EDITION" "$APP/Contents/Info.plist"
# App 名稱（Finder、啟動台、Spotlight、通知、登入項目顯示的名稱）。
# 資料夾名稱維持 macbookBatteryMonitor.app：舊版的一鍵更新會在 zip 裡找這個名稱
NAMES=("zh-Hant:電池與系統監控" "zh_TW:電池與系統監控" "zh-Hans:电池与系统监控" "en:Battery & System Monitor")
for entry in "${NAMES[@]}"; do
    lang="${entry%%:*}"
    name="${entry#*:}"
    mkdir -p "$APP/Contents/Resources/${lang}.lproj"
    printf '"CFBundleDisplayName" = "%s";\n"CFBundleName" = "%s";\n' "$name" "$name" > "$APP/Contents/Resources/${lang}.lproj/InfoPlist.strings"
done
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# 設定裡可切換的其他 App 圖示顏色
cp Resources/AppIcons/icon-*.png "$APP/Contents/Resources/" 2>/dev/null || true
codesign --force --sign - --timestamp=none "$APP"
echo "✅ 已產生 ${APP}（MBMEdition=${EDITION}，$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")）"

if [[ $INSTALL == 1 ]]; then
    pkill -x "$APP_NAME" || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$APP_NAME.app"
    echo "✅ 已安裝到 /Applications/$APP_NAME.app"
fi
