"""Fizz: two legs, a fuse on his head with a spark that flickers at its tip."""
import math
import rig
from rig import P, limb


def manifest(piv):
    fuse_h = 490 * 0.5  # fuse drawing height at its rig scale
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
            {"name": "sprout", "image": "fuse", "scale": 0.5, "pivot": piv["fuse"], "joint": [-30, 790], "z": -1},
            # The spark rides the fuse's tip.
            {"name": "spark", "image": "spark", "scale": 0.32, "pivot": piv["spark"],
             "joint": [-30 + (0.62 - piv["fuse"][0]) * 267 * 0.5, 790 + fuse_h * 0.86], "z": 1, "parent": "sprout"},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 105], "z": 0},
        ],
    }


def spark(t, pose):
    # Flickers: a quick pulse and spin, faster than the steps.
    pulse = 0.5 + 0.5 * math.sin(2 * math.pi * t * 3)
    return {"spark": P(deg=40 * math.sin(2 * math.pi * t * 2), sx=0.75 + 0.4 * pulse, sy=0.75 + 0.4 * pulse)}


def setup():
    rig.configure("fizz", manifest, extra_run=spark, extra_jump=spark)
