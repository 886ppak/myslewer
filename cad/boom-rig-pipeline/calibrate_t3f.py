"""
T3F color calibration, adapted from sample_wipeout_colors.py / fix_dark_gray_shapes.py.

Reference: pose_T3F_JL6.0_JA0 (the shortest jib-grid pose) plotted to PDF by
hand and rasterized at 300dpi. Registration uses a directly-optimized affine
fit (world->pixel) rather than a bbox-ratio guess - the naive bbox approach
was off by ~4.5% on the aspect ratio (verified via overlay), so this instead
minimizes projected-vertex distance to the nearest ink pixel (scipy Nelder-
Mead against a distance-transform of the raster) and confirmed visually.

The base reference pose has exactly 334 P-kind (WIPEOUT) shapes - this
EXACTLY matches the boom grid's constant P-count across all 10 lengths, so
those patch 1:1 by index, same as the original LTM 1650 method.

The jib grid's P-count grows with jib length (334 -> up to 366) because
longer jibs deploy extra lattice-section decal panels not present in the
JL=6.0 reference. Those extra entries can't be aligned by raw index, so each
jib length's header list is diff-aligned (difflib SequenceMatcher) against
the 334-shape base: matched runs inherit the sampled base color, and any
genuinely-new (inserted) entries fall back to their nearest matched
neighbor's color - a reasonable approximation for repeated panel-type
decals, but NOT verified pixel-ground-truth for those specific shapes (no
reference plot shows a longer jib yet).
"""
import json, base64, array, difflib
from collections import Counter
from PIL import Image
import numpy as np
from scipy.spatial import cKDTree
Image.MAX_IMAGE_PIXELS = None

PDF_PNG = "pdf_hires_real-1.png"
SX, SY, OX, OY = 0.193691, 0.193765, 118.980, 10079.587
STROKE_EXCLUDE_DIST = 80

SNAP_TARGETS = [
    (0, 0, 0), (84, 84, 84), (255, 212, 82), (173, 173, 173), (255, 255, 255),
    (112, 112, 112), (132, 132, 132), (214, 214, 214), (65, 65, 65),
]


def snap(rgb):
    return min(SNAP_TARGETS, key=lambda t: sum((a - b) ** 2 for a, b in zip(t, rgb)))


def world_to_pixel(x, y):
    return OX + x * SX, OY - y * SY


def point_in_polygon(x, y, poly):
    n = len(poly); inside = False; px, py = poly[-1]
    for qx, qy in poly:
        if (py > y) != (qy > y):
            xi = (qx - px) * (y - py) / (qy - py) + px
            if x < xi:
                inside = not inside
        px, py = qx, qy
    return inside


def sample_color(arr, px, py, radius=6):
    H, W, _ = arr.shape
    px, py = int(round(px)), int(round(py))
    y0, y1 = max(0, py - radius), min(H, py + radius + 1)
    x0, x1 = max(0, px - radius), min(W, px + radius + 1)
    if y1 <= y0 or x1 <= x0:
        return (255, 255, 255)
    patch = arr[y0:y1, x0:x1].reshape(-1, 3)
    vals, counts = np.unique(patch, axis=0, return_counts=True)
    return tuple(int(v) for v in vals[np.argmax(counts)])


def decode_shapes(entry, frame_idx=0):
    """Return list of (idx, kind, colorIdx, n, world_points_for_frame)."""
    OFFX, OFFY, SCALE = entry["_OFFX"], entry["_OFFY"], entry["_SCALE"]
    u16 = entry["_u16"]
    cursor = 0
    out = []
    for idx, (k, c, n) in enumerate(entry["h"]):
        base = cursor + frame_idx * n * 2
        pts = []
        for i in range(n):
            xq = u16[base + i * 2]; yq = u16[base + i * 2 + 1]
            pts.append((xq * SCALE + OFFX, yq * SCALE + OFFY))
        out.append((idx, k, c, n, pts))
        cursor += 9 * n * 2
    return out


def sample_p_shape(arr, tree, pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    cx = sum(xs) / len(xs); cy = sum(ys) / len(ys)
    sample_pts = [(cx, cy)]
    step = max(1, len(pts) // 6)
    for i in range(0, len(pts), step):
        vx, vy = pts[i]
        sample_pts.append((cx + 0.6 * (vx - cx), cy + 0.6 * (vy - cy)))
    samples = []
    for sx, sy in sample_pts:
        px, py = world_to_pixel(sx, sy)
        samples.append(snap(sample_color(arr, px, py)))
    return Counter(samples).most_common(1)[0][0]


def sample_fill_dark_gray(arr, tree, pts, dark_rgb=(84, 84, 84)):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    x0, x1 = min(xs), max(xs); y0, y1 = min(ys), max(ys)
    if x1 <= x0 or y1 <= y0:
        return None
    grid_n = 16
    clean, allc = [], []
    for i in range(grid_n):
        for j in range(grid_n):
            gx = x0 + (x1 - x0) * (i + 0.5) / grid_n
            gy = y0 + (y1 - y0) * (j + 0.5) / grid_n
            if not point_in_polygon(gx, gy, pts):
                continue
            px, py = world_to_pixel(gx, gy)
            col = snap(sample_color(arr, px, py, radius=3))
            allc.append(col)
            dist, _ = tree.query((gx, gy))
            if dist > STROKE_EXCLUDE_DIST:
                clean.append(col)
    samples = clean if clean else allc
    if not samples:
        return None
    return Counter(samples).most_common(1)[0][0]


def main():
    with open("t3f_poses.json") as f:
        data = json.load(f)

    jib_entry = dict(data["jib"]["lengths"]["6.0"])
    jib_entry["_OFFX"] = data["jib"]["offx"]; jib_entry["_OFFY"] = data["jib"]["offy"]; jib_entry["_SCALE"] = data["jib"]["scale"]
    u16 = array.array("H"); u16.frombytes(base64.b64decode(jib_entry["d"]))
    jib_entry["_u16"] = u16

    img = Image.open(PDF_PNG).convert("RGB")
    arr = np.array(img)

    shapes = decode_shapes(jib_entry, frame_idx=0)
    p_total = sum(1 for _, k, _, _, _ in shapes if k == "P")
    assert p_total == 334, f"expected 334 base P-kind shapes, got {p_total}"

    stroke_pts = []
    for idx, k, c, n, pts in shapes:
        if k == "S":
            stroke_pts.extend(pts)
    tree = cKDTree(np.array(stroke_pts))
    print(f"stroke vertex count: {len(stroke_pts)}")

    base_palette = data["jib"]["palette"]
    dark_hex = "#545454"
    dark_idx = base_palette.index(dark_hex) if dark_hex in base_palette else -1

    base_colors = {}  # idx -> hex color (real sampled), for P-kind AND dark-gray F-kind
    p_count = 0
    dark_fixed = 0
    for idx, k, c, n, pts in shapes:
        if k == "P":
            p_count += 1
            rgb = sample_p_shape(arr, tree, pts)
            base_colors[idx] = "#%02x%02x%02x" % rgb
        elif k == "F" and c == dark_idx:
            rgb = sample_fill_dark_gray(arr, tree, pts)
            if rgb is not None and rgb != (84, 84, 84):
                base_colors[idx] = "#%02x%02x%02x" % rgb
                dark_fixed += 1

    print(f"Sampled {p_count} P-kind shapes, fixed {dark_fixed} dark-gray F-kind shapes")
    with open("t3f_base_colors.json", "w") as f:
        json.dump(base_colors, f)
    print("Saved t3f_base_colors.json (index -> hex, keyed on the 334-shape base header order)")


if __name__ == "__main__":
    main()
