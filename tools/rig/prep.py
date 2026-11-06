"""Cuts a character's ChatGPT sheets into rig parts with joints, mirrored right-side copies and a check image.

    prep("gobbler", body=("gobbler-body.png", {"body": "base", "tail": "base", "hat": "base"}),
         arms="gobbler-wings.png", feet="gobbler-feet.png")

Body-sheet parts are named left to right with how to find their joint:
"base" (bottom center), "center", or "top" (top center). Arm rows are hang, fwd, back, up with the
joint at the shoulder end; foot rows are plant, push, kick, pass with the joint at the leg top.
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw

import cut

SRC = "/mnt/user-data/uploads/Downloads/"


def shoulder_end(im):
    """The end of an arm furthest up and to the right; the joint sits a little inside it."""
    a = np.array(im)[..., 3] > 128
    ys, xs = np.where(a)
    k = np.argsort(xs - ys)[-200:]
    ex, ey = xs[k].mean(), ys[k].mean()
    cx, cy = xs.mean(), ys.mean()
    jx, jy = ex + (cx - ex) * 0.18, ey + (cy - ey) * 0.18
    return [round(float(jx) / im.width, 4), round(1 - float(jy) / im.height, 4)]


def by_rule(im, rule):
    a = np.array(im)[..., 3] > 128
    ys, xs = np.where(a)
    if rule == "center":
        return [0.5, 0.5]
    if rule == "top":
        top = ys.min()
        return [round(float(xs[ys < top + 8].mean()) / im.width, 4), round(1 - (top + 4) / im.height, 4)]
    bot = ys.max()
    return [round(float(xs[ys > bot - 8].mean()) / im.width, 4), round(1 - (bot - 4) / im.height, 4)]


def prep(name, body, arms=None, feet=None, arm_names=("arm-hang", "arm-fwd", "arm-back", "arm-up"),
         foot_names=("foot-plant", "foot-push", "foot-kick", "foot-pass"), join=40, out_dir=None):
    out = out_dir or name
    os.makedirs(out, exist_ok=True)
    piv = {}
    sheet, rules = body
    parts = cut.split(SRC + sheet, join=join)
    if len(parts) != len(rules):
        raise ValueError(f"{sheet}: found {len(parts)} parts, expected {len(rules)} ({list(rules)})")
    for (im, _), (n, rule) in zip(parts, rules.items()):
        im.save(f"{out}/{n}.png")
        piv[n] = [0.5, 0.0] if n == "body" else by_rule(im, rule)
    for sheet, names, finder in [(arms, arm_names, shoulder_end), (feet, foot_names, cut.leg_top_pivot)]:
        if not sheet:
            continue
        row = cut.split(SRC + sheet, join=12)
        if len(row) != len(names):
            raise ValueError(f"{sheet}: found {len(row)} drawings, expected {len(names)}")
        for (im, _), n in zip(row, names):
            im.save(f"{out}/{n}.png")
            p = finder(im)
            piv[n] = [round(float(p[0]), 4), round(float(p[1]), 4)]
            im.transpose(Image.FLIP_LEFT_RIGHT).save(f"{out}/{n}-r.png")
            piv[n + "-r"] = [round(1 - piv[n][0], 4), piv[n][1]]
    with open(f"{out}/pivots.json", "w") as f:
        json.dump(piv, f, indent=1)
    # A check image: every part with its joint circled.
    names = [n for n in piv if not n.endswith("-r")]
    ims = [Image.open(f"{out}/{n}.png") for n in names]
    H = max(i.height for i in ims)
    W = sum(i.width for i in ims) + 20 * len(ims)
    s = Image.new("RGBA", (W, H), (243, 236, 222, 255))
    d = ImageDraw.Draw(s)
    x = 0
    for n, i in zip(names, ims):
        s.alpha_composite(i, (x, 0))
        px, py = x + piv[n][0] * i.width, (1 - piv[n][1]) * i.height
        d.ellipse([px - 12, py - 12, px + 12, py + 12], outline=(0, 90, 255, 255), width=6)
        x += i.width + 20
    s.resize((W * 2 // 5, H * 2 // 5)).save(f"out/{name}_pivots.png")
    return {n: Image.open(f"{out}/{n}.png").size for n in names}
