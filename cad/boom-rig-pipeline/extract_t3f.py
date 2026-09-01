"""
Extraction for jib-equipped configs (proof-of-concept: T3F), generalizing
extract_all_poses.py's single-axis (boom length x angle) approach to TWO
independent axis-pairs captured via the decoupled-sweep methodology:

  - "boom" grid: boom length x boom angle, jib held at a fixed reference
    (JL/JA) throughout - same shape as the original LTM 1650 T3 dataset.
  - "jib" grid: jib length x jib angle, boom held at a fixed reference
    (L/A = the "G30" boom-angle-30 reference used across the T3-family
    reference PDFs) throughout.

Each grid is self-contained (own palette, own pivot/groundY fit) and
structurally IDENTICAL to extract_all_poses.py's single-axis output - the
"pivot" fit for the jib grid locates the JIB's own hinge point (the mount
on the boom tip), not the boom's foot pin, because it's fit from the same
"vertex that moves most, circle-fit across the swept angle samples"
heuristic applied to the jib's own JA sweep instead of the boom's A sweep.

Does NOT attempt to recombine the two grids into one fully-independent
4-DOF (L, A, JL, JA) rig - that requires decomposing the jib grid into a
local frame relative to the boom tip and re-attaching it under the boom's
live rotation, which is a separate, not-yet-validated step. This script's
job is just the proof-of-concept: confirm the extraction pipeline handles
jib-equipped block configs and produces two independently-correct grids.

Usage: python3 extract_t3f.py   (run from a directory containing poses/)
Output: t3f_poses.json
"""
import ezdxf, math, json, struct, base64, sys
import numpy as np
from ezdxf.addons.drawing.recorder import Recorder
from ezdxf.addons.drawing import RenderContext, Frontend

BOOM_LENGTHS = ["16.6", "22.4", "28.2", "33.9", "39.7", "45.3", "51.0", "52.0", "53.0", "54.0"]
BOOM_ANGLES = [0, 10, 20, 30, 40, 50, 60, 70, 80]
JIB_LENGTHS = ["6.0", "9.5", "13.0", "16.5", "20.0", "23.5", "27.0", "30.5",
               "34.0", "37.5", "41.0", "44.5", "48.0", "51.5", "55.0", "58.5", "62.0"]
JIB_ANGLES = [0, 5, 10, 15, 20, 25, 30, 35, 40]
MAX_POINTS_PER_PATH = 20


def get_records(fname):
    doc = ezdxf.readfile(fname)
    msp = doc.modelspace()
    ctx = RenderContext(doc)
    backend = Recorder()
    Frontend(ctx, backend).draw_layout(msp, finalize=True)
    return backend.records, backend.properties


def natural_points(obj):
    if hasattr(obj, "control_vertices"):
        return [(v.x, v.y) for v in obj.control_vertices()]
    return [(v.x, v.y) for v in obj.vertices()]


def resample(obj, n):
    if hasattr(obj, "flattening"):
        flat = list(obj.flattening(3))
        coords = [(p.x, p.y) for p in flat]
    else:
        coords = [(v.x, v.y) for v in obj.vertices()]
    if len(coords) < 2:
        nat = natural_points(obj)
        base = nat[0] if nat else (0.0, 0.0)
        return [base] * n
    dists = [0.0]
    for i in range(1, len(coords)):
        dx = coords[i][0] - coords[i - 1][0]
        dy = coords[i][1] - coords[i - 1][1]
        dists.append(dists[-1] + math.hypot(dx, dy))
    total = dists[-1]
    if total == 0:
        return [coords[0]] * n
    out = []
    for k in range(n):
        target = total * k / (n - 1)
        i = 1
        while i < len(dists) and dists[i] < target:
            i += 1
        i = min(i, len(dists) - 1)
        seg_len = dists[i] - dists[i - 1]
        t = 0.0 if seg_len == 0 else (target - dists[i - 1]) / seg_len
        x = coords[i - 1][0] + t * (coords[i][0] - coords[i - 1][0])
        y = coords[i - 1][1] + t * (coords[i][1] - coords[i - 1][1])
        out.append((x, y))
    return out


def expand_sub_paths(p):
    if getattr(p, "has_sub_paths", False):
        return list(p.sub_paths())
    return [p]


def flatten_paths(record, tname):
    if tname == "PathRecord":
        base = [record.path] if record.path is not None else []
    elif tname == "FilledPathsRecord":
        base = list(record.paths)
    else:
        return []
    out = []
    for p in base:
        out.extend(expand_sub_paths(p))
    return out


def extract_pose_raw(fname):
    records, properties = get_records(fname)
    items = []
    for r in records:
        tname = type(r).__name__
        props = properties[r.property_hash]
        color = props.color
        if tname in ("PathRecord", "FilledPathsRecord"):
            kind = "S" if tname == "PathRecord" else "F"
            for p in flatten_paths(r, tname):
                items.append((kind, color, p))
        elif tname == "PointsRecord":
            items.append(("P", color, r.points))
    return items


def circle_fit(pts):
    x = np.array([p[0] for p in pts]); y = np.array([p[1] for p in pts])
    A = np.c_[2 * x, 2 * y, np.ones(len(x))]
    b = x ** 2 + y ** 2
    sol, *_ = np.linalg.lstsq(A, b, rcond=None)
    cx, cy, c = sol
    r = math.sqrt(c + cx ** 2 + cy ** 2)
    resid = [math.hypot(px - cx, py - cy) - r for px, py in pts]
    return cx, cy, r, resid


def find_pivot(all_length_data, LENGTHS, label):
    fits = []
    for L in LENGTHS:
        paths = all_length_data[L]
        best = None
        for p in paths:
            frames = p["f"]
            n = len(frames[0])
            for vi in range(n):
                x0, y0 = frames[0][vi]
                x8, y8 = frames[-1][vi]
                d = (x0 - x8) ** 2 + (y0 - y8) ** 2
                if best is None or d > best[0]:
                    best = (d, p, vi)
        _, p, vi = best
        arc = [tuple(frame[vi]) for frame in p["f"]]
        cx, cy, r, resid = circle_fit(arc)
        fits.append((L, cx, cy, r, max(abs(v) for v in resid)))

    xs = [f[1] for f in fits]; ys = [f[2] for f in fits]
    pivot_x = sum(xs) / len(xs); pivot_y = sum(ys) / len(ys)
    spread_x = max(xs) - min(xs); spread_y = max(ys) - min(ys)

    print(f"\n[{label}] Pivot fit per axis-length:", file=sys.stderr)
    for L, cx, cy, r, maxresid in fits:
        print(f"  {L:>6}  pivot=({cx:9.1f},{cy:8.1f})  r={r:9.1f}  "
              f"max|residual|={maxresid:.2f}mm", file=sys.stderr)
    print(f"  averaged pivot=({pivot_x:.1f},{pivot_y:.1f})  "
          f"spread=({spread_x:.1f},{spread_y:.1f})mm across {len(LENGTHS)} values", file=sys.stderr)
    if spread_x > 200 or spread_y > 200:
        print(f"  WARNING [{label}]: pivot fit disagrees by >200mm across axis-lengths.", file=sys.stderr)

    return pivot_x, pivot_y


def find_ground_y(all_length_data, LENGTHS):
    L0 = LENGTHS[0]
    all_y = [y for p in all_length_data[L0] for x, y in p["f"][0]]
    all_y.sort()
    WINDOW_MM = 3000
    cutoff = all_y[0] + WINDOW_MM
    low_y = [y for y in all_y if y <= cutoff]
    if not low_y:
        return all_y[0]
    hist, edges = np.histogram(low_y, bins=60)
    peak_i = int(np.argmax(hist))
    ground_y = (edges[peak_i] + edges[peak_i + 1]) / 2
    return ground_y


def extract_grid(label, lengths, angles, fname_pattern, find_pivot_landmark=True):
    """fname_pattern: a format string taking L= and A= kwargs, e.g.
    'poses/pose_T3F_L{L}_A{A}.dxf' or 'poses/pose_T3F_JL{L}_JA{A}.dxf'."""
    all_length_data = {}
    palette = []
    palette_index = {}

    def color_idx(c):
        if c not in palette_index:
            palette_index[c] = len(palette)
            palette.append(c)
        return palette_index[c]

    for L in lengths:
        print(f"[{label}] {L} ...", file=sys.stderr)
        per_angle_items = []
        for A in angles:
            fname = fname_pattern.format(L=L, A=A)
            items = extract_pose_raw(fname)
            per_angle_items.append(items)

        n_items = len(per_angle_items[0])
        for items in per_angle_items:
            assert len(items) == n_items, f"[{label}] item count mismatch for {L}"

        paths_out = []
        for idx in range(n_items):
            kind0, color0, obj0 = per_angle_items[0][idx]
            naturals = []
            for a in range(len(angles)):
                _, _, obj = per_angle_items[a][idx]
                naturals.append(natural_points(obj))
            counts = set(len(n) for n in naturals)
            max_natural = max(len(n) for n in naturals)
            if len(counts) == 1 and max_natural <= MAX_POINTS_PER_PATH:
                frames = [[[round(x, 1), round(y, 1)] for x, y in naturals[a]] for a in range(len(angles))]
            else:
                target_n = min(max(max_natural, 4), MAX_POINTS_PER_PATH)
                frames = []
                for a in range(len(angles)):
                    _, _, obj = per_angle_items[a][idx]
                    pts = resample(obj, target_n)
                    frames.append([[round(x, 1), round(y, 1)] for x, y in pts])
            paths_out.append({"k": kind0, "c": color_idx(color0), "f": frames})

        all_length_data[L] = paths_out
        total_pts = sum(len(p["f"][0]) * len(angles) for p in paths_out)
        print(f"  {n_items} paths, {total_pts} total points across {len(angles)} angles", file=sys.stderr)

    minx = miny = float("inf")
    maxx = maxy = float("-inf")
    per_length_bbox = {}
    for L in lengths:
        lminx = lminy = float("inf")
        lmaxx = lmaxy = float("-inf")
        for p in all_length_data[L]:
            for frame in p["f"]:
                for x, y in frame:
                    if x < minx: minx = x
                    if x > maxx: maxx = x
                    if y < miny: miny = y
                    if y > maxy: maxy = y
                    if x < lminx: lminx = x
                    if x > lmaxx: lmaxx = x
                    if y < lminy: lminy = y
                    if y > lmaxy: lmaxy = y
        per_length_bbox[L] = {"minx": lminx, "maxx": lmaxx, "miny": lminy, "maxy": lmaxy}
    print(f"[{label}] Global bbox: x=[{minx},{maxx}] y=[{miny},{maxy}]", file=sys.stderr)

    SCALE = 4
    OFFX = math.floor(minx)
    OFFY = math.floor(miny)
    span_x = (maxx - OFFX) / SCALE
    span_y = (maxy - OFFY) / SCALE
    assert span_x < 65535 and span_y < 65535, f"[{label}] scale too fine, coordinates overflow Uint16"

    def q(v, off):
        return max(0, min(65535, round((v - off) / SCALE)))

    lengths_out = {}
    for L in lengths:
        headers = []
        coords = []
        for p in all_length_data[L]:
            n = len(p["f"][0])
            headers.append([p["k"], p["c"], n])
            for frame in p["f"]:
                for x, y in frame:
                    coords.append(q(x, OFFX))
                    coords.append(q(y, OFFY))
        packed = struct.pack(f"<{len(coords)}H", *coords)
        b64 = base64.b64encode(packed).decode("ascii")
        lengths_out[L] = {"h": headers, "d": b64, "bbox": per_length_bbox[L]}

    pivot_x, pivot_y = find_pivot(all_length_data, lengths, label)
    ground_y = find_ground_y(all_length_data, lengths)

    return {
        "angles": angles,
        "palette": palette,
        "offx": OFFX, "offy": OFFY, "scale": SCALE,
        "bbox": {"minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy},
        "pivot": {"x": round(pivot_x, 1), "y": round(pivot_y, 1)},
        "groundY": round(ground_y, 1),
        "lengths": lengths_out,
    }


def main():
    boom = extract_grid("boom", BOOM_LENGTHS, BOOM_ANGLES, "poses/pose_T3F_L{L}_A{A}.dxf")
    jib = extract_grid("jib", JIB_LENGTHS, JIB_ANGLES, "poses/pose_T3F_JL{L}_JA{A}.dxf")

    out = {"boom": boom, "jib": jib}
    with open("t3f_poses.json", "w") as f:
        json.dump(out, f, separators=(",", ":"))

    import os
    size = os.path.getsize("t3f_poses.json")
    print(f"\nTotal packed JSON size: {size/1e6:.2f} MB", file=sys.stderr)
    print(f"Boom palette: {len(boom['palette'])} colors", file=sys.stderr)
    print(f"Jib palette: {len(jib['palette'])} colors", file=sys.stderr)


if __name__ == "__main__":
    main()
