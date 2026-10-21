#!/bin/bash
# 簽署 Release 並正式發布。GitHub Actions 只建立草稿（使用者與一鍵更新都看不到），在發布者的 Mac 上執行：
#   Scripts/sign-release.sh v1.7.5
# 會做的事：
#   1. 下載草稿的所有附檔，核對 SHA256SUMS.txt，每個附檔都要列在裡面
#   2. 打開每個 DMG 與 zip，確認裡面的 App 版本號與 tag 一致，而且是「macbookBatteryMonitor Signing」憑證簽的
#   3. 用登入鑰匙圈裡的更新簽章私鑰簽 SHA256SUMS.txt（第一次 macOS 可能請你允許存取鑰匙圈），再用 App 內建的公鑰驗證一次
#   4. 上傳 SHA256SUMS.sig，把草稿改成正式發布（正式版標成最新版本）
# 已經發布過的 Release 也可以再執行一次（例如補簽章），會覆蓋原本的 SHA256SUMS.sig
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
tag="${1:?用法：Scripts/sign-release.sh <tag>，例如 v1.7.5}"
repo="sgeric910601/macbookBatteryMonitor"
tool="$root/build/update-signing"

fail() { echo "❌ $*" >&2; exit 1; }

# 簽章工具：有「macbookBatteryMonitor Signing」憑證就用它簽，鑰匙圈才不會每次重新編譯都詢問
if [[ ! -x "$tool" || Scripts/update-signing.swift -nt "$tool" ]]; then
    mkdir -p build
    swiftc -O Scripts/update-signing.swift -o "$tool"
    if security find-identity -v -p codesigning | grep -q '"macbookBatteryMonitor Signing"'; then
        codesign --force --sign "macbookBatteryMonitor Signing" --identifier com.kuan.batterymonitor.update-signing --timestamp=none "$tool"
    fi
fi
public="$("$tool" public-key)"
grep -q "\"${public}\"" Sources/macbookBatteryMonitor/Model/Update.swift \
    || fail "鑰匙圈裡的金鑰不是 App 信任的公鑰（Update.swift 的 updatePublicKeys），用它簽的更新 App 不會接受"

draft="$(gh release view "$tag" --repo "$repo" --json isDraft --jq .isDraft)" || fail "找不到 ${tag} 的 Release"
prerelease="$(gh release view "$tag" --repo "$repo" --json isPrerelease --jq .isPrerelease)"

work="$(mktemp -d)"
mounts=()
cleanup() {
    for m in "${mounts[@]+"${mounts[@]}"}"; do
        diskutil eject force "$m" >/dev/null 2>&1 || hdiutil detach "$m" -force >/dev/null 2>&1 || true
    done
    rm -rf "$work"
}
trap cleanup EXIT

echo "下載 ${tag} 的附檔…"
gh release download "$tag" --repo "$repo" --dir "$work/assets"
cd "$work/assets"
[[ -f SHA256SUMS.txt ]] || fail "這個 Release 沒有 SHA256SUMS.txt"
shasum -a 256 -c SHA256SUMS.txt >/dev/null || fail "附檔和 SHA256SUMS.txt 對不上"
for file in *; do
    [[ "$file" == SHA256SUMS.txt || "$file" == SHA256SUMS.sig ]] && continue
    grep -q "  ${file}\$" SHA256SUMS.txt || fail "${file} 沒有列在 SHA256SUMS.txt 裡"
done

# tag 是 v1.7.5 或 v1.7.5-beta.1
version="${tag#v}"
short="${version%%-*}"
beta=""
[[ "$version" == *-* ]] && beta="${version#*-}"
check_app() {
    local app="$1" name="$2"
    "$root/Scripts/check-signature.sh" "$app" || fail "${name} 裡的 App 簽章不對"
    [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")" == "$short" ]] \
        || fail "${name} 裡的 App 版本號不是 ${short}"
    local app_beta
    app_beta="$(plutil -extract MBMPrerelease raw -o - "$app/Contents/Info.plist" 2>/dev/null)" || app_beta=""
    [[ "$app_beta" == "$beta" ]] || fail "${name} 裡的 App Beta 序號是「${app_beta}」，tag 是「${beta}」"
    echo "  ✅ ${name}"
}
echo "檢查每個下載檔裡的 App…"
for dmg in *.dmg; do
    [[ -e "$dmg" ]] || continue
    mount="$work/mount-${dmg%.dmg}"
    mkdir -p "$mount"
    diskutil image attach --readOnly --nobrowse --mountPoint "$mount" "$dmg" >/dev/null 2>&1 \
        || hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mount" "$dmg" >/dev/null \
        || fail "打不開 ${dmg}"
    mounts+=("$mount")
    check_app "$mount/macbookBatteryMonitor.app" "$dmg"
done
for zip in *.zip; do
    [[ -e "$zip" ]] || continue
    folder="$work/unzip-${zip%.zip}"
    ditto -x -k "$zip" "$folder"
    check_app "$folder/macbookBatteryMonitor.app" "$zip"
done

echo "簽署 SHA256SUMS.txt…"
"$tool" sign SHA256SUMS.txt > SHA256SUMS.sig
"$tool" verify SHA256SUMS.txt SHA256SUMS.sig "$public" >/dev/null || fail "簽好的簽章驗證不通過"
gh release upload "$tag" SHA256SUMS.sig --repo "$repo" --clobber

if [[ "$draft" == true ]]; then
    if [[ "$prerelease" == true ]]; then
        gh release edit "$tag" --repo "$repo" --draft=false >/dev/null
    else
        gh release edit "$tag" --repo "$repo" --draft=false --latest >/dev/null
    fi
    echo "✅ 已簽署並發布 ${tag}"
else
    echo "✅ 已簽署 ${tag}（原本就已發布）"
fi
