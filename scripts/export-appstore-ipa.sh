#!/usr/bin/env bash
# Export an already prepared xcarchive through a temporary empty user keychain.
# This avoids stale local identities hijacking Xcode's managed cloud signing path.

set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_API_KEY:?must set ASC_API_KEY}"
: "${ASC_API_ISSUER:?must set ASC_API_ISSUER}"

ASC_AUTH_KEY_PATH="${ASC_AUTH_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY}.p8}"
ARCHIVE_PATH="${1:?usage: export-appstore-ipa.sh <archive-path> <export-path>}"
EXPORT_PATH="${2:?usage: export-appstore-ipa.sh <archive-path> <export-path>}"

if [ ! -f "$ASC_AUTH_KEY_PATH" ]; then
  echo "App Store Connect key not found: $ASC_AUTH_KEY_PATH" >&2
  exit 2
fi

TMP_KEYCHAIN="$HOME/Library/Keychains/rfv-temp-build.keychain-db"
ORIG_DEFAULT="$(security default-keychain -d user 2>/dev/null || true)"
ORIG_DEFAULT="$(printf '%s' "$ORIG_DEFAULT" | tr -d '"')"
if [ -z "$ORIG_DEFAULT" ]; then
  ORIG_DEFAULT="$HOME/Library/Keychains/login.keychain-db"
fi

ORIG_KEYCHAINS=()
while IFS= read -r line; do
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | tr -d '"')"
  if [ -n "$line" ]; then
    ORIG_KEYCHAINS+=("$line")
  fi
done < <(security list-keychains -d user)

cleanup() {
  if [ "${#ORIG_KEYCHAINS[@]}" -gt 0 ]; then
    security list-keychains -d user -s "${ORIG_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  fi
  security default-keychain -d user -s "$ORIG_DEFAULT" >/dev/null 2>&1 || true
  security delete-keychain "$TMP_KEYCHAIN" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -f "$TMP_KEYCHAIN"
security create-keychain -p '' "$TMP_KEYCHAIN"
security unlock-keychain -p '' "$TMP_KEYCHAIN"
security set-keychain-settings "$TMP_KEYCHAIN"
security list-keychains -d user -s "$TMP_KEYCHAIN" /Library/Keychains/System.keychain
security default-keychain -d user -s "$TMP_KEYCHAIN"

mkdir -p build
cat > build/exportOptions-auto.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>FWFT4Z5ASR</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
EOF

rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist build/exportOptions-auto.plist \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_AUTH_KEY_PATH" \
  -authenticationKeyID "$ASC_API_KEY" \
  -authenticationKeyIssuerID "$ASC_API_ISSUER"
