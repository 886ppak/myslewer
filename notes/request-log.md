# Request Log

Purpose: a durable, append-only record of instructions/requests, kept
separate from chat history so nothing sent gets lost if a message drops,
a session compacts, or a conversation gets cut off mid-task. Every
substantive message logged here as soon as it arrives — before other
work continues — with a short status note once it's actioned.

Not part of the PWA itself (same as the other files in notes/) — this is
a working record, not app content.

---

## 2026-08-24

- **Cab Entry tool (artifact, not in this repo's codebase)**: default
  slew/radius to 180°/0m; click fields directly instead of a separate
  switch button; add Weight + Item Name fields that persist across log
  entries; pick/land (up/down arrow) toggle; new/old toggle for straight
  replacements; redesign UI to fit cleanly; collapsible bird's-eye
  clickable dot-plot view, placeholder/model-agnostic.
  **Status: done** — all built, tested, published to the artifact URL.
- Follow-up: dial-half click also switches slew side; Backspace/Delete
  clears the current input field.
  **Status: done.**
- Follow-up: readout should say "180" not "FRONT"; rename TAIL to REAR;
  Backspace/Delete should also fully clear Weight and Name fields, on
  all devices (not just numeric fields).
  **Status: done.**
- Request to keep a durable log of incoming messages so none get lost
  while work is in progress — this file.
  **Status: done (this entry).**
- Remove the red "out-of-range" color on a near-zero slew reading - it
  wrongly implies near-zero slew means near load capacity, which isn't
  true at all; a near-rear reading is just a normal reading.
  **Status: done** — the out-of-range flag/red styling removed entirely.
- Keep the 2D bird's-eye plot as-is. ALSO add a separate 3D plotter,
  same dots/same data, with a generic placeholder crane carrier (person
  referenced "the 110") sitting static in the middle - the specific
  crane model doesn't matter, this section is about load pick/place
  history (where a lift came from, where it went) so a back-to-back
  shift can see it at a glance, not about modelling the real crane.
  **Status: done** — hand-rolled isometric canvas view (no 3D library
  available inside an Artifact), same underlying position data as the
  2D radar, generic placeholder carrier box+mast, tested and published.
- Replace the on-screen custom numeric keypad with the device's own
  native keyboard popping up (e.g. Android's) for Radius/Slew/Weight
  entry - current fixed keypad makes it hard to see what's actually
  being typed, and native input should be cleaner UI-wise too. Person
  asked directly whether I agreed - yes, and for a real reason: the
  custom keypad's "buffer vs committed value" state machine is the
  actual root cause of every bug fixed so far in this build.
  **Status: done** — Radius/Weight/Slew are now real `inputmode="decimal"`
  inputs (device keyboard pops up on tap, native caret/backspace/
  selection); the whole active-field/entry-buffer state machine, the
  on-screen keypad grid, and the custom Backspace/Delete handler were
  removed outright rather than kept alongside. Tested (typing, blur
  reformatting, side-select + dial-half still work, full log flow, 3D
  plotter unaffected) and published. Also merged onto a newer version
  another session/agent had published in the meantime, so nothing from
  that round (red-zero fix, 3D plotter) was lost in the process.
- Revision to the slew default: 0, not 180 (radius stays 0m too). Both
  Radius/Slew/Weight should show their default as ghosted placeholder
  text, not a real pre-filled value, so the user never has to backspace
  it out before typing. And the 3D plotter isn't what was asked for -
  person wants the REAL LTM110T 3D carrier model (the actual GLB/
  Three.js infrastructure already in this repo - vendor/carrier3d.js,
  vendor/three/*, the .glb models) as the centrepiece with plots around
  it, not a hand-rolled placeholder box. Since an Artifact's CSP can't
  load Three.js from a CDN or reach this repo's own files at all, the
  whole Cab Entry tool should move INTO the actual PWA as a new tab,
  gated to the owner only (same userAccess/{uid} opt-in pattern as
  Service Fill/Assembly Plans) - not another Artifact.
  **Status: done** — new "Cab Entry" tab, owner-only (cabEntryAccess flag
  granted to myslewer@gmail.com), new vendor/cabentry3d.js module loading
  the real LTM 1110 carrier GLB with a real Three.js scene (own renderer,
  not folded into the shared carrier3d.js). Defaults are 0m/0deg shown
  as placeholder ghost text, slewSide starts genuinely unset. Restyled
  to the app's own existing design tokens/components rather than the
  Artifact's separate palette. Found and fixed a real bug in testing
  (3D dot hit-target was too small to reliably tap - fixed with a larger
  invisible hit-sphere). Tested end-to-end against the real app
  including the full 3D click-to-info path, plus smoke-tested three
  unrelated tabs for regressions. Shipped to main (CACHE_VERSION v225,
  app v5.30) - not shadowed to beta-trial, which has no auth system to
  gate an owner-only tab with.
- Remove the FRONT side-select button from Cab Entry - not worth the
  space, doesn't do anything.
  **Status: done** — removed, and cleaned up every now-dead 'front'
  branch it left behind rather than leaving unreachable code. Testing
  this surfaced a real bug: the slew input's own </> affix wasn't
  suppressed at exactly 180deg the way the dial's big readout already
  was, so it showed "< 180" while the dial showed plain "180" for the
  same reading - fixed to match. Shipped to main (CACHE_VERSION v226,
  app v6.0 - hit the .30 cap, rolled to next major per CLAUDE.md).
- "3d view loaded nothing" - reported with a screenshot from a real
  tablet (2D radar working, 3D panel just an empty box, no error).
  **Status: done** — root cause: the LTM 1110 carrier GLB is 32MB, one
  of the two largest of the seven exports - fine on a fast local test,
  not fine on a real device's network/memory. Switched the placeholder
  model to LRT 1100 (7.3MB, the smallest one). Also fixed the underlying
  bug class: this panel had zero loading/error visibility before, so a
  slow or failed load looked exactly like nothing happening - added a
  loading overlay and a real error message, plus fixed a related bug
  found while wiring it in (a failed load was permanently blocking retry
  on reopen). Verified the failure/retry path by pointing a scratch copy
  of the module at a genuinely missing file, since network route-mocking
  wasn't reliably reaching this panel's fetch in testing. Shipped to
  main (CACHE_VERSION v227, app v6.1).
- Is there an LTM option for the 3D carrier instead of LRT 1100? Also add
  a Fit View option.
  **Status: done** — gave all six LTM sizes, person picked LTM 1300
  (10.5MB, lightest LTM, still a 3x cut from the original 32MB LTM
  1110). Fit View added as a .toolbar-btn matching the exact convention
  already used for the Outrigger tab's own 3D preview, re-frames to fit
  the model + every currently plotted dot. Verified the real network
  request now hits ltm1300-carrier.glb, and confirmed (via temporary
  debug hooks, removed before shipping) that Fit View genuinely restores
  the camera after a manual pan, not just that the button doesn't error.
  Shipped to main (CACHE_VERSION v228, app v6.2).
- Fit View gives a weird angled/isometric view, not the top-down bird's-
  eye it should.
  **Status: done** — real bug: the first version of Fit View reused the
  same angled framing as the initial auto-frame, not the actual top-down
  math this app already settled on for the Outrigger tab's own Fit View
  button (methodology.txt 10.85). Ported that real math in - directly
  overhead camera, FOV-fitted distance, tiny tilt to avoid a degenerate
  OrbitControls angle. Verified via temporary debug hooks (removed
  before shipping) that the camera position is now genuinely near-
  overhead after Fit View, not just "moved." Shipped to main
  (CACHE_VERSION v229, app v6.3).
- Can the input fields sit together without scrolling - move the dial,
  or collapse it? Discussed both, person chose: move Status + Log
  Reading above the dial, dial sits below all the input fields instead.
  **Status: done** — dial (now its own "Slew Reference" card) moved from
  between Load and Position to after the Log Reading button. Full entry
  sequence (Name, Weight, Radius, Slew, side-select, Pick/Land, New/Old,
  Log Reading) is now one uninterrupted run. Pure DOM reorder, no JS
  changes needed (everything's id-based) - specifically checked the one
  order-dependent selector in this tab (the 3D panel's details.card[1]
  toggle listener) and confirmed it's unaffected since the dial isn't a
  details element. Verified at a realistic tablet viewport (400x850)
  that Name-through-Log-Reading now fits without scrolling, and that
  dial-half taps still work from the new position. Shipped to main
  (CACHE_VERSION v230, app v6.4).
- Move Status (Pick/Land, New/Old) into the bottom of the Position card,
  and remove its disclaimer text.
  **Status: done** — merged, no separate Status card anymore, disclaimer
  removed entirely. Log button's bottom edge dropped to 635px (was
  790px after the dial move alone) at the same tablet viewport test -
  measurably more compact, not just reordered. Shipped to main
  (CACHE_VERSION v231, app v6.5).
