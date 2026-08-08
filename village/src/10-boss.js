'use strict';
// ---------------------------------------------------------------------
// Графиня Морана. Bullets barely scratch her — except in the moment she
// rears back to strike, when the light under her ribs opens up. The whole
// fight is holding your nerve and your ammo until that window.
// ---------------------------------------------------------------------

const MORANA = {
  id: 'morana', name: 'Графиня Морана',
  hp: 1600, speed: 2.4, chaseSpeed: 3.6, dmg: 30, attackRange: 2.6,
  sight: 60, hearing: 60, tint: 0x6a1420, emissive: 0x3a0208, scale: 1.35,
  armorMul: 0.22,      // damage taken with the heart closed
  weakMul: 1.9,        // damage taken with it open
  holyMul: 2.2,
  growl: 'stryga',
  money: [0, 0], loot: [], staggerHp: 1e9,
};

function initMorana(e) {
  e.hpMax = MORANA.hp; e.hp = MORANA.hp;
  e.state = 'intro'; e.stateT = 0;
  e.phase = 1; e.weak = false;
  e.attackCd = 2.2; e.summonCd = 14; e.castCd = 7;
  e.dashVX = 0; e.dashVZ = 0;
  e.minions = 0;

  // the heart: hidden inside the ribs until she opens up
  const heart = new THREE.Mesh(new THREE.SphereGeometry(0.17, 12, 10),
    new THREE.MeshBasicMaterial({ color: 0xff2a30 }));
  heart.position.set(0, 1.28 * MORANA.scale, -0.2);
  heart.visible = false;
  e.group.add(heart);
  e.heart = heart;
  e.heartLight = new THREE.PointLight(0xff2020, 0, 8, 2);
  e.heartLight.position.copy(heart.position);
  e.group.add(e.heartLight);

  // cloak — hangs off the shoulders and pools on the floor, leaving the head
  // and the ribs (and therefore the heart) visible
  const cloak = new THREE.Mesh(new THREE.ConeGeometry(0.62, 1.55, 10, 1, true),
    new THREE.MeshLambertMaterial({ color: 0x2a0810, side: THREE.DoubleSide, emissive: 0x100004 }));
  cloak.position.set(0, 0.78 * MORANA.scale, 0.08);
  e.group.add(cloak);
  e.cloak = cloak;

  // she carries her own dim red light: a boss you cannot find in the dark is
  // not frightening, only annoying
  const aura = new THREE.PointLight(0xff4030, 0.85, 11, 2);
  aura.position.set(0, 1.5, 0);
  e.group.add(aura);

  if (e.ch.eyeMat) e.ch.eyeMat.color.setHex(0xff1010);
  show($('bossBar'), true);
  $('bossName').textContent = MORANA.name;
  SFX.play('bossRoar');
  SFX.setTension(1);
}

function moranaHit(e, amount, info) {
  // the damage was already applied by damageEnemy with a flat number; here we
  // correct it for armour, since only this fight has a weak point
  const mul = info && info.holy ? MORANA.holyMul : (e.weak ? MORANA.weakMul : MORANA.armorMul);
  e.hp += amount;                 // undo
  e.hp -= amount * mul;           // redo, weighted
  if (!e.weak && !(info && info.holy)) {
    SFX.play('ricochet', dist(e.x, e.z, G.player.x, G.player.z));
    if (!e.armorHintShown) { e.armorHintShown = true; toast('Пули её не берут. Жди, когда откроется', true); }
  }
  updateBossBar(e);
}

function updateBossBar(e) {
  const fill = $('bossFill');
  if (fill) fill.style.transform = `scaleX(${clamp(e.hp / e.hpMax, 0, 1)})`;
}

function setWeak(e, on) {
  e.weak = on;
  e.heart.visible = on;
  e.heartLight.intensity = on ? 2.6 : 0;
  for (const m of e.ch.materials) m.emissiveIntensity = on ? 0.9 : 0.35;
}

function updateMorana(e, dt) {
  const P = G.player;
  e.stateT += dt;
  e.attackCd = Math.max(0, e.attackCd - dt);
  e.summonCd = Math.max(0, e.summonCd - dt);
  e.castCd = Math.max(0, e.castCd - dt);

  const d = dist(P.x, P.z, e.x, e.z);
  const face = yawToward(P.x - e.x, P.z - e.z);

  // phase gates
  const frac = e.hp / e.hpMax;
  if (e.phase === 1 && frac < 0.66) startPhase(e, 2);
  else if (e.phase === 2 && frac < 0.33) startPhase(e, 3);

  switch (e.state) {
    case 'intro':
      e.yaw = approachAngle(e.yaw, face, dt * 2);
      playClip(e.ch, 'Idle');
      steerTo(e, e.x, e.z, 0);
      if (e.stateT > 2.4) { e.state = 'stalk'; e.stateT = 0; }
      break;

    case 'stalk': {
      playClip(e.ch, d > 5 ? 'Run' : 'Walk');
      e.yaw = approachAngle(e.yaw, face, dt * 3.4);
      const speed = e.phase >= 3 ? MORANA.chaseSpeed * 1.15 : (e.phase === 2 ? MORANA.chaseSpeed : MORANA.speed);
      // she circles rather than walking straight in
      const strafe = Math.sin(G.time * 0.7) * 0.55;
      const tx = P.x + Math.cos(face + Math.PI / 2) * strafe * 4;
      const tz = P.z + Math.sin(face + Math.PI / 2) * strafe * 4;
      steerTo(e, tx, tz, speed);

      if (e.summonCd <= 0 && e.phase >= 2 && countLivingMinions() < 3) { e.state = 'summon'; e.stateT = 0; break; }
      if (e.castCd <= 0 && e.phase >= 2 && d > 6) { e.state = 'cast'; e.stateT = 0; break; }
      if (e.attackCd <= 0 && d < 9) { e.state = 'telegraph'; e.stateT = 0; setWeak(e, true); SFX.play('stryga', d); }
      break;
    }

    case 'telegraph': {
      // she rears; the heart is open and this is the only window that matters
      playClip(e.ch, 'Idle', 0.1);
      steerTo(e, e.x, e.z, 0);
      e.yaw = approachAngle(e.yaw, face, dt * 2.2);
      e.group.position.y = Math.sin(e.stateT * 6) * 0.06;
      const windup = e.phase >= 3 ? 0.85 : e.phase === 2 ? 1.0 : 1.25;
      if (e.stateT >= windup) {
        e.state = 'dash'; e.stateT = 0;
        setWeak(e, false);
        const dx = P.x - e.x, dz = P.z - e.z, len = Math.hypot(dx, dz) || 1;
        const power = e.phase >= 3 ? 17 : 14;
        e.dashVX = dx / len * power; e.dashVZ = dz / len * power;
        e.dashHit = false;
        SFX.play('vurdalak', d);
      }
      break;
    }

    case 'dash': {
      playClip(e.ch, 'Run', 0.08);
      e.group.position.y = 0;
      e.vx = e.dashVX; e.vz = e.dashVZ;
      e.desiredX = e.dashVX; e.desiredZ = e.dashVZ;
      if (!e.dashHit && d < MORANA.attackRange) {
        e.dashHit = true;
        damagePlayer(MORANA.dmg, e.x, e.z);
        addShake(0.9);
      }
      if (e.stateT > 0.42) {
        e.state = 'recover'; e.stateT = 0;
        e.attackCd = e.phase >= 3 ? 1.5 : e.phase === 2 ? 2.1 : 2.8;
      }
      break;
    }

    case 'recover':
      playClip(e.ch, 'Idle', 0.15);
      steerTo(e, e.x, e.z, 0);
      e.vx *= Math.exp(-6 * dt); e.vz *= Math.exp(-6 * dt);
      if (e.stateT > 0.7) { e.state = 'stalk'; e.stateT = 0; }
      break;

    case 'cast': {
      playClip(e.ch, 'Idle', 0.12);
      steerTo(e, e.x, e.z, 0);
      e.yaw = approachAngle(e.yaw, face, dt * 4);
      if (!e.castDone && e.stateT > 0.6) {
        e.castDone = true;
        for (let i = 0; i < 3; i++) setTimeout(() => { if (e.alive) batBolt(e, i); }, i * 190);
      }
      if (e.stateT > 1.5) {
        e.state = 'stalk'; e.stateT = 0; e.castDone = false;
        e.castCd = e.phase >= 3 ? 5 : 8;
      }
      break;
    }

    case 'summon': {
      playClip(e.ch, 'Idle', 0.12);
      steerTo(e, e.x, e.z, 0);
      if (!e.summonDone && e.stateT > 0.8) {
        e.summonDone = true;
        SFX.play('bossRoar');
        const type = e.phase >= 3 ? 'vurdalak' : 'ghoul';
        for (let i = 0; i < 2; i++) {
          const a = rnd() * TAU;
          spawnEnemy(type, e.x + Math.cos(a) * 4, e.z + Math.sin(a) * 4, 'mn_add' + (G.enemySeq++));
        }
        toast('Морана зовёт своих', true);
      }
      if (e.stateT > 2.0) {
        e.state = 'stalk'; e.stateT = 0; e.summonDone = false;
        e.summonCd = e.phase >= 3 ? 16 : 22;
      }
      break;
    }

    case 'phaseShift':
      playClip(e.ch, 'Idle', 0.1);
      steerTo(e, e.x, e.z, 0);
      e.group.position.y = Math.sin(e.stateT * 9) * 0.1;
      if (e.stateT > 2.6) {
        e.state = 'stalk'; e.stateT = 0;
        setWeak(e, false);
        e.group.position.y = 0;
      }
      break;
  }

  applyEnemyMotion(e, dt);
  if (e.state !== 'telegraph' && e.state !== 'phaseShift') e.group.position.y = 0;
  e.group.position.x = e.x; e.group.position.z = e.z;
  e.group.rotation.y = e.yaw;
  if (e.ch.mixer) e.ch.mixer.update(dt);

  if (e.weak) {
    const pulse = 0.8 + Math.sin(G.time * 14) * 0.35;
    e.heartLight.intensity = 2.4 * pulse;
    e.heart.scale.setScalar(0.9 + pulse * 0.25);
  }
}

function startPhase(e, n) {
  e.phase = n;
  e.state = 'phaseShift'; e.stateT = 0;
  setWeak(e, true);                 // the stagger between phases is a free window
  SFX.play('bossRoar');
  addShake(1.0);
  toast(n === 2 ? 'Морана в ярости' : 'Морана истекает', true);
  if (e.cloak) e.cloak.material.color.setHex(n === 3 ? 0x4a0a14 : 0x3a0a12);
}

function batBolt(e, i) {
  const P = G.player;
  const sx = e.x, sy = 1.5, sz = e.z;
  const dx = P.x - sx, dy = (TUNE.eyeHeight - 0.3) - sy, dz = P.z - sz;
  const len = Math.hypot(dx, dy, dz) || 1;
  const speed = 15;
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(0.19, 8, 6),
    new THREE.MeshBasicMaterial({ color: 0x8a1030 }));
  mesh.position.set(sx, sy, sz);
  GFX.scene.add(mesh);
  const spread = (i - 1) * 0.09;
  G.projectiles.push({
    kind: 'shriek', mesh, x: sx, y: sy, z: sz,
    vx: (dx / len + spread) * speed, vy: dy / len * speed + 1.4, vz: (dz / len - spread * 0.4) * speed,
    life: 4, dmg: 16,
  });
  SFX.play('screech', dist(sx, sz, P.x, P.z));
}

function countLivingMinions() {
  let n = 0;
  for (const e of G.enemies) if (e.alive && !e.boss) n++;
  return n;
}

function onMoranaDead(e) {
  SFX.play('bossRoar');
  SFX.setTension(0);
  show($('bossBar'), false);
  setWeak(e, false);
  if (e.heartLight) e.heartLight.intensity = 0;
  G.flags.moranaDead = true;
  addShake(1.2);
  toast('Морана мертва');
  setTimeout(() => {
    if (G.mode !== 'playing') return;
    G.mode = 'victory';
    Input.release();
    $('victoryText').textContent =
      `Усадьба пуста. В подвале, за той дверью, что она стерегла, — живые. И твоя среди них.\n\n` +
      `Убито тварей: ${G.stats.kills}. Потрачено времени: ${Math.floor(G.stats.time / 60)} мин. ` +
      `Талеров при себе: ${G.money}.`;
    show($('victory'), true);
    show($('hud'), false);
  }, 3200);
}
