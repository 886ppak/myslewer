"""
Apply t3f_base_colors.json (sampled from the pose_T3F_JL6.0_JA0 reference,
334 P-kind + any dark-gray-fixed F-kind shapes, keyed by index into that
pose's own header list) onto t3f_poses.json's "boom" and "jib" sections.

boom grid + the 5 jib lengths whose header list is index-identical to the
base (verified: 0 kind-mismatches) patch directly by index.

The remaining 12 jib lengths have extra shapes (longer jibs deploy more
lattice-section decal panels) inserted at various points in the list, not
appended at the end - so raw index doesn't line up. Each gets diff-aligned
against the base via difflib.SequenceMatcher on (kind, pointcount) tuples:
matched runs inherit the base's sampled color; unmatched (inserted/new)
entries fall back to the nearest matched neighbor's color, since these are
almost certainly repeats of an already-known decal type - NOT verified
against real pixel ground truth (no reference plot shows a longer jib).
"""
import json, difflib

with open("t3f_poses.json") as f:
    data = json.load(f)
with open("t3f_base_colors.json") as f:
    base_colors_raw = json.load(f)
base_colors = {int(k): v for k, v in base_colors_raw.items()}

BASE_L = "6.0"
base_header = data["jib"]["lengths"][BASE_L]["h"]


def color_idx(palette, hexcol):
    if hexcol not in palette:
        palette.append(hexcol)
    return palette.index(hexcol)


def patch_direct(section, L, palette):
    h = data[section]["lengths"][L]["h"]
    changed = 0
    for idx, newhex in base_colors.items():
        if idx >= len(h):
            continue
        k, c, n = h[idx]
        ni = color_idx(palette, newhex)
        if c != ni:
            h[idx] = [k, ni, n]
            changed += 1
    return changed


def patch_aligned(L, palette):
    h = data["jib"]["lengths"][L]["h"]
    base_t = [(k, n) for k, c, n in base_header]
    other_t = [(k, n) for k, c, n in h]
    sm = difflib.SequenceMatcher(a=base_t, b=other_t, autojunk=False)

    resolved = {}  # j-index -> hex color
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for off in range(i2 - i1):
                bi, oj = i1 + off, j1 + off
                if bi in base_colors:
                    resolved[oj] = base_colors[bi]

    # fill unresolved P/dark-F entries from nearest resolved neighbor
    n_items = len(h)
    unresolved = [j for j in range(n_items) if j not in resolved and h[j][0] in ("P",)]
    for j in unresolved:
        left = right = None
        for d in range(1, n_items):
            if j - d >= 0 and (j - d) in resolved:
                left = resolved[j - d]; break
        for d in range(1, n_items):
            if j + d < n_items and (j + d) in resolved:
                right = resolved[j + d]; break
        pick = left or right
        if pick:
            resolved[j] = pick

    changed = 0
    for j, newhex in resolved.items():
        k, c, n = h[j]
        ni = color_idx(palette, newhex)
        if c != ni:
            h[j] = [k, ni, n]
            changed += 1
    return changed, len(unresolved), sum(1 for j in unresolved if j in resolved)


def main():
    boom_palette = data["boom"]["palette"]
    total = 0
    for L in data["boom"]["lengths"]:
        total += patch_direct("boom", L, boom_palette)
    print(f"boom: patched {total} (length x shape) entries across {len(data['boom']['lengths'])} lengths")

    jib_palette = data["jib"]["palette"]
    direct_lengths = []
    aligned_lengths = []
    for L, entry in data["jib"]["lengths"].items():
        h = entry["h"]
        base_t = [(k, n) for k, c, n in base_header]
        other_t = [(k, n) for k, c, n in h]
        if base_t == other_t[:len(base_t)] and len(other_t) == len(base_t):
            direct_lengths.append(L)
        else:
            aligned_lengths.append(L)

    for L in direct_lengths:
        c = patch_direct("jib", L, jib_palette)
        print(f"jib {L}: direct patch, {c} entries changed")

    for L in aligned_lengths:
        c, n_unresolved, n_fixed_via_neighbor = patch_aligned(L, jib_palette)
        print(f"jib {L}: diff-aligned patch, {c} entries changed "
              f"({n_unresolved} unmatched-new P-shapes, {n_fixed_via_neighbor} filled via nearest neighbor)")

    with open("t3f_poses.json", "w") as f:
        json.dump(data, f, separators=(",", ":"))
    print("Saved t3f_poses.json")


if __name__ == "__main__":
    main()
