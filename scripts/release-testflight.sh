#!/usr/bin/env bash
# Build, sign, and upload a fresh TestFlight build of RedFluent VPN.
# Run on a Mac that has:
#   - Xcode 26+
#   - The Apple Distribution cert in keychain
#   - Provisioning profiles installed at ~/Library/MobileDevice/Provisioning Profiles/
#   - App Store Connect API key at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#
# Required env vars:
#   ASC_API_KEY      e.g. MLZC98877C
#   ASC_API_ISSUER   e.g. ac346e65-0361-4b5a-849c-e443d78894aa
#
# Optional:
#   BUMP=patch|minor|none   default: patch (increments CFBundleVersion by 1)

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

: "${ASC_API_KEY:?must set ASC_API_KEY}"
: "${ASC_API_ISSUER:?must set ASC_API_ISSUER}"
BUMP="${BUMP:-patch}"

echo "==> Bumping build numbers ($BUMP)"
APP_PLIST="Supporting/RedFluentVPN-Info.plist"
TUN_PLIST="Supporting/RedFluentVPNTunnel-Info.plist"

current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
case "$BUMP" in
  none)  next="$current" ;;
  patch) next=$((current + 1)) ;;
  minor) next=$((current + 10)) ;;
  *)     echo "unknown BUMP=$BUMP"; exit 2 ;;
esac
echo "   $current -> $next"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$APP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$TUN_PLIST"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Cleaning build dir"
rm -rf build ~/Library/Developer/Xcode/DerivedData/RedFluentVPN-*
mkdir -p build

echo "==> Writing exportOptions.plist"
cat > build/exportOptions.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>FWFT4Z5ASR</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.redfluent.vpn</key>
    <string>RedFluent VPN App Store CLI 20260519044354</string>
    <key>com.redfluent.vpn.tunnel</key>
    <string>RedFluent VPN Tunnel App Store CLI 20260519044354</string>
  </dict>
  <key>uploadSymbols</key>
  <true/>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
EOF

echo "==> Archiving"
xcodebuild -project RedFluentVPN.xcodeproj \
  -scheme RedFluentVPN \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath build/RedFluentVPN.xcarchive \
  archive | tail -5

echo "==> Exporting IPA"
xcodebuild -exportArchive \
  -archivePath build/RedFluentVPN.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/exportOptions.plist | tail -5

echo "==> Uploading to App Store Connect"
xcrun altool --upload-app \
  -f build/export/RedFluentVPN.ipa \
  -t ios \
  --apiKey "$ASC_API_KEY" \
  --apiIssuer "$ASC_API_ISSUER"

echo
echo "Done. Check https://appstoreconnect.apple.com/apps/6767809544/testflight/ios"
echo "After 5-15 min the new build will appear. If it shows 'Missing Compliance',"
echo "answer the encryption questionnaire (option 4 = none of the above) until"
echo "the sing-box engine is integrated."
