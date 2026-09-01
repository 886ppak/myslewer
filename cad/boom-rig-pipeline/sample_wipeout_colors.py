"""
Samples the true color for every 'P'-kind (WIPEOUT-derived) shape directly
from a real AutoCAD PDF plot of one pose (L=16.6, A=0), since ezdxf cannot
resolve these colors correctly (verified: even proper BYBLOCK resolution
gives black, not the real per-shape color - the true color only exists in
AutoCAD's own rendering, not recoverable from the DXF data itself).

Shape identity/order is stable across all 90 poses (same block structure,
only coordinates differ), so this one reference PDF is enough to correct
every 'P' shape across the whole grid - no need to plot all 90.

Outputs: wipeout_colors.json - a list of hex colors, one per 'P'-kind path,
in the same order they appear in all_poses.json's per-length path list.
"""
import json, base64, array
from PIL import Image
import numpy as np

PDF_PNG = "pdf_hires-1.png"
REF_LENGTH = "16.6"

# Calibration: A=0-only world bbox for L=16.6 vs the PDF's non-white content
# pixel bbox (both computed and verified to match aspect ratio ~3.39).
WX0, WX1 = 7, 30383
WY0, WY1 = -1995, 6965
PX0, PX1 = 77, 3227
PY0, PY1 = 1876, 2804

# Snap noisy edge-sampled colors to a curated set of real, high-confidence
# colors (large sample counts) to avoid one-off antialiasing artifacts.
SNAP_TARGETS = [
    (84, 84, 84),      # #545454 dark gray
    (255, 212, 82),    # #ffd452 yellow
    (173, 173, 173),   # #adadad light gray
    (255, 255, 255),   # #ffffff white
    (112, 112, 112),   # #707070 mid gray
]


def snap(rgb):
    best = min(SNAP_TARGETS, key=lambda t: sum((a - b) ** 2 for a, b in zip(t, rgb)))
    return best


def world_to_pixel(x, y):
    px = PX0 + (x - WX0) / (WX1 - WX0) * (PX1 - PX0)
    svgy = -y
    svgy0, svgy1 = -WY1, -WY0
    py = PY0 + (svgy - svgy0) / (svgy1 - svgy0) * (PY1 - PY0)
    return px, py


def sample_color(arr, cx, cy, radius=6):
    H, W, _ = arr.shape
    px, py = world_to_pixel(cx, cy)
    px, py = int(round(px)), int(round(py))
    y0, y1 = max(0, py - radius), min(H, py + radius + 1)
    x0, x1 = max(0, px - radius), min(W, px + radius + 1)
    patch = arr[y0:y1, x0:x1].reshape(-1, 3)
    vals, counts = np.unique(patch, axis=0, return_counts=True)
    return tuple(int(v) for v in vals[np.argmax(counts)])


def main():
    with open("all_poses.json") as f:
        data = json.load(f)

    entry = data["lengths"][REF_LENGTH]
    OFFX, OFFY, SCALE = data["offx"], data["offy"], data["scale"]
    binstr = base64.b64decode(entry["d"])
    u16 = array.array("H")
    u16.frombytes(binstr)

    img = Image.open(PDF_PNG).convert("RGB")
    arr = np.array(img)

    cursor = 0
    fill_colors_hex = []  # one entry per P shape, in encounter order
    for k, c, n in entry["h"]:
        if k == "P":
            pts = []
            for i in range(n):
                xq = u16[cursor + i * 2]
                yq = u16[cursor + i * 2 + 1]
                pts.append((xq * SCALE + OFFX, yq * SCALE + OFFY))
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            # Robust against concave/complex shapes where the naive vertex
            # average can fall outside the shape: sample the centroid plus
            # several points pulled 60% of the way from centroid toward
            # spread-out vertices (stays inside for star-shaped-ish
            # polygons), and take the most common color across all samples.
            sample_pts = [(cx, cy)]
            step = max(1, n // 6)
            for i in range(0, n, step):
                vx, vy = pts[i]
                sample_pts.append((cx + 0.6 * (vx - cx), cy + 0.6 * (vy - cy)))
            samples = [snap(sample_color(arr, sx, sy)) for sx, sy in sample_pts]
            from collections import Counter
            rgb = Counter(samples).most_common(1)[0][0]
            fill_colors_hex.append("#%02x%02x%02x" % rgb)
        cursor += 9 * n * 2

    with open("wipeout_colors.json", "w") as f:
        json.dump(fill_colors_hex, f)

    from collections import Counter
    print(f"Sampled {len(fill_colors_hex)} fill-shape colors (F+P)")
    for c, n in Counter(fill_colors_hex).most_common():
        print(" ", c, n)


if __name__ == "__main__":
    main()
