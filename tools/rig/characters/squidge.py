"""Squidge: an octopus in a paper boat hat. He floats and paddles: two tentacles stroke out at his
sides between curled, reaching, pushing (with a splash) and trailing, the boat rocks on his head,
and the flag flaps between two drawings."""
import math
import rig
from rig import P, limb

FLOAT = 150


def manifest(piv):
    return {
        "name": "squidge",
        "view": "back",
        "parts": [
            # Tentacles use the arm slot: reaching by default, curled, pushing back with a splash, trailing.
            limb("arm-l", "arm-hang", [-160, FLOAT + 140], 0.55, -2,
                 {"fwd": "arm-curl", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [160, FLOAT + 140], 0.55, -2,
                 {"fwd": "arm-curl-r", "back": "arm-back-r", "up": "arm-up-r"}),
            {"name": "sprout", "image": "boat", "scale": 0.72, "pivot": [0.5, 0.12], "joint": [0, FLOAT + 640], "z": 1},
            {"name": "flag", "image": "flag-a", "scale": 0.42, "pivot": piv["flag-a"], "joint": [30, FLOAT + 820], "z": 0.5,
             "parent": "sprout", "variants": {"flap": {"image": "flag-b", "pivot": piv["flag-b"]}}},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, FLOAT], "z": 0},
        ],
    }


def paddle(t, pose):
    b = pose["body"]
    s = math.sin(4 * math.pi * t)
    return {
        "flag": P(deg=4 * s, variant="flap" if s > 0 else None),
        "body": P(dy=b["dy"] * 0.6 + 10 * math.sin(2 * math.pi * t), deg=b["deg"], sx=b["sx"], sy=b["sy"]),
    }


def setup():
    rig.configure("squidge", manifest, extra_run=paddle, extra_jump=paddle,
                  torso={"body", "arm-l", "arm-r", "sprout"})
