#!/usr/bin/env bash
# Cloud Mac wrap-up + ship build #2 script for the 2026-05-09 RedFluent VPN session.
#
# What this does:
#   1. Backs up .p8 / .xcarchive / .ipa to ~/Desktop/RedFluent_BACKUP for download
#   2. Pulls the latest iOS code (which now has the real activation UI + invite flow)
#   3. Bumps CFBundleVersion to 2 in both Info.plist files
#   4. Regenerates the Xcode project, archives, exports, uploads as build #2
#
# Run on the rented cloud Mac:
#   bash cloud-mac-wrap-up.sh

set -euo pipefail

REPO=~/Projects/redfluent-vpn-ios
P8=~/.appstoreconnect/private_keys/AuthKey_MLZC98877C.p8
DEST_DESKTOP=~/Desktop/RedFluent_BACKUP
ASC_API_KEY=MLZC98877C
ASC_API_ISSUER=ac346e65-0361-4b5a-849c-e443d78894aa

echo "==> Step 1: stage backups on Desktop for DeskIn download"
mkdir -p "$DEST_DESKTOP"
if [ -f "$P8" ]; then
  cp "$P8" "$DEST_DESKTOP/AuthKey_MLZC98877C.p8"
  echo "   .p8 staged"
else
  echo "   WARN: $P8 not found"
fi

if [ -d "$REPO/build/RedFluentVPN.xcarchive" ]; then
  cp -R "$REPO/build/RedFluentVPN.xcarchive" "$DEST_DESKTOP/RedFluentVPN-build1.xcarchive"
  echo "   build #1 .xcarchive staged"
fi

if [ -f "$REPO/build/export/RedFluentVPN.ipa" ]; then
  cp "$REPO/build/export/RedFluentVPN.ipa" "$DEST_DESKTOP/RedFluentVPN-build1.ipa"
  echo "   build #1 .ipa staged"
fi

echo
echo "==> Step 2: pull latest iOS code from GitHub (auto-stash to avoid conflicts)"
cd "$REPO"
git fetch origin
git checkout main
# Auto-stash so previous wrap-up's uncommitted bumps don't block pull
git stash --include-untracked --quiet || true
git pull --rebase origin main
git stash drop --quiet 2>/dev/null || true

echo
echo "==> Step 3: bump build number"
APP_PLIST="Supporting/RedFluentVPN-Info.plist"
TUN_PLIST="Supporting/RedFluentVPNTunnel-Info.plist"
current_app=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PLIST")
next_app=$((current_app + 1))
echo "   CFBundleVersion $current_app -> $next_app"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_app" "$APP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_app" "$TUN_PLIST"

# Commit + push immediately so next run won't conflict
echo "   committing + pushing bump (so the next wrap-up run won't conflict)"
git add "$APP_PLIST" "$TUN_PLIST"
git commit -m "Bump CFBundleVersion to $next_app (auto by wrap-up)" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || echo "   WARN: push failed, you may need to push manually later"

echo
echo "==> Step 3.5: keep existing AppIcon.png (the owner's designed icon is committed)"
echo "   To regenerate from the design sheet, run:"
echo "   python scripts/extract-design-assets.py path/to/design-sheet.png"

echo
echo "==> Step 4: regenerate Xcode project"
xcodegen generate >/dev/null

echo
echo "==> Step 5: clean build dir + write exportOptions.plist"
rm -rf build ~/Library/Developer/Xcode/DerivedData/RedFluentVPN-*
mkdir -p build
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
    <string>RedFluent VPN App Store</string>
    <key>com.redfluent.vpn.tunnel</key>
    <string>RedFluent VPN Tunnel App Store</string>
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

echo
echo "==> Step 6: archive (this takes 30-60 seconds)"
xcodebuild -project RedFluentVPN.xcodeproj \
  -scheme RedFluentVPN \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -archivePath build/RedFluentVPN.xcarchive \
  archive 2>&1 | tail -5

echo
echo "==> Step 7: export IPA"
xcodebuild -exportArchive \
  -archivePath build/RedFluentVPN.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/exportOptions.plist 2>&1 | tail -5

echo
echo "==> Step 8: upload to App Store Connect as build #$next_app"
xcrun altool --upload-app \
  -f build/export/RedFluentVPN.ipa \
  -t ios \
  --apiKey "$ASC_API_KEY" \
  --apiIssuer "$ASC_API_ISSUER"

echo
echo "==> Step 9: stage build #2 artefacts for download too"
cp -R build/RedFluentVPN.xcarchive "$DEST_DESKTOP/RedFluentVPN-build${next_app}.xcarchive"
cp build/export/RedFluentVPN.ipa "$DEST_DESKTOP/RedFluentVPN-build${next_app}.ipa"

echo
echo "==> Step 10: commit + push the bumped Info.plist files"
git add Supporting/RedFluentVPN-Info.plist Supporting/RedFluentVPNTunnel-Info.plist
if git diff --staged --quiet; then
  echo "   no plist changes to commit"
else
  git commit -m "Bump build number to $next_app (TestFlight build #$next_app uploaded)"
  git push origin main
fi

echo
echo "================================================================"
echo "DONE."
echo
echo "TestFlight build #$next_app uploaded. Will appear in App Store"
echo "Connect within 5-15 minutes. The Internal group 'Owner' has"
echo "Auto Distribution enabled, so the new build will go to your"
echo "iPhone TestFlight automatically."
echo
echo "Files staged in $DEST_DESKTOP for DeskIn download:"
ls -la "$DEST_DESKTOP"
echo
echo "Drag everything in $DEST_DESKTOP back to Windows. Recommended"
echo "storage: F:\\secure\\ (NOT inside any git repo)."
echo "================================================================"
