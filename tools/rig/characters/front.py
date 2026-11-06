"""Front-facing rig for the results card: an armless body (with a blink drawing) and two arms that
swap between rest, wave, cheer and slump. Same for every monster; only the joint numbers change."""
import math
import rig
from rig import P, smooth

# Per monster: arm joints (x from center, y from the ground, rig units) and arm scale.
SETUPS = {
    "bramble": {"arm": [-235, 455], "scale": 0.55},
    "fizz": {"arm": [-215, 330], "scale": 0.5},
    # Wings go in front: his tail fan fills the space behind him.
    "gobbler": {"arm": [-190, 330], "scale": 0.5, "z": 1},
    "comet": {"arm": [-205, 420], "scale": 0.55, "z": 1},
    "corrugo": {"arm": [-215, 410], "scale": 0.5},
    "wickling": {"arm": [-170, 440], "scale": 0.45},
    "squidge": {"arm": [-175, 330], "scale": 0.55},
    "crumple": {"arm": [-220, 390], "scale": 0.5},
}


def manifest_for(name):
    cfg = SETUPS[name]
    x, y = cfg["arm"]

    def manifest(piv):
        def arm(side, suffix):
            return {"name": f"arm-{side}", "image": f"arm-rest{suffix}", "scale": cfg["scale"],
                    "pivot": piv[f"arm-rest{suffix}"], "joint": [x if side == "l" else -x, y], "z": cfg.get("z", -1),
                    "variants": {v: {"image": f"arm-{v}{suffix}", "pivot": piv[f"arm-{v}{suffix}"]}
                                 for v in ("wave", "cheer", "slump")}}
        return {"name": f"{name}-front", "view": "front", "parts": [
            arm("l", ""), arm("r", "-r"),
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 0], "z": 0,
             "variants": {"blink": {"image": "body-blink", "pivot": [0.5, 0.0]}}},
        ]}
    return manifest


def idle(t):
    """Standing and breathing; the right arm waves in the middle of the loop, and he blinks."""
    breathe = math.sin(2 * math.pi * t)
    wave = smooth(0.3, 0.38, t) * (1 - smooth(0.72, 0.8, t))
    blink = "blink" if 0.9 < t < 0.94 else None
    return {
        "arm-l": P(deg=3 * breathe),
        "arm-r": P(deg=-3 * breathe + 18 * wave * math.sin(2 * math.pi * t * 6), variant="wave" if wave > 0.5 else None),
        "body": P(sx=1 - 0.01 * breathe, sy=1 + 0.015 * breathe, variant=blink),
    }


def cheer(t):
    """Won: two hops with both fists pumping."""
    hop = abs(math.sin(2 * math.pi * t))
    pump = math.sin(4 * math.pi * t)
    land = 1 - smooth(0, 0.12, hop)
    return {
        "arm-l": P(deg=10 * pump, variant="cheer"),
        "arm-r": P(deg=-10 * pump, variant="cheer"),
        "body": P(dy=70 * hop, sx=1 + 0.06 * land - 0.03 * hop, sy=1 - 0.08 * land + 0.05 * hop),
    }


def slump(t):
    """Caught by the storm: arms hang limp, the body sags and sways, eyes squeeze shut now and then."""
    sway = math.sin(2 * math.pi * t)
    return {
        "arm-l": P(deg=4 * sway, variant="slump"),
        "arm-r": P(deg=4 * sway, variant="slump"),
        "body": P(deg=3 * sway, sx=1.04, sy=0.93, variant="blink" if t > 0.5 else None),
    }


def setup(name):
    rig.configure(f"{name}-front", manifest_for(name), torso={"body", "arm-l", "arm-r"})


def preview(name, out_dir="out", size=(380, 450)):
    from PIL import Image
    setup(name)
    images = rig.load_images()
    frames = []
    for pose_fn, steps in [(idle, 60), (cheer, 36), (cheer, 36), (slump, 40)]:
        frames += [rig.render(images, pose_fn(i / steps)) for i in range(steps)]
    small = [f.convert("RGB").resize(size, Image.LANCZOS) for f in frames]
    small[0].save(f"{out_dir}/{name}-front-preview.gif", save_all=True, append_images=small[1:], duration=33, loop=0)
    keys = [idle(0.0), idle(0.55), cheer(0.25), slump(0.2)]
    sheet = Image.new("RGB", (size[0] * 4, size[1]), (255, 255, 255))
    for i, k in enumerate(keys):
        sheet.paste(rig.render(images, k).convert("RGB").resize(size, Image.LANCZOS), (size[0] * i, 0))
    sheet.save(f"{out_dir}/{name}-front-keys.png")
