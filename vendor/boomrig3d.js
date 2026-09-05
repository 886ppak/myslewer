// Live 3D Boom Clearance viewer - first entry, LTM 1110-5.1 ("LTM1110-3D"
// config in RIG_CONFIGS). Loads the real GLB, picks the correct copy of
// every duplicated part, frames the camera, and drives a length slider
// (buildLengthRig/applyLength) and a luffing-angle slider (buildAngleRig/
// applyAngle) - see each function's own comment for exactly what real data
// each one is and isn't grounded in. Not yet built: the luffing ram itself
// tracking the angle slider (it's currently fixed - see buildAngleRig's
// comment), outriggers, CWT stack - see the "Live Crane Configurator"
// design conversation for the full planned scope.
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
const rigCache = {}; // configKey -> { group, pivotZ, baseFixedLength, reachAtModeledPose } - see buildLengthRig()
const angleRigCache = {}; // configKey -> { group, pivot } - see buildAngleRig()
const pendingLength = {}; // configKey -> length (m), when __boomRig3DSetLength is called before load finishes
const pendingAngle = {}; // configKey -> degrees, when __boomRig3DSetAngle is called before load finishes

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

// Real part identity for a mesh, found by walking UP its ancestor chain -
// NOT by checking the mesh's own name or its immediate parent, which is
// what this file originally did and which turned out to be wrong for this
// export. Confirmed directly by dumping THREE.GLTFLoader's actual parsed
// scene graph (not gltf-transform's raw JSON, which is what every earlier
// verification in this file used): the real hierarchy for every part is
// occurrence_of_Part_58 > Part_58 > (one or more auto-named mesh
// primitives, e.g. "mesh6_mesh", "mesh6_mesh_1"...). Two problems this
// causes for a naive "obj.name || parent.name" check: (1) those
// auto-generated leaf mesh names are never empty, so the `||` fallback
// never actually reaches the parent at all; (2) GLTFLoader also silently
// turns the glTF node's own "Part 58" (space) into "Part_58" (underscore)
// - confirmed against the real file, not assumed. A genuine second
// occurrence of the same part gets a GLTFLoader-appended "_N" suffix at
// THIS ancestor level ("Part_58_1", or "id5__$_1" for the head parts,
// which keep their exact literal name otherwise). This function walks up
// past the auto-named mesh leaf to find that real identity and strips the
// disambiguation suffix, so "Part_58" and "Part_58_1" both resolve to the
// same "Part 58" - which is what every other function in this file needs
// to correctly group the two real duplicate instances together.
function realPartName(mesh) {
  let node = mesh;
  while (node) {
    const name = node.name || '';
    let m = /^Part[ _](\d+)(?:_\d+)?$/.exec(name);
    if (m) return `Part ${m[1]}`;
    m = /^(id\d+__\$)(?:_\d+)?$/.exec(name);
    if (m) return m[1];
    node = node.parent;
  }
  return mesh.name || '';
}

// Every "Part N" / headPart name appears as TWO real, valid mesh nodes in
// this export (see file header). Walk the whole loaded scene, group nodes
// by real part identity (realPartName - NOT obj.name, which is an
// auto-generated per-primitive string, unique per mesh even for two
// meshes belonging to the same real part), and for any identity with more
// than one mesh-bearing node, keep only the one with the larger
// world-space Z center - discard/hide the rest. Uses THREE's own world
// matrix (via Box3().setFromObject), deliberately NOT the raw wrapper-node
// matrix from the export - that's the exact thing that turned out
// unreliable here.
function pickRealCopyOnly(root) {
  const byName = {};
  root.traverse((obj) => {
    if (!obj.isMesh) return;
    const name = realPartName(obj);
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

// Real-length slider, worked out WITHOUT any per-section stroke data (none
// exists - the person only ever exported one static pose, essentially at
// full extension). Rather than fabricate a per-section overlap figure, this
// takes the one thing that IS real and verified - the model's own geometry,
// and this crane's already-shipped OEM catalog lengths (HOOK_BOOM_LENGTHS,
// index.html) - and uniformly scales everything beyond the fixed base
// section along the boom axis (world Z) to hit the real target length.
//
// This is a deliberate simplification, not a guess: the base section
// (config.sections.base) plus the luffing cylinder and its pivot pins never
// move relative to the boom foot, so they're left alone; every other named
// part (telescoping sections 1-6 + the head sub-assembly) gets reparented
// into one THREE.Group anchored at the base's own leading edge (pivotZ),
// which is then scaled along Z only. The model's own total modeled length
// was independently confirmed to match this crane's real ~60m max boom
// length to within 4cm (see RIG_CONFIGS['1110:3D']'s own comment) - that
// match is what makes treating the model's Z units as real metres, and
// therefore this whole approach, legitimate rather than invented. What it
// does NOT do is animate individual sections sliding past each other with
// the right overlap - that needs real per-section stroke data (an OEM
// figure, or a second retracted-pose export) this session doesn't have.
function buildLengthRig(root, config) {
  const fixedNames = new Set();
  (config.sections && config.sections.base || []).forEach((n) => fixedNames.add(`Part ${n}`));
  if (config.luffCylinderInner != null) fixedNames.add(`Part ${config.luffCylinderInner}`);
  if (config.luffCylinderOuter != null) fixedNames.add(`Part ${config.luffCylinderOuter}`);
  (config.pivotPins || []).forEach((n) => fixedNames.add(`Part ${n}`));

  const fixedMeshes = [];
  const movingMeshes = [];
  root.traverse((obj) => {
    if (!obj.isMesh || obj.visible === false) return;
    const name = realPartName(obj);
    (fixedNames.has(name) ? fixedMeshes : movingMeshes).push(obj);
  });
  if (!fixedMeshes.length || !movingMeshes.length) return null;

  const fixedBox = new THREE.Box3();
  fixedMeshes.forEach((m) => fixedBox.expandByObject(m));
  const movingBox = new THREE.Box3();
  movingMeshes.forEach((m) => movingBox.expandByObject(m));

  const pivotZ = fixedBox.max.z;
  const baseFixedLength = fixedBox.max.z - fixedBox.min.z;
  const reachAtModeledPose = movingBox.max.z - pivotZ;
  if (reachAtModeledPose <= 0) return null;

  const group = new THREE.Group();
  group.position.set(0, 0, pivotZ);
  root.add(group);
  // attach() (not add()) reparents while preserving each mesh's current
  // world transform, so this doesn't move anything - it only changes whose
  // local space each mesh's position is expressed in, which is what makes
  // group.scale.z below scale the right things around the right point.
  movingMeshes.forEach((m) => group.attach(m));

  return { group, pivotZ, baseFixedLength, reachAtModeledPose };
}

// Luffing-angle slider. Unlike the length slider, this one has a real,
// verified physical anchor to rotate around: config.pivotPins (Part 3/
// Part 4 for the 1110) are a matched pair sitting at the same X and Z but
// opposite Y (measured directly - centers [2.0,-0.397,1.71] and
// [2.0,0.397,1.71]) - exactly what a real pin's own axis looks like, so
// the pin's own axis (world Y here) is the real rotation axis, and its
// midpoint is the real pivot point, not an assumption.
//
// Checked this against four points spread across ~8m of the boom (section
// 5 through the tip and head) using atan2 of each one's offset from the
// pivot in the X-Z plane - all four agreed to within 1 degree, which is
// exactly what a straight rigid boom pivoting on a real pin should do, and
// confirms both the axis and the pivot point are right. What ISN'T known
// is what real-world elevation angle the exported pose itself represents
// (no OEM angle was given with this export) - so this slider is offset
// FROM that pose (0 = as-exported), not an absolute "degrees from
// horizontal" reading. Rotates the base + pivot pins + the whole length-
// rig group together (everything that tips with the boom); the luffing
// cylinder is deliberately left out - its outer end is turret-fixed and
// this pass doesn't compute ram kinematics (see luffCylinderInner/Outer's
// own comment in RIG_CONFIGS).
function buildAngleRig(root, config, lengthRig) {
  if (!lengthRig) return null;
  const pinNames = (config.pivotPins || []).map((n) => `Part ${n}`);
  const baseNames = new Set((config.sections && config.sections.base || []).map((n) => `Part ${n}`));

  const pinMeshes = [];
  const baseMeshes = [];
  root.traverse((obj) => {
    if (!obj.isMesh || obj.visible === false) return;
    const name = realPartName(obj);
    if (pinNames.includes(name)) pinMeshes.push(obj);
    else if (baseNames.has(name)) baseMeshes.push(obj);
  });
  if (pinMeshes.length < 2 || !baseMeshes.length) return null;

  const pinBox = new THREE.Box3();
  pinMeshes.forEach((m) => pinBox.expandByObject(m));
  const pivot = pinBox.getCenter(new THREE.Vector3());

  const group = new THREE.Group();
  group.position.copy(pivot);
  root.add(group);
  baseMeshes.forEach((m) => group.attach(m));
  pinMeshes.forEach((m) => group.attach(m));
  group.attach(lengthRig.group);

  return { group, pivot };
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
    if (configKey in pendingLength) applyLength(configKey, pendingLength[configKey]);
    if (configKey in pendingAngle) applyAngle(configKey, pendingAngle[configKey]);
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
      const lengthRig = buildLengthRig(gltf.scene, config);
      rigCache[configKey] = lengthRig;
      angleRigCache[configKey] = buildAngleRig(gltf.scene, config, lengthRig);
      scene.add(gltf.scene);
      if (configKey in pendingLength) applyLength(configKey, pendingLength[configKey]);
      if (configKey in pendingAngle) applyAngle(configKey, pendingAngle[configKey]);
      frameCameraOn(kept.length ? kept : [gltf.scene]);
      // Sliders silently doing nothing (rather than erroring) is exactly
      // the bug this is guarding against - if the part-name matching this
      // relies on ever breaks (a re-export, a naming change), surface it
      // instead of leaving someone moving a control that's quietly a
      // no-op.
      if (!lengthRig) console.warn('boomrig3d: length rig failed to build for', configKey, '- length slider will have no effect.');
      if (!angleRigCache[configKey]) console.warn('boomrig3d: angle rig failed to build for', configKey, '- angle slider will have no effect.');
      if (labelEl) labelEl.textContent = '';
    },
    undefined,
    (err) => {
      if (labelEl) labelEl.textContent = '3D model failed to load. Check your connection and try reselecting this config.';
      console.error('boomrig3d load error', err);
    }
  );
};

// Deliberately does NOT reframe the camera - __boomRig3DLoad frames it once
// (see above), and reframing again here would auto-zoom to fit the newly
// scaled model, which visually cancels out the length change itself (the
// exact bug: changing the length looked like nothing happened, because the
// camera was quietly re-fitting to whatever size the model just became).
function applyLength(configKey, lengthMeters) {
  const rig = rigCache[configKey];
  if (!rig) { pendingLength[configKey] = lengthMeters; return; }
  delete pendingLength[configKey];
  const factor = Math.max(0.02, (lengthMeters - rig.baseFixedLength) / rig.reachAtModeledPose);
  rig.group.scale.set(1, 1, factor);
}

// lengthMeters: a real OEM catalog boom length (HOOK_BOOM_LENGTHS in
// index.html), not an arbitrary number - see buildLengthRig()'s comment for
// exactly what this does and doesn't model.
window.__boomRig3DSetLength = function (configKey, lengthMeters) {
  applyLength(configKey, lengthMeters);
};

// Same "don't reframe" reasoning as applyLength above - rotating the boom
// is the whole point of the slider, so the camera stays put.
function applyAngle(configKey, angleDegrees) {
  const rig = angleRigCache[configKey];
  if (!rig) { pendingAngle[configKey] = angleDegrees; return; }
  delete pendingAngle[configKey];
  rig.group.rotation.y = THREE.MathUtils.degToRad(angleDegrees);
}

// angleDegrees: offset FROM the exported pose (0 = as-exported), not an
// absolute elevation reading - see buildAngleRig()'s comment for why.
window.__boomRig3DSetAngle = function (configKey, angleDegrees) {
  applyAngle(configKey, angleDegrees);
};

window.__boomRig3DResize = function (wrapId) { resizeRenderer(wrapId); };

window.__boomRig3DStop = function () { animating = false; };
