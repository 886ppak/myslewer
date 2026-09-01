"""
Generic boom-only extractor (no jib axis at all) for a config on any
crane, built on boom_rig_lib.py. Companion to extract_jib_config.py -
use this one for a config like the LTM 1300's "T" (plain boom, no jib)
or the LTM 1650's T3Y (boom + a separate guy-angle axis, not yet handled
here - see README's G-axis note).

Usage:
    python3 extract_boom_only_config.py CONFIG L1,L2,... A1,A2,... [OUTFILE_SUFFIX]

Run from a directory containing poses/pose_{CONFIG}_L{L}_A{A}.dxf.
Output: {config}_poses.json, or {config}_{suffix}_poses.json if given
(useful to disambiguate cranes sharing a config name, e.g. LTM 1300's "T").
"""
import sys, json, os
from boom_rig_lib import extract_grid


def main():
    if len(sys.argv) < 4:
        print("Usage: python3 extract_boom_only_config.py CONFIG L1,L2,... A1,A2,... [OUTFILE_SUFFIX]",
              file=sys.stderr)
        sys.exit(1)
    config = sys.argv[1]
    boom_lengths = sys.argv[2].split(",")
    boom_angles = [int(a) for a in sys.argv[3].split(",")]
    suffix = f"_{sys.argv[4]}" if len(sys.argv) > 4 else ""

    boom = extract_grid("boom", boom_lengths, boom_angles, f"poses/pose_{config}_L{{L}}_A{{A}}.dxf")
    out = {"boom": boom}
    outfile = f"{config.lower()}{suffix}_poses.json"
    with open(outfile, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print(f"Saved {outfile}: {os.path.getsize(outfile)/1e6:.2f} MB", file=sys.stderr)


if __name__ == "__main__":
    main()
