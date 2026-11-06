"""Stickle: a tape-roll beetle on six legs, scurrying with a tripod gait (front and back legs on one
side step with the middle leg on the other), antennae bobbing a beat behind."""
import math
import rig
from rig import P, limb

# Front legs sit higher up the shell (further away), back legs lower (closer to the camera).
LEGS = [(1, -335, 330, -2), (2, -385, 230, -2), (3, -300, 140, -1)]


def manifest(piv):
    parts = []
    for n, x, y, z in LEGS:
        parts.append(limb(f"leg-l{n}", f"leg{n}-down", [x, y], 0.5, z, {"up": f"leg{n}-up"}))
        parts.append(limb(f"leg-r{n}", f"leg{n}-down-r", [-x, y], 0.5, z, {"up": f"leg{n}-up-r"}))
    parts += [
        {"name": "antenna-l", "image": "antenna", "scale": 0.6, "pivot": piv["antenna"], "joint": [-150, 860], "z": -3},
        {"name": "antenna-r", "image": "antenna-r", "scale": 0.6, "pivot": piv["antenna-r"], "joint": [150, 860], "z": -3},
        {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 70], "z": 0},
    ]
    return {"name": "stickle", "view": "back", "parts": parts}


def legs(t, up_all=False):
    pose = {}
    s = math.sin(2 * math.pi * t)
    for n, _, _, _ in LEGS:
        for side, sign in (("l", 1), ("r", -1)):
            # Tripod: left 1 and 3 with right 2, then the other three.
            group_a = (side == "l") == (n != 2)
            lift = max(0.0, s if group_a else -s)
            up = up_all or lift > 0.25
            pose[f"leg-{side}{n}"] = P(dy=14 * lift, deg=sign * 6 * lift, variant="up" if up else None)
    return pose


def run_extras(t, pose):
    out = legs(t)
    wob = 8 * math.sin(4 * math.pi * (t - 0.08))
    out["antenna-l"] = P(deg=wob)
    out["antenna-r"] = P(deg=-wob)
    return out


def jump_extras(t, pose):
    out = legs(t, up_all=True)
    up = math.sin(math.pi * t)
    out["antenna-l"] = P(deg=-14 * up)
    out["antenna-r"] = P(deg=14 * up)
    return out


def setup():
    rig.configure("stickle", manifest, extra_run=run_extras, extra_jump=jump_extras,
                  torso={"body", "antenna-l", "antenna-r"} | {f"leg-{s}{n}" for s in "lr" for n in (1, 2, 3)})
