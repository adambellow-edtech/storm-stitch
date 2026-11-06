"""Fixes for arm drawings ChatGPT drew mirrored (hand at top right): flip them so the hand points
outward, and put the pivot at the shoulder end, which is then at the bottom right."""
import json, sys
import numpy as np
from PIL import Image


def bottom_end_pivot(im, frac=0.18):
    a = np.array(im)[..., 3] > 128
    ys, xs = np.where(a)
    y0 = ys.max() - (ys.max() - ys.min()) * frac
    sel = ys >= y0
    cx, cy = xs[sel].mean(), ys[sel].mean()
    mx, my = xs.mean(), ys.mean()
    jx, jy = cx + (mx - cx) * 0.1, cy + (my - cy) * 0.1
    return [round(float(jx) / im.width, 4), round(1 - float(jy) / im.height, 4)]


def flip_raised(name, poses, flip=True):
    d = f"{name}-front"
    piv = json.load(open(f"{d}/pivots.json"))
    for p in poses:
        im = Image.open(f"{d}/arm-{p}.png")
        if flip:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
            im.save(f"{d}/arm-{p}.png")
            im.transpose(Image.FLIP_LEFT_RIGHT).save(f"{d}/arm-{p}-r.png")
        v = bottom_end_pivot(im)
        piv[f"arm-{p}"] = v
        piv[f"arm-{p}-r"] = [round(1 - v[0], 4), v[1]]
    json.dump(piv, open(f"{d}/pivots.json", "w"), indent=1)


if __name__ == "__main__":
    flip_raised(sys.argv[1], sys.argv[2].split(","), flip=(len(sys.argv) < 4 or sys.argv[3] != "noflip"))
