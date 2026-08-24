// 3D load-position plot for the Cab Entry tab. Deliberately its OWN
// module, not folded into carrier3d.js, even though it imports the same
// three.js/GLTFLoader/DRACOLoader/OrbitControls and reuses the same
// computeFormulaCalibration math - carrier3d.js runs a single shared
// renderer re-parented between the Outrigger tab's two sub-tabs, with a
// lot of state (outrigger pads, slew circles, ground marks, mat edges,
// AR) that has nothing to do with this tab and no reason to risk
// entangling with it. This is its own renderer, own scene, own model.
//
// The carrier model is a fixed placeholder, not tied to whichever crane
// is actually doing the lift - this tab is about WHERE a load was
// picked/landed relative to the slew centre, not about modelling the
// real crane on site, so one representative carrier stands in
// regardless. Originally LTM 1110 (32MB) - switched to LRT 1100 (7.3MB,
// the lightest of the seven carrier exports) after a person reported the
// panel loading nothing on a real tablet: it worked in every desktop/
// localhost test here, which is exactly the profile of a model too big
// to reliably fetch+Draco-decode on a real device's network/memory
// budget rather than a logic bug - the 32MB original was one of the two
// largest of the seven exports (1650 is the only bigger one, at 46MB).
// See methodology.txt for the fuller story, including the added
// loading/error visibility below (there wasn't any before - a slow or
// failed load looked identical to "nothing happened", which is exactly
// how this went unnoticed until someone hit it on a real device).
import * as THREE from 'three';
import { GLTFLoader } from './three/GLTFLoader.js';
import { DRACOLoader } from './three/DRACOLoader.js';
import { OrbitControls } from './three/OrbitControls.js';

const MODEL_URL = './outrigger/models/lrt1100-carrier.glb';
const CALIBRATION = { frontAtMinZ: true, lateralSign: 1 };
const FOOTPRINT = { width: 3300, front: 4300, rear: 4388 };

const dracoLoader = new DRACOLoader();
dracoLoader.setDecoderPath('./vendor/three/draco/');

let renderer = null, scene = null, camera = null, controls = null;
let currentWrapId = null;
let modelRoot = null;
let modelCal = null; // {groundY, lateralCenter, slewZ, xSlope, zSlope}
let dotsGroup = null;
let loadingPromise = null;
let onDotClick = null; // set via __cabEntry3dOnDotClick

function loadGLTFAsync(url) {
  return new Promise((resolve, reject) => {
    const loader = new GLTFLoader();
    loader.setDRACOLoader(dracoLoader);
    loader.load(url, (gltf) => resolve(gltf.scene), undefined, reject);
  });
}

// Same formula as carrier3d.js's own computeFormulaCalibration (kept as a
// literal copy, not a shared import, since this module is deliberately
// standalone) - maps the site plan's mm-from-slew-centre convention onto
// the loaded model's own local coordinate space.
function computeFormulaCalibration(root, footprint, calibration) {
  const box = new THREE.Box3().setFromObject(root);
  const groundY = box.min.y;
  const lateralCenter = (box.min.x + box.max.x) / 2;
  const frontOverhang = footprint.front / 1000;
  const frontTipZ = calibration.frontAtMinZ ? box.min.z : box.max.z;
  const dirSign = calibration.frontAtMinZ ? 1 : -1;
  const lateralSign = calibration.lateralSign || 1;
  const slewZ = frontTipZ + dirSign * frontOverhang;
  return { groundY, lateralCenter, slewZ, xSlope: lateralSign / 1000, zSlope: dirSign / 1000 };
}

function ensureRenderer(wrapId) {
  const wrap = document.getElementById(wrapId);
  if (!wrap) return false;

  if (renderer) {
    const moved = currentWrapId !== wrapId;
    if (moved) { wrap.appendChild(renderer.domElement); currentWrapId = wrapId; }
    return moved;
  }

  currentWrapId = wrapId;
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0c0f0a);

  camera = new THREE.PerspectiveCamera(45, 1, 0.01, 100000);

  try {
    renderer = new THREE.WebGLRenderer({ antialias: true });
  } catch (err) {
    setStatus(wrapId, "3D isn't available on this device/browser.");
    throw err;
  }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  wrap.appendChild(renderer.domElement);

  scene.add(new THREE.AmbientLight(0xffffff, 0.7));
  const dir1 = new THREE.DirectionalLight(0xffffff, 1.0);
  dir1.position.set(1, 1, 1);
  scene.add(dir1);
  const dir2 = new THREE.DirectionalLight(0xffffff, 0.35);
  dir2.position.set(-1, 0.4, -1);
  scene.add(dir2);

  controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;

  renderer.domElement.addEventListener('click', onCanvasClick);
  window.addEventListener('resize', resizeRenderer);
  requestAnimationFrame(function tick() {
    if (!renderer) return;
    controls.update();
    renderer.render(scene, camera);
    requestAnimationFrame(tick);
  });

  return true;
}

// Loading/error visibility - there wasn't any before this, which is
// exactly how a too-large model (see the header comment) went unnoticed:
// a slow or failed load rendered nothing at all, identical on-screen to
// "hasn't been asked to load anything yet". Plain text overlay inside
// the wrap div, cleared once the model's actually up.
function setStatus(wrapId, text) {
  const wrap = document.getElementById(wrapId);
  if (!wrap) return;
  let el = wrap.querySelector('.ce-be3d-status');
  if (!text) { if (el) el.remove(); return; }
  if (!el) {
    el = document.createElement('div');
    el.className = 'ce-be3d-status';
    wrap.appendChild(el);
  }
  el.textContent = text;
}

function resizeRenderer() {
  const wrap = document.getElementById(currentWrapId);
  if (!renderer || !wrap || wrap.clientWidth === 0) return;
  camera.aspect = wrap.clientWidth / wrap.clientHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(wrap.clientWidth, wrap.clientHeight);
}

function frameCamera(box) {
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z) || 1;
  camera.position.set(center.x + maxDim * 0.85, center.y + maxDim * 0.65, center.z + maxDim * 0.85);
  camera.near = maxDim / 100;
  camera.far = maxDim * 20;
  camera.updateProjectionMatrix();
  controls.target.copy(center);
  controls.update();
}

// Mounts (or re-parents) the shared canvas into wrapId and loads the
// placeholder carrier once, cached for the rest of the page's life -
// there's only ever one model here, unlike carrier3d.js's per-crane cache.
export function activate(wrapId) {
  const moved = ensureRenderer(wrapId);
  if (moved) resizeRenderer();

  if (!loadingPromise) {
    setStatus(wrapId, 'Loading 3D model…');
    loadingPromise = loadGLTFAsync(MODEL_URL).then((root) => {
      modelRoot = root;
      scene.add(root);
      modelCal = computeFormulaCalibration(root, FOOTPRINT, CALIBRATION);
      dotsGroup = new THREE.Group();
      scene.add(dotsGroup);
      frameCamera(new THREE.Box3().setFromObject(root));
      resizeRenderer();
      setStatus(wrapId, null);
    }).catch((err) => {
      // Reset loadingPromise so re-opening the panel (a flaky connection
      // recovering, etc.) gets a genuine retry instead of being stuck on
      // one rejected promise forever.
      loadingPromise = null;
      setStatus(wrapId, "Couldn't load the 3D model - check your connection and try reopening this panel.");
      throw err;
    });
  }
  return loadingPromise;
}

// entries: [{id, name, weight, radius, slewSide, slewReading, direction, condition}]
// radius is metres, slewReading is 0-180 degrees - same convention as the
// 2D radar plot and the dial itself (side 'lt' sweeps toward C1/C2, 'gt'
// toward C3/C4; side is physically moot at exactly 0 or 180, so a null
// slewSide - never chosen yet - is treated the same as 'lt').
export function setEntries(entries) {
  if (!loadingPromise) return;
  loadingPromise.then(() => {
    while (dotsGroup.children.length) {
      const c = dotsGroup.children.pop();
      c.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });
    }

    const box = new THREE.Box3().setFromObject(modelRoot);

    entries.forEach((en) => {
      const sweep = 180 - Math.min(Math.max(en.slewReading, 0), 180);
      const rad = sweep * Math.PI / 180;
      const sign = en.slewSide === 'gt' ? -1 : 1;
      const dxMm = sign * en.radius * 1000 * Math.sin(rad);
      const dzMm = -en.radius * 1000 * Math.cos(rad);

      const localX = modelCal.lateralCenter + dxMm * modelCal.xSlope;
      const localZ = modelCal.slewZ + dzMm * modelCal.zSlope;
      const groundY = modelCal.groundY;
      const hover = en.direction === 'up' ? 0.9 : 0; // pick readings float slightly - still airborne

      const color = en.direction === 'up' ? 0xffb000 : 0x6fa85a;
      const core = new THREE.Mesh(
        new THREE.SphereGeometry(0.28, 16, 16),
        new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: 0.35 })
      );
      core.position.set(localX, groundY + hover, localZ);
      dotsGroup.add(core);
      box.expandByPoint(core.position);

      // The visible dot is a small, precise marker - fine to look at, far
      // too small a target to reliably tap on a phone/tablet (confirmed by
      // testing: raycasting straight at the visible sphere's own radius
      // missed clicks that were only a few px off). A separate, larger,
      // fully-transparent sphere at the same position carries the actual
      // hit-test, same technique as an oversized invisible tap target in
      // regular HTML/CSS.
      const hitTarget = new THREE.Mesh(
        new THREE.SphereGeometry(0.9, 8, 8),
        new THREE.MeshBasicMaterial({ transparent: true, opacity: 0 })
      );
      hitTarget.position.copy(core.position);
      hitTarget.userData.entry = en;
      dotsGroup.add(hitTarget);

      if (hover > 0) {
        const stem = new THREE.Mesh(
          new THREE.CylinderGeometry(0.03, 0.03, hover, 6),
          new THREE.MeshBasicMaterial({ color: 0x8a8c7e, transparent: true, opacity: 0.6 })
        );
        stem.position.set(localX, groundY + hover / 2, localZ);
        dotsGroup.add(stem);
      }

      if (en.condition === 'old') {
        const ring = new THREE.Mesh(
          new THREE.RingGeometry(0.38, 0.46, 24),
          new THREE.MeshBasicMaterial({ color: 0x8a8c7e, side: THREE.DoubleSide, transparent: true, opacity: 0.8 })
        );
        ring.rotation.x = -Math.PI / 2;
        ring.position.set(localX, groundY + 0.01, localZ);
        dotsGroup.add(ring);
      }
    });

    if (entries.length) frameCamera(box);
    resizeRenderer();
  });
}

function onCanvasClick(ev) {
  if (!onDotClick || !dotsGroup) return;
  const rect = renderer.domElement.getBoundingClientRect();
  const ndc = new THREE.Vector2(
    ((ev.clientX - rect.left) / rect.width) * 2 - 1,
    -((ev.clientY - rect.top) / rect.height) * 2 + 1
  );
  const raycaster = new THREE.Raycaster();
  raycaster.setFromCamera(ndc, camera);
  const hits = raycaster.intersectObjects(dotsGroup.children, false)
    .filter((h) => h.object.userData && h.object.userData.entry);
  if (hits.length) onDotClick(hits[0].object.userData.entry.id);
}

export function onDotSelected(cb) { onDotClick = cb; }

window.__cabEntry3dActivate = activate;
window.__cabEntry3dSetEntries = setEntries;
window.__cabEntry3dOnDotClick = onDotSelected;
