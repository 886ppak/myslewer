# Boom rig pipeline — build an interactive 2D crane diagram from real AutoCAD data

Built for the LTM 1650-8.1 boom rig (2026-09-01). Produces an SVG diagram
with working boom-length and boom-angle controls, where every frame is
real AutoCAD dynamic-block-evaluated geometry — not a heuristic
classification or hand-traced approximation. Reusable for any other crane
model that ships as a Liebherr AutoCAD dynamic block.

The whole point of this pipeline: AutoCAD's dynamic block already knows
how to correctly evaluate the boom at any length/angle combination
(that's what the block's own parameters are for) — so get AutoCAD itself
to do that evaluation many times over a grid of poses, export each result,
and turn the set into an interpolated web rig. Don't try to reimplement
boom kinematics from scratch.

## Pipeline overview

```
AutoCAD dynamic block (.dwg)
  -> export_sweep.lsp run inside AutoCAD/AutoCAD LT
     (sets the block's own length/angle parameters, WBLOCKs each pose)
  -> N x M pose .dwg files (N lengths x M angles)
  -> ODA File Converter -> .dxf (ASCII, same version)
  -> extract_all_poses.py (ezdxf, on this side)
     - also derives the boom's pivot point + ground level directly from
       the geometry (find_pivot() / find_ground_y()) and embeds them
  -> all_poses.json (Uint16-quantized, base64-packed, one blob for
     every pose - pristine colors at this point, see step 5 below)
  -> sample_wipeout_colors.py -> apply_color_patches.py wipeout
     -> fix_dark_gray_shapes.py -> apply_color_patches.py darkgray
     - REQUIRED, exact order matters - see "Two root-cause bugs" below
  -> rig_template.html (+ window.__RIG_DATA__ = all_poses.json)
  -> published as a Claude Artifact / dropped into the app
```

**Re-running `extract_all_poses.py` overwrites `all_poses.json` from
scratch, including any color patches already applied to it** - the color
step (5, below) has to be re-run every time, it does not "stick" through
a re-extraction. This bit once already in this project: a clean
re-extraction (only to pick up pivot/ground detection, nothing color-
related) silently regenerated the pre-bug-2-fix, wrong-color dataset,
because the color patches live in separate JSON files applied as a
post-process, not in `extract_all_poses.py` itself.

### 1. `export_sweep.lsp` — run inside AutoCAD LT, by the person, not Claude

Claude cannot run AutoCAD. This AutoLISP script is meant to be loaded and
run BY THE USER inside their own AutoCAD LT session, batch-exporting a
grid of dynamic-block poses so Claude can turn the outputs into a rig
without ever touching AutoCAD directly.

Commands defined:
- `TESTSWEEP` — exports 4 poses, for a quick sanity check before the full run
- `EXPORTSWEEP` — exports the full sweep (10 lengths x 9 angles = 90 files
  for the LTM 1650 config used here)

Key correctness details, all hard-won:
- Sets the block's OWN dynamic properties (`Стрела T3` = length,
  `Наклон основной стрелы` = angle in radians — property names are
  whatever the source block actually calls them; inspect with
  `GetDynamicBlockProperties` first) via `vlax-put`, then `vla-Update`/
  regens, rather than trying to redraw the boom geometrically.
- Copies the block reference (`vla-Copy`) and `-wblock`s the COPY —
  never explode it first. Exploding disconnects entities from their
  BYBLOCK color context and breaks live FIELD text (e.g. the model
  callout on the boom). WBLOCK-ing an un-exploded reference preserves
  both.
- Deletes any pre-existing output file before each `-wblock`
  (`vl-catch-all-apply 'vl-file-delete`) — otherwise AutoCAD's overwrite
  confirmation prompt breaks the scripted command sequencing on any
  re-run.

Output: `%USERPROFILE%\Documents\export\pose_L{length}_A{angle}.dwg`

### 2. Convert to DXF

ODA File Converter (free, from Open Design Alliance), batch mode, ASCII
DXF output, same AutoCAD version as the source. Anything that reads DXF
would technically work, but `extract_all_poses.py` is written against
ezdxf's own file reader.

### 3. `extract_all_poses.py` — the extraction pipeline

Uses ezdxf's `Recorder` backend (`RenderContext` + `Frontend` +
`Recorder`) to get already-resolved, already-flattened path/point
geometry per pose, rather than walking raw DXF entities and resolving
color/transform/curve-flattening by hand.

Per pose file: extracts `PathRecord` (stroke/line work, kind `'S'`),
`FilledPathsRecord` (solid fills/hatches, kind `'F'`), `PointsRecord`
(WIPEOUT-derived shapes, kind `'P'`) in encounter order. A path can
itself contain disjoint sub-loops (an outer boundary + inner hole
concatenated into one vertex list) — `expand_sub_paths` splits those to
avoid a spurious connector line between them.

Cross-pose consistency: for a rig to interpolate smoothly, every pose at
a given (length, path-index) needs the SAME point count across all 9
angle samples, so the same index in the flat coordinate array always
means "this vertex" no matter the angle. If natural vertex counts agree
across all 9 angles for a given path AND are small enough
(`MAX_POINTS_PER_PATH = 20`), the natural points are kept; otherwise
every angle's version of that path gets arc-length resampled to a common
point count. `assert len(items) == n_items` guards that entity counts
themselves don't drift between angle samples — if that fires, config
states (e.g. a jib section that only exists at some angles, or a
different lookup state) are in play and need to be scoped out before
this approach works at all.

Output format (`all_poses.json`): a shared color palette (list of hex
strings, deduplicated across all poses), a `pivot: {x, y}` + `groundY`
(world-mm, see below), plus one entry per length containing:
- `h`: header list, one `[kind, paletteColorIndex, pointCount]` per path,
  in the SAME order for every length (this stability is what lets a
  color patch keyed by index apply across all lengths at once — see
  below)
- `d`: base64 of a flat `Uint16Array` — every path's 9 angle-frames'
  (x,y) pairs back to back, quantized to a shared `OFFX/OFFY/SCALE` grid
  (`SCALE = 4` doc units per step here, i.e. ~4mm resolution — plenty for
  a diagram, and keeps the whole 90-pose set well under a browser tab's
  reasonable memory/network budget)

**Pivot and ground detection** (`find_pivot()` / `find_ground_y()`, run
automatically at the end of `main()`): locates the boom's mechanical
pivot (foot pin) and ground level directly from the extracted geometry,
no manual measurement or per-crane constants needed.

- *Pivot*: every point on the rotating boom traces a circle centred on
  the pivot as it sweeps through the 9 captured angles. For each length
  independently, the vertex that moved the most between the first and
  last angle frame (a reliable "something out near the boom tip, far
  from the pivot" proxy) gets its 9-angle arc least-squares circle-fit.
  The fitted centre is then cross-checked across all N catalog lengths -
  a genuine mechanical pivot doesn't move with boom length, so if the
  fits disagree by more than ~200mm the script prints a warning (wrong
  landmark picked, or this crane's block has some other part - a jib,
  say - animated across the same angle sweep, confusing the heuristic).
  On the LTM 1650 data this agreed to within 0.3mm across all 10
  lengths using the full-precision (pre-quantization) coordinates.
- *Ground*: the single largest cluster of vertices within a few metres
  of the drawing's lowest point - every wheel's tangent-to-ground point
  repeats at the same Y, so that cluster dwarfs any other low-lying
  detail (an outrigger pad mark, a dimension tick). Deliberately scoped
  to ONE length's own geometry with a fixed absolute window (not a
  percentage of the full multi-length Y range, which pulls in unrelated
  upper-vehicle geometry once a long boom's near-vertical pose is in the
  mix - this was tried and produced a visibly wrong, too-high pivot
  height until narrowed down).

### 4. Color patches — REQUIRED, run every time after extraction

`all_poses.json` fresh out of `extract_all_poses.py` has wrong colors
(see "Two root-cause bugs" below, bug 2). Run in EXACTLY this order —
`fix_dark_gray_shapes.py` has to run after the wipeout patch is already
applied to the file, not before (a pristine extraction resolves WIPEOUT
shapes to ezdxf's background-color placeholder, not a real color, so
scanning for "colored dark-gray but should be yellow" against still-
pristine data finds almost nothing — hit this once already, see
`apply_color_patches.py`'s own docstring):
```
python3 sample_wipeout_colors.py        # writes wipeout_colors.json
python3 apply_color_patches.py wipeout  # patches P-kind colors in
python3 fix_dark_gray_shapes.py         # writes dark_gray_fix.json - now sees real P-kind colors
python3 apply_color_patches.py darkgray # patches the dark-gray-fix shapes in
```
Both sampling scripts need their `PDF_PNG` reference image and
`WX0/WX1/WY0/WY1/PX0/PX1/PY0/PY1` calibration constants updated for the
new crane's own reference plot first — see bug 2 below for how those are
derived, and each script's own docstring.

### 5. `rig_template.html` — the interpolating SVG rig + building clearance

Vanilla JS, no dependencies. Decodes one length's `Uint16Array` blob
lazily, builds one `<polygon>`/`<polyline>` per path once per length
selection, and on angle change just linearly interpolates each vertex
between the two bracketing captured angle samples (10° spacing here) and
rewrites `points`. Cheap enough to run on every slider `input` event.

Also includes a built-in **building clearance check**: adjustable
building height and standoff-distance sliders, with a live readout of
the minimum safe boom-down angle before the boom's pivot→tip line fouls
the building (`tan(criticalAngle) = (buildingHeight - pivotHeight) /
standoff`) and the working radius that angle gives you, plus the current
radius and a CLEAR/FOULING status that tracks the live angle slider.
Boom-only clearance (the boom structure itself, not hook/rope sag under
load). Entirely driven by `DATA.pivot`/`DATA.groundY` from step 3 above
— no crane-specific constants in the template itself, so this carries
over automatically to whatever crane's `all_poses.json` gets loaded.

To use for a new crane: run the pipeline above to get a new
`all_poses.json`, then inject it before this template's IIFE:
```html
<script>window.__RIG_DATA__ = /* ...all_poses.json contents... */;</script>
<!-- rig_template.html contents follow -->
```
`LENGTH_ORDER` inside the template needs updating to that crane's own
catalog length list.

## Two root-cause bugs found the hard way — read this before repeating the process

These cost the most time in this build and will recur on any future
crane unless deliberately avoided.

### Bug 1: fills painted over their own outline strokes (z-order)

**Symptom:** boom/cab/counterweight rendered as flat blobs of color with
NO visible black line detail anywhere, despite the line-work data being
present and correct in the extraction.

**Root cause:** raw DXF entity order interleaves each component's stroke
(outline) entities immediately followed by that same component's fill —
e.g. `S,S,S,F,P,S,S,...`. Rendered in that literal order, the fill paints
directly on top of the strokes that were JUST drawn, hiding them
completely. AutoCAD's real on-screen paint order is NOT simply raw
database/creation order — it has its own draw-order resolution that
ezdxf's `Recorder`-based extraction (unlike its own native
`matplotlib`/other renderer backends) doesn't reproduce; it just replays
entities in encounter order.

**How it was actually diagnosed** (don't skip straight to the fix without
this step on a future crane — verify the theory first): temporarily hide
all fill/`polygon` elements in the built HTML (`#rig-svg polygon {
display: none !important; }`) and re-render. If the stroke-only render
looks complete and correct (matches the reference), it confirms the line
data was extracted fine all along and this is purely a z-order problem —
not a missing-geometry problem.

**Fix**, in `getLengthData()` inside `rig_template.html`: stable-sort
each length's path list so every fill (`F`/`P`) renders before every
stroke (`S`), preserving relative order within each group:
```js
paths.sort((a, b) => {
  const rank = (k) => (k === 'S' ? 1 : 0);
  return rank(a.k) - rank(b.k);
});
```
This matches AutoCAD's real convention (fills as a background layer,
line detail always on top) and is already baked into this repo's copy of
`rig_template.html`. It's a pure render-order fix — touches no color
data, safe to apply unconditionally to any future extraction from this
same pipeline.

### Bug 2: WIPEOUT/hatch fill colors can't be read from the DXF data at all

**Symptom:** individual shapes (mostly WIPEOUT-derived, kind `'P'`) come
back the wrong color no matter how carefully BYBLOCK/BYLAYER resolution
is implemented — even "correct" resolution gives black, not the shape's
real visible color. This is a `ezdxf`-and-DXF-format limitation, not a
bug in this pipeline's code: `Frontend.draw_wipeout_entity` in ezdxf's
drawing addon hardcodes WIPEOUT fill to the current layout's background
color regardless of the entity's true resolved color, and the true color
in general isn't fully recoverable from the DXF data by any third-party
reader — it only exists in AutoCAD's own internal rendering logic.

**Fix:** sample real colors directly from AutoCAD's own PDF output
(Publish/plot a reference pose to PDF, rasterize with `pdftoppm -r 300`+,
sample pixel colors at each shape's known world-space location using the
SAME quantized coordinates already in `all_poses.json`). Shape identity
and order are stable across every length in the same dataset (confirmed:
identical path count for every length here), so ONE reference PDF plot
covers every length/angle combination — no need to plot all N*M poses.

**The subtlety that actually caused most of the wasted time:** naive
color sampling (take a shape's centroid, or centroid + a few points
pulled toward vertices, snap to the nearest of a curated color list) is
NOT robust for two different reasons layered on top of each other:

1. **Large/concave/multi-region shapes** — a single WIPEOUT can span a
   wide area that's mostly one color with a small sub-region of another
   (e.g. a chassis hatch mostly gray with a small yellow notch). A
   centroid-based sample can land in the minority sub-region by pure
   chance depending on the shape's exact geometry. Fix: grid-sample many
   points across the shape's bounding box, keep only the ones inside the
   polygon via ray-casting (`point_in_polygon`), majority-vote the result
   — representative of the shape's actual visible area instead of one
   lucky/unlucky point.

2. **Shapes underneath dense line-work** — a background WIPEOUT's TRUE
   fill can be a single flat color (e.g. solid yellow) that, in the
   flattened reference PDF raster, is mostly covered by a dense mesh of
   separately-drawn stroke lines on top of it (hoses, panel outlines,
   mechanical detail). Even the grid-majority-vote from (1) gets fooled
   here: MORE of the sampled pixel area can genuinely be the thick black
   strokes than the shape's own true color, so majority vote on the raw
   raster gives the WRONG answer with high confidence. This is what
   caused the engine-bay/turret cluster to render dark gray when it's
   actually solid yellow underneath the line detail.

   Fix (`fix_dark_gray_shapes.py`): use the pipeline's OWN already-
   extracted vector stroke geometry (not more raster inference) to
   exclude any grid sample point that falls within `STROKE_EXCLUDE_DIST`
   world units of a real `S`-kind stroke vertex, THEN majority-vote only
   the remaining "clean" points. This is a general, principled fix (not
   a per-shape guess) — it correctly recovered yellow for the
   dense-linework shapes while leaving genuinely-gray shapes (e.g. a
   handrail frame with no fill at all underneath) unchanged, and even
   independently reproduced a previously-known-correct answer for one
   shape (a large chassis hatch that should read gray) as a sanity check.

   **This still isn't perfect** — a couple of shapes with very little
   "clean" polygon area (small/thin/mostly-covered-by-stroke) needed a
   manual override after visually inspecting a zoomed crop of the
   reference PDF at that shape's exact world-space location, because the
   automated method is conservative and under-fixes rather than
   over-fixes (it left a few known-bad shapes unchanged rather than risk
   flipping a correct one). Treat the automated pass as the first cut,
   then spot-check a rendered result against the reference PDF at
   multiple lengths/angles before trusting it, same as this build did
   (see verification below).

**Lesson for next time:** don't sample fill colors from a flattened
raster at all if it can be avoided. If a future export can capture each
entity's resolved RGB color directly (e.g. by NOT wrapping the WIPEOUT
resolution through ezdxf's Frontend, or by asking AutoCAD itself to
report resolved colors via the AutoLISP export script — e.g.
`vlax-get` the entity's `TrueColor`/`Color` property at export time,
before the WIPEOUT-specific rendering quirk ever enters the picture),
that sidesteps this entire class of bug. Wasn't discovered as a cleaner
alternative until after the raster-sampling approach above was already
built and working — worth trying FIRST on a future crane.

## Extending to jib-equipped configs (proof-of-concept: T3F)

The pipeline above assumes ONE swept axis-pair (boom length x angle). A
jib-equipped config (T3F on the LTM 1650) needs a second, independent
axis-pair (jib length x jib angle), captured via the same decoupled-sweep
idea used elsewhere in this project: a boom L x A grid with the jib held at
a fixed reference state, PLUS a jib JL x JA grid with the boom held at
whatever fixed reference state the export used (not otherwise recorded -
the pipeline never needed to know it, only that it's held constant across
the whole jib sweep). `extract_t3f.py` generalizes `extract_all_poses.py`'s
per-axis logic into a reusable `extract_grid()` function and runs it twice,
producing `t3f_poses.json` with independent `"boom"` and `"jib"` sections
(each with its own palette, pivot, groundY - `find_pivot()` applied to the
jib's own JA sweep locates the jib's hinge point on the boom tip, not the
boom's own foot pivot; on this data it fit to 0.0mm spread across all 17
jib lengths, tighter even than the boom's own 0.3mm).

`extract_t3f.py` was since generalized into `boom_rig_lib.py` (the shared
`extract_grid()`/pivot/ground logic) + `extract_jib_config.py` (a thin CLI
driver: config name + that config's own jib length/angle lists) to extend
this to the other 8 T3-family configs without copy-pasting the script per
config - each config's jib axis range was pulled straight from the real
Nextcloud file listing (`pose_{CONFIG}_JL{len}_JA{angle}.dxf`), not assumed
from the name: e.g. the N-family (T3N/T3NH/T3NY/T3NYH) uses a completely
different 21-length jib catalog (21.0-91.0m) than the F-family's 17-length
one (6.0-62.0m) T3F used.

**A third independent axis surfaced going through the other configs: guy
angle** (`G30`/`G45`/`G60` in the filenames - only 3 discrete states, not a
dense sweep), present on every "Y" config (T3Y, T3NY, T3NYH, T3YVEF,
T3YVEFH) on top of whichever of the boom/jib axes that config also has.
This is what the 5 existing reference PDFs (`pose_T3Y_G30`, etc.) actually
are - a specific guy-angle state, unrelated to boom angle. (Earlier text in
this file called `G30` a "boom angle 30° reference" - that was wrong,
corrected here; the two are unrelated dimensions.) Not yet extracted or
built out - only 3 poses per length instead of a 9-angle sweep, so it likely
doesn't need the same interpolation machinery, but that's unverified.

**Does NOT** attempt a full 4-DOF (L, A, JL, JA) combined rig - that would
require decomposing the jib grid into a local frame relative to the boom
tip and re-attaching it under the boom's live rotation, not yet built or
validated. The two grids currently drive two separate diagrams.

### Two new problems this surfaced (neither existed in the boom-only case)

**1. Bbox-ratio calibration can silently be wrong by several percent.**
The original `sample_wipeout_colors.py`/`fix_dark_gray_shapes.py` approach
computes `WX0/WX1/WY0/WY1` (a world bbox) and `PX0/PX1/PY0/PY1` (the PDF
raster's non-white content bbox) and assumes they map onto each other
directly. On the T3F reference plot this was off by ~4.5% on the aspect
ratio (1.595 world vs 1.523 pixel) even though the pixel-bbox detection
itself was clean - no stray content, robust to threshold changes. Root
cause not fully pinned down (plausibly a hook/rigging element that isn't
perfectly deterministic between the extracted DXF frame and a fresh live
plot); rather than chase it, **`solve_calibration.py`** replaces the whole
bbox-ratio idea with direct optimization: project a known pose's geometry
under a candidate affine transform, minimize its vertices' distance to the
nearest ink pixel (via a distance-transform of the raster's non-white
mask, scipy Nelder-Mead over `sx, sy, ox, oy`). Cut mean misalignment by
~6x here and produced a pixel-perfect overlay (verify with the
`calibration_overlay.png` it saves - don't trust the optimizer blindly,
same rule as everything else in this pipeline). **Use this for any future
crane instead of the bbox-ratio method** - it needs no manually-read pixel
coordinates at all, just one already-known pose's geometry and its plot.

**2. WIPEOUT (P-kind) shape count isn't always constant across an axis.**
The whole color-patch method assumes a fixed shape count/order across
every value of the swept axis, verified true for the boom-only case (P-kind
count was constant at every catalog length) - but on T3F's jib axis, P-kind
count GROWS with jib length (334 at JL=6.0 up to 366 at JL=41.0) because
longer jibs deploy more lattice-section decal panels, and the extra
entries are inserted throughout the list, not appended at the end (checked
via common-prefix length - diverges around index ~2810 out of 3385, well
before the list ends). Index-based patching breaks here.

Fix (`calibrate_t3f.py` + `apply_t3f_colors.py`): sample colors from ONE
reference plot (any jib length works - `pose_T3F_JL6.0_JA0` was used here,
the shortest, which happens to carry exactly the "base" 334-shape set
common to every other length too, boom grid included - confirmed by diff,
0 kind-mismatches for the boom grid and the five jib lengths that also
have exactly 334 P-shapes). For lengths whose header list doesn't match
1:1, `difflib.SequenceMatcher` on `(kind, pointcount)` tuples aligns each
length's list against the base: matched runs inherit the base's sampled
color, and any genuinely-new (inserted) entries fall back to their nearest
matched neighbor's color. On this data that covered 8-32 unresolved
shapes per length (out of 3385+), all successfully filled via a neighbor -
**that fallback is a reasonable approximation for repeated decal-type
panels, not verified pixel ground truth** (no reference plot shows a
longer jib yet). Get a second reference plot at a longer jib length if
per-shape accuracy on those extra panels matters before publishing.

### Files added for this

- `extract_t3f.py` - generalizes `extract_all_poses.py` into a reusable
  `extract_grid()`, run twice (boom axis, jib axis) into one
  `t3f_poses.json` with `"boom"`/`"jib"` sections
- `solve_calibration.py` - direct-optimization world-to-pixel calibration
  (see problem 1 above); reusable for any future crane's reference plot,
  supersedes the bbox-ratio approach in `sample_wipeout_colors.py`
- `calibrate_t3f.py` - samples P-kind + dark-gray-fixed F-kind colors from
  the reference pose's own 334-shape base list (combines what
  `sample_wipeout_colors.py` + `fix_dark_gray_shapes.py` did separately)
- `apply_t3f_colors.py` - patches `t3f_poses.json`'s boom section directly
  by index, and the jib section via direct index (where the header list
  matches 1:1) or diff-alignment + nearest-neighbor fallback (see problem
  2 above)

## Verification checklist before publishing

Take screenshots (Playwright/headless Chromium against the built HTML
file works well — `page.goto('file://...')`, drive the length `<select>`
and angle `<input type=range>` via `dispatchEvent`) at:
- multiple boom lengths (shortest, longest, at least one mid-range)
- multiple angles (0°, and whatever the default slider value is)
- crop and directly compare against the reference PDF/plot at the same
  region — don't eyeball the whole diagram at once, the bugs above are
  both local-region bugs that are easy to miss zoomed out

## Files in this folder

- `export_sweep.lsp` — AutoLISP, run by the user inside AutoCAD LT
- `extract_all_poses.py` — DXF -> `all_poses.json`, run with ezdxf and
  numpy installed, from a directory containing a `poses/` subfolder of
  `pose_L{length}_A{angle}.dxf` files. Also derives and embeds
  `pivot`/`groundY` automatically (see "Pivot and ground detection"
  above) — no manual measurement needed per crane.
- `sample_wipeout_colors.py` — samples real WIPEOUT (P-kind) colors from
  a reference AutoCAD PDF plot; calibration constants (`WX0/WX1/WY0/WY1/
  PX0/PX1/PY0/PY1`, `PDF_PNG`) are specific to the LTM 1650 reference
  plot used here and need recalibrating per crane (compute from the
  reference PDF's non-white content bbox vs. the known world-space bbox
  of the same pose)
- `fix_dark_gray_shapes.py` — reference implementation of the stroke-
  aware color-correction pass (bug 2 above); same per-crane calibration
  constants as above, MUST be run after the wipeout patch is applied
  (see "Color patches" above for why)
- `apply_color_patches.py` — applies the two sampling scripts' output
  (`wipeout_colors.json`, `dark_gray_fix.json`) into `all_poses.json`;
  takes a `wipeout` or `darkgray` argument, run in that order with the
  sampling scripts interleaved, never both at once
- `rig_template.html` — the reusable rig shell: z-order fix and the
  building-clearance feature both already applied, both driven by
  `DATA.pivot`/`DATA.groundY`/`DATA.lengths[L].bbox` rather than
  hardcoded constants. Inject a new `all_poses.json` as
  `window.__RIG_DATA__` and update `LENGTH_ORDER` to build a rig for a
  different crane — everything else carries over automatically.

The actual LTM 1650 `all_poses.json` (~11.5MB) and its 90 source
DXF/pose files are not committed here — regenerate from the pipeline
above if needed (verified byte-reproducible end to end, given the same
source DXFs and reference PDF), or pull the live version straight from
the published artifact.
