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
