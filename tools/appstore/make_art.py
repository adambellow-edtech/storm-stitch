"""Storm Stitch App Store art.

Usage:
  python3 tools/appstore/make_art.py                 # promo banner, social card, sample screenshots
  python3 tools/appstore/make_art.py shots/*.png     # frame your real screenshots with captions

Real screenshots: capture them on an iPhone 16/17 Pro Max (or that Simulator, Cmd+S) so they are
1320x2868 or 1290x2796. Name them 1.png ... 6.png in the order of CAPTIONS below.
Output goes to tools/appstore/out/.
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ART = os.path.join(ROOT, "StormStitch", "Art")
FONTS = os.path.join(ROOT, "StormStitch", "Fonts")
OUT = os.path.join(ROOT, "tools", "appstore", "out")

INK = (43, 35, 64)
GOLD = (244, 184, 28)
CREAM = (251, 244, 228)
SKY = (124, 196, 239)
STORM = (74, 69, 96)

# Order matters: the first three show in App Store search results.
CAPTIONS = [
    ("Outrun the storm", "Swipe, jump and slide through a paper world"),
    ("Stitch the color back", "Every golden spool sews a torn page together"),
    ("Unlock paper monsters", "Each one runs a different way"),
    ("Rewind time", "Earn gadgets like the Time Machine"),
    ("One Daily Storm for all", "Same course, one shot, dare your friends"),
    ("Sew the seam shut", "Finish every stage with a burst of color"),
]


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def art(name):
    return Image.open(os.path.join(ART, name + ".png")).convert("RGBA")


def fit_width(im, width):
    return im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)


def fit_height(im, height):
    return im.resize((round(im.width * height / im.height), height), Image.LANCZOS)


def cover(im, size):
    w, h = size
    scale = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    left, top = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((left, top, left + w, top + h))


def outlined_text(draw, xy, text, fnt, fill, outline=INK, stroke=None, anchor="la", shadow=True):
    stroke = stroke or max(4, fnt.size // 9)
    x, y = xy
    if shadow:
        draw.text((x, y + stroke * 1.4), text, font=fnt, fill=INK, stroke_width=stroke, stroke_fill=INK, anchor=anchor)
    draw.text((x, y), text, font=fnt, fill=fill, stroke_width=stroke, stroke_fill=outline, anchor=anchor)


def logo(width):
    """The STORM STITCH wordmark drawn in Fredoka, cream and gold with an ink outline."""
    size = round(width / 5.2)
    fnt = font("Fredoka-Bold.ttf", size)
    pad = size // 3
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    w1 = probe.textlength("STORM ", font=fnt)
    w2 = probe.textlength("STITCH", font=fnt)
    canvas = Image.new("RGBA", (round(w1 + w2 + pad * 2), round(size * 1.75 + pad)), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    outlined_text(d, (pad, pad // 2), "STORM ", fnt, CREAM)
    outlined_text(d, (pad + w1, pad // 2), "STITCH", fnt, GOLD)
    # Stitch marks under the word.
    y = pad // 2 + size * 1.32
    xs = canvas.width / 2
    for i in range(-3, 4):
        cx = xs + i * size * 0.32
        r = size * 0.1
        for a, b in (((cx - r, y - r), (cx + r, y + r)), ((cx - r, y + r), (cx + r, y - r))):
            d.line([a, b], fill=INK, width=max(6, size // 9))
            d.line([a, b], fill=GOLD, width=max(3, size // 16))
    return canvas.resize((width, round(canvas.height * width / canvas.width)), Image.LANCZOS)


def drop_shadow(im, offset=(0, 18), blur=24, alpha=110):
    shadow = Image.new("RGBA", (im.width + blur * 4, im.height + blur * 4), (0, 0, 0, 0))
    mask = im.split()[3].point(lambda a: a * alpha // 255)
    shadow.paste((0, 0, 0, 255), (blur * 2, blur * 2), mask)
    return shadow.filter(ImageFilter.GaussianBlur(blur)), (offset[0] - blur * 2, offset[1] - blur * 2)


def paste_with_shadow(base, im, xy, **kw):
    sh, (dx, dy) = drop_shadow(im, **kw)
    base.alpha_composite(sh, (xy[0] + dx, xy[1] + dy))
    base.alpha_composite(im, xy)


def torn_banner(size):
    """Gray shredded world on the left, stitched color on the right, gold seam between."""
    w, h = size
    gray = cover(art("backdrop-gray"), (w, h))
    color = cover(art("backdrop-color"), (w, h))
    base = gray.copy()
    mask = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(mask)
    seam = []
    for i in range(0, 25):
        y = h * i / 24
        x = w * 0.5 + (i % 2 * 2 - 1) * w * 0.012 + (y / h - 0.5) * w * 0.12
        seam.append((x, y))
    md.polygon(seam + [(w, h), (w, 0)], fill=255)
    base.paste(color, (0, 0), mask)
    d = ImageDraw.Draw(base)
    d.line(seam, fill=INK, width=max(10, w // 150))
    d.line(seam, fill=GOLD, width=max(6, w // 260))
    return base, seam


def promo_banner(size, name):
    w, h = size
    base, seam = torn_banner(size)
    storm = fit_height(art("storm-wall"), round(h * 0.62))
    fade = Image.linear_gradient("L").resize(storm.size).transpose(Image.FLIP_TOP_BOTTOM)
    fade = fade.point(lambda v: min(255, v * 3))
    alpha = storm.split()[3]
    storm.putalpha(Image.composite(alpha, Image.new("L", storm.size, 0), fade))
    base.alpha_composite(storm, (round(-storm.width * 0.35), round(h * 0.02)))
    hero = fit_height(art("bramble-win"), round(h * 0.78))
    paste_with_shadow(base, hero, (round(w * 0.56), h - hero.height - round(h * 0.03)))
    mark = logo(round(min(w * 0.5, h * 1.25)))
    base.alpha_composite(mark, (round(w * 0.04), round(h * 0.08)))
    tag = font("Fredoka-Bold.ttf", round(h * 0.06))
    d = ImageDraw.Draw(base)
    outlined_text(d, (round(w * 0.06), round(h * 0.08) + mark.height + round(h * 0.03)),
                  "Outrun the storm. Stitch the world.", tag, (255, 255, 255))
    base.convert("RGB").save(os.path.join(OUT, name), quality=92)


def caption_frame(shot, title, sub, size=(1320, 2868), index=0):
    """A store screenshot: caption on a paper strip, the real screen in a rounded frame below."""
    w, h = size
    bg_colors = [SKY, (108, 198, 111), (178, 132, 230), STORM, (74, 69, 96), (244, 184, 28)]
    base = Image.new("RGBA", size, bg_colors[index % len(bg_colors)] + (255,))
    # Soft paper clouds.
    d = ImageDraw.Draw(base)
    for cx, cy, r in ((0.1, 0.035, 0.16), (0.92, 0.05, 0.18)):
        d.ellipse([w * (cx - r), h * cy - w * r * 0.45, w * (cx + r), h * cy + w * r * 0.45], fill=(255, 255, 255, 50))
    title_font = font("Fredoka-Bold.ttf", 118)
    sub_font = font("NunitoSans-ExtraBold.ttf", 46)
    outlined_text(d, (w // 2, 230), title, title_font, (255, 255, 255), anchor="mm", stroke=10)
    d.text((w // 2, 370), sub, font=sub_font, fill=(255, 255, 255), anchor="mm",
           stroke_width=3, stroke_fill=INK)
    # Screen.
    sw = round(w * 0.78)
    screen = cover(shot.convert("RGBA"), (sw, round(sw * 2868 / 1320)))
    radius = round(sw * 0.11)
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, screen.width - 1, screen.height - 1], radius, fill=255)
    framed = Image.new("RGBA", (screen.width + 40, screen.height + 40), (0, 0, 0, 0))
    ImageDraw.Draw(framed).rounded_rectangle([0, 0, framed.width - 1, framed.height - 1], radius + 20, fill=INK)
    framed.paste(screen, (20, 20), mask)
    paste_with_shadow(base, framed, ((w - framed.width) // 2, 480), blur=30, alpha=120)
    return base.convert("RGB")


def main():
    os.makedirs(OUT, exist_ok=True)
    shots = sys.argv[1:]
    if shots:
        for i, path in enumerate(sorted(shots)[:len(CAPTIONS)]):
            title, sub = CAPTIONS[i]
            caption_frame(Image.open(path), title, sub, index=i).save(os.path.join(OUT, f"screenshot-{i + 1}.png"))
        print("Framed", min(len(shots), len(CAPTIONS)), "screenshots into", OUT)
        return
    promo_banner((1920, 1080), "promo-banner-1920x1080.jpg")
    promo_banner((1200, 630), "social-card-1200x630.jpg")
    promo_banner((3840, 2160), "featuring-art-3840x2160.jpg")
    sample = art("title-card")
    caption_frame(sample, *CAPTIONS[0], index=0).save(os.path.join(OUT, "sample-screenshot-layout.png"))
    print("Wrote promo art to", OUT)


if __name__ == "__main__":
    main()
