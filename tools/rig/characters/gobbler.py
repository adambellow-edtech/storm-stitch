"""Gobbler: a round feathered turkey with a tail fan behind, a hat on top, wings and bird legs."""
import math
import rig
from rig import P, limb


def manifest(piv):
    return {
        "name": "gobbler",
        "view": "back",
        "parts": [
            limb("foot-l", "foot-plant", [-80, 150], 0.3, -3,
                 {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
            limb("foot-r", "foot-plant-r", [80, 150], 0.3, -3,
                 {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
            limb("arm-l", "arm-hang", [-215, 390], 0.45, -2,
                 {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [215, 390], 0.45, -2,
                 {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
            # The tail fan stands up behind the body.
            {"name": "tail", "image": "tail", "scale": 0.85, "pivot": piv["tail"], "joint": [0, 250], "z": -4},
            # The hat plays the sprout's part: it sways a beat behind the body.
            {"name": "sprout", "image": "hat", "scale": 0.55, "pivot": piv["hat"], "joint": [0, 600], "z": 1},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 105], "z": 0},
        ],
    }


def tail(t, pose):
    # The fan wiggles a beat behind the steps.
    return {"tail": P(deg=3 * math.sin(2 * math.pi * (t - 0.12)))}


def tail_jump(t, pose):
    # It spreads a little wider at the top of a jump.
    up = math.sin(math.pi * t)
    return {"tail": P(sx=1 + 0.06 * up, sy=1 + 0.03 * up)}


def setup():
    rig.configure("gobbler", manifest, extra_run=tail, extra_jump=tail_jump,
                  torso={"body", "arm-l", "arm-r", "sprout", "tail"})
