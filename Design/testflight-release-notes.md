# TestFlight Release Notes (paste-ready)

Use these "What to Test" notes when prompting testers in App Store Connect.

## Build 1 (1.0)
First test build. Pipeline shake-out only — VPN engine is not wired.
- Confirm app installs and launches
- Confirm Connect button surfaces the iOS VPN permission prompt
- Confirm Disconnect cleanly tears down the VPN entry in iOS Settings
- Confirm app does not crash on backgrounding / foregrounding

## Build 2 (1.0)
Adds the real designed app icon and the full activation UI.
- Confirm new red app icon shows on home screen
- Confirm onboarding (3 slides) appears on first launch
- Confirm activation screen accepts invite code RF-OWNER-2026
  (will fail with a network error until the backend is deployed at
  api.redfluent.com — that's expected for build 2)
- Confirm Diagnostics sheet shows the device public ID
- Confirm Sign Out clears local activation and returns to invite screen

## Build 3 (1.0) — planned
Adds backend connectivity. Activation will succeed and dashboard will
render the real owner / region / config version from
api.redfluent.com.

## Build 4 (1.0) — planned
Integrates sing-box engine. Connect actually routes traffic through
the Tokyo VPS. Verify with https://ipinfo.io showing 45.32.31.229.
