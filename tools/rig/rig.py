"""Cutout rig preview: assembles part PNGs on joints from a manifest and renders animation frames.

Coordinates in the manifest are pixels with y up, origin at the ground under the character's center,
the same convention SpriteKit uses, so the Swift rig reads the same file.
"""
import json
import math
import sys
from PIL import Image

MANIFEST = {
    "name": "bramble",
    "view": "back",
    # Each part: image, scale, pivot as a fraction of the image (x from left, y from bottom),
    # joint position relative to the ground center (y up), and draw order (higher draws on top).
    "parts": [
        {"name": "foot-l", "scale": 0.68, "pivot": [0.5, 0.9], "joint": [-88, 196], "z": -3},
        {"name": "foot-r", "scale": 0.68, "pivot": [0.5, 0.9], "joint": [88, 196], "z": -3},
        {"name": "arm-l", "scale": 0.72, "pivot": [0.84, 0.52], "joint": [-188, 440], "z": -2},
        {"name": "arm-r", "scale": 0.72, "pivot": [0.16, 0.52], "joint": [188, 440], "z": -2},
        {"name": "sprout", "scale": 0.75, "pivot": [0.5, 0.1], "joint": [0, 775], "z": -1},
        {"name": "body", "scale": 1.0, "pivot": [0.5, 0.0], "joint": [0, 150], "z": 0},
    ],
}


def run_pose(t):
    """Run cycle, t from 0 to 1. Returns per-part (dx, dy, degrees, sx, sy) offsets."""
    p = 2 * math.pi * t
    lift_l = max(0.0, math.sin(p))
    lift_r = max(0.0, -math.sin(p))
    bob = 14 * abs(math.sin(p))
    sway = 3.5 * math.sin(p)
    return {
        # A lifted foot kicks up toward the camera: it rises, tips, and its sole grows a little.
        "foot-l": (6 * lift_l, 85 * lift_l, -12 * lift_l, 1 + 0.1 * lift_l, 1 - 0.12 * lift_l),
        "foot-r": (-6 * lift_r, 85 * lift_r, 12 * lift_r, 1 + 0.1 * lift_r, 1 - 0.12 * lift_r),
        # Arms pump opposite the feet.
        "arm-l": (0, -bob * 0.3, 30 * math.sin(p), 1, 1),
        "arm-r": (0, -bob * 0.3, 30 * math.sin(p), 1, 1),
        # The sprout lags behind the body's sway, so it flops.
        "sprout": (0, bob, -sway * 0.6 + 12 * math.sin(p - 1.1), 1, 1),
        "body": (0, bob, sway, 1 - 0.02 * abs(math.cos(p)), 1 + 0.025 * abs(math.sin(p))),
    }


def jump_pose(t):
    """Jump, t from 0 (take-off) to 1 (landing)."""
    up = math.sin(math.pi * t)
    arms = 75 * min(1, t * 4) * (1 - max(0, t - 0.75) * 4)
    tuck = 45 * up
    return {
        "foot-l": (10 * up, tuck, -18 * up, 1, 1),
        "foot-r": (-10 * up, tuck, 18 * up, 1, 1),
        # Arms shoot up and out past the leaves, like the painted jump pose.
        "arm-l": (-0.9 * arms, 0.5 * arms, -arms * 1.1, 1, 1),
        "arm-r": (0.9 * arms, 0.5 * arms, arms * 1.1, 1, 1),
        "sprout": (0, 0, 14 * math.cos(math.pi * t * 2), 1, 1),
        "body": (0, 0, 0, 1 - 0.05 * up, 1 + 0.07 * up),
    }


def render(images, pose, lift=0.0, canvas=(760, 820), ground=40, scale=0.62):
    """Draws one frame. Body offsets carry the parts attached to it (arms, sprout)."""
    W, H = canvas
    frame = Image.new("RGBA", canvas, (243, 236, 222, 255))
    # Soft ground shadow.
    shadow = Image.new("RGBA", canvas, (0, 0, 0, 0))
    from PIL import ImageDraw
    d = ImageDraw.Draw(shadow)
    sw = 230 * scale * max(0.5, 1 - lift / 600)
    d.ellipse([W / 2 - sw, H - ground - 14 * scale, W / 2 + sw, H - ground + 14 * scale], fill=(0, 0, 0, 50))
    frame.alpha_composite(shadow)
    body_dx, body_dy, body_rot = pose["body"][0], pose["body"][1], pose["body"][2]
    attached = {"arm-l", "arm-r", "sprout"}
    def order(p):
        if p["name"].startswith("foot") and pose[p["name"]][1] > 18:
            return 1  # a foot kicked up toward the camera passes in front of the body
        return p["z"]
    for part in sorted(MANIFEST["parts"], key=order):
        name = part["name"]
        img = images[name]
        dx, dy, deg, sx, sy = pose[name]
        jx, jy = part["joint"]
        if name in attached:
            # Ride along with the body: rotate the joint around the body's base, then add its bob.
            bx, by = MANIFEST["parts"][-1]["joint"]
            r = math.radians(body_rot)
            rx, ry = jx - bx, jy - by
            jx = bx + rx * math.cos(r) - ry * math.sin(r) + body_dx + dx
            jy = by + rx * math.sin(r) + ry * math.cos(r) + body_dy + dy
            deg += body_rot
        elif name == "body":
            jx += dx
            jy += dy
        else:
            jx += dx
            jy += dy
        jy += lift
        s = part["scale"] * scale
        w, h = img.size
        if name == "body":
            sxs, sys_ = s * sx, s * sy
        else:
            sxs, sys_ = s * sx, s * sy
        im = img.resize((max(1, int(w * sxs)), max(1, int(h * sys_))), Image.LANCZOS)
        px = part["pivot"][0] * im.width
        py = (1 - part["pivot"][1]) * im.height  # pivot y from the top, for PIL
        # Pad so rotation around the pivot never clips.
        R = int(math.hypot(im.width, im.height)) + 4
        pad = Image.new("RGBA", (R * 2, R * 2), (0, 0, 0, 0))
        pad.paste(im, (int(R - px), int(R - py)), im)
        rot = pad.rotate(deg, resample=Image.BICUBIC, center=(R, R))
        sx_screen = W / 2 + jx * scale
        sy_screen = H - ground - jy * scale
        frame.alpha_composite(rot, (int(sx_screen - R), int(sy_screen - R)))
    return frame


def main(out_dir):
    images = {p["name"]: Image.open(f"{MANIFEST['name']}/{p['name']}.png").convert("RGBA") for p in MANIFEST["parts"]}
    frames = []
    # Two run cycles at game speed (~0.23 s each), then two at half speed so the motion is easy to read.
    for speed, cycles in [(10, 2), (20, 2)]:
        for c in range(cycles):
            for i in range(speed):
                frames.append(render(images, run_pose(i / speed)))
    for i in range(18):
        t = i / 17
        frames.append(render(images, jump_pose(t), lift=260 * math.sin(math.pi * t)))
    for i in range(10):
        frames.append(render(images, run_pose(i / 10)))
    small = [f.convert("RGB").resize((380, 410), Image.LANCZOS) for f in frames]
    small[0].save(f"{out_dir}/bramble-rig-preview.gif", save_all=True, append_images=small[1:], duration=42, loop=0)
    # A contact sheet of key poses for checking joints by eye.
    keys = [run_pose(0), run_pose(0.25), run_pose(0.5), run_pose(0.75)]
    sheet = Image.new("RGB", (380 * 5, 410), (255, 255, 255))
    for i, pose in enumerate(keys):
        sheet.paste(render(images, pose).convert("RGB").resize((380, 410)), (380 * i, 0))
    sheet.paste(render(images, jump_pose(0.5), lift=0).convert("RGB").resize((380, 410)), (380 * 4, 0))
    sheet.save(f"{out_dir}/bramble-rig-keys.png")
    with open(f"{out_dir}/bramble-rig.json", "w") as f:
        json.dump(MANIFEST, f, indent=2)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")


def export(art_dir, export_scale=0.5):
    """Writes game-ready parts and the joint file. Parts are pre-scaled, so in the game a part's
    sprite size is simply its image size, and joints are in the same pixels."""
    name = MANIFEST["name"]
    out = {"name": name, "view": MANIFEST["view"], "parts": []}
    top = 0.0
    for part in MANIFEST["parts"]:
        img = Image.open(f"{name}/{part['name']}.png").convert("RGBA")
        k = part["scale"] * export_scale
        img = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
        img.save(f"{art_dir}/{name}-rig-{part['name']}.png", optimize=True)
        jx, jy = part["joint"]
        out["parts"].append({
            "name": part["name"],
            "pivot": part["pivot"],
            "joint": [round(jx * export_scale, 2), round(jy * export_scale, 2)],
            "z": part["z"],
        })
        top = max(top, jy * export_scale + (1 - part["pivot"][1]) * img.height)
    out["height"] = round(top, 2)
    with open(f"{art_dir}/{name}-rig.json", "w") as f:
        json.dump(out, f, indent=2)
    return out
