"""Blotch: an ink blob with no legs. He oozes: the wavy skirt under him ripples side to side
between three drawings, his body wobbles, and drops flick off behind him. Jumps land in a splat."""
import math
import rig
from rig import P


def manifest(piv):
    skirt_h = 280 * 1.35
    v = {n: {"image": f"skirt-{n}", "pivot": piv[f"skirt-{n}"]} for n in ("left", "right", "splat")}
    return {
        "name": "blotch",
        "view": "back",
        "parts": [
            {"name": "skirt", "image": "skirt", "scale": 1.35, "pivot": piv["skirt"], "joint": [0, skirt_h - 10], "z": -1,
             "variants": v},
            {"name": "drop-l", "image": "drop-big", "scale": 0.45, "pivot": [0.5, 0.5], "joint": [-330, 250], "z": 1},
            {"name": "drop-r", "image": "drop-small", "scale": 0.6, "pivot": [0.5, 0.5], "joint": [330, 300], "z": 1},
            {"name": "body", "image": "body", "scale": 0.9, "pivot": [0.5, 0.0], "joint": [0, skirt_h - 190], "z": 0},
        ],
    }


def flick(t, offset, side):
    """A drop flung off his side once a cycle, arcing out and shrinking away."""
    k = (t + offset) % 1.0
    out = k * 1.0
    return P(dx=side * 160 * out, dy=120 * math.sin(math.pi * out) - 60 * out, deg=side * 200 * out,
             sx=max(0.001, 1 - out ** 1.5), sy=max(0.001, 1 - out ** 1.5))


def ooze(t, pose):
    s = math.sin(2 * math.pi * t)
    return {
        "skirt": P(sx=1 + 0.05 * abs(s), sy=1 - 0.06 * abs(s), variant="left" if s > 0.45 else ("right" if s < -0.45 else None)),
        "drop-l": flick(t, 0.0, -1),
        "drop-r": flick(t, 0.5, 1),
    }


def jump(t, pose):
    land = t > 0.88
    up = math.sin(math.pi * t)
    return {
        "skirt": P(sx=1 - 0.1 * up + (0.15 if land else 0), sy=1 + 0.15 * up - (0.3 if land else 0),
                   variant="splat" if land else None),
        "drop-l": P(sx=0.001, sy=0.001),
        "drop-r": P(sx=0.001, sy=0.001),
    }


def setup():
    rig.configure("blotch", manifest, extra_run=ooze, extra_jump=jump, torso={"body", "drop-l", "drop-r"})
