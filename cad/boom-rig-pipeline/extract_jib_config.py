"""
Generic boom+jib grid extractor for any LTM 1650 T3-family config, built on
boom_rig_lib.py (factored out of extract_t3f.py). Every config shares the
same 10-length x 9-angle boom sweep; only the jib axis (length catalog,
angle range) varies per config - discovered from the actual Nextcloud file
listing (see README's "Extending to jib-equipped configs" section), never
assumed from the config's name.

Usage:
    python3 extract_jib_config.py CONFIG JL1,JL2,... JA1,JA2,...
    python3 extract_jib_config.py T3FH 6.0,9.5,13.0,... 0,5,10,...

Run from a directory containing poses/pose_{CONFIG}_L{L}_A{A}.dxf and
poses/pose_{CONFIG}_JL{L}_JA{A}.dxf. Output: {config}_poses.json
"""
import sys, json
from boom_rig_lib import extract_grid

BOOM_LENGTHS = ["16.6", "22.4", "28.2", "33.9", "39.7", "45.3", "51.0", "52.0", "53.0", "54.0"]
BOOM_ANGLES = [0, 10, 20, 30, 40, 50, 60, 70, 80]


def main():
    if len(sys.argv) != 4:
        print("Usage: python3 extract_jib_config.py CONFIG JL1,JL2,... JA1,JA2,...", file=sys.stderr)
        sys.exit(1)
    config = sys.argv[1]
    jib_lengths = sys.argv[2].split(",")
    jib_angles = [int(a) for a in sys.argv[3].split(",")]

    boom = extract_grid("boom", BOOM_LENGTHS, BOOM_ANGLES, f"poses/pose_{config}_L{{L}}_A{{A}}.dxf")
    jib = extract_grid("jib", jib_lengths, jib_angles, f"poses/pose_{config}_JL{{L}}_JA{{A}}.dxf")

    out = {"boom": boom, "jib": jib}
    outfile = f"{config.lower()}_poses.json"
    with open(outfile, "w") as f:
        json.dump(out, f, separators=(",", ":"))

    import os
    size = os.path.getsize(outfile)
    print(f"\nSaved {outfile}: {size/1e6:.2f} MB", file=sys.stderr)
    print(f"Boom palette: {len(boom['palette'])} colors", file=sys.stderr)
    print(f"Jib palette: {len(jib['palette'])} colors", file=sys.stderr)


if __name__ == "__main__":
    main()
