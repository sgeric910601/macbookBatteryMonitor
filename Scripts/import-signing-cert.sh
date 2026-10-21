#!/bin/bash
# GitHub Actions 用：把 Secrets 裡的簽章憑證（Scripts/make-signing-cert.sh 建立的 signing.p12）匯入一個暫時的鑰匙圈並信任，
# build.sh 就會用它簽。每個版本的簽章身分相同，使用者一鍵更新後「輔助使用」與藍牙權限都會保留。
# 沒有設定 MBM_SIGNING_P12 時什麼都不做（例如別人的 fork 開的 PR），build.sh 改用 ad-hoc 簽章；發布時則停下來
set -euo pipefail

if [[ -z "${MBM_SIGNING_P12:-}" ]]; then
    # 發布時（MBM_SIGNING_REQUIRED=1）一定要有憑證：ad-hoc 簽章的版本使用者更新後權限會失效，一鍵更新也不會安裝
    if [[ "${MBM_SIGNING_REQUIRED:-}" == 1 ]]; then
        echo "發布需要簽章憑證，但沒有設定 MBM_SIGNING_P12（見 Scripts/make-signing-cert.sh），停止發布" >&2
        exit 1
    fi
    echo "沒有設定簽章憑證（MBM_SIGNING_P12），用 ad-hoc 簽章"
    exit 0
fi
work="${RUNNER_TEMP:-$(mktemp -d)}"
keychain="$work/signing.keychain-db"
# 暫時鑰匙圈的密碼：只在這台打包機器上用一次
password="$(/usr/bin/openssl rand -base64 24)"
printf '%s' "$MBM_SIGNING_P12" | /usr/bin/base64 --decode > "$work/signing.p12"
trap 'rm -f "$work/signing.p12" "$work/signing-cert.pem"' EXIT

security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work/signing.p12" -k "$keychain" -P "$MBM_SIGNING_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
# 加進搜尋清單，codesign 才找得到
security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
# codesign 只用被信任的憑證簽：在這台暫時的打包機器上信任這張自簽憑證用於程式碼簽署
# （用系統內建的 LibreSSL：make-signing-cert.sh 也是用它做的 .p12）
/usr/bin/openssl pkcs12 -in "$work/signing.p12" -nokeys -passin env:MBM_SIGNING_PASSWORD -out "$work/signing-cert.pem"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$work/signing-cert.pem"
security find-identity -v -p codesigning "$keychain"
