"""
Slice the 2026-05-09 design intake sheet into the iOS asset catalog.

Source: a 1254x1254 composite design sheet provided by the owner with
layout:
  Top-left:    big "APP ICON - iOS" Default variant
  Top-right:   8 size badges (1024 -> 16)
  Middle row:  6 variants (Default, Dark Mode, Light Background,
               Monochrome Red, Monochrome White, Outline)
  Bottom rows: 16 feature glyphs (Secure, Fast, Global, Stable, ...)

We only need the Default variant for the App Store icon. The variants
are saved as side-by-side reference PNGs so we can ship Dark / Tinted
icons later without re-asking the designer.

Glyphs are intentionally NOT extracted as PNGs — the SwiftUI app uses
SF Symbols for them, which auto-adapt to dark mode and Dynamic Type.

Usage:
    python scripts/extract-design-assets.py path/to/design-sheet.png
"""
import sys
from pathlib import Path
from PIL import Image

if len(sys.argv) < 2:
    print("usage: python extract-design-assets.py <design-sheet.png>", file=sys.stderr)
    sys.exit(2)

src_path = Path(sys.argv[1])
img = Image.open(src_path).convert("RGB")
W, H = img.size
print(f"source: {W}x{H}")

repo = Path(__file__).resolve().parent.parent
icon_set = repo / "App" / "Assets.xcassets" / "AppIcon.appiconset"
design_dir = repo / "Design"
variants_dir = design_dir / "icon-variants"
icon_set.mkdir(parents=True, exist_ok=True)
variants_dir.mkdir(parents=True, exist_ok=True)


def crop(box, name, target_size=None, into=None):
    """Crop normalized [x0, y0, x1, y1] (0-1 range), optionally resize."""
    x0, y0, x1, y1 = box
    pixel_box = (
        int(x0 * W),
        int(y0 * H),
        int(x1 * W),
        int(y1 * H),
    )
    chunk = img.crop(pixel_box)
    if target_size is not None:
        chunk = chunk.resize((target_size, target_size), Image.LANCZOS)
    out_dir = into if into is not None else design_dir
    out_path = out_dir / f"{name}.png"
    chunk.save(out_path, "PNG")
    print(f"  -> {out_path.relative_to(repo)} ({chunk.size[0]}x{chunk.size[1]})")
    return chunk


# === Default app icon (top-left big tile) ===
# Strategy: crop a generous region around the top-left tile, then auto-tighten
# to the brand-red circle's bounding box so we don't carry padding or label
# text into the final 1024 PNG. Apple auto-rounds 1024 icons, so the dark
# square corners that remain are intentional and correct.

ROUGH_BOX = (0.030, 0.080, 0.420, 0.430)
rough_pixel_box = (
    int(ROUGH_BOX[0] * W),
    int(ROUGH_BOX[1] * H),
    int(ROUGH_BOX[2] * W),
    int(ROUGH_BOX[3] * H),
)
rough_chunk = img.crop(rough_pixel_box)

# Find the bounding box of brand-red pixels.
import numpy as np
arr = np.asarray(rough_chunk)
r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
red_mask = (r > 180) & (g < 90) & (b < 90)
ys, xs = np.where(red_mask)

if len(xs) == 0:
    print("  WARN: no red pixels found, falling back to rough box")
    default_icon = rough_chunk.resize((1024, 1024), Image.LANCZOS)
else:
    pad = 28  # leave a little dark gutter around the red so the arrow tail isn't clipped
    x0 = max(0, xs.min() - pad)
    x1 = min(rough_chunk.width, xs.max() + pad)
    y0 = max(0, ys.min() - pad)
    y1 = min(rough_chunk.height, ys.max() + pad)
    # Square it out around the center to get a perfect 1:1 icon.
    cx = (x0 + x1) // 2
    cy = (y0 + y1) // 2
    half = max(x1 - x0, y1 - y0) // 2 + 4
    x0 = max(0, cx - half)
    y0 = max(0, cy - half)
    x1 = min(rough_chunk.width, cx + half)
    y1 = min(rough_chunk.height, cy + half)
    default_icon = rough_chunk.crop((x0, y0, x1, y1)).resize((1024, 1024), Image.LANCZOS)

icon_path = icon_set / "AppIcon.png"
default_icon.save(icon_path, "PNG")
print(f"  -> {icon_path.relative_to(repo)} ({default_icon.size[0]}x{default_icon.size[1]})")

# Save the rough region too, for reference
ref = variants_dir / "default-source.png"
rough_chunk.save(ref, "PNG")
print(f"  -> {ref.relative_to(repo)} ({rough_chunk.size[0]}x{rough_chunk.size[1]})")

# === 6 variants in the middle row ===
# Row spans roughly y: 0.555 - 0.700, six tiles equally spaced left to right.
variant_y0, variant_y1 = 0.555, 0.700
variant_x0, variant_x1 = 0.045, 0.955
n_variants = 6
variant_names = [
    "default-small",
    "dark-mode",
    "light-background",
    "monochrome-red",
    "monochrome-white",
    "outline",
]
variant_width = (variant_x1 - variant_x0) / n_variants
for i, name in enumerate(variant_names):
    x0 = variant_x0 + i * variant_width + 0.005
    x1 = variant_x0 + (i + 1) * variant_width - 0.005
    crop((x0, variant_y0, x1, variant_y1), name=name, into=variants_dir)

# === Save full sheet for archival ===
sheet_path = design_dir / "icon-spec-sheet.png"
img.save(sheet_path, "PNG")
print(f"  -> {sheet_path.relative_to(repo)} ({W}x{H})")

print()
print("Done. Drop a more precise Default crop into")
print(f"  {(icon_set / 'AppIcon.png').relative_to(repo)}")
print("if the auto-cropped version isn't tight enough.")
