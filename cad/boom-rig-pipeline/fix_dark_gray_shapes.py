"""
Fix mis-colored dark-gray F/P shapes: several large background WIPEOUTs in
dense-linework clusters (engine bay / turret machinery) were sampled as
dark gray (#545454) because a plain grid-majority-vote against the flattened
reference PDF raster gets swamped by the thick black stroke lines drawn on
top of them, even when the shape's true fill is yellow underneath.

Fix: exclude grid sample points that land near ANY real S-kind stroke
vertex (using the actual vector geometry we already extracted, not the
raster) before taking the majority vote, so only "clean" fill-only pixels
count. Genuinely gray/thin shapes (e.g. handrail frames with white
background) are left alone because they have few/no clean points nearby
that read as anything but gray anyway.
"""
import json, base64, array
from collections import Counter
from PIL import Image
import numpy as np
from scipy.spatial import cKDTree

PDF_PNG = "pdf_hires-1.png"
REF_LENGTH = "16.6"
FRAME_IDX = 0  # matches pdf_hires-1.png (A=0)

WX0, WX1 = 7, 30383
WY0, WY1 = -1995, 6965
PX0, PX1 = 77, 3227
PY0, PY1 = 1876, 2804

STROKE_EXCLUDE_DIST = 80  # world units (~mm), matches stroke-width=12 w/ generous margin

SNAP_TARGETS = [
    (0,0,0),(84,84,84),(255,212,82),(173,173,173),(255,255,255),
    (112,112,112),(132,132,132),(214,214,214),
]
def snap(rgb):
    return min(SNAP_TARGETS, key=lambda t: sum((a-b)**2 for a,b in zip(t,rgb)))

def world_to_pixel(x,y):
    px = PX0 + (x-WX0)/(WX1-WX0)*(PX1-PX0)
    svgy = -y
    svgy0, svgy1 = -WY1, -WY0
    py = PY0 + (svgy-svgy0)/(svgy1-svgy0)*(PY1-PY0)
    return px,py

def point_in_polygon(x,y,poly):
    n=len(poly); inside=False; px,py=poly[-1]
    for qx,qy in poly:
        if (py>y)!=(qy>y):
            xi=(qx-px)*(y-py)/(qy-py)+px
            if x<xi: inside = not inside
        px,py=qx,qy
    return inside

def sample_color(arr,px,py,radius=3):
    H,W,_=arr.shape
    px,py=int(round(px)),int(round(py))
    y0,y1=max(0,py-radius),min(H,py+radius+1)
    x0,x1=max(0,px-radius),min(W,px+radius+1)
    if y1<=y0 or x1<=x0: return (255,255,255)
    patch=arr[y0:y1,x0:x1].reshape(-1,3)
    vals,counts=np.unique(patch,axis=0,return_counts=True)
    return tuple(int(v) for v in vals[np.argmax(counts)])

def main():
    with open("all_poses.json") as f:
        data = json.load(f)
    entry = data["lengths"][REF_LENGTH]
    OFFX,OFFY,SCALE = data["offx"],data["offy"],data["scale"]
    u16 = array.array("H"); u16.frombytes(base64.b64decode(entry["d"]))
    img = Image.open(PDF_PNG).convert("RGB")
    arr = np.array(img)

    palette = data["palette"]
    dark_idx = palette.index("#545454")
    yellow_idx = palette.index("#ffd452")

    # Pass 1: collect all S-kind stroke vertices at FRAME_IDX -> build KD-tree
    cursor = 0
    stroke_pts = []
    shapes = []  # (idx, kind, colorIdx, n, cursor)
    for idx, (k, c, n) in enumerate(entry["h"]):
        base = cursor + FRAME_IDX * n * 2
        if k == "S":
            for i in range(n):
                xq = u16[base+i*2]; yq = u16[base+i*2+1]
                stroke_pts.append((xq*SCALE+OFFX, yq*SCALE+OFFY))
        shapes.append((idx, k, c, n, cursor))
        cursor += 9 * n * 2

    tree = cKDTree(np.array(stroke_pts))
    print(f"stroke vertex count: {len(stroke_pts)}")

    changes = {}  # idx -> new colorIdx
    checked = 0
    for idx, k, c, n, cur in shapes:
        if k not in ("F","P") or c != dark_idx:
            continue
        checked += 1
        base = cur + FRAME_IDX * n * 2
        poly = []
        for i in range(n):
            xq = u16[base+i*2]; yq = u16[base+i*2+1]
            poly.append((xq*SCALE+OFFX, yq*SCALE+OFFY))
        xs=[p[0] for p in poly]; ys=[p[1] for p in poly]
        x0,x1=min(xs),max(xs); y0,y1=min(ys),max(ys)
        if x1<=x0 or y1<=y0:
            continue
        grid_n = 16
        clean_samples = []
        all_samples = []
        for i in range(grid_n):
            for j in range(grid_n):
                gx = x0+(x1-x0)*(i+0.5)/grid_n
                gy = y0+(y1-y0)*(j+0.5)/grid_n
                if not point_in_polygon(gx,gy,poly):
                    continue
                px,py = world_to_pixel(gx,gy)
                col = snap(sample_color(arr,px,py))
                all_samples.append(col)
                dist,_ = tree.query((gx,gy))
                if dist > STROKE_EXCLUDE_DIST:
                    clean_samples.append(col)
        samples = clean_samples if clean_samples else all_samples
        if not samples:
            continue
        winner = Counter(samples).most_common(1)[0][0]
        hexcol = "#%02x%02x%02x" % winner
        if hexcol in palette:
            new_idx = palette.index(hexcol)
        else:
            new_idx = len(palette)
            palette.append(hexcol)
        if new_idx != dark_idx:
            changes[idx] = (new_idx, hexcol, len(clean_samples), len(all_samples))

    print(f"checked {checked} dark-gray F/P shapes, {len(changes)} would change")
    for idx,(ni,hc,ncl,nall) in sorted(changes.items())[:50]:
        print(f"  idx={idx} -> {hc} (clean={ncl}/{nall})")

    with open("dark_gray_fix.json","w") as f:
        json.dump({str(k): v[0] for k,v in changes.items()}, f)
    with open("palette_updated.json","w") as f:
        json.dump(palette, f)

if __name__ == "__main__":
    main()
