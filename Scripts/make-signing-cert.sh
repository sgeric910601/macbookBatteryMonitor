#!/bin/bash
# 建立「電池與系統監控」專用的自簽程式碼簽署憑證（只需要執行一次）。
# 每個版本都用同一張憑證簽，macOS 就會把新版本當成同一個 App：「輔助使用」與藍牙權限在重裝、一鍵更新後都不用重加。
# 這不是 Apple 的開發者簽章與公證：第一次打開 App 時 macOS 一樣會擋，要「強制打開」。
#   Scripts/make-signing-cert.sh [備份資料夾]
# 會做的事：
#   1. 在備份資料夾（預設 ~/Documents/macbookBatteryMonitor-簽章）產生憑證與含私鑰的 signing.p12（隨機密碼另存一個檔）
#   2. 匯入登入鑰匙圈，私鑰只開放給 codesign 使用
#   3. 設定這張憑證「信任用於程式碼簽署」：macOS 會跳出視窗要你輸入密碼（codesign 只用被信任的憑證簽）
# 備份資料夾裡的 signing.p12 與密碼請妥善保存：遺失的話只能換一張新憑證，使用者更新到新憑證簽的版本時要再重加一次權限
set -euo pipefail

name="macbookBatteryMonitor Signing"
dir="${1:-$HOME/Documents/macbookBatteryMonitor-簽章}"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$keychain" | grep -q "\"$name\""; then
    echo "登入鑰匙圈裡已經有「${name}」，不用再建立"
    exit 0
fi
if [[ -e "$dir/signing.p12" ]]; then
    echo "${dir} 裡已經有 signing.p12，請先移走或改用另一個資料夾" >&2
    exit 1
fi
mkdir -p "$dir"
chmod 700 "$dir"
cd "$dir" || exit 1

cat > cert.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# 20 年有效：憑證過期後新版本要換憑證，使用者就得再重加一次權限
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 7300 -config cert.cnf 2>/dev/null
/usr/bin/openssl rand -base64 24 > p12-password.txt
chmod 600 key.pem p12-password.txt
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out signing.p12 -name "$name" -passout file:p12-password.txt
chmod 600 signing.p12
rm -f key.pem cert.cnf

security import signing.p12 -k "$keychain" -P "$(cat p12-password.txt)" -T /usr/bin/codesign
echo "接下來 macOS 會跳出視窗要你輸入密碼，允許信任這張憑證用於程式碼簽署"
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" cert.pem

/usr/bin/base64 -i signing.p12 -o signing.p12.base64
chmod 600 signing.p12.base64
security find-identity -v -p codesigning "$keychain" | grep "\"$name\"" >/dev/null && echo "✅ 已建立並信任「${name}」"

cat <<EOF

備份資料夾：${dir}（signing.p12 與 p12-password.txt 請妥善保存，不要放進 Git）

要讓 GitHub 自動發布的版本也用這張憑證簽，請在終端機執行（只需要一次）：
  gh secret set MBM_SIGNING_P12 < "$dir/signing.p12.base64"
  gh secret set MBM_SIGNING_PASSWORD < "$dir/p12-password.txt"
EOF
