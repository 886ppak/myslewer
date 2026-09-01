"""
Apply the two color-correction passes to all_poses.json in place.

THE ORDER BELOW IS NOT OPTIONAL - fix_dark_gray_shapes.py has to run
AFTER the wipeout patch is already applied to all_poses.json, not before.
A pristine extraction resolves WIPEOUT (P-kind) shapes to ezdxf's
background-color placeholder, not a real color at all - so scanning for
"shapes wrongly colored dark-gray that should really be yellow" against
still-pristine data finds almost nothing (that bug was hit once already:
a clean re-extraction followed by running both fixer scripts in the
"obvious" order silently produced a no-op dark-gray pass). Only once the
wipeout patch has given P-kind shapes their real sampled colors does the
dark-gray-vs-should-be-yellow distinction become detectable at all.

Correct sequence:

    python3 extract_all_poses.py
    python3 sample_wipeout_colors.py       # writes wipeout_colors.json
    python3 apply_color_patches.py wipeout # patches P-kind colors into all_poses.json
    python3 fix_dark_gray_shapes.py        # writes dark_gray_fix.json - MUST run after the line above
    python3 apply_color_patches.py darkgray

Both sampling scripts need PDF_PNG (a rasterized reference plot of one
pose, any length/angle) and its WX0/WX1/WY0/WY1/PX0/PX1/PY0/PY1
calibration constants updated for the new crane's own reference plot
before they'll produce anything meaningful - see their own docstrings.
"""
import json
import os
import sys


def apply_wipeout_patch(data):
    if not os.path.exists("wipeout_colors.json"):
        print("SKIP: wipeout_colors.json not found - run sample_wipeout_colors.py first", file=sys.stderr)
        return
    with open("wipeout_colors.json") as f:
        wipeout_colors = json.load(f)  # list of hex, one per P-kind path, encounter order

    palette = data["palette"]

    def color_idx(hexcol):
        if hexcol not in palette:
            palette.append(hexcol)
        return palette.index(hexcol)

    for L, entry in data["lengths"].items():
        h = entry["h"]
        wi = 0
        for idx, (k, c, n) in enumerate(h):
            if k == "P":
                h[idx] = [k, color_idx(wipeout_colors[wi]), n]
                wi += 1
        assert wi == len(wipeout_colors), (
            f"P-kind path count mismatch for length {L}: found {wi}, "
            f"wipeout_colors.json has {len(wipeout_colors)} - re-run "
            f"sample_wipeout_colors.py against the current all_poses.json first"
        )
    print(f"Applied wipeout (P-kind) color patch: {len(wipeout_colors)} paths x "
          f"{len(data['lengths'])} lengths", file=sys.stderr)


def apply_dark_gray_patch(data):
    if not os.path.exists("dark_gray_fix.json"):
        print("SKIP: dark_gray_fix.json not found - run fix_dark_gray_shapes.py first", file=sys.stderr)
        return
    with open("dark_gray_fix.json") as f:
        fix = json.load(f)  # {str(shape_idx): new_palette_idx}
    patch = {int(k): v for k, v in fix.items()}

    changed = 0
    for L, entry in data["lengths"].items():
        h = entry["h"]
        for idx, newc in patch.items():
            k, c, n = h[idx]
            if c != newc:
                h[idx] = [k, newc, n]
                changed += 1
    print(f"Applied dark-gray fix: {len(patch)} shapes, {changed} (length x shape) "
          f"entries actually changed", file=sys.stderr)


def main():
    stage = sys.argv[1] if len(sys.argv) > 1 else None
    if stage not in ("wipeout", "darkgray"):
        print("Usage: python3 apply_color_patches.py [wipeout|darkgray]\n"
              "Run 'wipeout' right after sample_wipeout_colors.py, then run\n"
              "fix_dark_gray_shapes.py, THEN run 'darkgray' - see this file's\n"
              "docstring for why the order matters.", file=sys.stderr)
        sys.exit(1)

    with open("all_poses.json") as f:
        data = json.load(f)

    if stage == "wipeout":
        apply_wipeout_patch(data)
    else:
        apply_dark_gray_patch(data)

    with open("all_poses.json", "w") as f:
        json.dump(data, f)
    print("Saved all_poses.json", file=sys.stderr)


if __name__ == "__main__":
    main()
