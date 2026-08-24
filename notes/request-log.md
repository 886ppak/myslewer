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
  **Status: in progress.**
