# RedFluent VPN — Icon & Visual Spec

Last updated: 2026-05-09 (intake from owner-provided design sheet)

## App Icon — Default Variant

- **Base shape**: rounded square, full bleed (iOS rounds the corners
  automatically for the home-screen rendering)
- **Background**: very dark, near-black (`#0F0F12` ish)
- **Brand mark backdrop**: solid brand-red circle (`#ED2A2E` ish),
  centered, taking ~78% of the canvas
- **Brand mark**: white paper plane / send-style arrow, pointing toward
  the upper right, with optional motion lines streaming off the
  bottom-left tail
- **Highlight**: a soft warm specular on the upper-left edge of the red
  circle to give it physical depth (very subtle)

## Icon Variants (declared but not all shipped yet)

| Variant            | Background | Mark color | Use |
|--------------------|------------|-----------|-----|
| Default            | Dark       | White     | Primary App Store icon |
| Dark Mode          | Charcoal   | White     | iOS 18+ Dark icon variant in asset catalog |
| Light Background   | White      | Red       | iOS 18+ Tinted/Light variant |
| Monochrome Red     | Dark       | Red       | Marketing badges |
| Monochrome White   | Dark       | White     | Press kit / dark-bg surfaces |
| Outline            | Transparent| Red stroke| Web favicon, watermark |

Currently shipping: **Default only**. The other variants are tracked
here so we don't lose them when the time comes to ship a polished
release. iOS 18+ supports Dark + Tinted icons via the asset catalog
appearance variants.

## Feature Icon System

The owner's design uses a unified red-on-dark glyph system. Inside the
SwiftUI app these are rendered with **SF Symbols** (no PNG assets
required) — this keeps the binary small, gives free Dynamic Type
scaling, and adapts to both light and dark mode automatically.

| Design label | SF Symbol used in app          | Where it appears |
|--------------|-------------------------------|------------------|
| Secure       | `lock.shield.fill`             | Connected state orb |
| Fast         | `bolt.fill`                    | (planned: speed widget) |
| Global       | `globe.asia.australia.fill`    | Server card "Server" row |
| Stable       | `wifi.shield`                  | (planned: stability widget) |
| Private      | `lock.fill`                    | (planned: privacy detail) |
| Safe         | `checkmark.shield.fill`        | (planned: safe browsing) |
| Connect      | `paperplane.fill`              | App icon (also planned: connect button accent) |
| Servers      | `server.rack`                  | (planned: server list) |
| Access       | `key.fill`                     | (planned: invite redemption) |
| Speed        | `gauge.with.dots.needle.bottom.50percent` | (planned) |
| Locations    | `mappin.and.ellipse`           | (planned) |
| Network      | `antenna.radiowaves.left.and.right` | Server card "Provider" row |
| Update       | `arrow.triangle.2.circlepath`  | Connecting state orb |
| Settings     | `gearshape.fill`               | Toolbar menu entry |
| Support      | `headphones`                   | (planned: support sheet) |
| Premium      | `crown.fill`                   | (planned: future tier) |

## Color Tokens

Defined in `App/Theme.swift`:

| Token                | Value            | Use |
|----------------------|------------------|-----|
| brandPrimary         | `#D32F2F`        | Buttons, active states, dashboard accents |
| brandSecondary       | `#9E1A1A`        | Gradients, hover/pressed |
| brandTertiary        | `#F26666`        | Highlights, success on red |
| surfaceCard          | `secondarySystemBackground` | Card surfaces |
| surfaceElevated      | `tertiarySystemBackground`  | Inputs, raised cells |
| textPrimary          | `label`          | Body text |
| textSecondary        | `secondaryLabel` | Captions, metadata |
| textOnBrand          | white            | Text over brand color |
| success / warning / danger | green / orange / red | Status semantics |

## How to replace the placeholder icon with the real designed PNG

Drop a 1024×1024 PNG (sRGB, no alpha) into:

```
App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Then either delete `scripts/generate-app-icon.swift` or remove the
"regenerate icon" step from `redfluent-vpn/scripts/cloud-mac-wrap-up.sh`
so subsequent ships do not overwrite the designed asset.

## How to ship Dark + Tinted variants later (iOS 18+)

Update `App/Assets.xcassets/AppIcon.appiconset/Contents.json` to
include `appearances` array with `luminosity` keyed entries, and
provide additional PNGs in the same folder. Reference:
<https://developer.apple.com/documentation/xcode/configuring-your-app-icon>
