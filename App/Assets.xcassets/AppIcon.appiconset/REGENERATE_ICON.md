# AppIcon.png

## How the icon is currently produced

`AppIcon.png` is generated programmatically by the Swift script
`scripts/generate-app-icon.swift`, which runs on macOS. The script
draws:

- Full-bleed dark background (#0F0F12)
- Subtle radial vignette for depth
- Brand red circle inset by ~11% of the canvas
- Specular highlight on the upper-left of the red circle
- White SF Symbols `paperplane.fill` mark, slightly nudged below center

This approximates the Default variant from the design spec the user
provided on 2026-05-09. It is intentionally a programmatic placeholder,
not a hand-designed icon.

## How to regenerate

```sh
cd <repo root>
swift scripts/generate-app-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

The cloud Mac wrap-up script
(`redfluent-vpn/scripts/cloud-mac-wrap-up.sh`) calls this automatically
before each archive.

## How to replace with a real designed icon

When the actual designer-exported 1024x1024 PNG is ready:

1. Save it as `AppIcon.png` in this same directory (overwrite the
   generated one).
2. Run `git update-index --skip-worktree` on this file so the
   regeneration script does not stomp it on subsequent ships, OR
   delete `scripts/generate-app-icon.swift` once a real icon is in
   place.
3. Re-archive and re-upload.

## Design spec source

See `Design/icon-spec.md` for the design intent (red circle with
white paper plane on dark base, multiple variants, feature icon set).
