#!/usr/bin/env python3
"""Generate the Surrealism DMG background as a HiDPI .tiff (crisp + correctly sized).

The DMG window is 660x420 POINTS. Finder renders the background 1:1 by pixel, so
the image must be 660x420 at 1x; we also render 1320x840 at 2x and combine both
into a HiDPI .tiff (via tiffutil) so it stays sharp on retina without cropping.

Layout is tuned around the icon slots create-dmg places at (points):
  app  = (175, 205)   applications = (485, 205)   icon size 120
so the wordmark sits ABOVE the icons, the arrow BETWEEN them, instruction BELOW.

Output: scripts/assets/dmg-background.tiff
Run:    python3 scripts/make-dmg-background.py
"""
import os, subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ASSETS = os.path.join(os.path.dirname(__file__), "assets")
TIFF = os.path.join(ASSETS, "dmg-background.tiff")

BG_TOP = (13, 10, 24)
BG_BOT = (5, 3, 8)
IRIS_VIOLET = (139, 92, 246)
IRIS_CYAN = (34, 211, 238)
TEXT = (246, 244, 255)
MUTED = (153, 144, 186)
LILAC = (196, 181, 253)


def font(size, bold=False):
    for p in ["/System/Library/Fonts/SFNS.ttf",
              "/System/Library/Fonts/HelveticaNeue.ttc",
              "/System/Library/Fonts/Helvetica.ttc",
              ("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold
               else "/System/Library/Fonts/Supplemental/Arial.ttf")]:
        if os.path.exists(p):
            try: return ImageFont.truetype(p, size)
            except Exception: continue
    return ImageFont.load_default()


def centered(d, cx, y, text, fnt, fill, spacing=0):
    ws = [d.textlength(c, font=fnt) for c in text]
    total = sum(ws) + spacing * (len(text) - 1)
    x = cx - total / 2
    for c, w in zip(text, ws):
        d.text((x, y), c, font=fnt, fill=fill)
        x += w + spacing


def render(s):
    """Render at scale s (1 or 2). Coordinates below are in POINTS × s."""
    W, H = 660 * s, 420 * s
    # vertical gradient
    col = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        col.putpixel((0, y), tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3)))
    img = col.resize((W, H)).convert("RGBA")

    # soft iridescent glow (kept low + central so it never fights the icons)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.20, H * 0.28, W * 0.80, H * 0.92], fill=(*IRIS_VIOLET, 46))
    gd.ellipse([W * 0.58, H * 0.34, W * 0.96, H * 0.86], fill=(*IRIS_CYAN, 26))
    glow = glow.filter(ImageFilter.GaussianBlur(70 * s))
    img = Image.alpha_composite(img, glow)

    d = ImageDraw.Draw(img, "RGBA")
    cx = W / 2
    # wordmark (top, clear of the icon band which is y≈145–265pt)
    centered(d, cx, 30 * s, "SURREALISM", font(22 * s, bold=True), TEXT, spacing=6 * s)
    centered(d, cx, 66 * s, "Video Screensaver for macOS", font(12 * s), MUTED)
    # arrow between the icons (gap ≈ 235–425pt) at icon-center height (205pt)
    ay = 205 * s
    x0, x1 = 250 * s, 410 * s
    d.line([(x0, ay), (x1 - 12 * s, ay)], fill=(*LILAC, 235), width=max(1, int(3.5 * s)))
    d.polygon([(x1, ay), (x1 - 14 * s, ay - 9 * s), (x1 - 14 * s, ay + 9 * s)], fill=(*LILAC, 235))
    # instruction (below the icon labels ≈277pt)
    centered(d, cx, 332 * s, "Drag Surrealism onto Applications to install.", font(14 * s, bold=True), TEXT)
    return img.convert("RGB")


os.makedirs(ASSETS, exist_ok=True)
p1 = os.path.join(ASSETS, "dmg-bg-1x.png")
p2 = os.path.join(ASSETS, "dmg-bg-2x.png")
render(1).save(p1, "PNG")
render(2).save(p2, "PNG")
# Combine into a HiDPI tiff Finder reads correctly (1x sizing, 2x sharpness).
subprocess.run(["tiffutil", "-cathidpicheck", p1, p2, "-out", TIFF], check=True)
print("wrote", TIFF)
