"""
Generic version of calibrate_t3f.py: sample colors from a config's own
L16.6_A0 reference plot (334-shape base, same as every LTM 1650 T3-family
config's boom grid) using a validated affine transform from
solve_calibration.py, then patch both the boom grid (direct index) and jib
grid (diff-align within the SAME config - proven reliable, unlike the
cross-config transfer that was tried and disproven) of that config's own
poses.json.

Usage: python3 calibrate_config.py CONFIG poses.json ref.png sx sy ox oy
"""
import json, base64, array, difflib, sys
from collections import Counter
from PIL import Image
import numpy as np
from scipy.spatial import cKDTree
Image.MAX_IMAGE_PIXELS = None

STROKE_EXCLUDE_DIST = 80
SNAP_TARGETS = [
    (0, 0, 0), (84, 84, 84), (255, 212, 82), (173, 173, 173), (255, 255, 255),
    (112, 112, 112), (132, 132, 132), (214, 214, 214), (65, 65, 65),
]


def snap(rgb):
    return min(SNAP_TARGETS, key=lambda t: sum((a - b) ** 2 for a, b in zip(t, rgb)))


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


def point_in_polygon(x, y, poly):
    n = len(poly); inside = False; px, py = poly[-1]
    for qx, qy in poly:
        if (py > y) != (qy > y):
            xi = (qx - px) * (y - py) / (qy - py) + px
            if x < xi:
                inside = not inside
        px, py = qx, qy
    return inside


def sample_p_shape(arr, w2p, pts):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    cx = sum(xs) / len(xs); cy = sum(ys) / len(ys)
    sample_pts = [(cx, cy)]
    step = max(1, len(pts) // 6)
    for i in range(0, len(pts), step):
        vx, vy = pts[i]
        sample_pts.append((cx + 0.6 * (vx - cx), cy + 0.6 * (vy - cy)))
    samples = []
    for sx, sy in sample_pts:
        px, py = w2p(sx, sy)
        samples.append(snap(sample_color(arr, px, py)))
    return Counter(samples).most_common(1)[0][0]


def sample_fill_dark_gray(arr, tree, w2p, pts):
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
            px, py = w2p(gx, gy)
            col = snap(sample_color(arr, px, py, radius=3))
            allc.append(col)
            dist, _ = tree.query((gx, gy))
            if dist > STROKE_EXCLUDE_DIST:
                clean.append(col)
    samples = clean if clean else allc
    if not samples:
        return None
    return Counter(samples).most_common(1)[0][0]


def decode_shapes(entry, frame_idx=0):
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


def color_idx(palette, hexcol):
    if hexcol not in palette:
        palette.append(hexcol)
    return palette.index(hexcol)


def main():
    config = sys.argv[1]
    poses_path = sys.argv[2]
    ref_png = sys.argv[3]
    sx, sy, ox, oy = [float(v) for v in sys.argv[4:8]]

    def w2p(x, y):
        return ox + x * sx, oy - y * sy

    with open(poses_path) as f:
        data = json.load(f)

    boom_entry = dict(data["boom"]["lengths"]["16.6"])
    boom_entry["_OFFX"] = data["boom"]["offx"]; boom_entry["_OFFY"] = data["boom"]["offy"]; boom_entry["_SCALE"] = data["boom"]["scale"]
    u16 = array.array("H"); u16.frombytes(base64.b64decode(boom_entry["d"]))
    boom_entry["_u16"] = u16

    img = Image.open(ref_png).convert("RGB")
    arr = np.array(img)

    shapes = decode_shapes(boom_entry, frame_idx=0)
    p_total = sum(1 for _, k, _, _, _ in shapes if k == "P")
    print(f"[{config}] base shapes: {len(shapes)} total, {p_total} P-kind", file=sys.stderr)

    stroke_pts = []
    for idx, k, c, n, pts in shapes:
        if k == "S":
            stroke_pts.extend(pts)
    tree = cKDTree(np.array(stroke_pts))

    boom_palette = data["boom"]["palette"]
    dark_hex = "#545454"
    dark_idx = boom_palette.index(dark_hex) if dark_hex in boom_palette else -1

    base_colors = {}
    p_count = 0
    dark_fixed = 0
    for idx, k, c, n, pts in shapes:
        if k == "P":
            p_count += 1
            rgb = sample_p_shape(arr, w2p, pts)
            base_colors[idx] = "#%02x%02x%02x" % rgb
        elif k == "F" and c == dark_idx:
            rgb = sample_fill_dark_gray(arr, tree, w2p, pts)
            if rgb is not None and rgb != (84, 84, 84):
                base_colors[idx] = "#%02x%02x%02x" % rgb
                dark_fixed += 1
    print(f"[{config}] sampled {p_count} P-kind, fixed {dark_fixed} dark-gray F-kind", file=sys.stderr)

    # patch boom (direct index - same shape list as the base itself)
    changed = 0
    for idx, newhex in base_colors.items():
        k, c, n = boom_entry["h"][idx]
        ni = color_idx(boom_palette, newhex)
        if c != ni:
            changed += 1
    for L in data["boom"]["lengths"]:
        h = data["boom"]["lengths"][L]["h"]
        for idx, newhex in base_colors.items():
            if idx >= len(h):
                continue
            k, c, n = h[idx]
            ni = color_idx(boom_palette, newhex)
            if c != ni:
                h[idx] = [k, ni, n]
    print(f"[{config}] boom: patched across {len(data['boom']['lengths'])} lengths", file=sys.stderr)

    # patch jib (diff-align against the boom base header, same as apply_t3f_colors.py)
    if "jib" in data:
        jib_palette = data["jib"]["palette"]
        base_header = boom_entry["h"]
        base_tn = [(k, n) for k, c, n in base_header]
        for L, entry in data["jib"]["lengths"].items():
            h = entry["h"]
            other_tn = [(k, n) for k, c, n in h]
            sm = difflib.SequenceMatcher(a=base_tn, b=other_tn, autojunk=False)
            resolved = {}
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag == "equal":
                    for off in range(i2 - i1):
                        bi, oj = i1 + off, j1 + off
                        if bi in base_colors:
                            resolved[oj] = base_colors[bi]
            n_items = len(h)
            unresolved = [j for j in range(n_items) if j not in resolved and h[j][0] == "P"]
            for j in unresolved:
                pick = None
                for d in range(1, n_items):
                    if j - d >= 0 and (j - d) in resolved:
                        pick = resolved[j - d]; break
                    if j + d < n_items and (j + d) in resolved:
                        pick = resolved[j + d]; break
                if pick:
                    resolved[j] = pick
            changed = 0
            for j, newhex in resolved.items():
                k, c, n = h[j]
                ni = color_idx(jib_palette, newhex)
                if c != ni:
                    h[j] = [k, ni, n]
                    changed += 1
            print(f"[{config}] jib {L}: {changed} changed, {len(unresolved)} unmatched-new "
                  f"P-shapes filled via neighbor", file=sys.stderr)

    with open(poses_path, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    print(f"[{config}] Saved {poses_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
