#!/usr/bin/env bash
# Run on macOS to capture App Store screenshots from a clean simulator state.
#
# Usage:
#   bash scripts/screenshots.sh
#
# Output: screenshots/iPhone-6.9/01-onboarding.png ... etc.

set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="iPhone 16 Pro Max"   # 6.9" — Apple's current required class
OS="iOS"
OUT_DIR="screenshots/iPhone-6.9"

mkdir -p "$OUT_DIR"

echo "==> Generating Xcode project"
xcodegen generate >/dev/null

echo "==> Booting simulator: $DEVICE"
DEVICE_ID=$(xcrun simctl list devices available | grep "$DEVICE " | head -1 | grep -oE '[A-F0-9-]{36}' || true)
if [ -z "$DEVICE_ID" ]; then
  echo "Could not find $DEVICE in available simulators"
  echo "Available iPhones:"
  xcrun simctl list devices available | grep -i iphone
  exit 1
fi
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
open -a Simulator

echo "==> Building for simulator (Debug)"
xcodebuild -project RedFluentVPN.xcodeproj \
  -scheme RedFluentVPN \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -configuration Debug \
  -derivedDataPath build/sim \
  build | tail -5

APP_PATH=$(find build/sim/Build/Products/Debug-iphonesimulator -name "RedFluentVPN.app" -maxdepth 4 | head -1)
echo "   APP at $APP_PATH"

echo "==> Installing on simulator"
xcrun simctl uninstall "$DEVICE_ID" com.redfluent.vpn 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

# Reset onboarding so the first screenshot captures it
xcrun simctl spawn "$DEVICE_ID" defaults delete \
  $(xcrun simctl spawn "$DEVICE_ID" defaults find rfv 2>/dev/null | head -1 | awk '{print $4}') \
  rfv.onboardingDone 2>/dev/null || true

echo "==> Launching"
xcrun simctl launch "$DEVICE_ID" com.redfluent.vpn

snap () {
  local name="$1"
  local file="$OUT_DIR/${name}.png"
  echo "   shooting $name -> $file"
  sleep 2
  xcrun simctl io "$DEVICE_ID" screenshot "$file"
}

# Caller is expected to manually advance the UI between snaps so we just
# pause and let them tap. For full automation we'd need UITest harness;
# this is a deliberate trade-off for v1.
echo
echo "MANUAL STEPS in the simulator:"
echo "  1. Wait for onboarding screen 1 to fully render."
read -r -p "   Press ENTER when ready to capture onboarding-1..." _
snap "01-onboarding-1"

echo "  2. Swipe to onboarding screen 2."
read -r -p "   Press ENTER..." _
snap "02-onboarding-2"

echo "  3. Swipe to onboarding screen 3, do NOT tap Get Started yet."
read -r -p "   Press ENTER..." _
snap "03-onboarding-3"

echo "  4. Tap Get Started so the activation screen shows. DO NOT type anything."
read -r -p "   Press ENTER when activation screen is fully visible..." _
snap "04-activation"

echo "  5. Activate with RF-OWNER-2026 (backend must be reachable)."
echo "     Then wait for the dashboard to appear in disconnected state."
read -r -p "   Press ENTER when the dashboard is fully visible..." _
snap "05-dashboard-disconnected"

echo "  6. Tap Connect, allow VPN permission. Once status reads Connected..."
read -r -p "   Press ENTER..." _
snap "06-dashboard-connected"

echo
echo "Done. Screenshots in $OUT_DIR. Upload to App Store Connect:"
echo "  https://appstoreconnect.apple.com/apps/6767809544/distribution/ios/version/deliverable"
