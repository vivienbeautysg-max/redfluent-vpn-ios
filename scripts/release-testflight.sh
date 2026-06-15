#!/usr/bin/env bash
# Build, re-sign, validate, and upload a fresh TestFlight build of RedFluent VPN.
#
# Verified working on the current Cloud Mac on 2026-05-19.
# Why this uses a two-step signing flow:
#   1. The machine's old local Apple Distribution identity can poison Xcode export,
#      causing errSecInternalComponent.
#   2. A fully unsigned archive drops Network Extension entitlements during export.
#   3. The stable path is:
#      - create an unsigned archive via automatic signing + ASC API key
#      - ad hoc sign app/appex/framework in the archive so entitlements are preserved
#      - export through a temporary empty keychain so Xcode uses managed cloud signing
#
# Required env vars:
#   ASC_API_KEY
#   ASC_API_ISSUER
#
# Optional env vars:
#   ASC_AUTH_KEY_PATH   defaults to ~/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY}.p8
#   BUMP=patch|minor|none   default: patch

set -euo pipefail

cd "$(dirname "$0")/.."

: "${ASC_API_KEY:?must set ASC_API_KEY}"
: "${ASC_API_ISSUER:?must set ASC_API_ISSUER}"

ASC_AUTH_KEY_PATH="${ASC_AUTH_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY}.p8}"
BUMP="${BUMP:-patch}"

if [ ! -f "$ASC_AUTH_KEY_PATH" ]; then
  echo "App Store Connect key not found: $ASC_AUTH_KEY_PATH" >&2
  exit 2
fi

APP_PLIST="Supporting/RedFluentVPN-Info.plist"
TUN_PLIST="Supporting/RedFluentVPNTunnel-Info.plist"
UNSIGNED_ARCHIVE="build/RedFluentVPN-unsigned.xcarchive"
PATCHED_ARCHIVE="build/RedFluentVPN-distribution.xcarchive"
EXPORT_DIR="build/export"
APP_PATH="$PATCHED_ARCHIVE/Products/Applications/RedFluentVPN.app"
TUNNEL_PATH="$APP_PATH/PlugIns/RedFluentVPNTunnel.appex"
LIBBOX_PATH="$APP_PATH/Frameworks/Libbox.framework"

current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
case "$BUMP" in
  none)  next="$current" ;;
  patch) next=$((current + 1)) ;;
  minor) next=$((current + 10)) ;;
  *)     echo "unknown BUMP=$BUMP" >&2; exit 2 ;;
esac

echo "==> Bumping build number"
echo "   $current -> $next"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$APP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$TUN_PLIST"

echo "==> Regenerating Xcode project"
xcodegen generate >/dev/null

echo "==> Cleaning build dir"
rm -rf build "$HOME/Library/Developer/Xcode/DerivedData/RedFluentVPN-"*
mkdir -p build

echo "==> Archiving unsigned payload via automatic signing"
if ! xcodebuild -project RedFluentVPN.xcodeproj \
  -scheme RedFluentVPN \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath "$UNSIGNED_ARCHIVE" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=FWFT4Z5ASR \
  PROVISIONING_PROFILE_SPECIFIER='' \
  CODE_SIGN_IDENTITY='' \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_AUTH_KEY_PATH" \
  -authenticationKeyID "$ASC_API_KEY" \
  -authenticationKeyIssuerID "$ASC_API_ISSUER" \
  archive > build/archive.log 2>&1; then
  tail -80 build/archive.log >&2
  exit 1
fi
tail -20 build/archive.log

echo "==> Rehydrating entitlements with ad hoc signatures"
rm -rf "$PATCHED_ARCHIVE"
cp -R "$UNSIGNED_ARCHIVE" "$PATCHED_ARCHIVE"
codesign -f -s - "$LIBBOX_PATH"
codesign -f -s - --entitlements Entitlements/RedFluentVPNTunnel.entitlements "$TUNNEL_PATH"
codesign -f -s - --entitlements Entitlements/RedFluentVPN.entitlements "$APP_PATH"

echo "==> Exporting IPA through temporary clean keychain"
bash scripts/export-appstore-ipa.sh "$PATCHED_ARCHIVE" "$EXPORT_DIR"

echo "==> Validating IPA with Apple"
xcrun altool --validate-app "$EXPORT_DIR/RedFluentVPN.ipa" \
  --apiKey "$ASC_API_KEY" \
  --apiIssuer "$ASC_API_ISSUER"

echo "==> Uploading IPA to App Store Connect"
upload_output="$(xcrun altool --upload-app \
  -f "$EXPORT_DIR/RedFluentVPN.ipa" \
  -t ios \
  --apiKey "$ASC_API_KEY" \
  --apiIssuer "$ASC_API_ISSUER" 2>&1)"
upload_rc=$?
printf '%s\n' "$upload_output"
if [ "$upload_rc" -ne 0 ]; then
  exit "$upload_rc"
fi

delivery_uuid="$(printf '%s\n' "$upload_output" | sed -n 's/^Delivery UUID: //p' | tail -n 1)"
if [ -n "$delivery_uuid" ]; then
  echo "==> Build status"
  xcrun altool --build-status \
    --delivery-id "$delivery_uuid" \
    --apiKey "$ASC_API_KEY" \
    --apiIssuer "$ASC_API_ISSUER" \
    --output-format json || true
fi

echo
echo "Done."
echo "Build number: $next"
echo "Archive: $PATCHED_ARCHIVE"
echo "IPA: $EXPORT_DIR/RedFluentVPN.ipa"
