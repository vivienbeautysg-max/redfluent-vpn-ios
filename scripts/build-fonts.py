#!/usr/bin/env python3
"""Builds the static fonts in App/Fonts from the Google Fonts variable sources.

The "01 Soft Landing" design sets Fraunces with font-variation-settings (opsz / SOFT / WONK). iOS cannot
drive SOFT / WONK on a variable font through SwiftUI, so each style the design uses is cut here into its own
static TTF at the design's axis values. Archivo is cut into its static weights the same way; IBM Plex Mono is
copied unchanged (its OFL reserves the name "Plex", so it must not be modified under that name).

All three are SIL Open Font License 1.1; the licence texts are copied next to the fonts and ship in the app.

Usage (fontTools: pip3 install --user fonttools):
  SRC=$(mktemp -d); B=https://raw.githubusercontent.com/google/fonts/main/ofl
  curl -fsSL -o $SRC/Fraunces-VF.ttf "$B/fraunces/Fraunces%5BSOFT,WONK,opsz,wght%5D.ttf"
  curl -fsSL -o $SRC/Fraunces-OFL.txt "$B/fraunces/OFL.txt"
  curl -fsSL -o $SRC/Archivo-VF.ttf "$B/archivo/Archivo%5Bwdth,wght%5D.ttf"
  curl -fsSL -o $SRC/Archivo-OFL.txt "$B/archivo/OFL.txt"
  curl -fsSL -o $SRC/IBMPlexMono-Regular.ttf "$B/ibmplexmono/IBMPlexMono-Regular.ttf"
  curl -fsSL -o $SRC/IBMPlexMono-Medium.ttf "$B/ibmplexmono/IBMPlexMono-Medium.ttf"
  curl -fsSL -o $SRC/IBMPlexMono-OFL.txt "$B/ibmplexmono/OFL.txt"
  python3 scripts/build-fonts.py $SRC App/Fonts

The PostScript names written here must match App/AppFonts.swift (scripts/selftest.sh checks that).
"""
import os
import shutil
import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

# (source, output file, PostScript name, family, style, axis location)
CUTS = [
    # Display: titles 46-60 pt ("Connected.", "People.", the big bandwidth figure). CSS: WONK 1, SOFT 30, wght 400.
    ("Fraunces-VF.ttf", "FrauncesRF-Display.ttf", "FrauncesRF-Display", "Fraunces RF Display", "Regular",
     {"opsz": 48, "wght": 400, "SOFT": 30, "WONK": 1}),
    # Text: the 19-21 pt serif (wordmark, row figures).
    ("Fraunces-VF.ttf", "FrauncesRF-Text.ttf", "FrauncesRF-Text", "Fraunces RF Text", "Regular",
     {"opsz": 21, "wght": 400, "SOFT": 30, "WONK": 1}),
    ("Archivo-VF.ttf", "ArchivoRF-Regular.ttf", "ArchivoRF-Regular", "Archivo RF", "Regular", {"wght": 400, "wdth": 100}),
    ("Archivo-VF.ttf", "ArchivoRF-Medium.ttf", "ArchivoRF-Medium", "Archivo RF", "Medium", {"wght": 500, "wdth": 100}),
    ("Archivo-VF.ttf", "ArchivoRF-SemiBold.ttf", "ArchivoRF-SemiBold", "Archivo RF", "SemiBold", {"wght": 600, "wdth": 100}),
]
COPIES = ["IBMPlexMono-Regular.ttf", "IBMPlexMono-Medium.ttf"]
LICENSES = [("Fraunces-OFL.txt", "OFL-Fraunces.txt"), ("Archivo-OFL.txt", "OFL-Archivo.txt"),
            ("IBMPlexMono-OFL.txt", "OFL-IBMPlexMono.txt")]


def normalized(font, location):
    """User-space axis location -> normalized (-1..1) coordinates, as the condition sets use them."""
    out = {}
    for axis in font["fvar"].axes:
        v = location.get(axis.axisTag, axis.defaultValue)
        if v == axis.defaultValue:
            n = 0.0
        elif v < axis.defaultValue:
            n = (v - axis.defaultValue) / (axis.defaultValue - axis.minValue)
        else:
            n = (v - axis.defaultValue) / (axis.maxValue - axis.defaultValue)
        out[axis.axisTag] = n
    return out


def active_substitutions(font, location):
    """Single substitutions of the FeatureVariations records that apply at `location` (e.g. Fraunces' WONK).

    A browser applies them through 'rvrn'. Core Text may not run 'rvrn' on a static font, so they are frozen
    into the cmap below: the character maps straight to the glyph the design shows.
    """
    gsub = font["GSUB"].table if "GSUB" in font else None
    if gsub is None or not getattr(gsub, "FeatureVariations", None):
        return {}
    coords = normalized(font, location)
    axes = [a.axisTag for a in font["fvar"].axes]
    lookups = gsub.LookupList.Lookup
    mapping = {}
    for record in gsub.FeatureVariations.FeatureVariationRecord:
        ok = all(c.FilterRangeMinValue - 1e-6 <= coords[axes[c.AxisIndex]] <= c.FilterRangeMaxValue + 1e-6
                 for c in record.ConditionSet.ConditionTable)
        if not ok:
            continue
        for sub in record.FeatureTableSubstitution.SubstitutionRecord:
            for index in sub.Feature.LookupListIndex:
                for st in lookups[index].SubTable:
                    st = getattr(st, "ExtSubTable", st)
                    mapping.update(getattr(st, "mapping", {}) or {})
        break  # the first matching record wins, as in the OpenType spec
    return mapping


def set_names(font, family, style, ps):
    name = font["name"]
    full = family if style == "Regular" else f"{family} {style}"
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            name.removeNames(nameID=rec.nameID)
    for nid, value in ((1, family if style in ("Regular",) else full), (2, "Regular"), (3, f"{ps};Redfluent cut"),
                       (4, full), (6, ps), (16, family), (17, style)):
        name.setName(value, nid, 3, 1, 0x409)
        name.setName(value, nid, 1, 0, 0)


def main(src, out):
    os.makedirs(out, exist_ok=True)
    for source, filename, ps, family, style, location in CUTS:
        vf = TTFont(os.path.join(src, source))
        subs = active_substitutions(vf, location)
        static = instancer.instantiateVariableFont(vf, location, inplace=False, updateFontNames=False)
        if subs:
            for table in static["cmap"].tables:
                for cp, glyph in list(table.cmap.items()):
                    if glyph in subs:
                        table.cmap[cp] = subs[glyph]
        for tag in ("DSIG", "STAT"):
            if tag in static:
                del static[tag]
        set_names(static, family, style, ps)
        static.save(os.path.join(out, filename))
        print(f"{filename}: {ps} at {location}" + (f", frozen {len(subs)} substitutions" if subs else ""))
    for filename in COPIES:
        shutil.copyfile(os.path.join(src, filename), os.path.join(out, filename))
        print(f"{filename}: copied unchanged")
    for source, target in LICENSES:
        shutil.copyfile(os.path.join(src, source), os.path.join(out, target))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
