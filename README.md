# RedFluent VPN for iOS

RedFluent VPN is a private, invite-only secure tunnel client for iOS.

## License

Copyright (C) 2026 Redfluent Pte. Ltd.

This program is free software: you can redistribute it and/or modify it under
the terms of the **GNU General Public License version 3** as published by the
Free Software Foundation, either version 3 of the License, or (at your option)
any later version. See [LICENSE](LICENSE) for the full text.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

### Why GPLv3

This app links against **Libbox**, built from
[sing-box](https://github.com/SagerNet/sing-box) (Copyright (C) 2022 by
nekohasekai, licensed under GPLv3). Because the shipped binary is a derivative
work of that code, this client is released under the same license, and its
complete corresponding source is published here.

sing-box is an independent project. This app is **not** affiliated with,
endorsed by, or associated with sing-box or its authors.

### What is not in this repository

Server-side components are separate programs that are not distributed with this
app and are therefore not covered by this license:

- the backend API (`vpn-api.redfluent.com`)
- server deployment configuration and operational credentials

Runtime VPN configuration is fetched from the backend at activation time; no
server credentials are contained in this repository.

## Building

This repository is the complete source for the RedFluent VPN iOS app.

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

## Current Cloud Mac Handoff

The current Rent a Mac cloud machine has this repo cloned at:

```sh
~/Projects/redfluent-vpn-ios
```

Xcode 26.4.1 is installed at:

```sh
/Users/rentamac/Downloads/Xcode.app
```

If `xcodebuild` reports that the active developer directory is `/Library/Developer/CommandLineTools`, run:

```sh
sudo xcode-select --switch "/Users/rentamac/Downloads/Xcode.app/Contents/Developer"
xcodebuild -version
```

Then build:

```sh
xcodebuild -project RedFluentVPN.xcodeproj -scheme RedFluentVPN -destination 'generic/platform=iOS' build
```

Full handoff notes are in `X:\Codex\REDFLUENT_VPN_HANDOFF.md` on the Windows/Codex workspace.

## Website URLs

- Marketing: https://www.redfluent.com/vpn
- Privacy: https://www.redfluent.com/privacy
- Terms: https://www.redfluent.com/terms
- Support: https://www.redfluent.com/support

## TestFlight Pipeline (verified working 2026-05-19)

The current Cloud Mac cannot reliably export with its legacy local Apple
Distribution identities in the active user keychain. The stable path is now
scripted:

1. create an unsigned archive via automatic signing + App Store Connect API key
2. ad hoc sign the archive contents so Network Extension entitlements stay on
   the app and tunnel extension
3. export through a temporary empty user keychain so Xcode uses managed cloud
   signing instead of stale local identities
4. validate and upload with `altool`

Run on the build Mac:

```sh
export ASC_API_KEY=<App Store Connect Key ID>
export ASC_API_ISSUER=<App Store Connect Issuer ID>
bash scripts/release-testflight.sh
```

`scripts/cloud-mac-wrap-up.sh` is a higher-level wrapper that pulls latest
source, runs the release pipeline, stages the shipped `.ipa` / `.xcarchive` on
the Desktop, and commits the final `CFBundleVersion` bump after a successful
upload.

Required on the build machine:

- App Store Connect `.p8` key at
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`
- Xcode 26+
- `xcodegen`

The repo still keeps `project.yml` on manual signing defaults for deterministic
bundle IDs and capabilities, but the release script overrides the export path to
use the verified managed-signing workflow above.

## Important

Do not hardcode production VPN secrets in source code for public release.

For TestFlight/App Review, use a dedicated review-safe server credential or
temporary profile that can be revoked.

The current `Tunnel/PacketTunnelProvider.swift` is a stub. It applies network
settings but does not route real traffic. Replace before any non-internal
testing.
