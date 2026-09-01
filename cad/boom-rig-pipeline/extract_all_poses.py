import ezdxf, math, json, struct, base64, sys
import numpy as np
from ezdxf.addons.drawing.recorder import Recorder
from ezdxf.addons.drawing import RenderContext, Frontend

LENGTHS = ["16.6","22.4","28.2","33.9","39.7","45.3","51.0","52.0","53.0","54.0"]
ANGLES = [0, 10, 20, 30, 40, 50, 60, 70, 80]
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
    # NumpyPoints2d (PointsRecord) - already a plain vertex list
    return [(v.x, v.y) for v in obj.vertices()]


def resample(obj, n):
    if hasattr(obj, "flattening"):
        flat = list(obj.flattening(3))
        coords = [(p.x, p.y) for p in flat]
    else:
        coords = [(v.x, v.y) for v in obj.vertices()]
    if len(coords) < 2:
        nat = natural_points(path)
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
    """A single path object can itself contain disjoint sub-loops (e.g. an
    outer boundary + an inner hole, opposite winding, concatenated into one
    control-vertex list). Rendered as one polygon that connects outer-to-hole
    with a spurious straight line. Split into separate loops instead - loses
    the true hole punch-through but avoids the connector-line artifact,
    matching how multi-path fills are already handled one level up."""
    if getattr(p, "has_sub_paths", False):
        return list(p.sub_paths())
    return [p]


def flatten_paths(record, tname):
    """Return list of path-like objects for this record (one, or several for fills)."""
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
    """Return list of items: (kind, color, path_object_or_point)"""
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
    """Kasa least-squares circle fit. pts: [(x,y),...]. Returns (cx,cy,r,residuals)."""
    x = np.array([p[0] for p in pts]); y = np.array([p[1] for p in pts])
    A = np.c_[2 * x, 2 * y, np.ones(len(x))]
    b = x ** 2 + y ** 2
    sol, *_ = np.linalg.lstsq(A, b, rcond=None)
    cx, cy, c = sol
    r = math.sqrt(c + cx ** 2 + cy ** 2)
    resid = [math.hypot(px - cx, py - cy) - r for px, py in pts]
    return cx, cy, r, resid


def find_pivot(all_length_data, LENGTHS):
    """Locate the boom's mechanical pivot (foot pin) directly from the
    data: every point ON the rotating boom traces a circle centred on the
    pivot as it sweeps through the captured angles, so track whichever
    vertex moves the most between the first and last angle frame (a
    reliable proxy for "something out near the boom tip, far from the
    pivot") and least-squares circle-fit its 9-angle arc. Repeated
    independently for every catalog length and cross-checked against each
    other - real mechanical pivots don't move with boom length, so if the
    fitted centre doesn't agree to within a few mm across all lengths,
    something is wrong (wrong landmark picked, or this crane's block has
    some other animated part sharing the angle sweep)."""
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

    print("\nPivot fit per length:", file=sys.stderr)
    for L, cx, cy, r, maxresid in fits:
        try:
            expect_r = float(L) * 1000
        except ValueError:
            expect_r = float("nan")
        print(f"  L={L:>6}  pivot=({cx:9.1f},{cy:8.1f})  r={r:9.1f} (expect~{expect_r:.0f})  "
              f"max|residual|={maxresid:.2f}mm", file=sys.stderr)
    print(f"  averaged pivot=({pivot_x:.1f},{pivot_y:.1f})  "
          f"spread=({spread_x:.1f},{spread_y:.1f})mm across {len(LENGTHS)} lengths", file=sys.stderr)
    if spread_x > 200 or spread_y > 200:
        print("  WARNING: pivot fit disagrees by >200mm across lengths - verify the "
              "landmark-selection heuristic actually picked a genuine boom-tip point at "
              "every length (an animated jib/attachment sharing the same angle sweep could "
              "throw this off) before trusting DATA.pivot downstream.", file=sys.stderr)

    return pivot_x, pivot_y


def find_ground_y(all_length_data, LENGTHS):
    """Ground level = wherever the single largest cluster of vertices sits
    near the bottom of the drawing - every wheel's tangent-to-ground point
    repeats at the same Y, so that cluster dwarfs any other low point
    (an outrigger pad mark, a dimension tick, etc). Much more reliable
    than trusting the raw minimum Y in the drawing, which usually belongs
    to one of those isolated low details instead of genuine ground
    contact."""
    # Chassis/wheel geometry is static across boom length, so one length's
    # frame-0 vertices are enough - no need to aggregate all of them (and
    # aggregating would also mean the window below has to account for
    # wildly different per-length Y ranges, which is what actually caused
    # this to misfire in testing: a window sized as a % of the full
    # multi-length Y range pulled in unrelated upper-vehicle geometry).
    # A crane's lowest drawn point is always at or extremely close to
    # actual ground contact (a wheel, or at worst an outrigger pad a
    # little below it) - so a fixed, generous few-metre window above
    # the drawing's own minimum Y reliably brackets "near ground" without
    # needing to know anything about this crane's actual scale.
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
    print(f"\nGround level: y={ground_y:.1f}  (peak histogram bin within {WINDOW_MM}mm of the "
          f"drawing's lowest point, {hist[peak_i]} vertices, vs drawing minimum {all_y[0]:.1f})",
          file=sys.stderr)
    return ground_y


def main():
    all_length_data = {}
    palette = []
    palette_index = {}

    def color_idx(c):
        if c not in palette_index:
            palette_index[c] = len(palette)
            palette.append(c)
        return palette_index[c]

    for L in LENGTHS:
        print(f"Length {L}m ...", file=sys.stderr)
        # extract raw items for all 9 angles
        per_angle_items = []
        for A in ANGLES:
            fname = f"poses/pose_L{L}_A{A}.dxf"
            items = extract_pose_raw(fname)
            per_angle_items.append(items)

        n_items = len(per_angle_items[0])
        for items in per_angle_items:
            assert len(items) == n_items, f"item count mismatch for L={L}"

        # determine per-index whether natural vertex counts agree across angles
        paths_out = []  # list of dicts: kind, color_idx, frames: [ [ [x,y],... ] x9 ]
        for idx in range(n_items):
            kind0, color0, obj0 = per_angle_items[0][idx]

            naturals = []
            for a in range(9):
                _, _, obj = per_angle_items[a][idx]
                naturals.append(natural_points(obj))
            counts = set(len(n) for n in naturals)
            max_natural = max(len(n) for n in naturals)
            if len(counts) == 1 and max_natural <= MAX_POINTS_PER_PATH:
                frames = [[[round(x, 1), round(y, 1)] for x, y in naturals[a]] for a in range(9)]
            else:
                target_n = min(max(max_natural, 4), MAX_POINTS_PER_PATH)
                frames = []
                for a in range(9):
                    _, _, obj = per_angle_items[a][idx]
                    pts = resample(obj, target_n)
                    frames.append([[round(x, 1), round(y, 1)] for x, y in pts])
            paths_out.append({"k": kind0, "c": color_idx(color0), "f": frames})

        all_length_data[L] = paths_out
        total_pts = sum(len(p["f"][0]) * 9 for p in paths_out)
        print(f"  {n_items} paths, {total_pts} total points across 9 angles", file=sys.stderr)

    # global bounding box (needed for the shared Uint16 quantization range)
    # plus a per-length bbox (so each length can use its own tight viewBox).
    minx = miny = float("inf")
    maxx = maxy = float("-inf")
    per_length_bbox = {}
    for L in LENGTHS:
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
    print(f"\nGlobal bbox: x=[{minx},{maxx}] y=[{miny},{maxy}]", file=sys.stderr)

    SCALE = 4  # doc units per Uint16 step (4mm resolution)
    OFFX = math.floor(minx)
    OFFY = math.floor(miny)
    span_x = (maxx - OFFX) / SCALE
    span_y = (maxy - OFFY) / SCALE
    print(f"Uint16 span needed: x={span_x:.0f} y={span_y:.0f} (max 65535)", file=sys.stderr)
    assert span_x < 65535 and span_y < 65535, "scale too fine, coordinates overflow Uint16"

    def q(v, off):
        return max(0, min(65535, round((v - off) / SCALE)))

    lengths_out = {}
    for L in LENGTHS:
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

    pivot_x, pivot_y = find_pivot(all_length_data, LENGTHS)
    ground_y = find_ground_y(all_length_data, LENGTHS)

    out = {
        "angles": ANGLES,
        "palette": palette,
        "offx": OFFX, "offy": OFFY, "scale": SCALE,
        "bbox": {"minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy},
        "pivot": {"x": round(pivot_x, 1), "y": round(pivot_y, 1)},
        "groundY": round(ground_y, 1),
        "lengths": lengths_out,
    }

    with open("all_poses.json", "w") as f:
        json.dump(out, f, separators=(",", ":"))

    import os
    size = os.path.getsize("all_poses.json")
    print(f"\nTotal packed JSON size: {size/1e6:.2f} MB", file=sys.stderr)
    print(f"Palette: {len(palette)} colors: {palette}", file=sys.stderr)


if __name__ == "__main__":
    main()
