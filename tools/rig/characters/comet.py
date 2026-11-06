"""Comet: a fluffy reindeer with jingle-bell antlers, a flapping scarf end, hoofed arms and legs."""
import math
import rig
from rig import P, limb


def manifest(piv):
    return {
        "name": "comet",
        "view": "back",
        "parts": [
            limb("foot-l", "foot-plant", [-66, 205], 0.36, -3,
                 {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
            limb("foot-r", "foot-plant-r", [66, 205], 0.36, -3,
                 {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
            limb("arm-l", "arm-hang", [-195, 500], 0.42, -2,
                 {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [195, 500], 0.42, -2,
                 {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
            # Antlers sit on top of his head, behind the top of the fur.
            {"name": "antlers", "image": "antlers", "scale": 0.85, "pivot": [0.5, 0.3], "joint": [0, 770], "z": -1},
            # The loose scarf end flies out from his left side, flapping between two drawings.
            {"name": "scarf", "image": "scarf-a", "scale": 0.6, "pivot": piv["scarf-a"], "joint": [-150, 470], "z": 1,
             "variants": {"flap": {"image": "scarf-b", "pivot": piv["scarf-b"]}}},
            # No tuft: the sprout slot stays empty.
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 130], "z": 0},
        ],
    }


def extras(t, pose):
    return {
        # Antlers rock a beat behind the body, the bells along with them.
        "antlers": P(deg=-4 * math.cos(2 * math.pi * (t - 0.09 - 0.15))),
        # The scarf flaps twice a cycle, swinging a little as it goes.
        "scarf": P(deg=8 * math.sin(4 * math.pi * t), variant="flap" if math.sin(4 * math.pi * t) > 0 else None),
    }


def setup():
    rig.configure("comet", manifest, extra_run=extras, extra_jump=extras,
                  torso={"body", "arm-l", "arm-r", "antlers", "scarf"})
