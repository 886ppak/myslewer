"""
Solve the world-to-pixel affine transform for a reference PDF plot by direct
optimization, instead of the older bbox-ratio approach (compute a world bbox
and a pixel non-white-content bbox, assume they map onto each other exactly).

Why: on the T3F reference plot this was built against, the bbox-ratio method
was off by ~4.5% on the aspect ratio (world bbox ratio 1.595 vs detected
pixel-content ratio 1.523) even though the pixel-bbox detection itself was
clean (no stray content) - the actual source was never fully pinned down,
plausibly a hook/rigging element whose position isn't perfectly deterministic
between the extracted DXF frame and the live re-plot. Rather than chase that
down, this fits directly: project every vertex of one known pose's geometry
under a candidate transform, look up its distance to the nearest ink pixel in
the raster (via a distance-transform of the non-white mask), and minimize the
mean over all vertices. Confirmed by overlay: this cut the naive method's
misalignment by ~6x and produced a pixel-perfect trace over the boom, jib
truss, wheels and cab.

Usage: point WORLD_POINTS_SRC at a helper that yields (x,y) world points for
the SAME pose that was plotted to PDF_PNG (any frame/angle - just has to
match), then run. Prints sx, sy, ox, oy for:
    px = ox + world_x * sx
    py = oy - world_y * sy
Also saves an overlay PNG (downsampled) so you can eyeball the fit before
trusting it - always do that, don't just take the optimizer's word for it.
"""
import json, base64, array, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
from scipy.optimize import minimize

Image.MAX_IMAGE_PIXELS = None


def world_points_for_pose(poses_json, section, length_key, frame_idx=0):
    """Every vertex of one pose (one length, one angle frame) in world space."""
    with open(poses_json) as f:
        d = json.load(f)
    entry = d[section]["lengths"][length_key]
    OFFX, OFFY, SCALE = d[section]["offx"], d[section]["offy"], d[section]["scale"]
    u16 = array.array("H")
    u16.frombytes(base64.b64decode(entry["d"]))
    cursor = 0
    pts = []
    for k, c, n in entry["h"]:
        base = cursor + frame_idx * n * 2
        for i in range(n):
            xq = u16[base + i * 2]; yq = u16[base + i * 2 + 1]
            pts.append((xq * SCALE + OFFX, yq * SCALE + OFFY))
        cursor += 9 * n * 2
    return np.array(pts), entry


def solve(pdf_png, world_pts, downsample=6, white_thresh=250):
    img = Image.open(pdf_png).convert("L")
    small = img.resize((img.width // downsample, img.height // downsample))
    arr = np.array(small)
    nonwhite = arr < white_thresh
    dist = distance_transform_edt(~nonwhite)
    H, W = dist.shape

    # crude bbox-ratio initial guess so the optimizer starts near the basin
    xs, ys = world_pts[:, 0], world_pts[:, 1]
    nz = np.where(nonwhite)
    px_lo, px_hi = nz[1].min(), nz[1].max()
    py_lo, py_hi = nz[0].min(), nz[0].max()
    sx0 = (px_hi - px_lo) / (xs.max() - xs.min())
    sy0 = (py_hi - py_lo) / (ys.max() - ys.min())
    ox0 = px_lo - xs.min() * sx0
    oy0 = py_hi + ys.min() * sy0
    init = [sx0, sy0, ox0, oy0]

    def cost(params):
        sx, sy, ox, oy = params
        px = ox + world_pts[:, 0] * sx
        py = oy - world_pts[:, 1] * sy
        px_i = np.clip(np.round(px).astype(int), 0, W - 1)
        py_i = np.clip(np.round(py).astype(int), 0, H - 1)
        return dist[py_i, px_i].mean()

    print(f"init cost (downsampled px): {cost(init):.3f}", file=sys.stderr)
    res = minimize(cost, init, method="Nelder-Mead",
                    options={"xatol": 1e-6, "fatol": 1e-4, "maxiter": 20000, "maxfev": 20000})
    print(f"optimized cost (downsampled px): {res.fun:.3f}", file=sys.stderr)

    sx, sy, ox, oy = res.x
    sx *= downsample; sy *= downsample; ox *= downsample; oy *= downsample
    print(f"sx={sx:.6f} sy={sy:.6f} ox={ox:.3f} oy={oy:.3f}  (sx/sy ratio={sx/sy:.4f}, "
          f"should be ~1.0 for an undistorted plot)", file=sys.stderr)
    return sx, sy, ox, oy


def save_overlay(pdf_png, world_pts, transform, out_png, shrink=7):
    sx, sy, ox, oy = transform
    img = Image.open(pdf_png).convert("RGB")
    draw = ImageDraw.Draw(img)
    px = ox + world_pts[:, 0] * sx
    py = oy - world_pts[:, 1] * sy
    for x, y in zip(px, py):
        draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(255, 0, 0))
    img.resize((img.width // shrink, img.height // shrink)).save(out_png)
    print(f"saved overlay: {out_png} - inspect it before trusting the fit", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python3 solve_calibration.py <poses.json> <section> <length_key> <pdf_png>", file=sys.stderr)
        sys.exit(1)
    poses_json, section, length_key, pdf_png = sys.argv[1:5]
    pts, _ = world_points_for_pose(poses_json, section, length_key)
    transform = solve(pdf_png, pts)
    save_overlay(pdf_png, pts, transform, "calibration_overlay.png")
