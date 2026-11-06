"""Corrugo: a taped cardboard-box robot. Stiff and blocky, so his steps stomp and his flaps flop."""
import math
import rig
from rig import P, limb


def manifest(piv):
    return {
        "name": "corrugo",
        "view": "back",
        "parts": [
            limb("foot-l", "foot-plant", [-75, 175], 0.32, -3,
                 {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
            limb("foot-r", "foot-plant-r", [75, 175], 0.32, -3,
                 {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
            limb("arm-l", "arm-hang", [-215, 560], 0.42, -2,
                 {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [215, 560], 0.42, -2,
                 {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
            # The open box flaps play the sprout's part, flopping a beat behind his steps.
            {"name": "sprout", "image": "flaps", "scale": 0.62, "pivot": [0.5, 0.2], "joint": [0, 835], "z": -1},
            {"name": "body", "image": "body", "scale": 0.95, "pivot": [0.5, 0.0], "joint": [0, 120], "z": 0},
        ],
    }


def setup():
    rig.configure("corrugo", manifest)
