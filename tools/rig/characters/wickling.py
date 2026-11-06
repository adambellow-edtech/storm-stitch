"""Wickling: a floating paper lantern. No legs: he hovers and bobs, his flame sleeves flutter
(using the arm slot), the lid tips a beat behind, and the tassel swings underneath like a pendulum."""
import math
import rig
from rig import P, limb

FLOAT = 230


def manifest(piv):
    return {
        "name": "wickling",
        "view": "back",
        "parts": [
            limb("arm-l", "arm-hang", [-300, FLOAT + 300], 0.48, -2,
                 {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [300, FLOAT + 300], 0.48, -2,
                 {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
            {"name": "sprout", "image": "lid", "scale": 0.62, "pivot": [0.5, 0.12], "joint": [0, FLOAT + 650], "z": 1},
            {"name": "tassel", "image": "tassel", "scale": 0.42, "pivot": piv["tassel"], "joint": [0, FLOAT + 45], "z": -1},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, FLOAT], "z": 0},
        ],
    }


def hover(t, pose):
    # A slow float on top of the run bounce, and the tassel swinging a beat behind.
    float_up = 14 * math.sin(2 * math.pi * t)
    out = {"tassel": P(deg=10 * math.sin(2 * math.pi * (t - 0.15)))}
    b = pose["body"]
    out["body"] = P(dy=b["dy"] * 0.5 + float_up, deg=b["deg"], sx=b["sx"], sy=b["sy"])
    return out


def setup():
    rig.configure("wickling", manifest, extra_run=hover, extra_jump=hover,
                  torso={"body", "arm-l", "arm-r", "sprout", "tassel"})
