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
- Rename Cab Entry tab to "Lift Logger" (or similar); add persistence so
  the lift log doesn't get wiped on reload - saved on-device for now,
  as a stopgap until a real shared backend (still being decided) gets
  built; merge the Load card (Name/Weight) and Position card into one
  condensed card at the top so it flows better.
  **Status: done** — tab button now reads "Lift Logger". Load + Position
  merged into one "Lift Details" card (Name/Weight in a new top row,
  then Radius/Slew/side-select/status below, unchanged otherwise). Added
  localStorage-based persistence (myslewer-cabentry-lifts-v1) as an
  explicit, code-commented stopgap - gets replaced wholesale, not
  extended, once the real shared backend is chosen. Verified: rename,
  merged card contents, log-then-reload restores entries correctly, and
  clearing storage still renders a clean empty state - plus full
  existing regression suite re-run clean. Shipped to main (CACHE_VERSION
  v232, app v6.6).
- Slew degree resolution needs decimal places - typed 7.7, it rounded
  up to 8, which is a different number/wrong reading.
  **Status: done** — real bug, not cosmetic: the input field's own
  re-sync (blur + render) and the display formatter (dial readout + log
  entries) were all rounding to a whole number, even though the actual
  stored/logged value was never touched (kept its decimal the whole
  time). Added a shared ceFormatSlewNum() helper (rounds to nearest 0.1°
  to kill float noise, without crushing a real decimal, and without
  forcing a noisy trailing ".0" on whole-number readings) and swapped
  all three rounding call sites onto it. Verified 7.7 now displays
  correctly at every step (typing, blur, dial readout, log entry,
  localStorage) while whole numbers and the 0/180 poles still render
  clean. Shipped to main (CACHE_VERSION v233, app v6.7).
- Way to delete individual lift log entries with an X, in case some were
  entered wrong.
  **Status: done** — small X button added to each log card (top-right,
  next to the weight), deletes just that entry from the array, clears
  it if currently selected on the 2D/3D plots, and persists the
  deletion to localStorage. Verified: delete removes the right entry
  from both the DOM and storage, deleting down to zero shows the clean
  empty state again, and the 2D radar's dot count tracks deletions.
  Shipped to main (CACHE_VERSION v234, app v6.8).
- Separately, brainstormed (not yet decided/built): shared invite/accept
  lift-log pools between users, an "overseer" supervisor role that can
  view logs across a pool without being a member, and a longer-term plan
  for other tabs (e.g. Lift Plans - admin assigns gear/method details to
  a user) needing a real backend + admin dashboard to push content to
  users. Person is still deciding the backend path - no implementation
  started.
- Full backend design pass: users able to see/browse each other to
  invite (by name, not email); asked me to go ahead and design the
  backend piece; admin dashboard able to assign roles and toggle tab
  access with a user database + toggles; single admin for now (can add
  more later); how does first-time username assignment work without
  duplicating on a second device; whether allowing a name change means
  building a full Profile tab.
  **Status: design done, Stage 1 built.** Design: `directory/{uid}`
  collection for name-only browsing (declared exception to the app's
  usual no-list rule, justified by this being a small invite-gated
  crew); `admins/{uid}` as the root of trust for a future admin
  dashboard (admin-granting itself stays a manual script, never self-
  service, single admin for now); pools/members/invites schema; zero
  Cloud Functions by design, one deliberate corner cut (empty-pool
  auto-delete is best-effort, not instant). Declined the "what you have
  access to" list per direct instruction - people shouldn't be able to
  see what's gated from them. Confirmed a Profile TAB is worth building
  given more tabs than Lift Logger are planned long-term. Explained the
  duplicate-proof mechanism for the one-time name prompt: gate it on the
  Firestore doc existing (cloud state), never local/device state.
  **Stage 1 actually shipped**: new Profile header icon/panel (name-only
  directory doc, editable display name, sign-out, auto-opens once on a
  genuinely first-ever sign-in). Stage 2 (pools/invites) and Stage 3
  (admin dashboard) not yet built, by design - staged deliberately
  rather than shipping everything in one enormous change. Shipped to
  main (CACHE_VERSION v235, app v6.9). One manual step still needed:
  the updated firestore.rules (added directory/{uid} rules) has to be
  pasted into the Firebase console's Rules tab by the person themselves
  - no rules-deploy tooling exists in this project - before the
  directory collection actually starts working live.
- Asked if I could deploy the rules myself using the existing service
  account, since it already has access.
  **Status: done.** Checked read-only first - the service account had
  Firestore document access but no permission on the separate Firebase
  Rules API (403 on a GET). Explained the gap and asked before doing
  anything about it, since a rules mistake affects the whole app's
  sign-in gate at once. Person granted the account the narrow "Firebase
  Rules Admin" role via Cloud Console IAM. Re-checked (now 200), diffed
  the currently-live rules against the repo first to make sure nothing
  had changed out of band, then deployed the updated firestore.rules
  directly via the Firebase Rules API and re-diffed the live result -
  byte-identical to the repo. Verified the actual rule BEHAVIOUR, not
  just that the deploy succeeded: two real throwaway Firebase accounts,
  own-doc write allowed, cross-user write blocked, an extra smuggled-in
  field blocked, cross-user name lookup allowed (by design), full-
  collection listing allowed and correct, unauthenticated access
  blocked - all six as intended, both throwaway accounts deleted
  afterward. The directory collection - and so the Profile panel's Save
  Name - now genuinely works live, no manual console step needed after
  all.
- "Go ahead with stage 2."
  **Status: done.** Built pools, membership, invites (create a pool,
  invite by name, accept/decline, leave), all inside the Profile panel
  under two new sections (Pending Invites, Your Pools). Rules deployed
  live the same way as before - created without touching the release
  first (clean, no syntax errors), then released, then verified with 20
  real behavioural checks across three throwaway accounts covering every
  allow/deny path (invite/accept/decline, non-members blocked
  everywhere, can't delete someone else's membership, can't re-accept an
  already-accepted invite, etc.) - all 20 passed, throwaway accounts and
  test docs cleaned up after. Full UI test suite plus the entire existing
  regression suite clean. Stage 3 (admin dashboard) still not built, by
  design. Shipped to main (CACHE_VERSION v236, app v6.10).
- "Go ahead" on Stage 3 (admin dashboard); "can I just give your service
  account admin rights?"; confirmed the Datastore permission grant
  should be permanent, not revoked after.
  **Status: done.** New Admin Dashboard tab (gated on a new admins/{uid}
  collection, not a userAccess flag - kept separate since it's the root
  of trust everything else sits on): toggle any user's gated-tab access,
  promote/demote pool member roles. Along the way found a real gap: the
  service account couldn't actually write Firestore data at all (only
  rules documents), confirmed by testing both raw REST and the real
  official Admin SDK - both failed. Explained it and asked before doing
  anything; person granted "Cloud Datastore User" to the service account
  (permanent, not temporary). Verified with 16 real behavioural checks
  across three throwaway accounts, all passed; verified cleanup was
  actually complete (found and removed 3 orphaned test pool docs left
  over from earlier stages, since pools have no delete mechanism until
  now). Granted the real admin flag to the account requesting this once
  everything checked out, so the dashboard is live and usable now, not
  just built. Full UI test suite plus entire existing regression suite
  clean. Shipped to main (CACHE_VERSION v237, app v6.11).
- Real-device feedback on the just-shipped Admin Dashboard: a card per
  user takes up too much space, want a dropdown instead with every
  gated tab toggleable per user; and for users who haven't set a
  display name yet, list them by email until they have.
  **Status: done.** Replaced the per-user-card list with one dropdown +
  a shared toggle row for whichever user's picked. Also fixed a real gap
  the email-fallback request surfaced: an unnamed user wasn't in the
  list AT ALL before (it only read the directory collection, which only
  gets an entry once someone sets a name) - added a new admin-only
  userEmails collection, written automatically for every signed-in user
  regardless of naming status, so an admin can grant access from someone's
  very first sign-in. Verified with 9 real behavioural checks (own-doc
  write allowed, cross-user write blocked, fake-email blocked, re-write
  blocked, admin-only listing enforced). Full UI + existing regression
  suite clean. Shipped to main (CACHE_VERSION v238, app v6.12).
- "Yeah go ahead and wire the lift logger to it."
  **Status: done.** New "Logging To" selector in Lift Details -
  Personal (unchanged local/localStorage behavior) or any pool the
  person belongs to. Pool mode is genuinely live-synced (a teammate's
  entry appears without reopening the tab), only a 'member' role can
  log (overseers view-only, enforced server-side not just hidden), and
  each entry is only editable/deletable by whoever logged it - the
  delete button is hidden entirely for anyone else's entry in pool
  mode, and shows who logged it. Verified with 9 real behavioural
  checks against real throwaway accounts before building the UI.
  Testing surfaced and fixed two real bugs: switching back to Personal
  could leave stale pool entries on screen if nothing was saved locally
  yet, and a synchronous (not async) auth-not-ready throw could escape
  switchTab() uncaught. Full new wiring test plus the entire existing
  regression suite clean. Shipped to main (CACHE_VERSION v239, app
  v6.13).
- "I still can't see other users be it with or without user name I
  thought we were making so I could see there email address if they
  hadn't set a user name"; "I would like the options to be able to turn
  on/off any tab that we currently have per user not just ther service
  fill lift logger I mean all of them is that possible?"
  **Status: done.** Checked the real data rather than guessing why -
  7 of 8 real signed-in accounts hadn't reopened the app since the
  email-backfill feature shipped, so their userEmails doc didn't exist
  yet. Ran a one-off backfill using the real list of every Firebase Auth
  account that's ever signed in - all 8 now show up immediately, no
  need to wait for anyone to happen to reopen the app. Also extended the
  toggle set from 3 tabs to all 11 top-level tabs - the other 8 use the
  opposite (deny-list/hidden-by-flag) mechanism under the hood, unified
  into the same single "is this tab visible" checkbox either way.
  Verified the underlying nested-field Firestore merge behaviour
  directly (not assumed) before relying on it for live data. Full UI
  test plus entire existing regression suite clean. Shipped to main
  (CACHE_VERSION v240, app v6.14).
