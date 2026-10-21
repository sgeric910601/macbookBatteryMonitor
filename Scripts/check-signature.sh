#!/bin/bash
# 確認 App 的簽章完好，而且是「macbookBatteryMonitor Signing」憑證簽的。
# 一鍵更新也用同一個條件決定能不能安裝（Sources/macbookBatteryMonitor/Model/Update.swift 的 codeRequirement，兩邊要一致）
#   Scripts/check-signature.sh <App>
set -euo pipefail
requirement='identifier "com.kuan.batterymonitor" and certificate leaf = H"8a0f04d547969a353a94b2697263f1326370aec0"'
app="${1:?用法：Scripts/check-signature.sh <App>}"
codesign --verify --deep --strict "$app"
if ! codesign --verify -R "=${requirement}" "$app" 2>/dev/null; then
    echo "${app} 不是用「macbookBatteryMonitor Signing」憑證簽的，一鍵更新不會安裝它" >&2
    exit 1
fi
