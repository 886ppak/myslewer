# Git workflow

`main` is the primary branch (production, `886ppak.github.io/myslewer/`).
Develop directly on `main`, commit, and push to `origin main`.

Do NOT shadow changes onto `beta-trial` any more (retired as of the LTM
1650 counterweight-dropdown fix — `beta-trial` had drifted far enough
behind main, e.g. missing the entire Lift Library feature, that routine
cherry-picking stopped making sense). Leave `beta-trial`/`myslewer-beta`
alone unless explicitly asked to touch them again.

Confirm each deploy actually landed by fetching `sw.js` from the live
Pages URL and checking `CACHE_VERSION` before considering the work done
(`886ppak.github.io/myslewer/sw.js`).

# App version number

The `.app-version` span next to the MYSLEWER wordmark in `index.html`
(`v2.27` as of this writing) is a separate, user-facing version, distinct
from the internal `CACHE_VERSION` build string. Bump its minor number
(v2.27 -> v2.28 -> ...) on every meaningful push to `main`, same as
`CACHE_VERSION` gets bumped for every app-shell change.

Cap the minor number at .30. Once a push would take the minor number past
.30, roll over to the next major instead: v2.30 -> v3.0 -> v3.1 -> ... ->
v3.30 -> v4.0, and so on for each future major.

Exception: pure user/account-management edits — adding or removing an
email from an allowlist (e.g. `GOOGLE_SIGNIN_ALLOWLIST`), or similar
account-only changes with no feature/UI change attached — bump
`CACHE_VERSION` only, not the app version. `CACHE_VERSION` still has to
move every time regardless (that's what actually gets the change out to
clients), but the visible version number next to the wordmark shouldn't
climb just because someone's access changed.

# Adding a new crane

When the user gives you a new crane's source documents (OEM manual,
load-chart manual, reeving-plan PDF, etc. — typically dropped in their
Nextcloud crane folder) and asks for it to be added, build ALL of the
following for it, not a subset — treat this as the default full scope
unless the user explicitly narrows it (e.g. "skip the boom rig for
now"). Each one is a separate data surface in `index.html`; check
whether the crane's key is already present in each before assuming it's
done:

1. **CWT Combos** (Counterweight tab) — `COUNTERWEIGHT_DATA`
2. **Driving w/ Equipment in Place** — `DRIVING_EQ_DATA`
3. **Crane Layout**: 360° Slew Clearance (`SLEW_CLEARANCE_DATA`),
   outrigger longitudinal/width dims + ground-marking layout
   (`GROUND_LAYOUT_DATA`, `FOOTPRINTS`)
4. **Reeving Plans** — `reeving/manifest.json` entry, `REEVE_CRANE_GROUPS`
   entry, per-config SVGs under `reeving/svg/`
5. **Load Chart Finder** — `LOAD_CHART_FILES` entry + a
   `loadchart/<crane>.json`, extracted from the crane's separate
   Load-chart/Tables manual (NOT the Operating Instructions manual —
   see methodology.txt §14 for the extraction method: PyMuPDF
   `find_tables()`, verified against rendered page images)
6. **Minimum Hook Block Weights** — `cranesData`
7. **Rope Retentioning** — `FLEET_BLOCK_SPEC`

**Boom Rig** (interactive AutoCAD-derived boom/jib CAD viewer) is the
one exception — it needs AutoCAD dynamic-block data the user prepares
separately in Onshape (methodology.txt §11), so it's NOT part of the
default set above. Only build it when the user separately hands over
that CAD export.

For each item, source real data from the documents provided — never
fabricate a figure. If a document needed for one item (e.g. the
load-chart manual) hasn't been provided yet, say so explicitly and ask
for it, rather than silently skipping that item or shipping the rest
and letting the gap go unmentioned. Log the work in methodology.txt as
you go, same as every other entry there.
