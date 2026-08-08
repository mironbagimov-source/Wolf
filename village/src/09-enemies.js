'use strict';
// ---------------------------------------------------------------------
// The dead. One state machine per body: patrol → hear/see → close →
// wind up → swing → recover. They can be staggered out of the windup,
// which is the whole reason to aim at heads instead of chests.
// ---------------------------------------------------------------------

function spawnEnemy(type, x, z, id, opts) {
  const def = type === 'morana' ? MORANA : ENEMIES[type];
  if (!def) return null;
  const o = opts || {};
  const scale = def.scale || 1;
  const ch = makeCharacter(def.tint, scale, def.emissive, def.hunch);
  ch.group.position.set(x, 0, z);
  GFX.zoneGroup.add(ch.group);

  const e = {
    id: id || ('e' + (G.enemySeq++)),
    type, def, ch, group: ch.group,
    x, z, yaw: rnd() * TAU, vx: 0, vz: 0,
    hp: def.hp * (o.hpMul || 1), hpMax: def.hp * (o.hpMul || 1),
    alive: true, state: 'idle', stateT: 0,
    radius: 0.42 * scale, height: 1.85 * scale, headY: 1.42 * scale,
    patrol: o.patrol || null, patrolIdx: 0, waitT: 0,
    targetX: x, targetZ: z,
    awareness: 0, seenT: 0,
    staggerAcc: 0, staggerWindow: 0, staggerT: 0,
    attackT: 0, cooldown: rndRange(0, 0.6),
    rangedCd: rndRange(1.5, 3.5),
    detour: 0, detourT: 0, stuckT: 0,
    growlCd: rndRange(1, 5),
    deathT: 0,
    boss: type === 'morana',
    phase: 1, weak: false, weakT: 0, summonCd: 12,
  };
  if (e.boss) initMorana(e);
  playClip(ch, 'Idle', 0);
  G.enemies.push(e);
  return e;
}

// Line of sight from the enemy's eyes to the player's chest.
function canSee(e, P) {
  const dx = P.x - e.x, dz = P.z - e.z;
  const d = Math.hypot(dx, dz);
  if (d > e.def.sight) return false;
  // behind-the-back blindness, unless you are right on top of them
  const ang = Math.abs(normalizeAngle(yawToward(dx, dz) - e.yaw));
  if (ang > 1.5 && d > 3.5) return false;
  const ox = e.x, oy = e.headY, oz = e.z;
  const nx = dx / d, nz = dz / d;
  const ty = (TUNE.eyeHeight - 0.35) - oy;
  const dirY = ty / d;
  for (const b of G.zone.colliders) {
    const t = rayBox(ox, oy, oz, nx, dirY, nz, b);
    if (t < d - 0.35) return false;
  }
  return true;
}

// Anything loud pulls every nearby corpse toward the sound.
function makeNoise(x, z, radius) {
  for (const e of G.enemies) {
    if (!e.alive || e.boss) continue;
    const d = dist(x, z, e.x, e.z);
    if (d > radius) continue;
    e.awareness = Math.min(1, e.awareness + 0.7);
    e.targetX = x + rndRange(-1.2, 1.2);
    e.targetZ = z + rndRange(-1.2, 1.2);
    if (e.state === 'idle') e.state = 'alert', e.stateT = 0;
  }
}

function damageEnemy(e, amount, info) {
  if (!e.alive) return;
  const i = info || {};
  e.hp -= amount;

  spawnBlood(i.x != null ? i.x : e.x, i.y != null ? i.y : 1.2, i.z != null ? i.z : e.z,
             i.dirX || 0, i.dirZ || 0, !!i.head);
  SFX.play(i.head ? 'head' : 'flesh', dist(e.x, e.z, G.player.x, G.player.z));

  // becoming aware of whoever just shot you
  e.awareness = 1;
  e.targetX = G.player.x; e.targetZ = G.player.z;
  if (e.state === 'idle' || e.state === 'alert') { e.state = 'chase'; e.stateT = 0; }

  if (e.boss) { moranaHit(e, amount, i); }
  else {
    // Stagger is a damage-in-a-window mechanic: burst them down and they drop.
    e.staggerAcc += amount * (i.stagger || 1);
    e.staggerWindow = 1.2;
    if (e.staggerAcc >= e.def.staggerHp && e.state !== 'stagger') {
      e.state = 'stagger';
      e.stateT = 0;
      e.staggerT = i.head ? 1.5 : 1.0;
      e.staggerAcc = 0;
      e.vx = (i.dirX || 0) * 2.4; e.vz = (i.dirZ || 0) * 2.4;
    }
  }

  if (e.hp <= 0) killEnemy(e, i);
}

function killEnemy(e, info) {
  e.alive = false;
  e.state = 'dead';
  e.deathT = 0;
  spawnBlood(e.x, 1.0, e.z, (info && info.dirX) || 0, (info && info.dirZ) || 0, true);
  spawnDecal(e.x, e.z);
  SFX.play('flesh', dist(e.x, e.z, G.player.x, G.player.z));
  if (e.ch.mixer) { for (const k in e.ch.actions) e.ch.actions[k].stop(); }
  if (e.ch.eyeMat) e.ch.eyeMat.color.setHex(0x220404);
  G.killed.add(e.id);
  G.stats.kills++;

  if (e.boss) { onMoranaDead(e); return; }

  // loot
  const money = rndInt(e.def.money[0], e.def.money[1]);
  if (money > 0) { G.money += money; toast(`+${money} ${plural(money, 'талер', 'талера', 'талеров')}`); SFX.play('coin'); }
  for (const [item, chance, count] of e.def.loot) {
    if (rnd() > chance) continue;
    dropLoot(item, count, e.x + rndRange(-0.5, 0.5), e.z + rndRange(-0.5, 0.5));
  }
  updateHUD();
}

let _lootSeq = 0;
function dropLoot(item, count, x, z) {
  const W = { add: m => GFX.zoneGroup.add(m), solid: () => {},
              interactables: G.zone.interactables, pickupMeshes: G.zone.pickupMeshes };
  const mesh = pickupMesh(W, x, z, item, 0.4);
  G.zone.interactables.push({
    id: 'loot' + (_lootSeq++), kind: 'pickup', item, count, x, z, y: 0.4, mesh, dropped: true,
    label: ITEMS[item].name + (count > 1 ? ` ×${count}` : ''),
  });
}

// ------------------------------------------------------------- the loop
function updateEnemies(dt) {
  const P = G.player;
  for (const e of G.enemies) {
    if (!e.alive) { updateCorpse(e, dt); continue; }
    if (e.ch.mixer) e.ch.mixer.update(dt);
    if (e.boss) { updateMorana(e, dt); continue; }

    e.stateT += dt;
    e.cooldown = Math.max(0, e.cooldown - dt);
    e.rangedCd = Math.max(0, e.rangedCd - dt);
    e.staggerWindow = Math.max(0, e.staggerWindow - dt);
    if (e.staggerWindow <= 0) e.staggerAcc *= Math.exp(-2.5 * dt);
    e.growlCd -= dt;

    const d = dist(P.x, P.z, e.x, e.z);
    const sees = !P.dead && canSee(e, P);
    if (sees) {
      e.awareness = Math.min(1, e.awareness + dt * 2.4);
      e.targetX = P.x; e.targetZ = P.z; e.seenT = 0;
    } else {
      e.seenT += dt;
      e.awareness = Math.max(0, e.awareness - dt * 0.12);
    }
    // the sound of you breathing nearby is enough
    if (d < e.def.hearing * 0.35 && !P.dead) e.awareness = Math.min(1, e.awareness + dt * 0.8);

    if (e.growlCd <= 0 && e.awareness > 0.2 && d < 26) {
      SFX.play(e.def.growl, d);
      e.growlCd = rndRange(2.6, 7) * (e.awareness > 0.8 ? 0.6 : 1);
    }

    switch (e.state) {
      case 'idle': aiIdle(e, dt); break;
      case 'alert': aiAlert(e, dt, d); break;
      case 'chase': aiChase(e, dt, d, sees); break;
      case 'attack': aiAttack(e, dt, d); break;
      case 'stagger': aiStagger(e, dt); break;
    }

    applyEnemyMotion(e, dt);
    faceMotion(e, dt);
    e.group.position.set(e.x, 0, e.z);
    e.group.rotation.y = e.yaw;
  }

  // pull apart bodies that ended up inside each other
  for (let i = 0; i < G.enemies.length; i++) {
    const a = G.enemies[i];
    if (!a.alive) continue;
    for (let j = i + 1; j < G.enemies.length; j++) {
      const b = G.enemies[j];
      if (!b.alive) continue;
      const dx = b.x - a.x, dz = b.z - a.z;
      const dd = Math.hypot(dx, dz), min = a.radius + b.radius;
      if (dd > min || dd < 0.001) continue;
      const push = (min - dd) * 0.5;
      const nx = dx / dd, nz = dz / dd;
      if (!a.boss) { a.x -= nx * push; a.z -= nz * push; }
      if (!b.boss) { b.x += nx * push; b.z += nz * push; }
    }
  }
}

function aiIdle(e, dt) {
  if (e.awareness > 0.45) { e.state = 'alert'; e.stateT = 0; return; }
  if (e.patrol && e.patrol.length) {
    const p = e.patrol[e.patrolIdx];
    e.targetX = p[0]; e.targetZ = p[1];
    if (dist(e.x, e.z, p[0], p[1]) < 1.2) {
      e.waitT -= dt;
      if (e.waitT <= 0) { e.patrolIdx = (e.patrolIdx + 1) % e.patrol.length; e.waitT = rndRange(1.5, 4); }
      steerTo(e, e.x, e.z, 0);
      playClip(e.ch, 'Idle');
      return;
    }
  } else {
    steerTo(e, e.x, e.z, 0);
    playClip(e.ch, 'Idle');
    return;
  }
  steerTo(e, e.targetX, e.targetZ, e.def.speed * 0.55);
  playClip(e.ch, 'Walk');
}

function aiAlert(e, dt, d) {
  playClip(e.ch, 'Walk');
  steerTo(e, e.targetX, e.targetZ, e.def.speed);
  if (e.awareness > 0.8) { e.state = 'chase'; e.stateT = 0; return; }
  if (dist(e.x, e.z, e.targetX, e.targetZ) < 1.0 && e.stateT > 2.5) {
    if (e.awareness < 0.3) { e.state = 'idle'; e.stateT = 0; }
    else e.stateT = 0, e.targetX = e.x + rndRange(-5, 5), e.targetZ = e.z + rndRange(-5, 5);
  }
}

function aiChase(e, dt, d, sees) {
  playClip(e.ch, 'Run');
  steerTo(e, e.targetX, e.targetZ, e.def.chaseSpeed);

  if (e.def.ranged && e.rangedCd <= 0 && sees && d > 5 && d < 20) {
    shriek(e);
    e.rangedCd = e.def.rangedCooldown;
  }
  if (d < e.def.attackRange && e.cooldown <= 0) {
    e.state = 'attack'; e.stateT = 0; e.attackT = e.def.attackWindup; e.swung = false;
    if (e.def.lunge) { e.vx = fwdX(e.yaw) * e.def.lunge; e.vz = fwdZ(e.yaw) * e.def.lunge; }
    return;
  }
  // lost the trail: sniff around, then give up
  if (!sees && e.seenT > 6 && dist(e.x, e.z, e.targetX, e.targetZ) < 1.5) {
    e.state = 'alert'; e.stateT = 0; e.awareness = 0.5;
  }
}

function aiAttack(e, dt, d) {
  playClip(e.ch, 'Idle', 0.1);
  e.attackT -= dt;
  const face = yawToward(G.player.x - e.x, G.player.z - e.z);
  e.yaw = approachAngle(e.yaw, face, dt * 3.2);
  steerTo(e, e.x, e.z, 0);

  if (!e.swung && e.attackT <= 0) {
    e.swung = true;
    if (d < e.def.attackRange + 0.45) {
      damagePlayer(e.def.dmg, e.x, e.z);
      addShake(0.35);
    } else SFX.play('knife');
    e.stateT = 0;
  }
  if (e.swung && e.stateT > e.def.attackRecover) {
    e.state = 'chase'; e.stateT = 0;
    e.cooldown = rndRange(0.5, 1.3);
  }
}

function aiStagger(e, dt) {
  playClip(e.ch, 'Idle', 0.08);
  e.staggerT -= dt;
  e.vx *= Math.exp(-4 * dt); e.vz *= Math.exp(-4 * dt);
  // knocked-down bodies lean back and get up slowly — the window to run or reload
  const lean = clamp(e.staggerT * 1.1, 0, 1.1);
  e.group.rotation.x = -lean * 0.5;
  if (e.staggerT <= 0) {
    e.group.rotation.x = 0;
    e.state = 'chase'; e.stateT = 0;
    e.cooldown = 0.5;
  }
}

function shriek(e) {
  SFX.play('screech', dist(e.x, e.z, G.player.x, G.player.z));
  const P = G.player;
  const sx = e.x, sy = e.headY, sz = e.z;
  const dx = P.x - sx, dy = (TUNE.eyeHeight - 0.2) - sy, dz = P.z - sz;
  const len = Math.hypot(dx, dy, dz) || 1;
  const speed = 13;
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(0.16, 8, 6),
    new THREE.MeshBasicMaterial({ color: 0xb060d0 }));
  mesh.position.set(sx, sy, sz);
  GFX.scene.add(mesh);
  G.projectiles.push({
    kind: 'shriek', mesh, x: sx, y: sy, z: sz,
    vx: dx / len * speed, vy: dy / len * speed + 1.6, vz: dz / len * speed,
    life: 3.5, dmg: e.def.rangedDmg,
  });
}

// Steering with a crude detour when a wall eats the movement — enough to get
// around a house without a navmesh.
function steerTo(e, tx, tz, speed) {
  if (speed <= 0) { e.desiredX = 0; e.desiredZ = 0; return; }
  let dx = tx - e.x, dz = tz - e.z;
  const d = Math.hypot(dx, dz);
  if (d < 0.05) { e.desiredX = 0; e.desiredZ = 0; return; }
  dx /= d; dz /= d;
  if (e.detourT > 0) {
    const a = e.detour * 1.05;
    const cx = dx * Math.cos(a) - dz * Math.sin(a);
    const cz = dx * Math.sin(a) + dz * Math.cos(a);
    dx = cx; dz = cz;
  }
  e.desiredX = dx * speed;
  e.desiredZ = dz * speed;
}

function applyEnemyMotion(e, dt) {
  const targetX = (e.desiredX || 0), targetZ = (e.desiredZ || 0);
  const a = 14 * dt;
  e.vx += clamp(targetX - e.vx, -a, a);
  e.vz += clamp(targetZ - e.vz, -a, a);

  const wantX = e.vx * dt, wantZ = e.vz * dt;
  const before = { x: e.x, z: e.z };
  const moved = moveWithCollision(e.x, e.z, wantX, wantZ, e.radius);
  e.x = moved.x; e.z = moved.z;

  const got = dist(before.x, before.z, e.x, e.z);
  const want = Math.hypot(wantX, wantZ);
  e.detourT = Math.max(0, e.detourT - dt);
  if (want > 0.004 && got < want * 0.45) {
    e.stuckT += dt;
    if (e.stuckT > 0.18 && e.detourT <= 0) {
      e.detour = rnd() < 0.5 ? -1 : 1;
      e.detourT = rndRange(0.5, 1.1);
      e.stuckT = 0;
    }
  } else e.stuckT = Math.max(0, e.stuckT - dt);
}

function faceMotion(e, dt) {
  const spd = Math.hypot(e.vx, e.vz);
  if (spd < 0.15) return;
  const target = yawToward(e.vx, e.vz);
  e.yaw = approachAngle(e.yaw, target, dt * (e.state === 'chase' ? 6 : 3));
}

function updateCorpse(e, dt) {
  if (e.deathT > 2.6) return;
  e.deathT += dt;
  const t = clamp(e.deathT / 0.85, 0, 1);
  e.group.rotation.x = lerp(0, -Math.PI / 2 + 0.12, t * t);
  e.group.position.y = lerp(0, 0.12, t);
  if (e.deathT > 1.6 && e.ch.materials) {
    const f = clamp(1 - (e.deathT - 1.6) / 1.0, 0, 1);
    for (const m of e.ch.materials) { m.transparent = true; m.opacity = 0.35 + f * 0.65; }
  }
}
