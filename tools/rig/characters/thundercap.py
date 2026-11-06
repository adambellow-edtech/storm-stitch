"""Thundercap: a floating storm cloud. His bolt flickers between four drawings under him, the
crest bobs on top, the cloud puffs, and sparkles orbit him. Jumps crack the big zap bolt."""
import math
import rig
from rig import P

FLOAT = 260


def manifest(piv):
    v = {n: {"image": f"bolt-{n}", "pivot": piv[f"bolt-{n}"]} for n in ("long", "fork", "zap")}
    return {
        "name": "thundercap",
        "view": "back",
        "parts": [
            {"name": "bolt", "image": "bolt", "scale": 0.5, "pivot": piv["bolt"], "joint": [0, FLOAT + 60], "z": -1,
             "variants": v},
            {"name": "sprout", "image": "crest", "scale": 0.55, "pivot": [0.5, 0.25], "joint": [0, FLOAT + 560], "z": -1.5},
            {"name": "spark-a", "image": "sparkle", "scale": 0.5, "pivot": [0.5, 0.5], "joint": [-380, FLOAT + 420], "z": 1},
            {"name": "spark-b", "image": "sparkle", "scale": 0.35, "pivot": [0.5, 0.5], "joint": [380, FLOAT + 250], "z": 1},
            {"name": "body", "image": "body", "scale": 0.8, "pivot": [0.5, 0.0], "joint": [0, FLOAT], "z": 0},
        ],
    }


def twinkle(t, phase):
    k = 0.5 + 0.5 * math.sin(2 * math.pi * (2 * t + phase))
    return P(dy=20 * math.sin(2 * math.pi * (t + phase)), deg=90 * t, sx=0.4 + 0.7 * k, sy=0.4 + 0.7 * k)


def storm(t, pose):
    # The bolt flickers: a new drawing four times a cycle.
    order = [None, "long", "fork", "long"]
    b = pose["body"]
    return {
        "bolt": P(deg=6 * math.sin(8 * math.pi * t), variant=order[int(t * 4) % 4]),
        "spark-a": twinkle(t, 0.0),
        "spark-b": twinkle(t, 0.5),
        "body": P(dy=b["dy"] * 0.5 + 12 * math.sin(2 * math.pi * t), deg=b["deg"],
                  sx=1 + 0.03 * math.sin(4 * math.pi * t), sy=1 - 0.03 * math.sin(4 * math.pi * t)),
    }


def zap(t, pose):
    out = storm(t, pose)
    out["bolt"] = P(variant="zap" if 0.2 < t < 0.8 else "long")
    return out


def setup():
    rig.configure("thundercap", manifest, extra_run=storm, extra_jump=zap,
                  torso={"body", "bolt", "sprout", "spark-a", "spark-b"})
