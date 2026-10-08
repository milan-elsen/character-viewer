#!/usr/bin/env python3
"""Renders the app icon (an omega on a blue gradient squircle) at every size an macOS AppIcon set needs.

Usage: python3 Tools/make-icon/make_icon.py
Writes Typecase/Resources/Assets.xcassets/AppIcon.appiconset/*.png and Contents.json
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Typecase", "Resources", "Assets.xcassets", "AppIcon.appiconset")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SIZE = 1024


def squircle_mask(size, inset, radius):
    scale = 4
    m = Image.new("L", (size * scale, size * scale), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([inset * scale, inset * scale, (size - inset) * scale, (size - inset) * scale], radius * scale, fill=255)
    return m.resize((size, size), Image.LANCZOS)


def master():
    inset = 100  # macOS icon grid: 824pt artwork inside the 1024pt canvas
    mask = squircle_mask(SIZE, inset, 185)

    # Vertical gradient, indigo to azure.
    top, bottom = (88, 86, 214), (10, 132, 255)
    grad = Image.new("RGB", (SIZE, SIZE))
    px = grad.load()
    for y in range(SIZE):
        t = y / (SIZE - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(SIZE):
            px[x, y] = c

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (0, 14), mask)
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(14)))
    body = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    body.paste(grad, (0, 0), mask)

    # Soft highlight along the top edge.
    hi = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    hd = ImageDraw.Draw(hi)
    hd.ellipse([-260, -640, SIZE + 260, 420], fill=(255, 255, 255, 30))
    hi = hi.filter(ImageFilter.GaussianBlur(40))
    hi.putalpha(Image.composite(hi.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), mask))
    body = Image.alpha_composite(body, hi)

    # The glyph: omega, with a small thin-space marker underneath (the whole point of the app).
    d = ImageDraw.Draw(body)
    font = ImageFont.truetype(FONT, 560)
    text = "Ω"
    bbox = d.textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    gap, bar_h = 64, 18
    group_h = h + gap + bar_h
    top_y = (SIZE - group_h) / 2
    x = (SIZE - w) / 2 - bbox[0]
    y = top_y - bbox[1]
    glyph_shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glyph_shadow).text((x, y + 10), text, font=font, fill=(0, 0, 60, 110))
    body = Image.alpha_composite(body, glyph_shadow.filter(ImageFilter.GaussianBlur(10)))
    d = ImageDraw.Draw(body)
    d.text((x, y), text, font=font, fill=(255, 255, 255, 255))

    # Em-width ruler under the glyph.
    bar_y = int(top_y + h + gap)
    d.rounded_rectangle([SIZE / 2 - 150, bar_y, SIZE / 2 + 150, bar_y + 18], 9, fill=(255, 255, 255, 120))
    d.rounded_rectangle([SIZE / 2 - 150, bar_y, SIZE / 2 - 60, bar_y + 18], 9, fill=(255, 255, 255, 255))

    return Image.alpha_composite(canvas, body)


def main():
    os.makedirs(OUT, exist_ok=True)
    img = master()
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"
            img.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
            images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
    img.save(os.path.join(HERE, "icon-preview.png"))


if __name__ == "__main__":
    main()
