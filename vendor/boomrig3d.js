// Live 3D Boom Clearance viewer - LTM 1110-5.1 ("1110:3D" config in
// RIG_CONFIGS). Second attempt at this (see methodology.txt 158-162 for
// the first one, pulled after the rendered model turned out to be a
// scattered heap of disconnected fragments - a genuine Onshape export
// defect: the whole assembly is duplicated inside itself, splitting
// correct POSITION and correct DETAIL across the two copies of most
// parts, with no single rule recovering both).
//
// This version is built from a fixed export pair instead: the same
// LTM1110COMP.glb (full extension) plus a second export at the crane's
// real minimum retraction, LTM1110FULLRETRACTED.glb. Two poses of the
// SAME document let each part's true moving copy be identified directly
// (whichever occurrence's own position actually changes between the two
// files) rather than guessed from one static pose - and, combined with
// choosing whichever occurrence has the most geometry for actual shape,
// gives a model where every part is both correctly positioned AND
// reasonably detailed. The two poses are pre-baked into
// ltm1110_boomrig.glb as one mesh per part with the extension pose as
// its base geometry and the retraction pose as a single glTF morph
// target - the length slider below just sets one weight per mesh
// (0 = fully extended, 1 = at the retracted export's own length), which
// three.js/the GPU interpolates for free. See build_production.mjs in
// this session's own working notes for exactly how that file was built.
//
// Real, verified per-section stroke lengths came out of this pairing
// too (~8.0-8.07m per section, 48.29m total vs this crane's real 48.5m
// OEM total stroke, well within the precision of a by-eye retraction) -
// this slider is driving genuine geometry, not an invented uniform
// scale the way the first attempt's length control was.
//
// Loaded as a <script type="module">, same reasoning as carrier3d.js/
// cwt3d.js: can't see the main app's classic-script bindings, talks
// back only via plain functions on window (__boomRig3DLoad).

import * as THREE from 'three';
import { GLTFLoader } from './three/GLTFLoader.js';
import { OrbitControls } from './three/OrbitControls.js';

let renderer = null, scene = null, camera = null, controls = null;
let currentWrapId = null;
let animating = false;
const modelCache = {}; // configKey -> THREE.Group
const morphMeshCache = {}; // configKey -> THREE.Mesh[] (only meshes carrying the retraction morph target)
const lengthRangeCache = {}; // configKey -> {minLength, maxLength}, from RIG_CONFIGS at load time
const pendingLength = {}; // configKey -> length (m), when __boomRig3DSetLength is called before load finishes

function ensureRenderer(wrapId) {
  const wrap = document.getElementById(wrapId);
  if (renderer) {
    if (currentWrapId !== wrapId) { wrap.appendChild(renderer.domElement); currentWrapId = wrapId; }
    return;
  }
  currentWrapId = wrapId;
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0f172a);

  camera = new THREE.PerspectiveCamera(45, 1, 0.01, 1000);

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

// Framed once, right after load, while every morph weight is still at
// its default (0 = fully extended - the biggest the model ever gets) -
// deliberately NOT reframed when the length slider changes afterward.
// Reframing on every length change is the exact bug methodology.txt 160
// found in the first attempt: fitting the camera to the newly-resized
// model cancels out the resize itself, so the slider visually appeared
// to do nothing.
function frameCameraOn(root) {
  const box = new THREE.Box3().setFromObject(root);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z);
  const dist = maxDim * 0.75;
  camera.position.set(center.x + dist * 0.7, center.y + dist * 0.25, center.z + dist * 0.7);
  camera.lookAt(center);
  controls.target.copy(center);
  controls.update();
}

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
    frameCameraOn(modelCache[configKey]);
    return;
  }

  if (labelEl) labelEl.textContent = 'Loading 3D model…';
  const loader = new GLTFLoader();
  loader.load(
    config.glbUrl,
    (gltf) => {
      const morphMeshes = [];
      gltf.scene.traverse((obj) => {
        if (obj.isMesh && obj.morphTargetInfluences && obj.morphTargetInfluences.length) {
          morphMeshes.push(obj);
        }
      });
      modelCache[configKey] = gltf.scene;
      morphMeshCache[configKey] = morphMeshes;
      lengthRangeCache[configKey] = { minLength: config.minLength, maxLength: config.maxLength };
      scene.add(gltf.scene);
      if (configKey in pendingLength) applyLength(configKey, pendingLength[configKey]);
      frameCameraOn(gltf.scene);
      if (!morphMeshes.length) console.warn('boomrig3d: no morph-target meshes found for', configKey, '- length slider will have no effect.');
      if (labelEl) labelEl.textContent = '';
    },
    undefined,
    (err) => {
      if (labelEl) labelEl.textContent = '3D model failed to load. Check your connection and try reselecting this config.';
      console.error('boomrig3d load error', err);
    }
  );
};

// lengthMeters: a real OEM catalog boom length (HOOK_BOOM_LENGTHS in
// index.html). Maps linearly onto this crane's real min/max span
// (config.minLength/maxLength, from the two source exports) to a 0-1
// morph weight - 0 at maxLength (the extended export), 1 at minLength
// (the retracted export). Values are real catalog lengths from a
// dropdown, not an arbitrary slider, so this never needs to extrapolate
// past either end.
function applyLength(configKey, lengthMeters) {
  const meshes = morphMeshCache[configKey];
  const range = lengthRangeCache[configKey];
  if (!meshes || !range) { pendingLength[configKey] = lengthMeters; return; }
  delete pendingLength[configKey];
  const t = Math.min(1, Math.max(0, (range.maxLength - lengthMeters) / (range.maxLength - range.minLength)));
  meshes.forEach((m) => { m.morphTargetInfluences[0] = t; });
}

window.__boomRig3DSetLength = function (configKey, lengthMeters) {
  applyLength(configKey, lengthMeters);
};

window.__boomRig3DResize = function (wrapId) { resizeRenderer(wrapId); };

window.__boomRig3DStop = function () { animating = false; };
