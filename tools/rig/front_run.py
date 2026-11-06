"""One-shot front rig for a monster: cut the sheets, center the body, preview and show a contact sheet.

    python3 front_run.py gobbler            # cut + contact sheet of the parts
    python3 front_run.py gobbler preview    # after adding SETUPS, render keys + GIF
    python3 front_run.py gobbler export
"""
import sys, json
sys.path.insert(0, "characters")
import numpy as np
from PIL import Image, ImageDraw
import front_prep

name = sys.argv[1]
step = sys.argv[2] if len(sys.argv) > 2 else "cut"
D = f"{name}-front"


def center_body(band=(0.45, 0.7)):
    """Pad the body drawings so the widest part of the torso band sits at the image center."""
    for f in ("body", "body-blink"):
        im = Image.open(f"{D}/{f}.png")
        a = np.array(im)[..., 3] > 128
        rows = a[int(im.height * band[0]):int(im.height * band[1])]
        cols = np.where(rows.any(0))[0]
        c = (cols.min() + cols.max()) / 2
        pad = int(round(im.width - 2 * c))
        new = Image.new("RGBA", (im.width + abs(pad), im.height))
        new.paste(im, (max(pad, 0), 0))
        new.save(f"{D}/{f}.png")
        print(f, "half width", (cols.max() - cols.min()) / 2, "size", new.size)


if step == "cut":
    print(front_prep.front_prep(name, floor=int(sys.argv[3]) if len(sys.argv) > 3 else None))
    center_body()
    body = Image.open(f"{D}/body.png")
    names = ["body-blink", "arm-rest", "arm-wave", "arm-cheer", "arm-slump"]
    ims = [body] + [Image.open(f"{D}/{n}.png") for n in names]
    piv = json.load(open(f"{D}/pivots.json"))
    W = sum(i.width for i in ims) + 20 * len(ims)
    H = max(i.height for i in ims)
    sheet = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(sheet)
    x = 0
    for n, im in zip(["body"] + names, ims):
        sheet.paste(im, (x, 0), im)
        if n.startswith("arm"):
            px, py = piv[n]
            cx, cy = x + px * im.width, (1 - py) * im.height
            d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], outline="blue", width=4)
        else:
            for yy in range(0, im.height, 100):
                d.line([x, yy, x + 25, yy], fill="red", width=2)
                d.text((x + 28, yy - 6), str(im.height - yy), fill="red")
            d.line([x + im.width / 2, 0, x + im.width / 2, im.height], fill="red")
        x += im.width + 20
    sheet.thumbnail((2000, 700))
    sheet.save(f"out/{name}-front-parts.png")
elif step == "preview":
    import front
    front.preview(name)
elif step == "export":
    import front, rig
    front.setup(name)
    rig.export("/home/claude/storm-stitch/StormStitch/Art")
