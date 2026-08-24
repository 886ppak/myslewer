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
