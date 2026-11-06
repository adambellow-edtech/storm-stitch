"""Crumple: a shaggy paper yeti with horns, a flapping red scarf end, blue boots."""
import math
import rig
from rig import P, limb


def manifest(piv):
    return {
        "name": "crumple",
        "view": "back",
        "parts": [
            limb("foot-l", "foot-plant", [-68, 192], 0.34, -3,
                 {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
            limb("foot-r", "foot-plant-r", [68, 192], 0.34, -3,
                 {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
            limb("arm-l", "arm-hang", [-190, 470], 0.42, -2,
                 {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [190, 470], 0.42, -2,
                 {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
            # The loose scarf end flies out from his left side, flapping between two drawings.
            {"name": "scarf", "image": "scarf-a", "scale": 0.55, "pivot": piv["scarf-a"], "joint": [-150, 505], "z": 1,
             "variants": {"flap": {"image": "scarf-b", "pivot": piv["scarf-b"]}}},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 120], "z": 0},
        ],
    }


def extras(t, pose):
    return {"scarf": P(deg=8 * math.sin(4 * math.pi * t), variant="flap" if math.sin(4 * math.pi * t) > 0 else None)}


def setup():
    rig.configure("crumple", manifest, extra_run=extras, extra_jump=extras,
                  torso={"body", "arm-l", "arm-r", "scarf"})
