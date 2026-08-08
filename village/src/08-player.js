'use strict';
// ---------------------------------------------------------------------
// The player: movement with weight, AABB collision, stamina, guarding,
// and the guns. Shots are hitscan rays tested against enemy capsules and
// occluded by the same boxes that stop your feet.
// ---------------------------------------------------------------------

function makePlayer() {
  return {
    x: 0, z: 0, yaw: 0, pitch: 0, vx: 0, vz: 0,
    hp: TUNE.hpMax, hpMax: TUNE.hpMax,
    stamina: TUNE.staminaMax, staminaCd: 0,
    equipped: 'revolver',
    owned: { knife: true, revolver: true, shotgun: false },
    mag: { revolver: 7, shotgun: 0 },
    upg: { revolver: [0, 0, 0], shotgun: [0, 0, 0] },
    fireCd: 0, reloadT: 0, reloadTotal: 0,
    aim: 0, guard: false, guardT: 0,
    invuln: 0, hurtFlash: 0, hitMark: 0,
    bobT: 0, stepAcc: 0,
    recoil: 0, recoilV: 0, swayX: 0, swayY: 0,
    dead: false, deathT: 0,
  };
}

// Weapon stat with merchant upgrades folded in.
function wstat(wid, stat) {
  const base = WEAPONS[wid][stat];
  const ladders = UPGRADES[wid];
  if (!ladders) return base;
  let v = base;
  const levels = G.player.upg[wid] || [];
  ladders.forEach((up, i) => {
    if (up.stat !== stat) return;
    const lvl = levels[i] || 0;
    for (let k = 0; k < lvl; k++) {
      if (up.mul != null) v *= up.mul;
      if (up.add != null) v += up.add;
    }
  });
  return stat === 'mag' ? Math.round(v) : v;
}

// ------------------------------------------------------------ viewmodel
function buildViewmodels() {
  const models = {};
  const gunMat = new THREE.MeshLambertMaterial({ color: 0x2e3238, emissive: 0x0a0c10 });
  const woodMat = new THREE.MeshLambertMaterial({ color: 0x4b3524, emissive: 0x0a0604 });
  const steel = new THREE.MeshLambertMaterial({ color: 0x8a9099, emissive: 0x101418 });

  // revolver
  {
    const g = new THREE.Group();
    const body = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.09, 0.2), gunMat);
    body.position.set(0, 0, -0.05); g.add(body);
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.017, 0.017, 0.26, 8), gunMat);
    barrel.rotation.x = Math.PI / 2; barrel.position.set(0, 0.022, -0.22); g.add(barrel);
    const cyl = new THREE.Mesh(new THREE.CylinderGeometry(0.038, 0.038, 0.07, 8), steel);
    cyl.rotation.x = Math.PI / 2; cyl.position.set(0, 0.005, -0.08); g.add(cyl);
    const grip = new THREE.Mesh(new THREE.BoxGeometry(0.045, 0.13, 0.06), woodMat);
    grip.position.set(0, -0.09, 0.02); grip.rotation.x = -0.28; g.add(grip);
    models.revolver = g;
  }
  // sawn-off
  {
    const g = new THREE.Group();
    for (const s of [-1, 1]) {
      const b = new THREE.Mesh(new THREE.CylinderGeometry(0.026, 0.026, 0.42, 8), gunMat);
      b.rotation.x = Math.PI / 2; b.position.set(s * 0.028, 0.02, -0.2); g.add(b);
    }
    const rec = new THREE.Mesh(new THREE.BoxGeometry(0.085, 0.085, 0.16), steel);
    rec.position.set(0, 0.005, 0.02); g.add(rec);
    const stock = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.1, 0.16), woodMat);
    stock.position.set(0, -0.05, 0.12); stock.rotation.x = -0.2; g.add(stock);
    models.shotgun = g;
  }
  // knife
  {
    const g = new THREE.Group();
    const blade = new THREE.Mesh(new THREE.BoxGeometry(0.022, 0.012, 0.26), steel);
    blade.position.set(0, 0, -0.14); g.add(blade);
    const hilt = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.03, 0.1), woodMat);
    hilt.position.set(0, 0, 0.02); g.add(hilt);
    models.knife = g;
  }

  const holder = new THREE.Group();
  // far enough out that a 30 cm revolver reads as a revolver and not as a
  // wall of grey polygons across the lower right of the screen
  holder.position.set(0.2, -0.19, -0.55);
  holder.scale.setScalar(0.9);
  for (const k in models) { models[k].visible = false; holder.add(models[k]); }
  GFX.camera.add(holder);
  return { holder, models };
}

function equipWeapon(id) {
  const P = G.player;
  if (!P.owned[id] || P.equipped === id) return;
  P.equipped = id;
  P.reloadT = 0;
  P.fireCd = Math.max(P.fireCd, 0.25);
  for (const k in G.vm.models) G.vm.models[k].visible = (k === id);
  SFX.play('reload');
  updateHUD();
}

// --------------------------------------------------------------- combat
function ammoInBag(wid) {
  const def = WEAPONS[wid];
  return def.ammo ? countOf(G.inv, def.ammo) : 0;
}

function startReload() {
  const P = G.player, wid = P.equipped, def = WEAPONS[wid];
  if (def.kind !== 'gun' || P.reloadT > 0) return;
  const cap = wstat(wid, 'mag');
  if (P.mag[wid] >= cap) return;
  if (ammoInBag(wid) <= 0) { SFX.play('dry'); toast('Нет патронов', true); return; }
  P.reloadTotal = wstat(wid, 'reload');
  P.reloadT = P.reloadTotal;
  SFX.play('reload');
}

function finishReload() {
  const P = G.player, wid = P.equipped, def = WEAPONS[wid];
  const cap = wstat(wid, 'mag');
  const need = cap - P.mag[wid];
  const got = invConsume(G.inv, def.ammo, need);
  P.mag[wid] += got;
  updateHUD();
}

// One hitscan ray. Returns the enemy it hit, if any.
function traceShot(ox, oy, oz, dx, dy, dz, range) {
  let wallT = range;
  for (const b of G.zone.colliders) {
    const t = rayBox(ox, oy, oz, dx, dy, dz, b);
    if (t < wallT) wallT = t;
  }
  let best = null, bestT = wallT, bestHead = false;
  for (const e of G.enemies) {
    if (!e.alive) continue;
    const hit = rayCapsule(ox, oy, oz, dx, dy, dz, e.x, e.z, e.radius, 0, e.height, e.headY);
    if (hit && hit.t < bestT) { bestT = hit.t; best = e; bestHead = hit.head; }
  }
  return { enemy: best, t: bestT, head: bestHead, wallT };
}

function fireWeapon() {
  const P = G.player, wid = P.equipped, def = WEAPONS[wid];

  if (def.kind === 'melee') {
    P.fireCd = def.rate;
    SFX.play('knife');
    swingMelee(def);
    kickView(0.02, 0.04);
    return;
  }

  if (P.reloadT > 0) return;
  if (P.mag[wid] <= 0) {
    SFX.play('dry');
    P.fireCd = 0.25;
    if (ammoInBag(wid) > 0) startReload();
    return;
  }

  P.mag[wid]--;
  P.fireCd = def.rate;
  SFX.play(def.sfx);
  GFX.muzzle.intensity = 3.2;
  addShake(def.shake * 0.35);
  kickView(def.recoil, def.kick);

  const cam = GFX.camera;
  const dir = new THREE.Vector3();
  cam.getWorldDirection(dir);
  const origin = new THREE.Vector3();
  cam.getWorldPosition(origin);

  const spread = lerp(def.spread, def.adsSpread, P.aim);
  const dmg = wstat(wid, 'dmg');
  const hitEnemies = new Set();

  for (let i = 0; i < def.pellets; i++) {
    // random cone around the aim direction
    const a = rnd() * TAU, r = Math.sqrt(rnd()) * spread * (def.pellets > 1 ? 1 : 1);
    const ox = Math.cos(a) * r, oy = Math.sin(a) * r;
    const d = dir.clone();
    const right = new THREE.Vector3().crossVectors(d, new THREE.Vector3(0, 1, 0)).normalize();
    const up = new THREE.Vector3().crossVectors(right, d).normalize();
    d.addScaledVector(right, ox).addScaledVector(up, oy).normalize();

    const hit = traceShot(origin.x, origin.y, origin.z, d.x, d.y, d.z, 70);
    const hx = origin.x + d.x * hit.t, hy = origin.y + d.y * hit.t, hz = origin.z + d.z * hit.t;

    if (hit.enemy) {
      const mul = hit.head ? def.headMul : 1;
      damageEnemy(hit.enemy, dmg * mul, {
        head: hit.head, stagger: def.stagger * (hit.head ? 1.8 : 1),
        dirX: d.x, dirZ: d.z, x: hx, y: hy, z: hz,
      });
      hitEnemies.add(hit.enemy);
      P.hitMark = 0.14;
    } else {
      spawnSparks(hx, hy, hz);
      if (i === 0) SFX.play('ricochet', 2);
    }
  }
  makeNoise(P.x, P.z, 26);
  updateHUD();
}

function swingMelee(def) {
  const P = G.player;
  let hitAny = false;
  for (const e of G.enemies) {
    if (!e.alive) continue;
    const d = dist(P.x, P.z, e.x, e.z);
    if (d > def.range + e.radius) continue;
    const ang = Math.abs(normalizeAngle(yawToward(e.x - P.x, e.z - P.z) - P.yaw));
    if (ang > def.arc) continue;
    const dx = (e.x - P.x) / (d || 1), dz = (e.z - P.z) / (d || 1);
    damageEnemy(e, def.dmg, { stagger: def.stagger, dirX: dx, dirZ: dz, x: e.x, y: 1.2, z: e.z });
    hitAny = true;
  }
  if (hitAny) { G.player.hitMark = 0.14; addShake(0.12); }
  makeNoise(P.x, P.z, 7);
}

function kickView(pitchKick, backKick) {
  const P = G.player;
  P.recoilV += pitchKick * 22;
  P.vmKick = (P.vmKick || 0) + backKick;
}

// ------------------------------------------------------------ throwables
function throwHolyWater() {
  const P = G.player;
  if (countOf(G.inv, 'holywater') <= 0) { SFX.play('deny'); toast('Святой воды нет', true); return; }
  invConsume(G.inv, 'holywater', 1);
  const cam = GFX.camera;
  const dir = new THREE.Vector3();
  cam.getWorldDirection(dir);
  const o = new THREE.Vector3();
  cam.getWorldPosition(o);

  const mesh = new THREE.Mesh(new THREE.SphereGeometry(0.1, 8, 6),
    new THREE.MeshBasicMaterial({ color: 0x9fd8ff }));
  mesh.position.copy(o);
  GFX.scene.add(mesh);
  const light = new THREE.PointLight(0x9fd8ff, 0.8, 5, 2);
  mesh.add(light);
  G.projectiles.push({
    kind: 'holy', mesh, x: o.x, y: o.y, z: o.z,
    vx: dir.x * 15, vy: dir.y * 15 + 2.5, vz: dir.z * 15, life: 5,
  });
  P.fireCd = Math.max(P.fireCd, 0.4);
  updateHUD();
}

function updateProjectiles(dt) {
  for (let i = G.projectiles.length - 1; i >= 0; i--) {
    const p = G.projectiles[i];
    p.life -= dt;
    p.vy -= 16 * dt;
    p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;

    let boom = p.y <= 0.05 || p.life <= 0;
    if (!boom) {
      for (const b of G.zone.colliders) {
        if (p.x > b.x - b.hw && p.x < b.x + b.hw && p.z > b.z - b.hd && p.z < b.z + b.hd &&
            p.y > b.y0 && p.y < b.y1) { boom = true; break; }
      }
    }
    if (!boom && p.kind === 'holy') {
      for (const e of G.enemies) {
        if (e.alive && dist(p.x, p.z, e.x, e.z) < e.radius + 0.3 && p.y < e.height) { boom = true; break; }
      }
    }
    if (!boom && p.kind === 'shriek') {
      const P = G.player;
      if (dist(p.x, p.z, P.x, P.z) < 0.6 && Math.abs(p.y - 1.2) < 1.1) {
        damagePlayer(p.dmg, p.x, p.z);
        boom = true;
      }
    }

    p.mesh.position.set(p.x, p.y, p.z);
    if (boom) {
      if (p.kind === 'holy') holyBurst(p.x, p.y, p.z);
      else SFX.play('flesh', dist(p.x, p.z, G.player.x, G.player.z));
      GFX.scene.remove(p.mesh);
      G.projectiles.splice(i, 1);
    }
  }
}

function holyBurst(x, y, z) {
  SFX.play('shatter');
  const flash = new THREE.PointLight(0xbfe4ff, 4, 14, 2);
  flash.position.set(x, y + 0.4, z);
  GFX.scene.add(flash);
  G.fxLights.push({ light: flash, life: 0.5, base: 4 });
  for (const e of G.enemies) {
    if (!e.alive) continue;
    const d = dist(x, z, e.x, e.z);
    if (d > 4.2) continue;
    const falloff = 1 - d / 4.2;
    const mul = e.def.holyMul || 1.4;
    damageEnemy(e, ITEMS.holywater.dmg * falloff * mul, {
      stagger: 1.2, dirX: (e.x - x) / (d || 1), dirZ: (e.z - z) / (d || 1),
      x: e.x, y: 1.1, z: e.z, holy: true,
    });
  }
  makeNoise(x, z, 20);
}

// ----------------------------------------------------------- taking hits
function damagePlayer(amount, fromX, fromZ) {
  const P = G.player;
  if (P.dead || P.invuln > 0 || G.mode !== 'playing') return;
  let dmg = amount;

  // guarding costs stamina and does not fully save you
  const facing = fromX == null ? true
    : Math.abs(normalizeAngle(yawToward(fromX - P.x, fromZ - P.z) - P.yaw)) < 1.0;
  if (P.guard && facing && P.stamina > 5) {
    dmg *= (1 - TUNE.guardReduction);
    P.stamina = Math.max(0, P.stamina - TUNE.guardStamina);
    P.staminaCd = TUNE.staminaRegenDelay;
    SFX.play('guard');
    addShake(0.25);
  } else {
    SFX.play('hurt');
    addShake(0.5);
  }

  P.hp = Math.max(0, P.hp - dmg);
  P.invuln = TUNE.iframes;
  P.hurtFlash = 1;
  updateHUD();
  if (P.hp <= 0) killPlayer();
}

function healPlayer(amount) {
  const P = G.player;
  P.hp = Math.min(P.hpMax, P.hp + amount);
  SFX.play('heal');
  updateHUD();
}

function killPlayer() {
  const P = G.player;
  P.dead = true; P.deathT = 0;
  SFX.play('death');
  Input.release();
  setTimeout(() => {
    if (G.player.dead) {
      G.mode = 'dead';
      $('deathSub').textContent = G.lastZoneName ? `${G.lastZoneName} забрала ещё одного` : 'Деревня забрала ещё одного';
      show($('death'), true);
      show($('hud'), false);
    }
  }, 1400);
}

// ------------------------------------------------------------- movement
function moveWithCollision(px, pz, dx, dz, radius) {
  let x = px + dx, z = pz + dz;
  // two passes: resolve, then resolve again for corners
  for (let pass = 0; pass < 2; pass++) {
    for (const b of G.zone.colliders) {
      if (b.y0 > 1.2) continue;             // walk under lintels and low ceilings
      const push = boxPush(b, x, z, radius);
      if (!push) continue;
      x += push.x; z += push.z;
    }
  }
  return { x, z };
}

function updatePlayer(dt) {
  const P = G.player;
  if (P.dead) {
    P.deathT += dt;
    GFX.camera.position.y = lerp(GFX.camera.position.y, 0.35, clamp(dt * 3, 0, 1));
    GFX.camera.rotation.z = lerp(GFX.camera.rotation.z, 0.7, clamp(dt * 2.4, 0, 1));
    return;
  }

  // ---- look
  const sens = TUNE.lookSens * lerp(1, TUNE.aimSensMul, P.aim);
  const look = Input.takeLook(dt, sens);
  P.yaw = normalizeAngle(P.yaw + look.yaw);
  P.pitch = clamp(P.pitch + look.pitch, -TUNE.pitchLimit, TUNE.pitchLimit);

  // recoil climbs fast and settles slowly, like a real muzzle rising
  P.recoilV -= P.recoil * 42 * dt;
  P.recoilV *= Math.exp(-9 * dt);
  P.recoil += P.recoilV * dt;
  P.recoil *= Math.exp(-3.2 * dt);

  // ---- input flags
  const aiming = Input.mouseHeld(2);
  P.aim = clamp(P.aim + (aiming ? dt * 7 : -dt * 9), 0, 1);
  P.guard = Input.held('Space') && !aiming && P.stamina > 3;

  // ---- movement
  let ix = 0, iz = 0;
  if (Input.held('KeyW')) iz -= 1;
  if (Input.held('KeyS')) iz += 1;
  if (Input.held('KeyA')) ix -= 1;
  if (Input.held('KeyD')) ix += 1;
  const mag = Math.hypot(ix, iz);
  if (mag > 0) { ix /= mag; iz /= mag; }

  const wantSprint = (Input.held('ShiftLeft') || Input.held('ShiftRight')) && iz < 0 && P.stamina > 1 && !aiming && !P.guard;
  let speed = TUNE.walkSpeed;
  if (aiming) speed = TUNE.aimSpeed;
  else if (P.guard) speed = TUNE.walkSpeed * 0.55;
  else if (wantSprint) speed = TUNE.sprintSpeed;
  if (iz > 0) speed *= TUNE.backMul;
  if (P.hp < P.hpMax * 0.3) speed *= 0.88;     // wounded men do not run well

  if (wantSprint && mag > 0) {
    P.stamina = Math.max(0, P.stamina - TUNE.staminaDrain * dt);
    P.staminaCd = TUNE.staminaRegenDelay;
  } else {
    P.staminaCd = Math.max(0, P.staminaCd - dt);
    if (P.staminaCd <= 0) P.stamina = Math.min(TUNE.staminaMax, P.stamina + TUNE.staminaRegen * dt);
  }

  // world-space desired velocity
  const fx = fwdX(P.yaw), fz = fwdZ(P.yaw), rx = rightX(P.yaw), rz = rightZ(P.yaw);
  const tvx = (fx * -iz + rx * ix) * speed;
  const tvz = (fz * -iz + rz * ix) * speed;

  const a = (mag > 0 ? TUNE.accel : TUNE.friction) * dt;
  P.vx += clamp(tvx - P.vx, -a * 2, a * 2);
  P.vz += clamp(tvz - P.vz, -a * 2, a * 2);
  if (mag === 0) { P.vx *= Math.exp(-TUNE.friction * dt); P.vz *= Math.exp(-TUNE.friction * dt); }

  const moved = moveWithCollision(P.x, P.z, P.vx * dt, P.vz * dt, TUNE.playerRadius);
  P.x = moved.x; P.z = moved.z;

  // ---- footsteps double as noise the dead can hear
  const spd = Math.hypot(P.vx, P.vz);
  P.stepAcc += spd * dt;
  const stepEvery = wantSprint ? 1.55 : 2.0;
  if (P.stepAcc > stepEvery) {
    P.stepAcc = 0;
    SFX.play('step', 0);
    makeNoise(P.x, P.z, wantSprint ? 13 : 6.5);
  }

  // ---- weapon timers
  P.fireCd = Math.max(0, P.fireCd - dt);
  P.invuln = Math.max(0, P.invuln - dt);
  P.hitMark = Math.max(0, P.hitMark - dt);
  P.hurtFlash = Math.max(0, P.hurtFlash - dt * 1.6);
  if (P.reloadT > 0) {
    P.reloadT -= dt;
    if (P.reloadT <= 0) { P.reloadT = 0; finishReload(); }
  }

  const def = WEAPONS[P.equipped];
  const wantFire = Input.mouseHeld(0);
  const canAuto = false;                       // everything here is manual action
  if (P.fireCd <= 0 && wantFire && (canAuto ? true : Input.mousePressed(0))) fireWeapon();
  if (Input.pressed('KeyR')) startReload();
  if (Input.pressed('Digit1')) equipWeapon('knife');
  if (Input.pressed('Digit2')) equipWeapon('revolver');
  if (Input.pressed('Digit3')) equipWeapon('shotgun');
  if (Input.pressed('KeyQ')) throwHolyWater();
  if (Input.pressed('KeyH')) useBrew();

  // ---- camera placement
  P.bobT += spd * dt * 2.1;
  const bobAmp = lerp(0.035, 0.008, P.aim) * clamp(spd / TUNE.walkSpeed, 0, 1.6);
  const bobY = Math.sin(P.bobT * 2) * bobAmp;
  const bobX = Math.cos(P.bobT) * bobAmp * 0.6;

  GFX.shake = Math.max(0, GFX.shake - dt * 2.6);
  GFX.shakeT += dt * 42;
  const sh = GFX.shake * GFX.shake * 0.05;

  GFX.rig.position.set(P.x, 0, P.z);
  GFX.rig.rotation.y = P.yaw + Math.sin(GFX.shakeT * 0.9) * sh * 0.5;
  GFX.camera.position.set(bobX, TUNE.eyeHeight + bobY + Math.sin(GFX.shakeT) * sh, 0);
  GFX.camera.rotation.x = clamp(P.pitch + P.recoil, -TUNE.pitchLimit, TUNE.pitchLimit) + Math.cos(GFX.shakeT * 1.3) * sh;
  GFX.camera.rotation.z = lerp(GFX.camera.rotation.z, -bobX * 0.5, clamp(dt * 8, 0, 1));

  GFX.camera.fov = lerp(74, 60, P.aim);
  GFX.camera.updateProjectionMatrix();
  GFX.muzzle.intensity = Math.max(0, GFX.muzzle.intensity - dt * 26);
  GFX.lantern.intensity = 1.35 + Math.sin(G.time * 8.3) * 0.09 + Math.sin(G.time * 3.1) * 0.05;

  updateViewmodel(dt, spd);
}

function updateViewmodel(dt, spd) {
  const P = G.player;
  const h = G.vm.holder;
  P.vmKick = (P.vmKick || 0) * Math.exp(-11 * dt);

  const aimX = lerp(0.2, 0.0, P.aim);
  const aimY = lerp(-0.19, -0.075, P.aim);
  const aimZ = lerp(-0.55, -0.44, P.aim);

  const sway = Math.sin(P.bobT) * 0.012 * (1 - P.aim * 0.8);
  const swayY = Math.sin(P.bobT * 2) * 0.01 * (1 - P.aim * 0.8);

  const reloadDip = P.reloadT > 0 ? Math.sin((1 - P.reloadT / Math.max(0.01, P.reloadTotal)) * Math.PI) * 0.16 : 0;
  const guardDip = P.guard ? 0.06 : 0;

  h.position.x = lerp(h.position.x, aimX + sway, clamp(dt * 12, 0, 1));
  h.position.y = lerp(h.position.y, aimY + swayY - reloadDip - guardDip, clamp(dt * 12, 0, 1));
  h.position.z = lerp(h.position.z, aimZ + P.vmKick * 0.5, clamp(dt * 16, 0, 1));
  h.rotation.x = lerp(h.rotation.x, -P.recoil * 1.4 - reloadDip * 2.4, clamp(dt * 14, 0, 1));
  // held at an angle from the hip so you read the gun's side, squared up on aim
  h.rotation.y = lerp(h.rotation.y, lerp(-0.15, 0, P.aim), clamp(dt * 12, 0, 1));
  h.rotation.z = lerp(h.rotation.z, P.guard ? 0.5 : 0, clamp(dt * 12, 0, 1));
}

function useBrew() {
  if (countOf(G.inv, 'brew') <= 0) { SFX.play('deny'); toast('Отвара нет', true); return; }
  if (G.player.hp >= G.player.hpMax) { toast('Раны и так затянулись'); return; }
  invConsume(G.inv, 'brew', 1);
  healPlayer(ITEMS.brew.heal);
  toast('Выпит отвар');
}
