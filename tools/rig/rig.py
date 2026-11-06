"""Cutout rig tool: assembles part PNGs on joints, renders preview animations, and exports game files.

Coordinates are pixels with y up, origin at the ground under the character's center (SpriteKit's
convention), so the game's CutoutRig reads the exported JSON directly.

A part can have alternate drawings ("variants"), for example a foot kicked up showing its sole.
A pose picks a variant per part; a variant can be the mirror image of its picture.
"""
import json
import math
import sys
from PIL import Image, ImageDraw

MANIFEST = {
    "name": "bramble",
    "view": "back",
    # scale: picture to rig size. pivot: fraction of the picture (x from left, y from bottom).
    # joint: where the pivot sits, from the ground center, y up. z: draw order (higher on top).
    "parts": [
        {"name": "foot-l", "scale": 0.5, "pivot": [0.5, 0.95], "joint": [-78, 272], "z": -3,
         "variants": {"kick": {"image": "foot-kick", "pivot": [0.3, 0.95], "mirror": True}}},
        {"name": "foot-r", "scale": 0.5, "pivot": [0.5, 0.95], "joint": [78, 272], "z": -3,
         "variants": {"kick": {"image": "foot-kick", "pivot": [0.3, 0.95], "mirror": False}}},
        {"name": "arm-l", "scale": 0.52, "pivot": [0.8, 0.9], "joint": [-160, 440], "z": -2},
        {"name": "arm-r", "scale": 0.52, "pivot": [0.2, 0.9], "joint": [160, 440], "z": -2},
        {"name": "sprout", "scale": 0.75, "pivot": [0.5, 0.1], "joint": [0, 735], "z": -1},
        {"name": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 110], "z": 0},
    ],
}

# Parts that ride on the torso, so they bob and sway with the body.
TORSO = {"body", "arm-l", "arm-r", "sprout"}
# A foot lifted past this switches to its kicked drawing and passes in front of the body.
KICK_AT = 0.3


def P(dx=0.0, dy=0.0, deg=0.0, sx=1.0, sy=1.0, variant=None):
    return {"dx": dx, "dy": dy, "deg": deg, "sx": sx, "sy": sy, "variant": variant}


def run_pose(t):
    """Running away from the camera. t goes 0 to 1 over one cycle (two steps)."""
    p = 2 * math.pi * t
    s = math.sin(p)
    lift_l = max(0.0, s)
    lift_r = max(0.0, -s)
    bob = 14 * abs(s)
    sway = 3 * s

    def foot(lift, side):
        if lift > KICK_AT:
            # Kicked back toward the camera: the bent leg with its sole showing, rising off the ground.
            return P(dy=55 * lift, deg=side * 6 * lift, variant="kick")
        # Planted, or just leaving the ground: a small rise as the heel peels up.
        return P(dy=30 * lift)

    def arm(forward, side):
        # From behind, an arm swinging forward moves away from you: it rises, shrinks and tucks in.
        # Swinging back, it comes toward you: it drops, grows and swings out.
        return P(dy=16 * forward, deg=side * 18 * forward, sx=1 - 0.1 * forward, sy=1 - 0.1 * forward)

    return {
        "foot-l": foot(lift_l, -1),
        "foot-r": foot(lift_r, 1),
        # The arm on the same side as the kicking foot swings forward.
        "arm-l": arm(s, 1),
        "arm-r": arm(-s, -1),
        "sprout": P(dy=bob * 0.5, deg=-sway * 0.6 + 12 * math.sin(p - 1.1)),
        "body": P(dy=bob, deg=sway, sx=1 - 0.02 * abs(math.cos(p)), sy=1 + 0.025 * abs(s)),
    }


def jump_pose(t):
    """A jump, t from 0 at take-off to 1 at landing. The game moves the rig up and down."""
    up = math.sin(math.pi * t)
    arms = min(1, t * 4) * (1 - max(0, t - 0.75) * 4)
    return {
        # Both legs tuck up with their soles showing.
        "foot-l": P(dy=40 * up, variant="kick" if up > 0.25 else None),
        "foot-r": P(dy=40 * up, variant="kick" if up > 0.25 else None),
        # Arms swing up and out past the leaves, like a cheer.
        "arm-l": P(dx=-30 * arms, dy=40 * arms, deg=-125 * arms),
        "arm-r": P(dx=30 * arms, dy=40 * arms, deg=125 * arms),
        "sprout": P(deg=14 * math.cos(2 * math.pi * t)),
        "body": P(sx=1 - 0.05 * up, sy=1 + 0.07 * up),
    }


def load_images(folder):
    names = set()
    for part in MANIFEST["parts"]:
        names.add(part["name"])
        for v in part.get("variants", {}).values():
            names.add(v["image"])
    return {n: Image.open(f"{folder}/{n}.png").convert("RGBA") for n in names}


def picture_for(part, variant, images):
    """The picture and pivot a part draws with for a variant (or its default)."""
    if variant and variant in part.get("variants", {}):
        v = part["variants"][variant]
        img = images[v["image"]]
        pivot = list(v["pivot"])
        if v.get("mirror"):
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
            pivot[0] = 1 - pivot[0]
        return img, pivot
    return images[part["name"]], part["pivot"]


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
        if part["name"].startswith("foot") and pose[part["name"]]["variant"] == "kick":
            return 1  # seen from behind, a kicked foot passes in front of the body
        return part["z"]

    for part in sorted(MANIFEST["parts"], key=order):
        name = part["name"]
        q = pose[name]
        img, pivot = picture_for(part, q["variant"], images)
        jx, jy = part["joint"]
        deg = q["deg"]
        if name in TORSO and name != "body":
            bx, by = body_part["joint"]
            r = math.radians(body["deg"])
            rx, ry = jx - bx, jy - by
            jx = bx + rx * math.cos(r) - ry * math.sin(r) + body["dx"] + q["dx"]
            jy = by + rx * math.sin(r) + ry * math.cos(r) + body["dy"] + q["dy"]
            deg += body["deg"]
        else:
            jx += q["dx"]
            jy += q["dy"]
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


def preview(folder, out_dir, size=(380, 450)):
    images = load_images(folder)
    frames = []
    # Two cycles at game speed (about 0.23 s each), then two at half speed so the motion is easy to read.
    for steps, cycles in [(10, 2), (20, 2)]:
        for _ in range(cycles):
            frames += [render(images, run_pose(i / steps)) for i in range(steps)]
    frames += [render(images, jump_pose(i / 17), lift=260 * math.sin(math.pi * i / 17)) for i in range(18)]
    frames += [render(images, run_pose(i / 10)) for i in range(10)]
    small = [f.convert("RGB").resize(size, Image.LANCZOS) for f in frames]
    small[0].save(f"{out_dir}/{MANIFEST['name']}-rig-preview.gif", save_all=True, append_images=small[1:],
                  duration=42, loop=0)
    keys = [run_pose(0), run_pose(0.25), run_pose(0.5), run_pose(0.75), jump_pose(0.5)]
    sheet = Image.new("RGB", (size[0] * len(keys), size[1]), (255, 255, 255))
    for i, pose in enumerate(keys):
        sheet.paste(render(images, pose).convert("RGB").resize(size, Image.LANCZOS), (size[0] * i, 0))
    sheet.save(f"{out_dir}/{MANIFEST['name']}-rig-keys.png")


def export(folder, art_dir, export_scale=0.5):
    """Writes game-ready pictures and the joint file. Pictures are pre-scaled, so in the game a part's
    sprite size is its picture size, and joints are in the same pixels."""
    name = MANIFEST["name"]
    out = {"name": name, "view": MANIFEST["view"], "parts": []}
    images = load_images(folder)
    written = set()

    def save(image_name, k):
        if image_name in written:
            return
        img = images[image_name]
        img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS).save(
            f"{art_dir}/{name}-rig-{image_name}.png", optimize=True)
        written.add(image_name)

    top = 0.0
    for part in MANIFEST["parts"]:
        k = part["scale"] * export_scale
        save(part["name"], k)
        entry = {"name": part["name"], "pivot": part["pivot"],
                 "joint": [round(part["joint"][0] * export_scale, 2), round(part["joint"][1] * export_scale, 2)],
                 "z": part["z"]}
        if part.get("variants"):
            entry["variants"] = {}
            for vname, v in part["variants"].items():
                save(v["image"], k)
                entry["variants"][vname] = {"image": v["image"], "pivot": v["pivot"], "mirror": v.get("mirror", False)}
        out["parts"].append(entry)
        h = images[part["name"]].height * k
        top = max(top, part["joint"][1] * export_scale + (1 - part["pivot"][1]) * h)
    out["height"] = round(top, 2)
    with open(f"{art_dir}/{name}-rig.json", "w") as f:
        json.dump(out, f, indent=2)
    return out


if __name__ == "__main__":
    preview(sys.argv[1] if len(sys.argv) > 1 else MANIFEST["name"], sys.argv[2] if len(sys.argv) > 2 else ".")
