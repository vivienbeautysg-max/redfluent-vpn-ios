#!/usr/bin/env bash
# Cloud Mac wrap-up helper for RedFluent VPN TestFlight releases.
# Runs the verified release pipeline, then stages resulting artifacts on Desktop.

set -euo pipefail

REPO=~/Projects/redfluent-vpn-ios
P8=~/.appstoreconnect/private_keys/AuthKey_MLZC98877C.p8
DEST_DESKTOP=~/Desktop/RedFluent_BACKUP
ASC_API_KEY=MLZC98877C
ASC_API_ISSUER=ac346e65-0361-4b5a-849c-e443d78894aa

echo "==> Step 1: stage existing artifacts on Desktop for download"
mkdir -p "$DEST_DESKTOP"
if [ -f "$P8" ]; then
  cp "$P8" "$DEST_DESKTOP/AuthKey_MLZC98877C.p8"
fi

echo
echo "==> Step 2: sync latest source"
cd "$REPO"
git fetch origin
git checkout main
git stash --include-untracked --quiet || true
git pull --rebase origin main
git stash drop --quiet 2>/dev/null || true

echo
echo "==> Step 3: run verified TestFlight pipeline"
ASC_API_KEY="$ASC_API_KEY" \
ASC_API_ISSUER="$ASC_API_ISSUER" \
BUMP="${BUMP:-patch}" \
bash scripts/release-testflight.sh

build_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Supporting/RedFluentVPN-Info.plist)

echo
echo "==> Step 4: stage shipped artifacts"
if [ -d build/RedFluentVPN-distribution.xcarchive ]; then
  rm -rf "$DEST_DESKTOP/RedFluentVPN-build${build_number}.xcarchive"
  cp -R build/RedFluentVPN-distribution.xcarchive "$DEST_DESKTOP/RedFluentVPN-build${build_number}.xcarchive"
fi
if [ -f build/export/RedFluentVPN.ipa ]; then
  cp build/export/RedFluentVPN.ipa "$DEST_DESKTOP/RedFluentVPN-build${build_number}.ipa"
fi

echo
echo "==> Step 5: commit shipped build number if needed"
git add Supporting/RedFluentVPN-Info.plist Supporting/RedFluentVPNTunnel-Info.plist
if git diff --staged --quiet; then
  echo "   no plist bump to commit"
else
  git commit -m "Bump build number to ${build_number} after TestFlight upload"
  git push origin main
fi

echo
echo "DONE."
echo "Build number: ${build_number}"
echo "Artifacts staged at: $DEST_DESKTOP"
ls -la "$DEST_DESKTOP"
