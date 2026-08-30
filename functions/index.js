const { onSchedule } = require('firebase-functions/v2/scheduler');
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
    region: 'australia-southeast2',
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
