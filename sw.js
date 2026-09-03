// Bump CACHE_VERSION any time you change index.html or the other app-shell
// files — that's what triggers clients to fetch the new version instead of
// serving stale cache. This does NOT affect already-cached content like
// reeving diagrams (see CONTENT_CACHE below) — those persist across updates
// so a crew doesn't lose offline access to plans they've already viewed just
// because an app update shipped.
const CACHE_VERSION = 'myslewer-v317';
const APP_SHELL_CACHE = `app-shell-${CACHE_VERSION}`;

// Fetched-on-demand content (reeving diagrams, etc). Fixed name, never
// versioned, never cleared automatically — only ever grows. If this ever
// needs a manual reset, change this constant's name once.
const CONTENT_CACHE = 'app-content-v1';

// Paths are relative to this file's location (repo root on GitHub Pages).
// Counterweight diagrams are precached here (versioned, refreshed on every
// CACHE_VERSION bump) rather than left to fall into CONTENT_CACHE like
// reeving diagrams - these get actively edited as part of ongoing app
// development (unlike reeving diagrams, which don't change once shipped),
// so they need the same "update replaces the old one" guarantee as
// index.html itself. Getting this wrong is exactly how a person can keep
// seeing a diagram fixed weeks ago after every possible cache-version bump -
// the fix landed in CONTENT_CACHE the first time, which nothing here ever
// clears. See methodology.txt 10.28.
//
// reeving/manifest.json gets the same treatment, for the same reason - the
// SVG diagrams it references genuinely don't change once shipped (real
// OEM reeving diagrams), but the manifest also carries the PROSE around
// them (labels, notes) which does occasionally need correcting - see
// methodology.txt 41 (the "these four models" note that didn't name them).
// Only the manifest itself is listed here, not the dozens of SVG files -
// those stay in CONTENT_CACHE, matching the stable-content reasoning this
// whole comment describes.
//
// vendor/carrier3d.js is the same story again, caught the same way: a
// person kept seeing a stale, pre-fix 3D calibration result across two
// separate CACHE_VERSION bumps because this file was never in APP_SHELL -
// it's dynamically imported by index.html, not referenced as a normal
// page asset, so it fell into the generic fetch-once-cache-forever
// CONTENT_CACHE path same as everything not listed here. It's genuinely
// actively-edited app logic (not stable vendored library code - see
// methodology.txt 61/62), so it needs the same guarantee as index.html
// itself. The vendor/three/* library files it imports (GLTFLoader.js,
// DRACOLoader.js, OrbitControls.js, three.module.min.js) and the .glb
// carrier models are deliberately NOT added here - genuinely stable,
// unedited third-party/OEM-export content, same reasoning as the reeving
// SVGs above, correctly left in CONTENT_CACHE.
//
// outrigger/models/ltm1650-carrier.glb was a one-off exception to "GLB
// carrier models stay in CONTENT_CACHE" for several versions (v259
// through v268) - it had stopped being stable/unedited (re-exported
// with the rear outrigger box properly separated from the body,
// methodology.txt 105), and a stale cached copy wasn't just a cosmetic
// miss the way an old diagram is - it would silently bring back the
// exact whole-chassis-hides bug (methodology.txt 95/98) for anyone
// whose browser already cached the old file, since the old model's
// "Part 16" and the new model's "Part 16" are different real parts.
// CONTENT_CACHE_INVALIDATE got that correctness fix without forcing an
// eager 45MB download on every visitor via APP_SHELL. But it was left
// listed there indefinitely instead of only for the one deploy that
// actually needed it - CONTENT_CACHE_INVALIDATE runs on every single
// activate regardless of what changed, so every subsequent deploy kept
// force-evicting and re-downloading this 45MB file for anyone who'd
// viewed the 3D preview, even though the model itself hadn't changed
// since 105. Caught via a direct question about exactly this ("aren't
// we just adding overlays on top, shouldn't the base model still be
// cached?") - removed now that file is confirmed stable through many
// label/overlay-only deploys since. See methodology.txt 115. If this
// model is ever genuinely re-exported again, add it back here for
// exactly the one deploy that ships the new file, then remove it again
// the same way.
//
// vendor/cabentry3d.js is the Cab Entry tab's own 3D module - same
// dynamically-imported, actively-edited situation as carrier3d.js above,
// so it needs the same APP_SHELL guarantee for the same reason. The GLB
// carrier model it loads (outrigger/models/ltm1110-carrier.glb) is
// already covered by carrier3d.js's own reasoning above (stable OEM
// export, correctly left in CONTENT_CACHE) - it's the exact same file.
//
// cad/x650-inline.jpg and cad/x650-69.jpg (the X%H sub-tab's mud maps)
// get the same counterweight-diagram treatment for the same reason -
// these were already corrected once this same session (a line-weight
// export issue), so treating them as stable/CONTENT_CACHE from day one
// would risk exactly the stale-diagram bug methodology.txt 10.28
// describes the first time a future correction ships.
//
// guides/paint-mark-method.html (linked from Bog Mat Marking's "How O/R %
// Marking Works" button) is genuinely-edited explainer content, not a
// stable one-off export - the very first version already needed a
// correctness fix (the paint mark was keyed to the support plate's
// centre instead of its outer edge) - so it gets the same APP_SHELL
// update-guarantee as carrier3d.js above rather than falling into
// CONTENT_CACHE's fetch-once-cache-forever path.
const APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-512-maskable.png',
  './icons/apple-touch-icon.png',
  './counterweight/img/ltm1250-cwt-exploded-v2.png',
  './counterweight/img/ltm1110-cwt-exploded-v2.png',
  './counterweight/img/ltm1130-cwt-exploded-v2.png',
  './counterweight/img/ltm1160-cwt-newangle.jpg',
  './counterweight/img/ltm1160-cwt-uk-exploded.png',
  './counterweight/img/ltm1650-cwt-exploded.jpg',
  './counterweight/img/ltm1300-cwt-exploded.png',
  './counterweight/img/ltm1300-cwt-uk-exploded.png',
  './counterweight/img/ltr1220-cwt-exploded.png',
  './cad/x650-inline.jpg',
  './cad/x650-69.jpg',
  './cad/x650-ds-inline.jpg',
  './cad/x650-ds-69.jpg',
  './cad/x650-ps-inline.jpg',
  './cad/x650-ps-69.jpg',
  './reeving/manifest.json',
  './vendor/carrier3d.js',
  './vendor/cabentry3d.js',
  './guides/paint-mark-method.html'
];

// Purged from CONTENT_CACHE on every activate WITHOUT being precached
// like APP_SHELL - too large to justify an eager download for every
// visitor. A person who's never viewed the affected 3D preview never
// had a stale copy to begin with, so an entry here is a no-op for
// them; a person who had, gets a fresh fetch the next time they open
// it, same as first-ever viewing it would. This list should normally
// be EMPTY - only add an entry for the one deploy that actually ships
// a corrected/re-exported large file (a GLB, typically), then remove
// it again on the next deploy. Leaving an entry here indefinitely
// forces that same large re-download on every future deploy regardless
// of what changed, which is exactly the mistake methodology.txt 115
// found and fixed - see that entry before adding anything here again.
const CONTENT_CACHE_INVALIDATE = [];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(APP_SHELL_CACHE)
      .then((cache) => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const keys = await caches.keys();
      // Only clean up old APP-SHELL versions. CONTENT_CACHE is never in
      // this deletion list regardless of its name, so previously-viewed
      // reeving diagrams survive every future app update.
      await Promise.all(
        keys
          .filter((key) => key.startsWith('app-shell-') && key !== APP_SHELL_CACHE)
          .map((key) => caches.delete(key))
      );
      // Purge any stale duplicate of a now-APP_SHELL url that was
      // previously cached into CONTENT_CACHE before it was added here
      // (this is exactly how the LTM 1650/1160/1300 diagram fixes stayed
      // invisible through several CACHE_VERSION bumps - the old copy
      // landed in CONTENT_CACHE on first view and nothing ever cleared
      // it). Without this, a stale CONTENT_CACHE entry can still win a
      // caches.match() lookup depending on cache iteration order, even
      // though a fresh copy now sits in APP_SHELL_CACHE too.
      const contentCache = await caches.open(CONTENT_CACHE);
      await Promise.all(APP_SHELL.map((url) => contentCache.delete(url)));
      // Same purge, for the handful of large assets in
      // CONTENT_CACHE_INVALIDATE that get corrected occasionally but are
      // too big to justify precaching into APP_SHELL_CACHE for everyone -
      // see that constant's own comment above.
      await Promise.all(CONTENT_CACHE_INVALIDATE.map((url) => contentCache.delete(url)));
      // Defensive cleanup to match the fetch handler's own explicit
      // cross-origin-never-persists rule below (Lift Plan Library
      // photos) - real testing found nothing cross-origin was actually
      // reaching CONTENT_CACHE before that rule existed either (see
      // that rule's own comment on why), so this is precautionary
      // rather than undoing real accumulated damage. Cheap insurance
      // either way, and genuinely a no-op on every device where nothing
      // cross-origin ever got in.
      const contentKeys = await contentCache.keys();
      await Promise.all(
        contentKeys
          .filter((req) => new URL(req.url).origin !== self.location.origin)
          .map((req) => contentCache.delete(req))
      );
      await self.clients.claim();
    })()
  );
});

// App-shell files (precached above) are matched from APP_SHELL_CACHE
// explicitly first and always win, even if a stale copy of the same URL
// still exists in CONTENT_CACHE - this is what actually GUARANTEES an
// updated diagram replaces the old one on the next activate, rather than
// just hoping cache iteration order favours the fresh copy. Everything
// else falls back to cache-first/network, caching into the persistent
// CONTENT_CACHE the first time it's successfully fetched - EXCEPT
// cross-origin requests (see the branch below), which always go live.
// Falls back to the cached index.html for any navigation request that
// fails offline, so deep links / reloads still open the app instead of
// a browser error page.
self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  event.respondWith(
    caches.open(APP_SHELL_CACHE).then((shellCache) => shellCache.match(event.request)).then((shellHit) => {
      if (shellHit) return shellHit;

      // Cross-origin requests always go straight to the network, never
      // through CONTENT_CACHE. In practice this is entirely Lift Plan
      // Library photos (Firebase Storage, and Nextcloud once a photo's
      // been backed up there) - nothing else in this app fetches
      // cross-origin at runtime. This wasn't fixing a live bug found by
      // testing real devices - a plain <img src> without a crossorigin
      // attribute (which these have never had) makes a no-cors request,
      // and the SW's own `if (response && response.ok)` check below
      // already treats an opaque no-cors response as not-ok, so these
      // photos were never actually landing in CONTENT_CACHE to begin
      // with. Made it an explicit rule instead of an accidental side
      // effect of that response.ok quirk, for two real reasons: it's
      // what this file's own persistentLocalCache comment already
      // SAID the intent was ("Storage's ... photos are meant to always
      // come from the network ... same as any other image") without
      // actually being guaranteed by anything nearby it, and relying on
      // the opaque-response accident is fragile - anyone who ever added
      // crossorigin="anonymous" to one of these <img> tags for an
      // unrelated reason (canvas access, better error detail) would
      // silently flip the response to non-opaque and start caching
      // these permanently again, with nothing here to catch it. The
      // browser's own ordinary HTTP cache still sits underneath this
      // fetch() regardless (governed by whatever Cache-Control the
      // photo's own host sends, same as any other image on the web) -
      // this only concerns this app's OWN permanent, self-managed layer.
      if (new URL(event.request.url).origin !== self.location.origin) {
        return fetch(event.request).catch(() => undefined);
      }

      return caches.match(event.request).then((cached) => {
        if (cached) return cached;

        return fetch(event.request)
          .then((response) => {
            if (response && response.ok) {
              const responseClone = response.clone();
              caches.open(CONTENT_CACHE).then((cache) => cache.put(event.request, responseClone));
            }
            return response;
          })
          .catch(() => {
            if (event.request.mode === 'navigate') {
              return caches.match('./index.html');
            }
            return undefined;
          });
      });
    })
  );
});

// Manual update check, triggered by the header refresh button. Re-fetches
// every app-shell file fresh from the network (cache: 'reload' bypasses the
// HTTP cache too, not just this SW's own cache), overwrites the existing
// entries in the current APP_SHELL_CACHE in place, and reports back whether
// index.html actually changed so the page knows whether to reload. This
// works regardless of whether CACHE_VERSION was bumped on deploy — it
// doesn't rely on the browser's own (throttled) SW-script update check.
self.addEventListener('message', (event) => {
  if (!event.data || event.data.type !== 'CHECK_FOR_UPDATE') return;

  event.waitUntil((async () => {
    try {
      const cache = await caches.open(APP_SHELL_CACHE);

      const oldIndexRes = await cache.match('./index.html');
      const oldIndexText = oldIndexRes ? await oldIndexRes.text() : '';

      await Promise.all(APP_SHELL.map(async (url) => {
        const res = await fetch(url, { cache: 'reload' });
        if (res && res.ok) await cache.put(url, res.clone());
      }));

      const newIndexRes = await cache.match('./index.html');
      const newIndexText = newIndexRes ? await newIndexRes.text() : '';

      event.source.postMessage({
        type: 'UPDATE_CHECK_RESULT',
        changed: oldIndexText !== newIndexText
      });
    } catch (e) {
      event.source.postMessage({ type: 'UPDATE_CHECK_RESULT', error: true });
    }
  })());
});
