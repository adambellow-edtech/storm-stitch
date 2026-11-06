"""Origo: an origami dragon. Runs on two folded legs while his wings flap twice a cycle, and spreads
them into a glide when he jumps (his power is a slow, gliding fall)."""
import math
import rig
from rig import P, limb


def manifest(piv):
    return {
        "name": "origo",
        "view": "back",
        "parts": [
            limb("foot-l", "foot-plant", [-55, 195], 0.36, -3,
                 {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
            limb("foot-r", "foot-plant-r", [55, 195], 0.36, -3,
                 {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
            limb("wing-l", "wing-level", [-55, 590], 0.75, -1,
                 {"up": "wing-up", "down": "wing-down", "glide": "wing-glide"}),
            limb("wing-r", "wing-level-r", [55, 590], 0.75, -1,
                 {"up": "wing-up-r", "down": "wing-down-r", "glide": "wing-glide-r"}),
            # The tail hangs behind him and curls, swishing a beat behind his steps.
            {"name": "tail", "image": "tail", "scale": 0.5, "pivot": piv["tail"], "joint": [60, 340], "z": -4},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 150], "z": 0},
        ],
    }


def wings(t, pose):
    f = math.sin(4 * math.pi * t)
    v = "up" if f > 0.4 else ("down" if f < -0.4 else None)
    return {"wing-l": P(deg=-6 * f, variant=v), "wing-r": P(deg=6 * f, variant=v),
            "tail": P(deg=5 * math.sin(2 * math.pi * (t - 0.12)))}


def glide(t, pose):
    up = math.sin(math.pi * t)
    return {"wing-l": P(deg=-4 * up, variant="glide"), "wing-r": P(deg=4 * up, variant="glide"),
            "tail": P(deg=-6 * up)}


def setup():
    rig.configure("origo", manifest, extra_run=wings, extra_jump=glide,
                  torso={"body", "wing-l", "wing-r", "tail"})
