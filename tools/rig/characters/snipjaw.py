"""Snipjaw: a four-legged felt croc. Back legs run the stepping cycle; front legs peek out at his
sides and paddle opposite them (they use the arm slot); his curly tail wags behind."""
import math
import rig
from rig import P, limb


def manifest(piv):
    return {
        "name": "snipjaw",
        "view": "back",
        "parts": [
            limb("foot-l", "foot-plant", [-110, 175], 0.34, -3,
                 {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
            limb("foot-r", "foot-plant-r", [110, 175], 0.34, -3,
                 {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
            # Front legs: planted by default, reaching forward, pushing back, tucked for jumps.
            limb("arm-l", "arm-hang", [-285, 470], 0.4, -2,
                 {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
            limb("arm-r", "arm-hang-r", [285, 470], 0.4, -2,
                 {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
            # Like his painted back view: the tail grows out of the middle of his lower back, where his
            # spikes end, sweeps right and curls up, in front of his body.
            {"name": "tail", "image": "tail", "scale": 0.95, "pivot": piv["tail-root"], "joint": [-20, 300], "z": 1},
            {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 140], "z": 0},
        ],
    }


def tail(t, pose):
    # A lazy wag, once per cycle, a beat behind the steps.
    return {"tail": P(deg=7 * math.sin(2 * math.pi * (t - 0.12)))}


def setup():
    rig.configure("snipjaw", manifest, extra_run=tail, extra_jump=tail,
                  torso={"body", "arm-l", "arm-r", "tail"})
