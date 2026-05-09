# RedFluent VPN iOS MVP Skeleton

This repository is a Mac-ready source skeleton for the first RedFluent VPN iOS app.

It uses XcodeGen to generate the `.xcodeproj` on a Mac or in Xcode Cloud.

Generate locally on Mac:

```sh
brew install xcodegen
xcodegen generate
open RedFluentVPN.xcodeproj
```

## Targets

Main app:

- Target name: `RedFluentVPN`
- Bundle ID: `com.redfluent.vpn`

Packet tunnel extension:

- Target name: `RedFluentVPNTunnel`
- Bundle ID: `com.redfluent.vpn.tunnel`

## Required Capability

Both App ID / extension setup must support Network Extension:

- `packet-tunnel-provider`

## Suggested Xcode Steps

1. Clone this repo on a Mac/cloud Mac.
2. Run `xcodegen generate`.
3. Open `RedFluentVPN.xcodeproj`.
4. Confirm signing team is RedFluent Pte. Ltd.
5. Build to a physical iPhone.

## Website URLs

- Marketing: https://www.redfluent.com/vpn
- Privacy: https://www.redfluent.com/privacy
- Terms: https://www.redfluent.com/terms
- Support: https://www.redfluent.com/support

## Important

Do not hardcode production VPN secrets in source code for public release.

For TestFlight/App Review, use a dedicated review-safe server credential or temporary profile that can be revoked.
