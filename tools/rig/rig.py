"""Cutout rig tool: assembles part drawings on joints, renders preview animations, and exports game files.

Coordinates are pixels with y up, origin at the ground under the character's center (SpriteKit's
convention), so the game's CutoutRig reads the exported JSON directly.

Hands and feet swap between a few drawings as they move (the way cutout animation is done), while the
body, arms and tuft turn and bounce on their joints. Each part has a default drawing ("image") and
named alternates ("variants"); a pose picks one per part.

Usage:  python3 rig.py <parts-folder> <preview-folder>
"""
import json
import math
import sys
from PIL import Image, ImageDraw

PARTS_DIR = sys.argv[1] if len(sys.argv) > 1 else "bramble4"
# Optional per-character motion for extra parts (sparks, flags...): f(t, pose) -> {part: P(...)}.
EXTRA_RUN = None
EXTRA_JUMP = None


def _pivots():
    try:
        with open(f"{PARTS_DIR}/pivots.json") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


PIV = _pivots()


def limb(name, image, joint, scale, z, variants):
    """A part whose drawings all come from the pivot file: default `image`, plus `variants`."""
    return {"name": name, "image": image, "scale": scale, "pivot": PIV.get(image, [0.5, 1.0]), "joint": joint,
            "z": z, "variants": {v: {"image": img, "pivot": PIV.get(img, [0.5, 1.0])} for v, img in variants.items()}}


MANIFEST = {
    "name": "bramble",
    "view": "back",
    # scale: drawing to rig size. pivot: fraction of the drawing (x from left, y from bottom).
    # joint: where the pivot sits, from the ground center, y up. z: draw order (higher on top).
    "parts": [
        limb("foot-l", "foot-plant", [-62, 166], 0.4, -3,
             {"push": "foot-push", "kick": "foot-kick", "pass": "foot-pass"}),
        limb("foot-r", "foot-plant-r", [62, 166], 0.4, -3,
             {"push": "foot-push-r", "kick": "foot-kick-r", "pass": "foot-pass-r"}),
        limb("arm-l", "arm-hang", [-212, 470], 0.46, -2,
             {"fwd": "arm-fwd", "back": "arm-back", "up": "arm-up"}),
        limb("arm-r", "arm-hang-r", [212, 470], 0.46, -2,
             {"fwd": "arm-fwd-r", "back": "arm-back-r", "up": "arm-up-r"}),
        {"name": "sprout", "image": "sprout", "scale": 0.75, "pivot": [0.5, 0.1], "joint": [0, 735], "z": -1},
        {"name": "body", "image": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 105], "z": 0},
    ],
}

# Parts that ride on the torso, so they bob and sway with the body. A part can also name a "parent"
# part it hangs from (a spark on a fuse): it then follows that part's position and turn.
TORSO = {"body", "arm-l", "arm-r", "sprout"}


def configure(parts_dir, manifest, extra_run=None, extra_jump=None, torso=None):
    """Switch to another character."""
    global PARTS_DIR, PIV, MANIFEST, EXTRA_RUN, EXTRA_JUMP, TORSO
    PARTS_DIR = parts_dir
    PIV = _pivots()
    MANIFEST = manifest(PIV) if callable(manifest) else manifest
    EXTRA_RUN, EXTRA_JUMP = extra_run, extra_jump
    if torso:
        TORSO = set(torso)
# Drawings that show a foot kicked up toward the camera, so it passes in front of the body.
IN_FRONT = {"kick"}


def P(dx=0.0, dy=0.0, deg=0.0, sx=1.0, sy=1.0, variant=None):
    return {"dx": dx, "dy": dy, "deg": deg, "sx": sx, "sy": sy, "variant": variant}


def smooth(a, b, x):
    """0 below a, 1 above b, an S-curve between."""
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def snap(t, length=0.25):
    """Size just after a drawing swaps in: starts 90% and settles to 100%, so the swap reads as a snap."""
    return 0.9 + 0.1 * smooth(0.0, length, t)


# One step, from the foot landing (0) to landing again (1): where each drawing starts.
FOOT_TIMING = [(0.0, None), (0.3, "push"), (0.42, "kick"), (0.68, "pass")]


def foot_pose(phase, side):
    """One foot through a stride, swapping drawings: planted, push-off, kicked up, passing forward."""
    phase %= 1.0
    if phase < 0.3:
        # Planted. Landing squashes it flat for a moment.
        land = 1 - smooth(0.0, 0.08, phase)
        return P(sx=1 + 0.1 * land, sy=1 - 0.14 * land)
    if phase < 0.42:
        k = (phase - 0.3) / 0.12
        s = snap(k)
        # Push-off: the heel rolls up, the foot pressing into the ground.
        return P(dy=4 * k, deg=side * -4 * k, sx=s, sy=s, variant="push")
    if phase < 0.68:
        k = (phase - 0.42) / 0.26
        s = snap(k)
        # Kicked up behind the runner, sole to the camera, rising in an arc.
        return P(dy=8 + 34 * math.sin(math.pi * k), deg=side * (8 - 12 * k), sx=s, sy=s, variant="kick")
    k = (phase - 0.68) / 0.32
    s = snap(k)
    # Passing forward under the body to land. The drawing is already lifted; it drops to the ground.
    return P(dy=6 - 10 * smooth(0.4, 1.0, k), deg=side * 4 * (1 - k), sx=s, sy=s, variant="pass")


def arm_pose(forward, side):
    """forward from -1 (swung back toward you) to 1 (swung forward, away from you)."""
    if forward > 0.45:
        variant, base = "fwd", 0.7
    elif forward < -0.45:
        variant, base = "back", -0.7
    else:
        variant, base = None, 0.0
    # Within each drawing the arm keeps turning a little, so the swing never stops.
    rest = forward - base
    return P(dy=6 * forward, deg=side * 10 * rest, variant=variant)


def run_pose(t):
    """Running away from the camera. t goes 0 to 1 over one cycle (two steps)."""
    stance_mid = 0.15
    p = 2 * math.pi * t
    # Lowest when a foot is planted under the body, highest in between steps.
    low = 0.5 + 0.5 * math.cos(4 * math.pi * (t - stance_mid))
    bob = 16 * (1 - low)
    sway = 3 * math.cos(p - 2 * math.pi * stance_mid)
    # Each arm swings opposite its own leg: forward while that leg kicks back.
    swing = math.sin(p - 2 * math.pi * 0.3)
    lag = 0.09
    low_late = 0.5 + 0.5 * math.cos(4 * math.pi * (t - lag - stance_mid))
    sway_late = 3 * math.cos(2 * math.pi * (t - lag - stance_mid))
    pose = {
        "foot-l": foot_pose(t, -1),
        "foot-r": foot_pose(t + 0.5, 1),
        "arm-l": arm_pose(swing, 1),
        "arm-r": arm_pose(-swing, -1),
        "sprout": P(dy=-6 * low_late, deg=-sway_late * 3, sx=1 + 0.05 * low_late, sy=1 - 0.08 * low_late),
        "body": P(dy=bob, deg=sway, sx=1 + 0.03 * low - 0.015 * (1 - low), sy=1 - 0.04 * low + 0.02 * (1 - low)),
    }
    return _with_extras(pose, EXTRA_RUN, t)


def jump_pose(t):
    """A jump, t from 0 at take-off to 1 at landing. The game moves the rig up and down."""
    up = math.sin(math.pi * t)
    feet = "push" if t < 0.12 else ("kick" if t < 0.8 else "pass")
    arms = "back" if t < 0.1 else ("up" if t < 0.85 else None)
    raise_k = smooth(0.1, 0.3, t)
    return _with_extras({
        "foot-l": P(dy=10 * up, variant=feet),
        "foot-r": P(dy=10 * up, variant=feet),
        # Arms wind back, then throw up in a cheer, wobbling a little at the top.
        "arm-l": P(dy=12 * raise_k * up, deg=6 * math.sin(6 * math.pi * t) * raise_k, variant=arms),
        "arm-r": P(dy=12 * raise_k * up, deg=-6 * math.sin(6 * math.pi * t) * raise_k, variant=arms),
        "sprout": P(deg=14 * math.cos(2 * math.pi * t)),
        "body": P(sx=1 - 0.05 * up, sy=1 + 0.07 * up),
    }, EXTRA_JUMP, t)


def _with_extras(pose, extra, t):
    if extra:
        pose.update(extra(t, pose))
    for part in MANIFEST["parts"]:
        pose.setdefault(part["name"], P())
    return pose


def load_images(folder=None):
    folder = folder or PARTS_DIR
    names = set()
    for part in MANIFEST["parts"]:
        names.add(part["image"])
        for v in part.get("variants", {}).values():
            names.add(v["image"])
    return {n: Image.open(f"{folder}/{n}.png").convert("RGBA") for n in names}


def picture_for(part, variant, images):
    if variant and variant in part.get("variants", {}):
        v = part["variants"][variant]
        return images[v["image"]], v["pivot"]
    return images[part["image"]], part["pivot"]


def render(images, pose, lift=0.0, canvas=(760, 900), ground=40, scale=0.62):
    W, H = canvas
    frame = Image.new("RGBA", canvas, (243, 236, 222, 255))
    shadow = Image.new("RGBA", canvas, (0, 0, 0, 0))
    sw = 230 * scale * max(0.5, 1 - lift / 600)
    ImageDraw.Draw(shadow).ellipse([W / 2 - sw, H - ground - 14 * scale, W / 2 + sw, H - ground + 14 * scale],
                                   fill=(0, 0, 0, 50))
    frame.alpha_composite(shadow)
    body_part = next(p for p in MANIFEST["parts"] if p["name"] == "body")
    body = pose["body"]

    def order(part):
        return 1 if pose[part["name"]]["variant"] in IN_FRONT else part["z"]

    # Where each part's pivot ends up and how far it's turned, parents first.
    placed = {}
    by_name = {p["name"]: p for p in MANIFEST["parts"]}

    def place(part):
        name = part["name"]
        if name in placed:
            return placed[name]
        q = pose[name]
        jx, jy = part["joint"]
        deg = q["deg"]
        parent = part.get("parent")
        if parent:
            ppart = by_name[parent]
            px_, py_, pdeg = place(ppart)
            r = math.radians(pdeg)
            rx, ry = jx - ppart["joint"][0], jy - ppart["joint"][1]
            jx = px_ + rx * math.cos(r) - ry * math.sin(r) + q["dx"]
            jy = py_ + rx * math.sin(r) + ry * math.cos(r) + q["dy"]
            deg += pdeg
        elif name in TORSO and name != "body":
            bx, by = body_part["joint"]
            r = math.radians(body["deg"])
            rx, ry = jx - bx, jy - by
            jx = bx + rx * math.cos(r) - ry * math.sin(r) + body["dx"] + q["dx"]
            jy = by + rx * math.sin(r) + ry * math.cos(r) + body["dy"] + q["dy"]
            deg += body["deg"]
        else:
            jx += q["dx"]
            jy += q["dy"]
        placed[name] = (jx, jy, deg)
        return placed[name]

    for part in sorted(MANIFEST["parts"], key=order):
        name = part["name"]
        q = pose[name]
        img, pivot = picture_for(part, q["variant"], images)
        jx, jy, deg = place(part)
        jy += lift
        s = part["scale"] * scale
        im = img.resize((max(1, int(img.width * s * q["sx"])), max(1, int(img.height * s * q["sy"]))), Image.LANCZOS)
        px = pivot[0] * im.width
        py = (1 - pivot[1]) * im.height
        R = int(math.hypot(im.width, im.height)) + 4
        pad = Image.new("RGBA", (R * 2, R * 2), (0, 0, 0, 0))
        pad.paste(im, (int(R - px), int(R - py)), im)
        rot = pad.rotate(deg, resample=Image.BICUBIC, center=(R, R))
        frame.alpha_composite(rot, (int(W / 2 + jx * scale - R), int(H - ground - jy * scale - R)))
    return frame


def strip(out_path, n=12, cols=6, size=(253, 300)):
    images = load_images()
    frames = [render(images, run_pose(i / n)).convert("RGB").resize(size, Image.LANCZOS) for i in range(n)]
    rows = (n + cols - 1) // cols
    sheet = Image.new("RGB", (size[0] * cols, size[1] * rows), (255, 255, 255))
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % cols) * size[0], (i // cols) * size[1]))
    sheet.save(out_path)


def preview(out_dir, size=(380, 450)):
    images = load_images()
    frames = []
    # Three cycles near game speed, then two at a quarter speed so each drawing can be seen.
    for steps, cycles in [(14, 3), (40, 2)]:
        for _ in range(cycles):
            frames += [render(images, run_pose(i / steps)) for i in range(steps)]
    frames += [render(images, jump_pose(i / 23), lift=260 * math.sin(math.pi * i / 23)) for i in range(24)]
    frames += [render(images, run_pose(i / 14)) for i in range(14)]
    small = [f.convert("RGB").resize(size, Image.LANCZOS) for f in frames]
    small[0].save(f"{out_dir}/{MANIFEST['name']}-rig-preview.gif", save_all=True, append_images=small[1:],
                  duration=33, loop=0)


def export(art_dir, export_scale=0.5):
    """Writes game-ready drawings and the joint file. Drawings are pre-scaled, so in the game a part's
    sprite size is its drawing's size, and joints are in the same pixels."""
    name = MANIFEST["name"]
    out = {"name": name, "view": MANIFEST["view"], "parts": []}
    images = load_images()
    written = set()

    def save(image_name, k):
        if image_name not in written:
            img = images[image_name]
            img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS).save(
                f"{art_dir}/{name}-rig-{image_name}.png", optimize=True)
            written.add(image_name)

    top = 0.0
    for part in MANIFEST["parts"]:
        k = part["scale"] * export_scale
        save(part["image"], k)
        entry = {"name": part["name"], "image": part["image"], "pivot": part["pivot"],
                 "joint": [round(part["joint"][0] * export_scale, 2), round(part["joint"][1] * export_scale, 2)],
                 "z": part["z"]}
        if part.get("parent"):
            entry["parent"] = part["parent"]
        if part["name"] in TORSO:
            entry["torso"] = True
        if part.get("variants"):
            entry["variants"] = {}
            for vname, v in part["variants"].items():
                save(v["image"], k)
                entry["variants"][vname] = {"image": v["image"], "pivot": v["pivot"]}
        out["parts"].append(entry)
        h = images[part["image"]].height * k
        top = max(top, part["joint"][1] * export_scale + (1 - part["pivot"][1]) * h)
    out["height"] = round(top, 2)
    out["inFront"] = sorted(IN_FRONT)
    with open(f"{art_dir}/{name}-rig.json", "w") as f:
        json.dump(out, f, indent=2)
    return out


if __name__ == "__main__":
    preview(sys.argv[2] if len(sys.argv) > 2 else ".")


def slide_pose(t):
    """Matches CutoutRig.slide in the game (rig units are 2x the game's)."""
    down = smooth(0, 0.15, t) * (1 - smooth(0.85, 1, t))
    tuck = "pass" if down > 0.3 else None
    pose = {
        "foot-l": P(dy=-8 * down, variant=tuck), "foot-r": P(dy=-8 * down, variant=tuck),
        "arm-l": P(dy=-12 * down, deg=-20 * down, variant="back" if down > 0.3 else None),
        "arm-r": P(dy=-12 * down, deg=20 * down, variant="back" if down > 0.3 else None),
        "sprout": P(dy=-6 * down, deg=-8 * down, sx=1 + 0.06 * down, sy=1 - 0.12 * down),
        "body": P(dy=-20 * down, sx=1 + 0.08 * down, sy=1 - 0.12 * down),
    }
    return _with_extras(pose, EXTRA_RUN, t * 2)


def hit_pose(t):
    """Matches CutoutRig.hit in the game."""
    shock = 1 - smooth(0, 1, t)
    wob = math.sin(t * 18) * shock
    pose = {
        "foot-l": P(dy=12 * shock, variant="push" if shock > 0.4 else None),
        "foot-r": P(dy=6 * shock, variant="pass" if shock > 0.4 else None),
        "arm-l": P(dy=12 * shock, deg=-30 * wob, variant="up" if shock > 0.3 else None),
        "arm-r": P(dy=12 * shock, deg=30 * wob, variant="up" if shock > 0.3 else None),
        "sprout": P(deg=25 * wob),
        "body": P(dy=8 * shock, deg=8 * wob, sx=1 - 0.06 * shock, sy=1 + 0.08 * shock),
    }
    return _with_extras(pose, EXTRA_RUN, t)
