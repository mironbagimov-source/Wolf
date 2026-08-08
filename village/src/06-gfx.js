'use strict';
// ---------------------------------------------------------------------
// Renderer, procedural textures, prop builders, particles.
// Nothing is loaded from disk except the humanoid rig — walls, snow, wood
// and stone are all painted into canvases at boot.
// ---------------------------------------------------------------------

const GFX = {
  renderer: null, scene: null, camera: null, rig: null,
  lantern: null, muzzle: null,
  zoneGroup: null,
  fx: [], decals: [], snow: null,
  shake: 0, shakeT: 0,
  _lightPool: [],
};

// ------------------------------------------------------------ textures
function texCanvas(size, draw) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  const g = c.getContext('2d');
  draw(g, size);
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

function noiseTex(base, speck, density, size) {
  return texCanvas(size || 128, (g, s) => {
    g.fillStyle = base; g.fillRect(0, 0, s, s);
    for (let i = 0; i < s * s * (density || 0.25); i++) {
      const a = Math.random() * 0.5;
      g.fillStyle = `rgba(${speck[0]},${speck[1]},${speck[2]},${a.toFixed(3)})`;
      g.fillRect(Math.random() * s, Math.random() * s, 1 + Math.random() * 2, 1 + Math.random() * 2);
    }
  });
}

function plankTex() {
  return texCanvas(128, (g, s) => {
    g.fillStyle = '#3a2d22'; g.fillRect(0, 0, s, s);
    for (let y = 0; y < s; y += 16) {
      g.fillStyle = `rgb(${52 + Math.random() * 26 | 0},${40 + Math.random() * 20 | 0},${30 + Math.random() * 14 | 0})`;
      g.fillRect(0, y, s, 15);
      g.fillStyle = 'rgba(0,0,0,0.55)';
      g.fillRect(0, y + 15, s, 1);
      for (let i = 0; i < 30; i++) {
        g.fillStyle = `rgba(20,14,10,${(Math.random() * 0.35).toFixed(2)})`;
        g.fillRect(Math.random() * s, y + Math.random() * 14, 6 + Math.random() * 20, 1);
      }
    }
  });
}

function stoneTex() {
  return texCanvas(128, (g, s) => {
    g.fillStyle = '#3c3c40'; g.fillRect(0, 0, s, s);
    const bh = 16;
    for (let row = 0, y = 0; y < s; y += bh, row++) {
      const off = (row % 2) * 20;
      for (let x = -20; x < s; x += 32) {
        const v = 46 + Math.random() * 26 | 0;
        g.fillStyle = `rgb(${v},${v + 2},${v + 6})`;
        g.fillRect(x + off + 1, y + 1, 30, bh - 2);
      }
    }
    for (let i = 0; i < 400; i++) {
      g.fillStyle = `rgba(10,10,14,${(Math.random() * 0.4).toFixed(2)})`;
      g.fillRect(Math.random() * s, Math.random() * s, 2, 2);
    }
  });
}

function snowTex() {
  return texCanvas(128, (g, s) => {
    g.fillStyle = '#8e97a6'; g.fillRect(0, 0, s, s);
    for (let i = 0; i < 2600; i++) {
      const v = 130 + Math.random() * 80 | 0;
      g.fillStyle = `rgba(${v},${v + 6},${v + 16},${(Math.random() * 0.55).toFixed(2)})`;
      g.fillRect(Math.random() * s, Math.random() * s, 1 + Math.random() * 3, 1 + Math.random() * 3);
    }
    for (let i = 0; i < 60; i++) {
      g.fillStyle = `rgba(50,55,66,${(Math.random() * 0.25).toFixed(2)})`;
      g.fillRect(Math.random() * s, Math.random() * s, 6 + Math.random() * 14, 3 + Math.random() * 6);
    }
  });
}

let TEX = null;
function initTextures() {
  TEX = {
    snow: snowTex(),
    wood: plankTex(),
    stone: stoneTex(),
    dirt: noiseTex('#2b2620', [70, 60, 48], 0.3),
    plaster: noiseTex('#4a4238', [90, 82, 70], 0.2),
    flesh: noiseTex('#3a2a2a', [90, 50, 50], 0.25),
  };
}

const MATS = {};
function mat(key, opts) {
  if (MATS[key]) return MATS[key];
  MATS[key] = new THREE.MeshLambertMaterial(opts);
  return MATS[key];
}

function initMaterials() {
  mat('snow', { map: TEX.snow, color: 0x8a94a6 });
  mat('dirt', { map: TEX.dirt, color: 0x5e564c });
  mat('wood', { map: TEX.wood, color: 0x8a7a64 });
  mat('woodDark', { map: TEX.wood, color: 0x594c3e });
  mat('stone', { map: TEX.stone, color: 0x6e6e78 });
  mat('stoneDark', { map: TEX.stone, color: 0x484850 });
  mat('plaster', { map: TEX.plaster, color: 0x8a8274 });
  mat('roof', { color: 0x2e2a2c });
  mat('metal', { color: 0x4a4c52 });
  mat('iron', { color: 0x33363c });
  mat('gold', { color: 0xb08d3c, emissive: 0x3a2a08 });
  mat('cloth', { color: 0x5a2028 });
  mat('bark', { color: 0x2c2620 });
  mat('needle', { color: 0x1d2a24 });
  mat('bone', { color: 0xb9b0a0 });
  mat('glass', { color: 0x223040, transparent: true, opacity: 0.35 });
}

// --------------------------------------------------------------- boot
function initGraphics(canvas) {
  GFX.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
  GFX.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
  if (THREE.sRGBEncoding) GFX.renderer.outputEncoding = THREE.sRGBEncoding;
  // Without tone mapping the lantern clips everything it touches to white and
  // the dead come out looking like plaster statues. ACES rolls the highlights
  // off and keeps the palette cold.
  if (THREE.ACESFilmicToneMapping) {
    GFX.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    GFX.renderer.toneMappingExposure = 1.05;
  }

  GFX.scene = new THREE.Scene();
  GFX.scene.background = new THREE.Color(0x05070c);
  GFX.scene.fog = new THREE.FogExp2(0x05070c, 0.035);

  GFX.camera = new THREE.PerspectiveCamera(74, 1, 0.06, 190);
  GFX.rig = new THREE.Object3D();
  GFX.rig.add(GFX.camera);
  GFX.scene.add(GFX.rig);

  GFX.ambient = new THREE.AmbientLight(0x2a3242, 0.42);
  GFX.scene.add(GFX.ambient);
  GFX.moon = new THREE.DirectionalLight(0x5a6b8c, 0.3);
  GFX.moon.position.set(-18, 30, -14);
  GFX.scene.add(GFX.moon);

  // the lamp the player carries — the main reason anything is visible at all
  GFX.lantern = new THREE.PointLight(0xffb463, 1.5, 17, 1.6);
  GFX.lantern.position.set(0.25, -0.12, 0.1);
  GFX.camera.add(GFX.lantern);

  GFX.muzzle = new THREE.PointLight(0xffd08a, 0, 12, 2);
  GFX.muzzle.position.set(0.2, -0.15, -0.6);
  GFX.camera.add(GFX.muzzle);

  initTextures();
  initMaterials();
  initFxPools();
}

let _lastW = 0, _lastH = 0;
function resizeRenderer(stage) {
  const w = stage.clientWidth, h = stage.clientHeight;
  if (w === _lastW && h === _lastH) return;
  _lastW = w; _lastH = h;
  GFX.renderer.setSize(w, h, false);
  GFX.camera.aspect = w / h || 1;
  GFX.camera.updateProjectionMatrix();
}

// -------------------------------------------------------- zone builder
// A builder collects meshes into one group plus the parallel gameplay data
// (colliders, interactables, spawn points) that the systems read.
function makeBuilder() {
  const group = new THREE.Group();
  return {
    group,
    colliders: [],
    interactables: [],
    spawns: {},
    torches: [],
    pickupMeshes: [],
    add(mesh) { group.add(mesh); return mesh; },
    solid(b) { this.colliders.push(b); return b; },
    interact(o) { this.interactables.push(o); return o; },
    spawn(name, x, z, yaw) { this.spawns[name] = { x, z, yaw: yaw || 0 }; },
  };
}

// Box UVs run 0..1 per face, so a texture on a 12 m wall gets stretched into
// one enormous brick. Rescaling the UVs by real size keeps the tiling honest —
// and it has to happen on the geometry, not the texture, because materials
// (and their maps) are shared across every wall in the game.
const TILE = 2.2;
function tileBoxUV(geo, w, h, d, tile) {
  const uv = geo.attributes.uv;
  if (!uv) return;
  const t = tile || TILE;
  const faces = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];   // +x -x +y -y +z -z
  for (let f = 0; f < 6; f++) {
    const su = faces[f][0] / t, sv = faces[f][1] / t;
    for (let i = 0; i < 4; i++) {
      const k = f * 4 + i;
      uv.setXY(k, uv.getX(k) * su, uv.getY(k) * sv);
    }
  }
  uv.needsUpdate = true;
}

function tilePlaneUV(geo, w, d, tile) {
  const uv = geo.attributes.uv;
  if (!uv) return;
  const t = tile || TILE;
  for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * w / t, uv.getY(i) * d / t);
  uv.needsUpdate = true;
}

function meshBox(w, h, d, material, tile) {
  const geo = new THREE.BoxGeometry(w, h, d);
  tileBoxUV(geo, w, h, d, tile);
  const m = new THREE.Mesh(geo, material);
  m.matrixAutoUpdate = false;
  return m;
}

function place(m, x, y, z, ry) {
  m.position.set(x, y, z);
  if (ry) m.rotation.y = ry;
  m.updateMatrix();
  return m;
}

// solid box: mesh + collider in one call. y is the bottom.
function bx(W, x, y, z, w, h, d, material, opts) {
  const o = opts || {};
  const m = meshBox(w, h, d, material);
  place(m, x, y + h / 2, z);
  if (o.uv) { /* map repeat is per-material; kept simple on purpose */ }
  W.add(m);
  if (!o.ghost) W.solid(box(x, z, w / 2, d / 2, y, y + h));
  return m;
}

function ground(W, x, z, w, d, material, y, tile) {
  const geo = new THREE.PlaneGeometry(w, d);
  tilePlaneUV(geo, w, d, tile || 3.2);
  const m = new THREE.Mesh(geo, material);
  m.rotation.x = -Math.PI / 2;
  m.position.set(x, y || 0, z);
  m.matrixAutoUpdate = false; m.updateMatrix();
  W.add(m);
  return m;
}

function ceiling(W, x, z, w, d, material, y, tile) {
  const geo = new THREE.PlaneGeometry(w, d);
  tilePlaneUV(geo, w, d, tile || 3.2);
  const m = new THREE.Mesh(geo, material);
  m.rotation.x = Math.PI / 2;
  m.position.set(x, y, z);
  m.matrixAutoUpdate = false; m.updateMatrix();
  W.add(m);
  return m;
}

// A rectangular room with optional doorway gaps. side: 'n' (-z), 's' (+z),
// 'e' (+x), 'w' (-x); `at` is the gap centre measured along that wall.
// `open: ['e']` skips a side entirely — used where a neighbouring room's wall
// already closes that edge, so two coincident walls never z-fight.
function room(W, cx, cz, w, d, opts) {
  const o = opts || {};
  const open = o.open || [];
  const h = o.h || 3.4, th = o.th || 0.4;
  const wallMat = o.wall || mat('stone');
  const floorMat = o.floor || mat('stoneDark');
  ground(W, cx, cz, w, d, floorMat, o.y || 0);
  if (o.ceiling !== false) ceiling(W, cx, cz, w, d, o.ceil || mat('woodDark'), (o.y || 0) + h);

  const doors = o.doors || [];
  const sides = [
    { k: 'n', along: 'x', len: w, fixed: cz - d / 2, },
    { k: 's', along: 'x', len: w, fixed: cz + d / 2, },
    { k: 'w', along: 'z', len: d, fixed: cx - w / 2, },
    { k: 'e', along: 'z', len: d, fixed: cx + w / 2, },
  ];
  for (const s of sides) {
    if (open.indexOf(s.k) >= 0) continue;
    const gaps = doors.filter(g => g.side === s.k)
      .map(g => ({ a: g.at - g.width / 2, b: g.at + g.width / 2 }))
      .sort((p, q) => p.a - q.a);
    let cursor = -s.len / 2;
    const segs = [];
    for (const g of gaps) {
      if (g.a > cursor) segs.push([cursor, Math.min(g.a, s.len / 2)]);
      cursor = Math.max(cursor, g.b);
    }
    if (cursor < s.len / 2) segs.push([cursor, s.len / 2]);

    for (const [a, b] of segs) {
      const len = b - a;
      if (len <= 0.02) continue;
      const mid = (a + b) / 2;
      if (s.along === 'x') bx(W, cx + mid, o.y || 0, s.fixed, len, h, th, wallMat);
      else bx(W, s.fixed, o.y || 0, cz + mid, th, h, len, wallMat);
    }
    // lintel above each doorway so you never see the void through the gap
    for (const g of gaps) {
      const dh = g.height || 2.3;
      if (dh >= h) continue;
      if (s.along === 'x') bx(W, cx + g.at, (o.y || 0) + dh, s.fixed, g.width, h - dh, th, wallMat, { ghost: true });
      else bx(W, s.fixed, (o.y || 0) + dh, cz + g.at, th, h - dh, g.width, wallMat, { ghost: true });
    }
  }
}

// ------------------------------------------------------------- props
function house(W, x, z, w, d, h, ry, opts) {
  const o = opts || {};
  const g = new THREE.Group();
  const wallMat = o.wall || mat('woodDark');
  const body = meshBox(w, h, d, wallMat);
  place(body, 0, h / 2, 0);
  g.add(body);

  // roof: two slabs leaning together
  const rl = Math.hypot(d / 2, h * 0.45) + 0.3;
  for (const s of [-1, 1]) {
    const slab = meshBox(w + 0.5, 0.16, rl, mat('roof'));
    slab.position.set(0, h + h * 0.22, s * d / 4);
    slab.rotation.x = s * Math.atan2(h * 0.45, d / 2);
    slab.updateMatrix();
    g.add(slab);
  }
  // door + windows as dark inset panels (the houses are shells; only key
  // buildings can be entered, and those are separate zones)
  const doorPanel = meshBox(1.0, 2.0, 0.12, mat('iron'));
  place(doorPanel, 0, 1.0, d / 2 + 0.02);
  g.add(doorPanel);
  for (const wx of [-w / 3, w / 3]) {
    const win = meshBox(0.9, 0.8, 0.1, o.lit ? mat('gold') : mat('glass'));
    place(win, wx, h * 0.62, d / 2 + 0.02);
    g.add(win);
  }
  g.position.set(x, 0, z);
  g.rotation.y = ry || 0;
  W.add(g);

  // collider: axis-aligned box big enough for either orientation
  const rot = Math.abs(Math.sin(ry || 0)) > 0.5;
  W.solid(box(x, z, (rot ? d : w) / 2, (rot ? w : d) / 2, 0, h));
  return g;
}

function tree(W, x, z, scale) {
  const s = scale || 1;
  const g = new THREE.Group();
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.16 * s, 0.26 * s, 3.4 * s, 6), mat('bark'));
  trunk.position.y = 1.7 * s;
  g.add(trunk);
  for (let i = 0; i < 3; i++) {
    const cone = new THREE.Mesh(new THREE.ConeGeometry((1.5 - i * 0.32) * s, (1.7 + i * 0.1) * s, 7), mat('needle'));
    cone.position.y = (2.1 + i * 0.95) * s;
    g.add(cone);
  }
  g.position.set(x, 0, z);
  g.rotation.y = rnd() * TAU;
  W.add(g);
  W.solid(box(x, z, 0.34 * s, 0.34 * s, 0, 3 * s));
}

function deadTree(W, x, z, scale) {
  const s = scale || 1;
  const g = new THREE.Group();
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.1 * s, 0.3 * s, 4.2 * s, 5), mat('bark'));
  trunk.position.y = 2.1 * s;
  g.add(trunk);
  for (let i = 0; i < 5; i++) {
    const br = new THREE.Mesh(new THREE.CylinderGeometry(0.04 * s, 0.09 * s, 1.6 * s, 4), mat('bark'));
    br.position.set(0, (2.2 + rnd() * 1.6) * s, 0);
    br.rotation.set(rndRange(-0.9, 0.9), rnd() * TAU, rndRange(0.6, 1.2));
    g.add(br);
  }
  g.position.set(x, 0, z);
  W.add(g);
  W.solid(box(x, z, 0.3 * s, 0.3 * s, 0, 3.4 * s));
}

function fence(W, x1, z1, x2, z2) {
  const len = Math.hypot(x2 - x1, z2 - z1);
  const n = Math.max(2, Math.round(len / 1.1));
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const px = lerp(x1, x2, t), pz = lerp(z1, z2, t);
    const post = meshBox(0.12, 1.35 + rnd() * 0.3, 0.12, mat('woodDark'));
    place(post, px, 0.7, pz, rnd() * 0.4);
    W.add(post);
  }
  const mx = (x1 + x2) / 2, mz = (z1 + z2) / 2;
  const horiz = Math.abs(x2 - x1) > Math.abs(z2 - z1);
  const rail = meshBox(horiz ? len : 0.08, 0.1, horiz ? 0.08 : len, mat('woodDark'));
  place(rail, mx, 0.95, mz);
  W.add(rail);
  W.solid(box(mx, mz, horiz ? len / 2 : 0.18, horiz ? 0.18 : len / 2, 0, 1.3));
}

function torch(W, x, y, z, color) {
  const g = new THREE.Group();
  const pole = meshBox(0.09, 1.1, 0.09, mat('woodDark'));
  place(pole, 0, 0.55, 0);
  g.add(pole);
  const flame = new THREE.Mesh(new THREE.SphereGeometry(0.16, 8, 6),
    new THREE.MeshBasicMaterial({ color: color || 0xffa040 }));
  flame.position.y = 1.2;
  g.add(flame);
  const light = new THREE.PointLight(color || 0xff9a3c, 1.15, 11, 1.7);
  light.position.y = 1.25;
  g.add(light);
  g.position.set(x, y, z);
  W.add(g);
  W.torches.push({ light, flame, phase: rnd() * TAU, base: 1.15 });
  return g;
}

function bonfire(W, x, z) {
  const g = new THREE.Group();
  for (let i = 0; i < 7; i++) {
    const log = meshBox(0.16, 0.16, 1.5, mat('woodDark'));
    log.position.set(rndRange(-0.3, 0.3), 0.12, rndRange(-0.3, 0.3));
    log.rotation.set(rndRange(-0.3, 0.3), rnd() * TAU, rndRange(-0.4, 0.4));
    log.updateMatrix();
    g.add(log);
  }
  const flame = new THREE.Mesh(new THREE.ConeGeometry(0.5, 1.3, 8),
    new THREE.MeshBasicMaterial({ color: 0xff8a2a, transparent: true, opacity: 0.9 }));
  flame.position.y = 0.75;
  g.add(flame);
  const light = new THREE.PointLight(0xff9840, 2.4, 20, 1.5);
  light.position.y = 1.1;
  g.add(light);
  g.position.set(x, 0, z);
  W.add(g);
  W.torches.push({ light, flame, phase: rnd() * TAU, base: 2.4, big: true });
  W.solid(box(x, z, 0.8, 0.8, 0, 0.5));
}

function well(W, x, z) {
  const g = new THREE.Group();
  const ring = new THREE.Mesh(new THREE.CylinderGeometry(1.0, 1.1, 1.0, 12), mat('stone'));
  ring.position.y = 0.5; g.add(ring);
  const hole = new THREE.Mesh(new THREE.CircleGeometry(0.82, 12), new THREE.MeshBasicMaterial({ color: 0x000000 }));
  hole.rotation.x = -Math.PI / 2; hole.position.y = 1.01; g.add(hole);
  for (const s of [-1, 1]) {
    const post = meshBox(0.14, 2.0, 0.14, mat('woodDark'));
    place(post, s * 0.9, 1.0, 0); g.add(post);
  }
  const beam = meshBox(2.1, 0.16, 0.16, mat('woodDark'));
  place(beam, 0, 2.05, 0); g.add(beam);
  g.position.set(x, 0, z);
  W.add(g);
  W.solid(box(x, z, 1.15, 1.15, 0, 1.1));
}

// A door you look at but never walk through — the wall behind it is solid and
// the zone change happens on the interact prompt, not by stepping into a gap.
function doorPanel(W, x, z, ry, w, h) {
  const g = new THREE.Group();
  const leaf = meshBox(w || 2.0, h || 2.4, 0.14, mat('wood'));
  place(leaf, 0, (h || 2.4) / 2, 0);
  g.add(leaf);
  for (const s of [-1, 1]) {
    const band = meshBox((w || 2.0) * 0.9, 0.12, 0.05, mat('iron'));
    place(band, 0, (h || 2.4) * (s < 0 ? 0.25 : 0.75), 0.09);
    g.add(band);
  }
  const handle = new THREE.Mesh(new THREE.SphereGeometry(0.07, 8, 6), mat('metal'));
  handle.position.set((w || 2.0) * 0.32, (h || 2.4) * 0.5, 0.12);
  g.add(handle);
  g.position.set(x, 0, z);
  g.rotation.y = ry || 0;
  W.add(g);
  return g;
}

function crate(W, x, z, ry) {
  const m = meshBox(0.9, 0.85, 0.9, mat('wood'));
  place(m, x, 0.43, z, ry || 0);
  W.add(m);
  W.solid(box(x, z, 0.5, 0.5, 0, 0.85));
  return m;
}

function barrel(W, x, z) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.38, 1.05, 10), mat('woodDark'));
  m.position.set(x, 0.52, z);
  W.add(m);
  W.solid(box(x, z, 0.44, 0.44, 0, 1.05));
  return m;
}

function grave(W, x, z) {
  const m = meshBox(0.6, rndRange(0.7, 1.1), 0.12, mat('stone'));
  place(m, x, 0.45, z, rndRange(-0.3, 0.3));
  W.add(m);
  W.solid(box(x, z, 0.35, 0.2, 0, 1.0));
}

function coffin(W, x, z, ry, open) {
  const g = new THREE.Group();
  const body = meshBox(0.8, 0.55, 2.1, mat('woodDark'));
  place(body, 0, 0.28, 0); g.add(body);
  if (!open) {
    const lid = meshBox(0.84, 0.1, 2.14, mat('wood'));
    place(lid, 0, 0.6, 0); g.add(lid);
  } else {
    const lid = meshBox(0.84, 0.1, 2.14, mat('wood'));
    lid.position.set(0.75, 0.35, 0.2); lid.rotation.z = 0.9; lid.updateMatrix();
    g.add(lid);
    const inner = meshBox(0.66, 0.06, 1.9, new THREE.MeshLambertMaterial({ color: 0x140d0d }));
    place(inner, 0, 0.53, 0); g.add(inner);
  }
  g.position.set(x, 0, z); g.rotation.y = ry || 0;
  W.add(g);
  W.solid(box(x, z, 0.55, 1.1, 0, 0.7));
  return g;
}

function pillar(W, x, z, h) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.5, h || 5, 10), mat('stone'));
  m.position.set(x, (h || 5) / 2, z);
  W.add(m);
  W.solid(box(x, z, 0.5, 0.5, 0, h || 5));
}

function chandelier(W, x, y, z) {
  const g = new THREE.Group();
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.9, 0.06, 6, 18), mat('iron'));
  ring.rotation.x = Math.PI / 2; g.add(ring);
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * TAU;
    const candle = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.3, 6), mat('bone'));
    candle.position.set(Math.cos(a) * 0.9, 0.2, Math.sin(a) * 0.9);
    g.add(candle);
    const fl = new THREE.Mesh(new THREE.SphereGeometry(0.06, 6, 5), new THREE.MeshBasicMaterial({ color: 0xffc070 }));
    fl.position.set(Math.cos(a) * 0.9, 0.4, Math.sin(a) * 0.9);
    g.add(fl);
  }
  const light = new THREE.PointLight(0xffb060, 1.5, 18, 1.6);
  g.add(light);
  g.position.set(x, y, z);
  W.add(g);
  W.torches.push({ light, flame: ring, phase: rnd() * TAU, base: 1.5 });
}

function cart(W, x, z, ry) {
  const g = new THREE.Group();
  const bed = meshBox(2.4, 0.3, 1.3, mat('woodDark'));
  place(bed, 0, 0.85, 0); g.add(bed);
  for (const s of [-1, 1]) {
    const wheel = new THREE.Mesh(new THREE.TorusGeometry(0.55, 0.09, 5, 14), mat('woodDark'));
    wheel.position.set(0.5, 0.6, s * 0.72);
    wheel.rotation.y = Math.PI / 2;
    g.add(wheel);
  }
  const crateM = meshBox(0.8, 0.7, 0.8, mat('wood'));
  place(crateM, -0.6, 1.35, 0); g.add(crateM);
  g.position.set(x, 0, z); g.rotation.y = ry || 0;
  W.add(g);
  W.solid(box(x, z, 1.4, 0.9, 0, 1.4));
  return g;
}

function shrine(W, x, z) {
  const g = new THREE.Group();
  const stand = meshBox(0.7, 1.0, 0.5, mat('woodDark'));
  place(stand, 0, 0.5, 0); g.add(stand);
  const iconM = meshBox(0.5, 0.65, 0.06, mat('gold'));
  place(iconM, 0, 1.35, 0); g.add(iconM);
  const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.11, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffd070 }));
  lamp.position.set(0, 1.08, 0.22); g.add(lamp);
  const light = new THREE.PointLight(0xffc060, 1.0, 8, 1.6);
  light.position.set(0, 1.2, 0.3); g.add(light);
  g.position.set(x, 0, z);
  W.add(g);
  W.torches.push({ light, flame: lamp, phase: rnd() * TAU, base: 1.0 });
  W.solid(box(x, z, 0.45, 0.35, 0, 1.0));
  return g;
}

// A pickup that visibly sits in the world and bobs, so loot reads at a glance.
// Deliberately unlit: a point light per pickup looks lovely and costs a whole
// forward-render pass over the level for every single one of them.
const _glowSprite = { tex: null };
function pickupMesh(W, x, z, itemId, y) {
  const d = ITEMS[itemId] || KEY_ITEMS[itemId] || {};
  const g = new THREE.Group();
  const color = d.kind === 'ammo' ? 0xd8b45a : d.kind === 'heal' ? 0x7fdf8a
    : d.kind === 'treasure' ? 0xf0d878 : d.kind === 'weapon' ? 0xaebac8 : 0xa8c0e0;
  const cube = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.2, 0.2),
    new THREE.MeshBasicMaterial({ color }));
  g.add(cube);

  if (!_glowSprite.tex) {
    _glowSprite.tex = texCanvas(48, (ctx, s) => {
      const grd = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
      grd.addColorStop(0, 'rgba(255,255,255,0.85)');
      grd.addColorStop(0.35, 'rgba(255,255,255,0.22)');
      grd.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = grd; ctx.fillRect(0, 0, s, s);
    });
  }
  const glow = new THREE.Sprite(new THREE.SpriteMaterial({
    map: _glowSprite.tex, color, transparent: true, depthWrite: false, opacity: 0.7 }));
  glow.scale.setScalar(0.85);
  g.add(glow);

  g.position.set(x, (y == null ? 0.55 : y), z);
  g.userData.bob = { baseY: g.position.y, phase: rnd() * TAU };
  W.add(g);
  if (W.pickupMeshes) W.pickupMeshes.push(g);
  return g;
}

// Loot turning slowly in the dark is the cheapest way to say "walk over here".
function updatePickups(list, t) {
  if (!list) return;
  for (const g of list) {
    if (!g.visible) continue;
    const b = g.userData.bob;
    g.rotation.y = t * 1.1 + b.phase;
    g.position.y = b.baseY + Math.sin(t * 2 + b.phase) * 0.06;
  }
}

// ------------------------------------------------------------ characters
const ASSETS = { soldier: null };

function loadSoldier(onDone) {
  const b64 = window.SOLDIER_GLB_BASE64;
  if (!b64 || !THREE.GLTFLoader) { onDone(); return; }
  try {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    new THREE.GLTFLoader().parse(bytes.buffer, '', gltf => { ASSETS.soldier = gltf; onDone(); },
      err => { console.warn('rig parse failed, using capsules', err); onDone(); });
  } catch (err) {
    console.warn('rig decode failed, using capsules', err);
    onDone();
  }
}

// One rigged body per walker, tinted per species. If the rig failed to load
// the game still runs — it just fields blocky capsules instead.
function makeCharacter(tint, scale, emissive, hunch) {
  const group = new THREE.Group();
  const out = { group, mixer: null, actions: {}, current: null, materials: [] };
  const src = ASSETS.soldier;

  if (src && THREE.SkeletonUtils) {
    const rigNode = THREE.SkeletonUtils.clone(src.scene);
    rigNode.scale.setScalar(scale || 1);
    rigNode.rotation.y = Math.PI;      // the rig faces +z, our forward is -z
    // a forward lean turns an upright soldier silhouette into something that
    // walks wrong, which is most of what makes these things read as dead
    if (hunch) rigNode.rotation.x = hunch;
    rigNode.traverse(n => {
      if (!n.isMesh) return;
      n.material = n.material.clone();
      // drop the source model's camo texture — a flat, cold body colour reads
      // as a corpse, the texture reads as a soldier in fatigues
      n.material.map = null;
      n.material.color = new THREE.Color(tint);
      n.material.emissive = new THREE.Color(emissive == null ? 0x120608 : emissive);
      n.material.emissiveIntensity = 0.35;
      n.frustumCulled = false;
      out.materials.push(n.material);
    });
    group.add(rigNode);
    out.mixer = new THREE.AnimationMixer(rigNode);
    for (const clip of src.animations) out.actions[clip.name] = out.mixer.clipAction(clip);
  } else {
    const m = new THREE.MeshLambertMaterial({ color: tint, emissive: 0x140808 });
    out.materials.push(m);
    const body = new THREE.Mesh(new THREE.CylinderGeometry(0.3 * (scale || 1), 0.38 * (scale || 1), 1.35 * (scale || 1), 8), m);
    body.position.y = 0.72 * (scale || 1);
    group.add(body);
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.24 * (scale || 1), 10, 8), m);
    head.position.y = 1.58 * (scale || 1);
    group.add(head);
  }

  // eyes: two dots that hang in the dark long before the body resolves
  const eyeMat = new THREE.MeshBasicMaterial({ color: 0xff3020 });
  const s0 = scale || 1;
  for (const s of [-1, 1]) {
    const eye = new THREE.Mesh(new THREE.SphereGeometry(0.026 * s0, 6, 5), eyeMat);
    eye.position.set(s * 0.058 * s0, 1.70 * s0, -0.13 * s0);
    group.add(eye);
  }
  out.eyeMat = eyeMat;
  return out;
}

function playClip(ch, name, fade) {
  if (!ch.mixer) return;
  if (ch.current === name) return;
  const next = ch.actions[name];
  if (!next) return;
  const prev = ch.current ? ch.actions[ch.current] : null;
  next.reset().setEffectiveWeight(1).fadeIn(fade == null ? 0.22 : fade).play();
  if (prev) prev.fadeOut(fade == null ? 0.22 : fade);
  ch.current = name;
}

// ------------------------------------------------------------ particles
let bloodPool = [], sparkPool = [], _decalGeo = null, _decalMat = null;

function initFxPools() {
  const g = new THREE.SphereGeometry(0.06, 5, 4);
  for (let i = 0; i < 90; i++) {
    const m = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: 0x7a0d12 }));
    m.visible = false;
    GFX.scene.add(m);
    bloodPool.push({ mesh: m, life: 0, vx: 0, vy: 0, vz: 0 });
  }
  const sg = new THREE.SphereGeometry(0.035, 4, 3);
  for (let i = 0; i < 40; i++) {
    const m = new THREE.Mesh(sg, new THREE.MeshBasicMaterial({ color: 0xffc070 }));
    m.visible = false;
    GFX.scene.add(m);
    sparkPool.push({ mesh: m, life: 0, vx: 0, vy: 0, vz: 0 });
  }
  _decalGeo = new THREE.CircleGeometry(0.3, 8);
  _decalMat = new THREE.MeshBasicMaterial({ color: 0x4a0a0e, transparent: true, opacity: 0.75, depthWrite: false });
}

function burst(pool, x, y, z, n, spread, up, life) {
  let spawned = 0;
  for (const p of pool) {
    if (spawned >= n) break;
    if (p.life > 0) continue;
    p.life = life * rndRange(0.7, 1.2);
    p.mesh.position.set(x, y, z);
    p.mesh.visible = true;
    p.vx = rndRange(-spread, spread);
    p.vy = up * rndRange(0.4, 1.3);
    p.vz = rndRange(-spread, spread);
    spawned++;
  }
}

function spawnBlood(x, y, z, dirX, dirZ, big) {
  burst(bloodPool, x, y, z, big ? 16 : 8, 1.8, 2.4, 0.75);
  // bias the spray away from the shooter
  for (const p of bloodPool) {
    if (p.life > 0.6) { p.vx += dirX * 2.2; p.vz += dirZ * 2.2; }
  }
}
function spawnSparks(x, y, z) { burst(sparkPool, x, y, z, 6, 1.4, 1.6, 0.32); }

function spawnDecal(x, z) {
  if (!GFX.zoneGroup) return;
  const m = new THREE.Mesh(_decalGeo, _decalMat);
  m.rotation.x = -Math.PI / 2;
  m.rotation.z = rnd() * TAU;
  m.scale.setScalar(rndRange(0.7, 1.5));
  m.position.set(x, 0.02, z);
  GFX.zoneGroup.add(m);
  GFX.decals.push(m);
  while (GFX.decals.length > TUNE.bloodDecals) {
    const old = GFX.decals.shift();
    if (old.parent) old.parent.remove(old);
  }
}

function updateParticles(dt) {
  for (const pool of [bloodPool, sparkPool]) {
    for (const p of pool) {
      if (p.life <= 0) continue;
      p.life -= dt;
      if (p.life <= 0) { p.mesh.visible = false; continue; }
      p.vy -= 9.8 * dt;
      p.mesh.position.x += p.vx * dt;
      p.mesh.position.y += p.vy * dt;
      p.mesh.position.z += p.vz * dt;
      if (p.mesh.position.y < 0.03) {
        if (pool === bloodPool && p.life > 0.05) spawnDecal(p.mesh.position.x, p.mesh.position.z);
        p.life = 0; p.mesh.visible = false;
      }
    }
  }
}

// --------------------------------------------------------------- snow
function makeSnow() {
  const n = 620;
  const geo = new THREE.BufferGeometry();
  const pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    pos[i * 3] = rndRange(-26, 26);
    pos[i * 3 + 1] = rndRange(0, 22);
    pos[i * 3 + 2] = rndRange(-26, 26);
  }
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  const sprite = texCanvas(32, (g, s) => {
    const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    grd.addColorStop(0, 'rgba(255,255,255,1)');
    grd.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grd; g.fillRect(0, 0, s, s);
  });
  const m = new THREE.PointsMaterial({ size: 0.13, map: sprite, transparent: true,
    opacity: 0.75, depthWrite: false, sizeAttenuation: true });
  const pts = new THREE.Points(geo, m);
  pts.frustumCulled = false;
  return pts;
}

function updateSnow(dt, px, pz, t) {
  if (!GFX.snow || !GFX.snow.visible) return;
  const arr = GFX.snow.geometry.attributes.position.array;
  for (let i = 0; i < arr.length; i += 3) {
    arr[i + 1] -= (1.4 + (i % 7) * 0.12) * dt;
    arr[i] += Math.sin(t * 0.6 + i) * 0.32 * dt;
    if (arr[i + 1] < 0) {
      arr[i + 1] = 22;
      arr[i] = px + rndRange(-26, 26);
      arr[i + 2] = pz + rndRange(-26, 26);
    }
  }
  GFX.snow.geometry.attributes.position.needsUpdate = true;
}

// ------------------------------------------------------------- camera fx
function addShake(amount) { GFX.shake = Math.min(1.4, GFX.shake + amount); }

function updateTorches(zone, dt, t) {
  if (!zone || !zone.torches) return;
  for (const tr of zone.torches) {
    const f = 0.78 + Math.sin(t * 11 + tr.phase) * 0.11 + Math.sin(t * 23.7 + tr.phase * 2) * 0.07;
    tr.light.intensity = tr.base * f;
    if (tr.flame && tr.flame.scale) {
      const s = 0.9 + f * 0.22;
      tr.flame.scale.set(s, s + Math.sin(t * 17 + tr.phase) * 0.12, s);
    }
  }
}
