'use strict';
// ---------------------------------------------------------------------
// Small shared helpers: math, RNG, DOM.
// ---------------------------------------------------------------------

const TAU = Math.PI * 2;
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const lerp = (a, b, t) => a + (b - a) * t;
const dist2 = (ax, az, bx, bz) => { const dx = ax - bx, dz = az - bz; return dx * dx + dz * dz; };
const dist = (ax, az, bx, bz) => Math.sqrt(dist2(ax, az, bx, bz));

// three.js convention: rotation.y = yaw, forward = (-sin yaw, 0, -cos yaw)
const yawToward = (dx, dz) => Math.atan2(-dx, -dz);
const fwdX = yaw => -Math.sin(yaw), fwdZ = yaw => -Math.cos(yaw);
const rightX = yaw => Math.cos(yaw), rightZ = yaw => -Math.sin(yaw);

function normalizeAngle(a) {
  while (a > Math.PI) a -= TAU;
  while (a < -Math.PI) a += TAU;
  return a;
}
function approachAngle(cur, target, maxStep) {
  const d = normalizeAngle(target - cur);
  return cur + clamp(d, -maxStep, maxStep);
}

// Deterministic-ish RNG so a seeded layout can be reproduced when debugging.
let _seed = 1337;
function srand(s) { _seed = s >>> 0 || 1; }
function rnd() {
  _seed ^= _seed << 13; _seed >>>= 0;
  _seed ^= _seed >> 17;
  _seed ^= _seed << 5; _seed >>>= 0;
  return _seed / 4294967296;
}
const rndRange = (a, b) => a + rnd() * (b - a);
const rndInt = (a, b) => Math.floor(a + rnd() * (b - a + 1));
const pick = arr => arr[Math.floor(rnd() * arr.length) % arr.length];

const $ = id => document.getElementById(id);
function show(el, on) { if (el) el.classList.toggle('hidden', !on); }
function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
}

function plural(n, one, few, many) {
  const m10 = n % 10, m100 = n % 100;
  if (m10 === 1 && m100 !== 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

// ---------------------------------------------------------------- toasts
const TOAST_MS = 3200;
function toast(text, bad) {
  const host = $('toasts');
  if (!host) return;
  const n = el('div', 'toast' + (bad ? ' bad' : ''), text);
  host.appendChild(n);
  setTimeout(() => {
    n.style.transition = 'opacity .4s ease';
    n.style.opacity = '0';
    setTimeout(() => n.remove(), 420);
  }, TOAST_MS);
  while (host.children.length > 5) host.firstChild.remove();
}

// ------------------------------------------------------------ geometry
// Axis-aligned box collider. Everything solid in the world is one of these,
// which keeps movement, line-of-sight and bullet occlusion on one cheap path.
function box(x, z, hw, hd, y0, y1) {
  return { x, z, hw, hd, y0: y0 == null ? 0 : y0, y1: y1 == null ? 4 : y1 };
}

// Closest point on a box to (px, pz), used for circle-vs-box resolution.
function boxPush(b, px, pz, radius) {
  const dx = px - b.x, dz = pz - b.z;
  const ox = b.hw + radius - Math.abs(dx);
  const oz = b.hd + radius - Math.abs(dz);
  if (ox <= 0 || oz <= 0) return null;
  // push out along the shallower axis — standard AABB depenetration
  if (ox < oz) return { x: Math.sign(dx || 1) * ox, z: 0 };
  return { x: 0, z: Math.sign(dz || 1) * oz };
}

// Ray vs AABB (slab test) in 3D, returns t or Infinity.
function rayBox(ox, oy, oz, dx, dy, dz, b) {
  let tmin = 0, tmax = Infinity;
  const lo = [b.x - b.hw, b.y0, b.z - b.hd];
  const hi = [b.x + b.hw, b.y1, b.z + b.hd];
  const o = [ox, oy, oz], d = [dx, dy, dz];
  for (let i = 0; i < 3; i++) {
    if (Math.abs(d[i]) < 1e-8) {
      if (o[i] < lo[i] || o[i] > hi[i]) return Infinity;
      continue;
    }
    const inv = 1 / d[i];
    let t1 = (lo[i] - o[i]) * inv, t2 = (hi[i] - o[i]) * inv;
    if (t1 > t2) { const t = t1; t1 = t2; t2 = t; }
    if (t1 > tmin) tmin = t1;
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return Infinity;
  }
  return tmin;
}

// Ray vs vertical capsule (enemy body), returns { t, head } or null.
function rayCapsule(ox, oy, oz, dx, dy, dz, cx, cz, r, y0, y1, headY) {
  // Solve in 2D for the infinite cylinder, then clamp against the caps.
  const mx = ox - cx, mz = oz - cz;
  const a = dx * dx + dz * dz;
  if (a < 1e-9) return null;
  const b = 2 * (mx * dx + mz * dz);
  const c = mx * mx + mz * mz - r * r;
  const disc = b * b - 4 * a * c;
  if (disc < 0) return null;
  const sq = Math.sqrt(disc);
  let t = (-b - sq) / (2 * a);
  if (t < 0) t = (-b + sq) / (2 * a);
  if (t < 0) return null;
  const hy = oy + dy * t;
  if (hy < y0 || hy > y1) return null;
  return { t, head: hy >= headY };
}
