"""
TK's jib has no luffing-angle dynamic property (Гусек ТК = length only,
confirmed against the real Nextcloud listing: pose_TK_JL{len}.dxf, no _JA
suffix at all - unlike every other jib-equipped config here). So there's
no 9-angle sweep to interpolate between, and boom_rig_lib.extract_grid()'s
pivot/ground detection (which fits a circle to a landmark's arc across
angle frames) doesn't apply - a single static frame per length can't be
circle-fit at all. This is a deliberately separate, minimal extraction:
one frame per catalog length, no interpolation axis, no pivot/groundY for
the jib section (the boom section's own pivot/groundY still apply as
normal - only the jib is fixed-angle).

Usage: python3 extract_tk_jib.py   (run from a dir with poses/pose_TK_JL{L}.dxf)
Output: merges a "jib" key into tk_ltm1300_poses.json (boom section must
already exist there, from the standard extract_grid() boom pass).
"""
import sys, json, math, struct, base64
from boom_rig_lib import extract_pose_raw, natural_points, resample, MAX_POINTS_PER_PATH

JIB_LENGTHS = ["5.5", "12.5", "19.5", "21.0", "26.5", "28.0", "35.0"]


def main():
    palette = []
    palette_index = {}

    def color_idx(c):
        if c not in palette_index:
            palette_index[c] = len(palette)
            palette.append(c)
        return palette_index[c]

    all_length_data = {}
    for L in JIB_LENGTHS:
        print(f"[jib-fixed-angle] {L} ...", file=sys.stderr)
        items = extract_pose_raw(f"poses/pose_TK_JL{L}.dxf")
        paths_out = []
        for kind, color, obj in items:
            naturals = natural_points(obj)
            if len(naturals) <= MAX_POINTS_PER_PATH:
                frame = [[round(x, 1), round(y, 1)] for x, y in naturals]
            else:
                pts = resample(obj, MAX_POINTS_PER_PATH)
                frame = [[round(x, 1), round(y, 1)] for x, y in pts]
            paths_out.append({"k": kind, "c": color_idx(color), "f": [frame]})  # single frame
        all_length_data[L] = paths_out
        print(f"  {len(paths_out)} paths (single static frame)", file=sys.stderr)

    minx = miny = float("inf")
    maxx = maxy = float("-inf")
    per_length_bbox = {}
    for L in JIB_LENGTHS:
        lminx = lminy = float("inf")
        lmaxx = lmaxy = float("-inf")
        for p in all_length_data[L]:
            for x, y in p["f"][0]:
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
                if x < lminx: lminx = x
                if x > lmaxx: lmaxx = x
                if y < lminy: lminy = y
                if y > lmaxy: lmaxy = y
        per_length_bbox[L] = {"minx": lminx, "maxx": lmaxx, "miny": lminy, "maxy": lmaxy}

    SCALE = 4
    OFFX = math.floor(minx)
    OFFY = math.floor(miny)

    def q(v, off):
        return max(0, min(65535, round((v - off) / SCALE)))

    lengths_out = {}
    for L in JIB_LENGTHS:
        headers = []
        coords = []
        for p in all_length_data[L]:
            n = len(p["f"][0])
            headers.append([p["k"], p["c"], n])
            for x, y in p["f"][0]:
                coords.append(q(x, OFFX))
                coords.append(q(y, OFFY))
        packed = struct.pack(f"<{len(coords)}H", *coords)
        b64 = base64.b64encode(packed).decode("ascii")
        lengths_out[L] = {"h": headers, "d": b64, "bbox": per_length_bbox[L]}

    jib_out = {
        "angles": [0],  # single fixed angle - no luffing on TK's jib
        "palette": palette,
        "offx": OFFX, "offy": OFFY, "scale": SCALE,
        "bbox": {"minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy},
        "lengths": lengths_out,
        "note": "TK jib has no angle dynamic property - single static frame per length, no pivot/groundY fit (can't circle-fit a single frame)",
    }

    with open("tk_ltm1300_poses.json") as f:
        data = json.load(f)
    data["jib"] = jib_out
    with open("tk_ltm1300_poses.json", "w") as f:
        json.dump(data, f, separators=(",", ":"))
    import os
    print(f"Merged jib section into tk_ltm1300_poses.json: "
          f"{os.path.getsize('tk_ltm1300_poses.json')/1e6:.2f} MB", file=sys.stderr)


if __name__ == "__main__":
    main()
