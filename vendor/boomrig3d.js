// Live 3D Boom Clearance viewer - first entry, LTM 1110-5.1 ("LTM1110-3D"
// config in RIG_CONFIGS). Static preview only for now: loads the real GLB,
// picks the correct copy of every duplicated part, and frames the camera
// on it. No extend/retract or luffing-angle sliders yet - see the "Live
// Crane Configurator" design conversation for the full planned scope
// (boom telescoping, luffing ram driven by pivot geometry, outriggers,
// CWT stack); this ships the one piece that's actually verified so far.
//
// Loaded as a <script type="module">, same reasoning as carrier3d.js/
// cwt3d.js: can't see the main app's classic-script bindings, talks back
// only via plain functions on window (__boomRig3DLoad).
//
// The core problem this file works around: every "occurrence of Part N"
// wrapper node in this export carries a near-identical matrix regardless
// of which real part it is (confirmed directly - Part 58 in the base and
// Part 47 at the boom tip, ~25m apart in reality, both report the exact
// same wrapper-node translation). That's NOT the outrigger/CWT precedent's
// "occurrence node carries the real position, bare Part N node sits at
// identity" pattern - here the wrapper node's own transform is unreliable
// and the real position is baked directly into each mesh's own vertex
// data instead. Confirmed independently via a Node.js gltf-transform pass
// reading raw vertex positions before any of this ran through three.js's
// own loader - see the "Live Crane Configurator" conversation for the
// full diagnostic trail (this took several wrong turns: first trusting
// the wrapper node's matrix at all, then trusting a naive per-part
// instance-index split, before landing on "world Z tells you which copy
// is real" as the one property that actually holds up).
//
// Separately, and unrelated to the above: every part in this file's boom/
// head sub-assembly exists as two REAL, valid meshes several METRES apart
// (not the wrapper-matrix bug - both copies have genuinely different bare
// mesh vertex data) - a real, so-far-unexplained duplicate sitting in the
// Onshape document, not a manufacturing twin (a true left/right pair
// differs by centimetres, not metres - the pivot pins/luff cylinder show
// exactly that small a difference, correctly, once read the right way).
// Until the person confirms/removes it on the Onshape side, this file
// picks whichever mesh instance has the larger world-space Z per part -
// verified this selects a single, internally consistent copy: section
// centroids climb monotonically and cleanly (base through section 6, then
// the head just past it) with under 5 degrees of axis deviation between
// any two consecutive sections just using this rule.

import * as THREE from 'three';
import { GLTFLoader } from './three/GLTFLoader.js';
import { DRACOLoader } from './three/DRACOLoader.js';
import { OrbitControls } from './three/OrbitControls.js';

const dracoLoader = new DRACOLoader();
dracoLoader.setDecoderPath('./vendor/three/draco/');

let renderer = null, scene = null, camera = null, controls = null;
let currentWrapId = null;
let animating = false;
const modelCache = {}; // configKey -> THREE.Group (the cleaned, real-copy-only scene)

function ensureRenderer(wrapId) {
  const wrap = document.getElementById(wrapId);
  if (renderer) {
    if (currentWrapId !== wrapId) { wrap.appendChild(renderer.domElement); currentWrapId = wrapId; }
    return;
  }
  currentWrapId = wrapId;
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0f172a);

  camera = new THREE.PerspectiveCamera(45, 1, 0.01, 100000);

  renderer = new THREE.WebGLRenderer({ antialias: true });
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
}

function resizeRenderer(wrapId) {
  const wrap = document.getElementById(wrapId);
  if (!renderer || !wrap || wrap.clientWidth === 0) return;
  camera.aspect = wrap.clientWidth / wrap.clientHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(wrap.clientWidth, wrap.clientHeight);
}

function onFrame() {
  if (!animating) return;
  requestAnimationFrame(onFrame);
  controls.update();
  renderer.render(scene, camera);
}

// Every "Part N" / headPart name appears as TWO real, valid mesh nodes in
// this export (see file header). Walk the whole loaded scene, group nodes
// by base name, and for any name with more than one mesh-bearing node,
// keep only the one with the larger world-space Z center - discard/hide
// the rest. Uses THREE's own world matrix (via Box3().setFromObject),
// deliberately NOT the raw wrapper-node matrix from the export - that's
// the exact thing that turned out unreliable here.
function pickRealCopyOnly(root) {
  const byName = {};
  root.traverse((obj) => {
    if (!obj.isMesh) return;
    const name = obj.name || (obj.parent && obj.parent.name) || '';
    (byName[name] = byName[name] || []).push(obj);
  });
  const kept = [];
  Object.values(byName).forEach((meshes) => {
    if (meshes.length === 1) { kept.push(meshes[0]); return; }
    let best = null, bestZ = -Infinity;
    meshes.forEach((m) => {
      const box = new THREE.Box3().setFromObject(m);
      const center = box.getCenter(new THREE.Vector3());
      if (center.z > bestZ) { bestZ = center.z; best = m; }
    });
    meshes.forEach((m) => { if (m !== best) m.visible = false; });
    kept.push(best);
  });
  return kept;
}

function frameCameraOn(objects) {
  const box = new THREE.Box3();
  objects.forEach((o) => box.expandByObject(o));
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z);
  const dist = maxDim * 1.4;
  camera.position.set(center.x + dist * 0.6, center.y + dist * 0.4, center.z - dist * 0.6);
  camera.lookAt(center);
  controls.target.copy(center);
  controls.update();
}

// wrapId: DOM element to mount the canvas into. labelId: overlay element for
// loading/error text, same role as carrier3d.js's #carrier-3d-label and
// cwt3d.js's #cwt-3d-label. configKey/config: the RIG_CONFIGS entry
// (glbUrl, sections, headParts, etc.) - only glbUrl is actually used yet,
// the rest is read once slider interactivity lands. Void, not a promise -
// same reasoning as window.__cwt3dActivate: errors (a 55MB fetch over a
// real network can fail) are handled here, not left for the caller.
window.__boomRig3DLoad = function (wrapId, labelId, configKey, config) {
  ensureRenderer(wrapId);
  animating = true;
  requestAnimationFrame(onFrame);
  resizeRenderer(wrapId);
  const labelEl = document.getElementById(labelId);

  if (modelCache[configKey]) {
    if (labelEl) labelEl.textContent = '';
    scene.add(modelCache[configKey]);
    frameCameraOn([modelCache[configKey]]);
    return;
  }

  if (labelEl) labelEl.textContent = 'Loading 3D model…';
  const loader = new GLTFLoader();
  loader.setDRACOLoader(dracoLoader);
  loader.load(
    config.glbUrl,
    (gltf) => {
      const kept = pickRealCopyOnly(gltf.scene);
      modelCache[configKey] = gltf.scene;
      scene.add(gltf.scene);
      frameCameraOn(kept.length ? kept : [gltf.scene]);
      if (labelEl) labelEl.textContent = '';
    },
    undefined,
    (err) => {
      if (labelEl) labelEl.textContent = '3D model failed to load. Check your connection and try reselecting this config.';
      console.error('boomrig3d load error', err);
    }
  );
};

window.__boomRig3DResize = function (wrapId) { resizeRenderer(wrapId); };

window.__boomRig3DStop = function () { animating = false; };
