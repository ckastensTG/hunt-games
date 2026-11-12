#!/usr/bin/env python3
"""Puts the game pictures from tools/store_shots.gd on the store canvases,
with a caption above each: the screenshots for the App Store and Google Play.

Run from the hunt-games root:
    python3 tools/store/compose.py --sizes
        prints each device class's canvas and the picture size to render
        store_shots.gd at (its --resolution)
    python3 tools/store/compose.py --raw=DIR --captions=FILE --out=DIR [--lang=en]
        DIR/<class>/<scene>.png (store_shots.gd output, one folder per class)
        -> OUT/app-store/<lang>/iphone-6.9/01_brass.png, ...
    python3 tools/store/compose.py --raw3d=DIR3D --rawui=DIRUI --captions=... --out=... --lang=...
        the same from store_shots.gd --layer=3d (rendered once per size) with
        --layer=ui (once per size and language) laid over it: how every
        language after the first is made. --classes picks the device
        classes (the App Store and Google Play use different locale codes,
        so run once per store with its --lang).
    python3 tools/store/compose.py --search --raw3d=... --rawui=... --captions=... --out=... --lang=...
        the App Store's search results image (3:2, 3840x2560; iOS 27 shows it
        in search instead of the first screenshots): the --search-scene
        picture (store_shots.gd at the "search" size, default "capture")
        under the --search-caption caption (default "brass")
        -> OUT/app-store/<lang>/search-results.png
    python3 tools/store/compose.py --header=RENDER --out=DIR
        the App Store's product page header (21:9, 3840x1646, no text: the
        icon and name sit under it), from a hero render (style_frame.gd
        --views=hero at 3840x1646) -> OUT/app-store/header/product-page-header.png

Captions: a JSON file {"order": [scenes...], "<scene>": [headline, line]}
(timeless-store-assets/<title>/shared/<lang>/captions.json, next to the
repos). Fonts: the series fonts in ui/fonts (Alegreya SC for the headline,
Alegreya Sans for the line); a language whose script they lack needs its own
(--headline-font, --line-font).
Needs Pillow.
"""
from __future__ import annotations

import argparse
import json
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONTS = ROOT / "ui" / "fonts"

# Series colours (ui/series_theme.gd).
ACCENT = (245, 194, 107)
TEXT = (242, 230, 204)
TEXT_DIM = (194, 179, 153)
BRASS = (204, 158, 87)

# Device classes: the store's exact canvas, the caption band's height, and
# the game picture's box (left, top, width, height) on the canvas.
CLASSES = {
    # App Store: iPhone 6.9" (also used for the smaller iPhones).
    "iphone": {"store": "app-store", "folder": "iphone-6.9", "canvas": (1320, 2868),
               "band": 600, "frame": (80, 600, 1160, 2188), "headline": 140, "line": 68},
    # App Store: iPad 13" (also used for the smaller iPads).
    "ipad": {"store": "app-store", "folder": "ipad-13", "canvas": (2064, 2752),
             "band": 560, "frame": (150, 560, 1764, 2072), "headline": 150, "line": 76},
    # Google Play: phones (9:16).
    "play_phone": {"store": "google-play", "folder": "phone", "canvas": (1080, 1920),
                   "band": 430, "frame": (70, 430, 940, 1420), "headline": 102, "line": 50},
    # Google Play: 10" tablets (16:9); the 7" set is the same, scaled to 1920x1080.
    "play_tablet": {"store": "google-play", "folder": "tablet-10", "canvas": (2560, 1440),
                    "band": 280, "frame": (330, 280, 1900, 1100), "headline": 88, "line": 44,
                    "also": ("tablet-7", (1920, 1080))},
    # App Store: the search results image (3:2), a landscape game picture (the
    # 10" tablet's shape) under a caption big enough to read on a phone.
    "search": {"store": "app-store", "folder": "", "canvas": (3840, 2560),
               "band": 720, "frame": (400, 720, 3040, 1760), "headline": 240, "line": 124},
}
HEADER = (3840, 1646)


def background(size: tuple[int, int], glow_box: tuple[int, int, int, int]) -> Image.Image:
    w, h = size
    top, bottom = (34, 25, 17), (7, 5, 4)
    col = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        col.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    img = col.resize(size, Image.BILINEAR)
    # A warm glow behind the picture, like the game's key light.
    glow = Image.new("L", size, 0)
    x, y, fw, fh = glow_box
    ImageDraw.Draw(glow).ellipse((x - fw * 0.2, y - fh * 0.1, x + fw * 1.2, y + fh * 0.9), fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
    warm = Image.new("RGB", size, (120, 78, 34))
    return Image.composite(warm, img, glow)


def fit_font(path: pathlib.Path, size: int, text: str, max_w: int) -> ImageFont.FreeTypeFont:
    while size > 10:
        f = ImageFont.truetype(str(path), size)
        if f.getlength(text) <= max_w:
            return f
        size -= 2
    return ImageFont.truetype(str(path), size)


# Where a run without spaces (Chinese, Japanese) breaks best: after these.
CJK_BREAK_AFTER = "、，。；：！？）」』"


def wrap(text: str, font: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    """As few lines as _wrap_at(max_w) gives, made as even as possible (no
    single word left alone on the last line)."""
    lines = _wrap_at(text, font, max_w)
    if len(lines) < 2 or all(ln[-1] in CJK_BREAK_AFTER for ln in lines[:-1]):
        return lines  # one line, or broken after punctuation: keep those breaks
    lo, hi = 1, max_w
    while lo < hi:  # the narrowest width that still needs no more lines
        mid = (lo + hi) // 2
        if len(_wrap_at(text, font, mid)) <= len(lines):
            hi = mid
        else:
            lo = mid + 1
    return _wrap_at(text, font, lo)


def _wrap_at(text: str, font: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    """Lines no wider than max_w, broken at spaces; a run without spaces
    (Chinese, Japanese) that is too wide is broken between characters."""
    words, lines, cur = text.split(), [], ""
    for wd in words:
        trial = (cur + " " + wd).strip()
        if font.getlength(trial) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = wd
    if cur:
        lines.append(cur)
    out: list[str] = []
    for ln in lines:
        while font.getlength(ln) > max_w and len(ln) > 1:
            cut = len(ln)
            while cut > 1 and font.getlength(ln[:cut]) > max_w:
                cut -= 1
            # Prefer to break after a comma or full stop in the second half,
            # so a name like ヴォ・ゼファ isn't split.
            soft = max((i + 1 for i, ch in enumerate(ln[:cut]) if ch in CJK_BREAK_AFTER), default=0)
            if soft >= cut / 2:
                cut = soft
            out.append(ln[:cut])
            ln = ln[cut:]
        out.append(ln)
    return out


def compose(cls: dict, shot: Image.Image, headline: str, line: str,
            headline_font: pathlib.Path, line_font: pathlib.Path) -> Image.Image:
    cw, ch = cls["canvas"]
    fx, fy, fw, fh = cls["frame"]
    img = background((cw, ch), (fx, fy, fw, fh)).convert("RGBA")
    d = ImageDraw.Draw(img)
    band = cls["band"]
    max_w = int(cw * 0.86)
    hf = fit_font(headline_font, cls["headline"], headline, max_w)
    lf = ImageFont.truetype(str(line_font), cls["line"])
    line_rows = wrap(line, lf, max_w)
    h_asc, h_desc = hf.getmetrics()
    l_asc, l_desc = lf.getmetrics()
    rule_gap = int(cls["line"] * 0.55)
    block_h = h_asc + h_desc + rule_gap * 2 + len(line_rows) * int((l_asc + l_desc) * 1.12)
    y = (band - block_h) // 2 + int(band * 0.02)
    d.text((cw / 2, y), headline, font=hf, fill=ACCENT, anchor="ma")
    y += h_asc + h_desc + rule_gap
    rw = int(cls["line"] * 1.6)
    d.line((cw / 2 - rw, y, cw / 2 + rw, y), fill=BRASS + (170,), width=max(2, cls["line"] // 22))
    y += rule_gap
    for row in line_rows:
        d.text((cw / 2, y), row, font=lf, fill=TEXT, anchor="ma")
        y += int((l_asc + l_desc) * 1.12)
    # The game picture: rounded corners, a thin brass edge and a soft shadow.
    shot = shot.convert("RGB").resize((fw, fh), Image.LANCZOS) if shot.size != (fw, fh) else shot.convert("RGB")
    r = int(min(fw, fh) * 0.045)
    mask = Image.new("L", (fw, fh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, fw - 1, fh - 1), r, fill=255)
    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((fx, fy + r * 0.3, fx + fw, fy + fh + r * 0.3), r, fill=(0, 0, 0, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(r * 0.8))
    img = Image.alpha_composite(img, shadow)
    img.paste(shot, (fx, fy), mask)
    edge = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((fx, fy, fx + fw - 1, fy + fh - 1), r,
                                           outline=BRASS + (150,), width=max(2, fw // 400))
    img = Image.alpha_composite(img, edge)
    return img.convert("RGB")  # the stores want no alpha


def feature_graphic(render: Image.Image, title: str, line: str, logo: Image.Image | None,
                    headline_font: pathlib.Path, line_font: pathlib.Path) -> Image.Image:
    # headline_font sets the title ("Bagh Chal", or the title in the language's
    # own script); line_font the line under it.
    """Google Play's 1024x500 feature graphic: the hero render (rendered at
    2048x1000), the title in the sky at the top left over a soft shade, and
    the line's lockup at the top right. No alpha."""
    w, h = 1024, 500
    img = render.convert("RGB").resize((w, int(render.height * w / render.width)), Image.LANCZOS)
    if img.height != h:
        top = (img.height - h) // 2
        img = img.crop((0, top, w, top + h))
    cx, ty = 270, 46
    shade = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shade).ellipse((cx - 300, ty - 120, cx + 300, ty + 200), fill=150)
    shade = shade.filter(ImageFilter.GaussianBlur(60))
    img = Image.composite(Image.new("RGB", (w, h), (10, 7, 5)), img, shade).convert("RGBA")
    d = ImageDraw.Draw(img)
    hf = fit_font(headline_font, 92, title, 440)
    lf = fit_font(line_font, 30, line, 440)
    h_asc, h_desc = hf.getmetrics()
    y = ty
    d.text((cx, y), title, font=hf, fill=ACCENT, anchor="ma")
    y += h_asc + h_desc + 10
    d.line((cx - 46, y, cx + 46, y), fill=BRASS + (180,), width=2)
    y += 14
    d.text((cx, y), line, font=lf, fill=TEXT, anchor="ma")
    if logo is not None:
        lw = 118
        lg = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
        lg.putalpha(lg.getchannel("A").point(lambda v: int(v * 0.85)))
        img.alpha_composite(lg, (w - lw - 40, 34))
    return img.convert("RGB")


def icon(render: Image.Image, box: tuple[int, int, int] | None = None) -> tuple[Image.Image, Image.Image]:
    """The App Store icon (1024, RGB, square corners) and Google Play's (512).
    `box` (left, top, side[, percent]) picks the square, by default the
    centre; a percent under 100 shrinks it onto the dark table colour, so
    the rounded corners the stores add don't cut into it."""
    if box is None:
        side = min(render.size)
        box = ((render.width - side) // 2, (render.height - side) // 2, side)
    l, t, side = box[:3]
    sq = render.convert("RGB").crop((l, t, l + side, t + side)).resize((1024, 1024), Image.LANCZOS)
    if len(box) > 3 and box[3] < 100:  # a 4th value: shrink to that % on the dark table colour
        inner = int(1024 * box[3] / 100)
        bg = Image.new("RGB", (1024, 1024), (16, 11, 8))
        glow = Image.new("L", (1024, 1024), 0)
        ImageDraw.Draw(glow).ellipse((60, 60, 964, 964), fill=90)
        bg = Image.composite(Image.new("RGB", (1024, 1024), (70, 44, 20)), bg, glow.filter(ImageFilter.GaussianBlur(120)))
        off = (1024 - inner) // 2
        bg.paste(sq.resize((inner, inner), Image.LANCZOS), (off, off))
        sq = bg
    return sq, sq.resize((512, 512), Image.LANCZOS)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sizes", action="store_true")
    ap.add_argument("--raw", help="DIR/<class>/<scene>.png: whole pictures")
    ap.add_argument("--raw3d", help="instead of --raw: the 3D pictures (store_shots.gd --layer=3d) ...")
    ap.add_argument("--rawui", help="... with the interface pictures (--layer=ui) laid over them")
    ap.add_argument("--captions")
    ap.add_argument("--out")
    ap.add_argument("--lang", default="en")
    ap.add_argument("--classes", default=",".join(k for k in CLASSES if k != "search"))
    ap.add_argument("--headline-font", default=str(FONTS / "AlegreyaSC-Medium.ttf"))
    ap.add_argument("--line-font", default=str(FONTS / "AlegreyaSans-Regular.ttf"))
    ap.add_argument("--feature", help="hero render -> OUT/google-play/LANG/feature-graphic.png")
    ap.add_argument("--feature-title", default="Bagh Chal")
    ap.add_argument("--feature-title-font", default=str(FONTS / "AlegreyaSC-Medium.ttf"))
    ap.add_argument("--feature-line", default="")
    ap.add_argument("--logo", help="the line's white lockup (TEX_Logo_TimelessGames_White.png)")
    ap.add_argument("--search", action="store_true", help="the App Store search results image")
    ap.add_argument("--search-scene", default="capture")
    ap.add_argument("--search-caption", default="brass")
    ap.add_argument("--header", help="hero render -> OUT/app-store/header/product-page-header.png")
    ap.add_argument("--icon", action="append", default=[],
                    help="NAME=render.png[@left,top,side] -> OUT/app-store/icon/AppIcon-1024_NAME.png "
                         "and google-play/icon/icon-512_NAME.png")
    a = ap.parse_args()
    if a.header:
        im = Image.open(a.header).convert("RGB")
        if im.size != HEADER:
            # Fill the width, then keep the middle.
            im = im.resize((HEADER[0], round(im.height * HEADER[0] / im.width)), Image.LANCZOS)
            top = max(0, (im.height - HEADER[1]) // 2)
            im = im.crop((0, top, HEADER[0], top + HEADER[1]))
        dst = pathlib.Path(a.out) / "app-store" / "header" / "product-page-header.png"
        dst.parent.mkdir(parents=True, exist_ok=True)
        im.save(dst, optimize=True)
        print(f"{dst}  {im.size[0]}x{im.size[1]}")
        return
    if a.search:
        c = CLASSES["search"]
        caps = json.loads(pathlib.Path(a.captions).read_text(encoding="utf-8"))
        scene = a.search_scene
        if a.raw3d:
            shot = Image.alpha_composite(Image.open(pathlib.Path(a.raw3d) / "search" / f"{scene}.png").convert("RGBA"),
                                         Image.open(pathlib.Path(a.rawui) / "search" / f"{scene}.png").convert("RGBA"))
        else:
            shot = Image.open(pathlib.Path(a.raw) / "search" / f"{scene}.png")
        headline, line = caps[a.search_caption]
        img = compose(c, shot, headline, line, pathlib.Path(a.headline_font), pathlib.Path(a.line_font))
        dst = pathlib.Path(a.out) / "app-store" / a.lang / "search-results.png"
        dst.parent.mkdir(parents=True, exist_ok=True)
        img.save(dst, optimize=True)
        print(f"{dst}  {img.size[0]}x{img.size[1]}")
        return
    if a.feature or a.icon:
        out = pathlib.Path(a.out)
        if a.feature:
            logo = Image.open(a.logo).convert("RGBA") if a.logo else None
            fg = feature_graphic(Image.open(a.feature), a.feature_title, a.feature_line, logo,
                                 pathlib.Path(a.feature_title_font), pathlib.Path(a.line_font))
            dst = out / "google-play" / a.lang / "feature-graphic.png"
            dst.parent.mkdir(parents=True, exist_ok=True)
            fg.save(dst, optimize=True)
            print(dst)
        for spec in a.icon:
            name, src = spec.split("=", 1)
            box = None
            if "@" in src:  # NAME=render.png@left,top,side[,percent]
                src, b = src.split("@")
                box = tuple(int(v) for v in b.split(","))
            big, small = icon(Image.open(src), box)
            for store, im, fname in (("app-store", big, f"AppIcon-1024_{name}.png"),
                                     ("google-play", small, f"icon-512_{name}.png")):
                dst = out / store / "icon" / fname
                dst.parent.mkdir(parents=True, exist_ok=True)
                im.save(dst, optimize=True)
                print(dst)
        return
    if a.sizes:
        for name, c in CLASSES.items():
            print(f"{name:12} canvas {c['canvas'][0]}x{c['canvas'][1]}  render --resolution {c['frame'][2]}x{c['frame'][3]}")
        return
    caps = json.loads(pathlib.Path(a.captions).read_text(encoding="utf-8"))
    out = pathlib.Path(a.out)
    for name in a.classes.split(","):
        c = CLASSES[name]
        folders = [(c["folder"], None)]
        if "also" in c:
            folders.append(c["also"])
        for i, scene in enumerate(caps["order"], 1):
            if a.raw3d:
                s3, su = (pathlib.Path(a.raw3d) / name / f"{scene}.png", pathlib.Path(a.rawui) / name / f"{scene}.png")
                if not (s3.exists() and su.exists()):
                    print(f"missing {s3} or {su}")
                    continue
                shot = Image.alpha_composite(Image.open(s3).convert("RGBA"), Image.open(su).convert("RGBA"))
            else:
                src = pathlib.Path(a.raw) / name / f"{scene}.png"
                if not src.exists():
                    print(f"missing {src}")
                    continue
                shot = Image.open(src)
            headline, line = caps[scene]
            img = compose(c, shot, headline, line,
                          pathlib.Path(a.headline_font), pathlib.Path(a.line_font))
            for folder, size in folders:
                dst = out / c["store"] / a.lang / folder / f"{i:02d}_{scene}.png"
                dst.parent.mkdir(parents=True, exist_ok=True)
                (img.resize(size, Image.LANCZOS) if size else img).save(dst, optimize=True)
                print(f"{dst}  {(size or img.size)[0]}x{(size or img.size)[1]}")


if __name__ == "__main__":
    main()
