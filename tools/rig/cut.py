"""Cuts a ChatGPT parts row into clean, separate PNGs.

ChatGPT's "transparent" sheets have interiors at about 99% opacity and a faint haze around each part.
This makes interiors solid, drops the haze, and recolors edge pixels from the solid color next to them
so no dark or colored halo shows in game. Parts come back left to right, with their crop box on the sheet.
"""
import numpy as np
from PIL import Image
from scipy import ndimage


def clean(path):
    src = np.array(Image.open(path).convert("RGBA")).astype(float)
    alpha = np.clip((src[..., 3] - 40) / (220 - 40), 0, 1) * 255
    solid = alpha >= 250
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    rgb = src[..., :3].copy()
    edge = (alpha > 0) & ~solid
    rgb[edge] = src[iy[edge], ix[edge], :3]
    return np.dstack([rgb, alpha]).clip(0, 255).astype(np.uint8)


def split(path, min_area=3000, pad=4, join=6):
    """Returns [(image, (left, top) of the image on the sheet)] left to right."""
    sheet = clean(path)
    labels, _ = ndimage.label(ndimage.binary_dilation(sheet[..., 3] > 0, iterations=join))
    found = []
    for i, box in enumerate(ndimage.find_objects(labels)):
        if (labels[box] == i + 1).sum() < min_area:
            continue
        piece = sheet[box].copy()
        piece[labels[box] != i + 1] = 0
        im = Image.fromarray(piece)
        bx, by, bx2, by2 = im.getbbox()
        im = im.crop((bx, by, bx2, by2))
        canvas = Image.new("RGBA", (im.width + pad * 2, im.height + pad * 2), (0, 0, 0, 0))
        canvas.paste(im, (pad, pad))
        found.append((canvas, (box[1].start + bx - pad, box[0].start + by - pad)))
    found.sort(key=lambda f: f[1][0])
    return found


def leg_top_pivot(im, rows=8):
    """Pivot at the center of a leg's flat top edge, as (x from left, y from bottom) fractions."""
    a = np.array(im)[..., 3] > 128
    top = np.argmax(a.any(axis=1))
    cols = np.where(a[top:top + rows].any(axis=0))[0]
    return [round(float(cols.mean()) / im.width, 4), round(1 - (top + 2) / im.height, 4)]


def shoulder_pivot(im):
    """Pivot at the shoulder: the center of the cream stitched rim, which sits at the top right."""
    px = np.array(im).astype(int)
    r, g, b, a = px[..., 0], px[..., 1], px[..., 2], px[..., 3]
    cream = (a > 200) & (r > 190) & (g > 180) & (b > 130) & (abs(r - g) < 40)
    h, w = cream.shape
    region = np.zeros_like(cream)
    region[: int(h * 0.6), int(w * 0.45):] = True
    ys, xs = np.where(cream & region)
    if len(xs) == 0:
        return [0.8, 0.85]
    # The rim is the outer edge of the shoulder; the joint sits a little inside it.
    cx, cy = xs.mean(), ys.mean()
    body = np.array(np.where(a > 200))
    mx, my = body[1].mean(), body[0].mean()
    jx, jy = cx + (mx - cx) * 0.12, cy + (my - cy) * 0.12
    return [round(float(jx) / w, 4), round(1 - float(jy) / h, 4)]
