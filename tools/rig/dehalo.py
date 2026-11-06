"""Strips the pale haze ChatGPT leaves around a drawing: pale, grey-ish pixels that aren't fully solid,
plus anything only connected to the drawing through them. Then trims a 2 px soft edge."""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage


def dehalo(path, light=200, chroma=30):
    im = np.array(Image.open(path).convert("RGBA")).astype(int)
    r, g, b, a = im[..., 0], im[..., 1], im[..., 2], im[..., 3]
    pale = (np.minimum(np.minimum(r, g), b) > light) & ((np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)) < chroma)
    keep = (a > 0) & ~(pale & (a < 255)) & ~(pale & ndimage.binary_dilation(a < 200, iterations=6))
    lab, n = ndimage.label(keep)
    if n:
        sizes = ndimage.sum(keep, lab, range(1, n + 1))
        keep = lab == (1 + int(np.argmax(sizes)))
        keep = ndimage.binary_fill_holes(keep)
    soft = ndimage.distance_transform_edt(keep)
    alpha = np.clip(soft / 2.0, 0, 1) * np.minimum(a, 255)
    im[..., 3] = alpha.astype(int)
    Image.fromarray(im.astype(np.uint8)).save(path)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        dehalo(p)
