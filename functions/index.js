const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onObjectFinalized } = require('firebase-functions/v2/storage');
const { defineString, defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

initializeApp();

// Monthly sweep for orphaned Lift Plan Library photos - runs with the
// Admin SDK, so it bypasses both Firestore's and Storage's security
// rules entirely (real admin access, not a client working around them).
// This exists specifically because the client CAN'T safely clean these
// up itself: an admin deleting or editing someone ELSE's lift entry
// can't also delete that person's Storage photo (storage.rules ties
// delete to the uploader's own uid, tracked in the object's own
// customMetadata - see storage.rules' own comment on why it can't
// check isAdmin() there, and methodology.txt 130/131 for the full
// story). A photo becomes orphaned either because its entry was
// deleted outright, or because an edit removed just that one photo
// from the entry's photos list - this sweep catches both the same way,
// by simply comparing what's actually referenced against what's
// actually sitting in the bucket, rather than needing separate
// bookkeeping for each removal path.
//
// Monthly rather than a live per-delete/per-edit call - not because of
// any real Cloud Functions quota pressure (the free tier is 2 million
// invocations/month, nowhere near a constraint at this app's scale -
// see methodology.txt 133), but because a periodic sweep is simply
// simpler: no synchronous callable needed on the client's delete/edit
// path, no risk of a partial cleanup if that call fails mid-flight,
// and an orphaned photo sitting around for up to a month is genuinely
// harmless (inert Storage clutter, nothing references it, nobody sees
// it) so there's no real cost to batching.
exports.cleanupOrphanedLiftLibraryPhotos = onSchedule(
  {
    schedule: '0 3 1 * *',
    timeZone: 'UTC',
    // australia-southeast2 (this project's Firestore location) isn't
    // one of Cloud Scheduler's supported regions - confirmed via
    // cloudscheduler.googleapis.com's own locations list, not assumed -
    // australia-southeast1 (Sydney) is the nearest one that is. The
    // function itself doesn't need to be co-located with Firestore for
    // this to work correctly (Admin SDK calls reach Firestore/Storage
    // over their own APIs regardless of the calling function's region,
    // unlike the cross-service Storage-rules firestore.get() problem
    // from 130/133 which was a rules-engine-specific limitation).
    region: 'australia-southeast1',
  },
  async () => {
    const db = getFirestore();
    const bucket = getStorage().bucket();

    const entriesSnap = await db.collection('liftLibraryEntries').get();
    const referencedPaths = new Set();
    entriesSnap.forEach((doc) => {
      const photos = doc.data().photos;
      if (Array.isArray(photos)) {
        photos.forEach((p) => { if (p && p.path) referencedPaths.add(p.path); });
      }
    });

    const [files] = await bucket.getFiles({ prefix: 'liftLibrary/' });

    let deletedCount = 0;
    for (const file of files) {
      if (!referencedPaths.has(file.name)) {
        try {
          await file.delete();
          deletedCount++;
        } catch (err) {
          console.error(`Failed to delete orphaned photo ${file.name}:`, err.message);
        }
      }
    }

    console.log(`Lift Library photo cleanup: scanned ${files.length} file(s) under liftLibrary/, deleted ${deletedCount} orphaned photo(s).`);
  }
);

// Non-secret config (domain/username/target folder aren't sensitive
// the way the app password is - that alone is the Secret Manager
// value below) - but the actual domain and username still identify a
// real self-hosted server and person, so real values live only in a
// local functions/.env (gitignored, never committed - see .gitignore's
// own comment) rather than as defaults here, same treatment as the
// Firebase service account key this whole project's admin work has
// used all along. A deploy without that .env present fails cleanly in
// non-interactive mode rather than silently deploying with a wrong or
// placeholder value.
const NEXTCLOUD_DOMAIN = defineString('NEXTCLOUD_DOMAIN');
const NEXTCLOUD_USERNAME = defineString('NEXTCLOUD_USERNAME');
const NEXTCLOUD_BACKUP_PATH = defineString('NEXTCLOUD_BACKUP_PATH');
const NEXTCLOUD_APP_PASSWORD = defineSecret('NEXTCLOUD_APP_PASSWORD');

function ncAuthHeader() {
  const basic = Buffer.from(`${NEXTCLOUD_USERNAME.value()}:${NEXTCLOUD_APP_PASSWORD.value()}`).toString('base64');
  return `Basic ${basic}`;
}

// MKCOL on a collection that already exists correctly returns 405, not
// an error worth failing the whole backup over - only genuine failures
// (network, auth, a real 5xx) should stop the migration for this photo.
async function ncEnsureFolder(davPath) {
  const res = await fetch(`${NEXTCLOUD_DOMAIN.value()}/remote.php/dav/files/${NEXTCLOUD_USERNAME.value()}${davPath}`, {
    method: 'MKCOL',
    headers: { Authorization: ncAuthHeader() },
  });
  if (res.status !== 201 && res.status !== 405) {
    throw new Error(`MKCOL ${davPath} failed: ${res.status}`);
  }
}

async function ncUpload(davPath, bytes, contentType) {
  const res = await fetch(`${NEXTCLOUD_DOMAIN.value()}/remote.php/dav/files/${NEXTCLOUD_USERNAME.value()}${davPath}`, {
    method: 'PUT',
    headers: { Authorization: ncAuthHeader(), 'Content-Type': contentType || 'application/octet-stream' },
    body: bytes,
  });
  if (res.status !== 201 && res.status !== 204) {
    throw new Error(`PUT ${davPath} failed: ${res.status}`);
  }
}

// OCS Share API - the same account/app-password works here too (not
// WebDAV-specific). shareType 3 = public link, permissions 1 =
// read-only - matches this app's own existing "view-only link" pattern
// (the contribution form's External Link field carries the same
// instruction to the person pasting one in by hand).
async function ncCreatePublicShareUrl(davPath) {
  const res = await fetch(`${NEXTCLOUD_DOMAIN.value()}/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json`, {
    method: 'POST',
    headers: {
      Authorization: ncAuthHeader(),
      'OCS-APIRequest': 'true',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ path: davPath, shareType: '3', permissions: '1' }).toString(),
  });
  if (!res.ok) throw new Error(`OCS share create for ${davPath} failed: ${res.status}`);
  const body = await res.json();
  const url = body?.ocs?.data?.url;
  if (!url) throw new Error(`OCS share create for ${davPath} returned no url`);
  return url;
}

// Monthly, unconditional (person's own choice over quota-triggered -
// see methodology.txt 133's own note on why simple/periodic won over
// clever/conditional). Moves every Lift Plan Library photo still
// living in Firebase Storage over to Nextcloud, frees the 5GB Storage
// quota back up, and re-points the Firestore doc at a public read-only
// Nextcloud share link instead - the same "view-only link" the
// contribution form's own External Link field already asks a person to
// paste in by hand, just generated automatically here.
//
// Ordering is deliberate and safety-critical: upload to Nextcloud,
// THEN create the share link, THEN update the Firestore doc, and ONLY
// THEN delete the Firebase Storage original - each step only runs
// after the previous one is confirmed to have actually succeeded, so a
// failure anywhere in the chain leaves the original safely in Storage
// rather than losing the only copy of someone's photo. Migrated
// entries drop their `path` field entirely (no Storage object to
// reference any more) rather than leaving a stale one behind -
// index.html's own delete/edit-remove-photo paths check for that
// (`p.path` present) before ever calling __liftLibraryDeletePhoto, so
// removing a migrated photo from an entry just drops the reference,
// it doesn't (and can't, without WebDAV credentials in the client)
// touch the Nextcloud archive copy - closer to how a real backup
// should behave than not.
exports.backupLiftLibraryPhotosToNextcloud = onSchedule(
  {
    schedule: '0 4 1 * *',
    timeZone: 'UTC',
    region: 'australia-southeast1',
    secrets: [NEXTCLOUD_APP_PASSWORD],
  },
  async () => {
    const db = getFirestore();
    const bucket = getStorage().bucket();
    const backupBase = NEXTCLOUD_BACKUP_PATH.value();

    const entriesSnap = await db.collection('liftLibraryEntries').get();

    let migratedCount = 0;
    let failedCount = 0;

    for (const doc of entriesSnap.docs) {
      const entry = doc.data();
      const photos = Array.isArray(entry.photos) ? entry.photos : [];
      // Nothing to do for entries with no Storage-backed photos left -
      // already fully migrated in a prior month's run, or never had
      // any to begin with.
      if (!photos.some((p) => p && p.path)) continue;

      const updatedPhotos = [];
      let anyChanged = false;

      for (const photo of photos) {
        if (!photo || !photo.path) { updatedPhotos.push(photo); continue; }

        try {
          const [bytes] = await bucket.file(photo.path).download();
          const fileName = photo.path.split('/').pop();
          const entryFolder = `${backupBase}/${doc.id}`;
          const davPath = `${entryFolder}/${fileName}`;

          await ncEnsureFolder(entryFolder);
          await ncUpload(davPath, bytes);
          const shareUrl = await ncCreatePublicShareUrl(davPath);

          // The bare share URL (https://domain/s/{token}) renders
          // Nextcloud's own HTML preview page, not the raw image bytes
          // - useless as an <img src>. Appending /download is
          // Nextcloud's documented pattern for a single-file public
          // share's direct raw-content URL, which is what
          // llOpenEntry's own <img>/<a href> actually need (same
          // "opens the raw image" behavior a Firebase-hosted photo
          // already has, kept consistent either way).
          //
          // Firestore doc updated (this photo's entry replaced) before
          // the Storage original is touched - see the function's own
          // top comment for why this ordering matters.
          updatedPhotos.push({ url: `${shareUrl}/download`, nextcloud: true });
          anyChanged = true;
        } catch (err) {
          console.error(`Failed to migrate photo ${photo.path} (entry ${doc.id}):`, err.message);
          updatedPhotos.push(photo);
          failedCount++;
        }
      }

      if (anyChanged) {
        await doc.ref.update({ photos: updatedPhotos });
        // Only now, after the Firestore doc itself confirms the new
        // Nextcloud-backed reference - delete the Storage originals
        // that were actually migrated this pass.
        const migratedPaths = photos
          .filter((p) => p && p.path)
          .map((p) => p.path)
          .filter((path) => !updatedPhotos.some((u) => u && u.path === path));
        for (const path of migratedPaths) {
          try {
            await bucket.file(path).delete();
            migratedCount++;
          } catch (err) {
            console.error(`Migrated but could not delete original ${path}:`, err.message);
          }
        }
      }
    }

    console.log(`Lift Library Nextcloud backup: migrated ${migratedCount} photo(s), ${failedCount} failure(s).`);
  }
);

// Video gets a DIFFERENT migration cadence than photos - immediately,
// per-upload, rather than batched once a month - because the two have a
// genuinely different cost shape. A photo sitting in Firebase Storage
// for up to a month is cheap even at real usage (a few MB, viewed a
// handful of times). A video is 10-50x the size, and every VIEW during
// that month - not just the eventual migration - is a full download
// billed as Storage egress; the monthly cron's whole "it's fine, it's
// backed up eventually" reasoning doesn't cover that, and was flagged
// to the person as a real gap before this was built, not assumed away.
// Firing on upload instead of waiting for the cron shrinks that exposed
// window from "up to a month, viewed by everyone" to "seconds, viewed
// by nobody" - normal viewers only ever hit this video's Nextcloud
// share link, never Firebase Storage.
//
// A Storage OBJECT trigger (not a client-called callable) so the
// existing upload path in index.html doesn't change at all - the
// client still does a normal resumable uploadBytes() straight to
// Storage (the only way to get real progress/retry over a flaky mobile
// connection for a 100MB+ file; a callable/HTTP function would need
// the whole file in one request and hit Cloud Functions' request-size
// ceiling on anything but a short clip). This just reacts once that
// upload finishes.
//
// Scoped to liftLibrary/ AND to video/* content types specifically -
// this bucket also receives photo uploads (handled by the monthly
// backupLiftLibraryPhotosToNextcloud above) and this function's OWN
// output would never re-trigger itself even without the filter (this
// only ever calls .delete() on the Storage original, never creates a
// new object there), but the content-type check still keeps this
// function from doing any work at all on the vastly more common photo
// uploads - cheap to skip, no reason not to.
exports.migrateLiftLibraryVideoToNextcloud = onObjectFinalized(
  {
    // A Storage EVENT trigger (unlike the two scheduled functions above,
    // which just call the Firestore/Storage APIs directly and genuinely
    // don't care where they run) has a real platform constraint the
    // scheduled ones don't: Eventarc requires the function to sit in the
    // SAME region as the bucket it's watching, confirmed the hard way -
    // a first deploy attempt at australia-southeast1 (matching the other
    // two, out of habit) failed outright with "A function in region
    // australia-southeast1 cannot listen to a bucket in region
    // us-west1." The bucket itself lives in us-west1 (picked for Cloud
    // Storage's Always Free tier - see storage.rules' own history), so
    // this function has to as well.
    region: 'us-west1',
    secrets: [NEXTCLOUD_APP_PASSWORD],
    // Real phone video easily runs 50-150MB - well past the default
    // Cloud Functions memory/timeout for a function that has to hold
    // the whole file in memory to relay it to Nextcloud (no streaming
    // WebDAV client here, same download-then-PUT approach as the photo
    // backup above, just one file instead of a whole month's batch).
    memory: '512MiB',
    timeoutSeconds: 300,
  },
  async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType || '';
    if (!filePath.startsWith('liftLibrary/') || !contentType.startsWith('video/')) return;

    // liftLibrary/{entryId}/{fileName} - same layout photos use (see
    // index.html's __liftLibraryUploadVideo), entryId is always the
    // first path segment after the prefix.
    const parts = filePath.split('/');
    const entryId = parts[1];
    const fileName = parts[parts.length - 1];
    if (!entryId || !fileName) return;

    const db = getFirestore();
    const bucket = getStorage().bucket();
    const backupBase = NEXTCLOUD_BACKUP_PATH.value();

    const docRef = db.collection('liftLibraryEntries').doc(entryId);
    // index.html's own submit only writes the Firestore doc AFTER the
    // video upload's own uploadBytes() promise resolves (photo
    // compositing and the rest of the entry's fields still happen in
    // between) - this trigger fires from the SAME upload finishing, so
    // it can genuinely win that race and see no `video` field yet, not
    // just an already-migrated or already-removed one. A few short
    // retries covers that realistic gap without having to restructure
    // the client into writing the entry doc in two passes; if `video`
    // still doesn't reference this exact path after that, this really
    // is stale (already migrated by an earlier run of this same
    // trigger, superseded by a re-upload, or the entry write itself
    // failed and the video is genuinely orphaned) and it correctly
    // does nothing rather than guessing.
    let entry = null;
    for (let attempt = 0; attempt < 6; attempt++) {
      const snap = await docRef.get();
      if (!snap.exists) return; // entry deleted between upload and this trigger firing
      entry = snap.data();
      if (entry.video && entry.video.path === filePath) break;
      entry = null;
      if (attempt < 5) await new Promise((resolve) => setTimeout(resolve, 4000));
    }
    if (!entry) return;

    try {
      const [bytes] = await bucket.file(filePath).download();
      const entryFolder = `${backupBase}/${entryId}`;
      const davPath = `${entryFolder}/${fileName}`;

      await ncEnsureFolder(entryFolder);
      await ncUpload(davPath, bytes, contentType);
      const shareUrl = await ncCreatePublicShareUrl(davPath);

      // Same ordering discipline as the photo backup above: Firestore
      // doc updated to the new Nextcloud-backed reference FIRST, and
      // only once that's confirmed does the Storage original get
      // deleted - a failure partway through leaves the original safely
      // in Storage (still playable from there, just not yet what this
      // function considers "done") rather than losing the only copy.
      await docRef.update({ video: { url: `${shareUrl}/download`, nextcloud: true } });
      await bucket.file(filePath).delete();
      console.log(`Migrated video for entry ${entryId} to Nextcloud.`);
    } catch (err) {
      console.error(`Failed to migrate video ${filePath} (entry ${entryId}):`, err.message);
      // Left as-is (still pending, still in Storage) rather than
      // guessing at a fix - a real network/auth failure here means the
      // video is still perfectly fine and playable straight from
      // Storage in the meantime; nothing is lost, it just missed this
      // one migration attempt.
    }
  }
);

// PDFs (OEM lift designs, COG drawings) get the same "migrate on
// upload, don't wait for the monthly sweep" treatment as video - a
// deliberate choice even though a PDF's actual bandwidth cost is much
// closer to a photo's than a video's (typically low single-digit MB,
// not 10-50x a photo like real phone video is). Requested that way,
// and it's a genuinely reasonable default regardless of the exact
// cost shape: now that this trigger-on-upload pattern exists and
// works, there's no real reason to make a reference document wait up
// to a month in Storage when it could just be archived within
// seconds instead - the earlier "monthly is simpler, and an orphaned
// file sitting around is harmless" reasoning for photos (methodology
// 133) was about batching being FINE, not about immediate being
// worse.
//
// Kept as its OWN function rather than folded into
// migrateLiftLibraryVideoToNextcloud above, even though the two share
// most of their WebDAV logic - the two aren't just "same thing,
// different content type": a video is a single field on the entry
// (one clip that matters, see 145's own reasoning), a PDF is a LIST
// like photos (a real lift plan often comes with several reference
// documents - an OEM capacity chart, a separate COG drawing, etc.),
// so this one has to find-and-replace ONE element inside an array
// rather than overwrite a single field outright - different enough
// update logic that branching one function on content type would
// have made both harder to follow than two small, focused ones.
exports.migrateLiftLibraryPdfsToNextcloud = onObjectFinalized(
  {
    // Same bucket-co-location requirement as the video function above
    // - Eventarc Storage triggers have to sit in the bucket's own
    // region (us-west1), not wherever the scheduled functions live.
    region: 'us-west1',
    secrets: [NEXTCLOUD_APP_PASSWORD],
    memory: '256MiB',
    timeoutSeconds: 180,
  },
  async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType || '';
    if (!filePath.startsWith('liftLibrary/') || contentType !== 'application/pdf') return;

    const parts = filePath.split('/');
    const entryId = parts[1];
    const fileName = parts[parts.length - 1];
    if (!entryId || !fileName) return;

    const db = getFirestore();
    const bucket = getStorage().bucket();
    const backupBase = NEXTCLOUD_BACKUP_PATH.value();

    const docRef = db.collection('liftLibraryEntries').doc(entryId);
    // Same race as migrateLiftLibraryVideoToNextcloud's own comment
    // explains - the client's Firestore write (adding this PDF's
    // pending stub to the `pdfs` array) can genuinely still be in
    // flight when this trigger fires, so retry rather than bail on
    // the first miss.
    let pdfIndex = -1;
    let pdfs = null;
    for (let attempt = 0; attempt < 6; attempt++) {
      const snap = await docRef.get();
      if (!snap.exists) return; // entry deleted between upload and this trigger firing
      const entry = snap.data();
      pdfs = Array.isArray(entry.pdfs) ? entry.pdfs : [];
      pdfIndex = pdfs.findIndex((p) => p && p.path === filePath);
      if (pdfIndex !== -1) break;
      if (attempt < 5) await new Promise((resolve) => setTimeout(resolve, 4000));
    }
    // Not found after retrying - either the entry write genuinely
    // failed (orphaned upload) or this PDF was already migrated/
    // removed by the time this attempt ran. Does nothing rather than
    // guessing, same as the video function.
    if (pdfIndex === -1) return;

    try {
      const [bytes] = await bucket.file(filePath).download();
      const entryFolder = `${backupBase}/${entryId}`;
      const davPath = `${entryFolder}/${fileName}`;

      await ncEnsureFolder(entryFolder);
      await ncUpload(davPath, bytes, contentType);
      const shareUrl = await ncCreatePublicShareUrl(davPath);

      // Re-read right before writing rather than reusing the `pdfs`
      // array from the retry loop above - another PDF on the SAME
      // entry could have finished migrating (or been added/removed)
      // in the time this upload took, and a stale array would
      // silently undo that concurrent change on write.
      const freshSnap = await docRef.get();
      if (!freshSnap.exists) { await bucket.file(filePath).delete().catch(() => {}); return; }
      const freshPdfs = Array.isArray(freshSnap.data().pdfs) ? freshSnap.data().pdfs : [];
      const freshIndex = freshPdfs.findIndex((p) => p && p.path === filePath);
      if (freshIndex === -1) { await bucket.file(filePath).delete().catch(() => {}); return; }
      freshPdfs[freshIndex] = { url: `${shareUrl}/download`, nextcloud: true, name: freshPdfs[freshIndex].name };
      await docRef.update({ pdfs: freshPdfs });
      await bucket.file(filePath).delete();
      console.log(`Migrated PDF ${fileName} for entry ${entryId} to Nextcloud.`);
    } catch (err) {
      console.error(`Failed to migrate PDF ${filePath} (entry ${entryId}):`, err.message);
    }
  }
);
