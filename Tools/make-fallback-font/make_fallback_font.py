#!/usr/bin/env python3
"""Builds the small fallback fonts bundled with the app: GNU Unifont reduced to the characters that the macOS
system fonts cannot draw (list produced by .github/workflows/coverage.yml, see system-missing.txt).

    pip install fonttools
    python3 Tools/make-fallback-font/make_fallback_font.py /path/to/unifont.otf /path/to/unifont_upper.otf

Writes Typecase/Resources/Fonts/TypecaseFallback.otf (Basic Multilingual Plane) and TypecaseFallbackUpper.otf
(other planes). Unifont is dual licensed (GPLv2+ with the font embedding exception, and SIL OFL 1.1);
see Typecase/Resources/Fonts/THIRD-PARTY.md.
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

root = Path(__file__).resolve().parents[2]
wanted = {int(line, 16) for line in (Path(__file__).parent / "system-missing.txt").read_text().split()}
out_dir = root / "Typecase/Resources/Fonts"
out_dir.mkdir(parents=True, exist_ok=True)

for source, name in zip(sys.argv[1:3], ["TypecaseFallback", "TypecaseFallbackUpper"]):
    font = TTFont(source)
    have = set(font.getBestCmap())
    keep = sorted(wanted & have)
    options = subset.Options()
    options.layout_features = []
    options.hinting = False
    options.notdef_outline = True
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=keep)
    subsetter.subset(font)
    for record in font["name"].names:
        if record.nameID in (1, 16):
            record.string = name
        elif record.nameID == 4:
            record.string = name
        elif record.nameID == 6:
            record.string = name
    target = out_dir / f"{name}.otf"
    font.save(target)
    print(f"{target.name}: {len(keep)} characters, {target.stat().st_size / 1024:.0f} KB")
