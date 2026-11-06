"""Fizz: two legs, a fuse growing from his lower back with a spark that flickers at its tip."""
import math
import rig
from rig import P, limb


# The fuse grows out of his lower back on the left, like a tail, and leans out past his arm,
# the way the painting has it. The drawing is tilted once here, since parts have no resting angle.
FUSE_JOINT = [-250, 300]
FUSE_TILT = 32  # degrees, top leaning out to the left
FUSE_SCALE = 0.68


def tilt_fuse(piv):
    """Writes fuse-tilt.png and returns its pivot (at the rope's base) and the spark's offset from it."""
    import math
    from PIL import Image
    im = Image.open("fizz/fuse.png")
    w, h = im.size
    base = (piv["fuse"][0] * w, (1 - piv["fuse"][1]) * h)
    tip = (0.62 * w, h * (1 - 0.86))
    out = im.rotate(FUSE_TILT, resample=Image.BICUBIC, expand=True)
    W, H = out.size
    a = math.radians(FUSE_TILT)

    def move(pt):
        x, y = pt[0] - w / 2, pt[1] - h / 2
        # PIL turns counterclockwise on screen (y down).
        return (x * math.cos(a) + y * math.sin(a) + W / 2, -x * math.sin(a) + y * math.cos(a) + H / 2)

    b, t = move(base), move(tip)
    out.save("fizz/fuse-tilt.png")
    pivot = [round(b[0] / W, 4), round(1 - b[1] / H, 4)]
    return pivot, ((t[0] - b[0]) * FUSE_SCALE, (b[1] - t[1]) * FUSE_SCALE)


def manifest(piv):
    fuse_pivot, (sx, sy) = tilt_fuse(piv)
    return {
        "name": "fizz",
        "view": "back",
        "parts": [
            limb("foot-l", "foot-plant", [-70, 158], 0.36, -3,
                 {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
            limb("foot-r", "foot-plant-r", [70, 158], 0.36, -3,
                 {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
            limb("arm-l", "arm-hang", [-205, 430], 0.42, -2,
                 {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [205, 430], 0.42, -2,
                 {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
            # The fuse plays the sprout's part: it sways a beat behind the body.
            {"name": "sprout", "image": "fuse-tilt", "scale": FUSE_SCALE, "pivot": fuse_pivot, "joint": FUSE_JOINT, "z": -3},
            # The spark rides the fuse's tip.
            {"name": "spark", "image": "spark", "scale": 0.32, "pivot": piv["spark"],
             "joint": [FUSE_JOINT[0] + sx, FUSE_JOINT[1] + sy], "z": 1, "parent": "sprout"},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 105], "z": 0},
        ],
    }


def spark(t, pose):
    # Flickers: a quick pulse and spin, faster than the steps.
    pulse = 0.5 + 0.5 * math.sin(2 * math.pi * t * 3)
    return {"spark": P(deg=40 * math.sin(2 * math.pi * t * 2), sx=0.75 + 0.4 * pulse, sy=0.75 + 0.4 * pulse)}


def setup():
    rig.configure("fizz", manifest, extra_run=spark, extra_jump=spark)
