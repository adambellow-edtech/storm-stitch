import cut, prep, json, os
from PIL import Image


def front_prep(name, join=12):
    """Cuts <name>-front-sheet-body.png (body, body blinking) and <name>-front-sheet-arms.png
    (rest, wave, cheer, slump) into <name>-front/ with joints and mirrored right arms."""
    out = f"{name}-front"
    os.makedirs(out, exist_ok=True)
    body = cut.split(prep.SRC + f"{name}-front-sheet-body.png", join=join)
    arms = cut.split(prep.SRC + f"{name}-front-sheet-arms.png", join=12)
    if len(body) < 2 or len(arms) != 4:
        raise ValueError(f"{name}: body sheet has {len(body)} parts, arm sheet {len(arms)}")
    piv = {}
    for (im, _), n in zip(body[:2], ["body", "body-blink"]):
        im.save(f"{out}/{n}.png")
        piv[n] = [0.5, 0.0]
    for (im, _), n in zip(arms, ["arm-rest", "arm-wave", "arm-cheer", "arm-slump"]):
        im.save(f"{out}/{n}.png")
        p = prep.shoulder_end(im)
        piv[n] = p
        im.transpose(Image.FLIP_LEFT_RIGHT).save(f"{out}/{n}-r.png")
        piv[n + "-r"] = [round(1 - p[0], 4), p[1]]
    with open(f"{out}/pivots.json", "w") as f:
        json.dump(piv, f, indent=1)
    return {n: Image.open(f"{out}/{n}.png").size for n in piv if not n.endswith("-r")}
