'use strict';
// ---------------------------------------------------------------------
// Game state, zone loading, interaction, saves and the frame loop.
// ---------------------------------------------------------------------

const SAVE_KEY = 'wolf_village_save_v1';

const G = {
  mode: 'boot',            // boot | menu | playing | inventory | shop | note | lockbox | paused | dead | victory
  time: 0, enemySeq: 1,
  player: null, inv: null,
  zone: null, lastZoneName: '',
  enemies: [], projectiles: [], fxLights: [],
  keys: {}, flags: {}, money: 0,
  taken: new Set(), killed: new Set(), wavesFired: new Set(),
  stats: { kills: 0, time: 0 },
  objective: '',
  vm: null,
};

// ------------------------------------------------------------ new game
function newGame() {
  G.player = makePlayer();
  G.inv = makeInventory(6, 5);
  G.keys = {}; G.flags = {}; G.money = 120;
  G.taken = new Set(); G.killed = new Set(); G.wavesFired = new Set();
  G.stats = { kills: 0, time: 0 };
  G.enemies = []; G.projectiles = []; G.fxLights = [];

  invAdd(G.inv, 'revolver', 1);
  invAdd(G.inv, 'ammo38', 16);
  invAdd(G.inv, 'herb', 2);
  invAdd(G.inv, 'brew', 1);

  startPlaying('village', 'start');
  showZoneName('Волчий Лог');
  toast('ЛКМ — взять управление мышью');
  setTimeout(() => toast('Tab — кейс, E — действие'), 1800);
}

function startPlaying(zoneId, spawnName) {
  G.mode = 'playing';
  show($('menu'), false); show($('controls'), false); show($('pause'), false);
  show($('death'), false); show($('victory'), false); show($('loading'), false);
  show($('hud'), true);
  loadZone(zoneId, spawnName);
  updateHUD();
  updateObjective();
  SFX.resume();
  SFX.startAmbience();
}

// ------------------------------------------------------------ zone load
function loadZone(zoneId, spawnName) {
  const def = ZONES[zoneId];
  if (!def) return;

  // tear the old one down
  if (GFX.zoneGroup) {
    GFX.scene.remove(GFX.zoneGroup);
    disposeTree(GFX.zoneGroup);
  }
  for (const p of G.projectiles) GFX.scene.remove(p.mesh);
  G.projectiles = [];
  for (const l of G.fxLights) GFX.scene.remove(l.light);
  G.fxLights = [];
  G.enemies = [];
  GFX.decals = [];
  show($('bossBar'), false);

  const W = makeBuilder();
  def.build(W);
  GFX.zoneGroup = W.group;
  GFX.scene.add(W.group);

  G.zone = {
    id: zoneId, name: def.name, def,
    colliders: W.colliders, interactables: W.interactables,
    spawns: W.spawns, torches: W.torches, group: W.group,
    merchantAt: W.merchantAt, trigger: W.trigger, gateMesh: W.gateMesh, gear: W.gear,
    pickupMeshes: W.pickupMeshes, npcs: [],
  };
  G.lastZoneName = def.name;

  // mood
  GFX.scene.fog.color.setHex(def.fog.color);
  GFX.scene.fog.density = def.fog.density;
  GFX.scene.background.setHex(def.fog.color);
  GFX.ambient.color.setHex(def.ambient.color);
  GFX.ambient.intensity = def.ambient.intensity;
  GFX.moon.intensity = def.moon;
  SFX.setAmbience(def.outdoor ? 1 : 0.35);
  SFX.setTension(def.tension);

  if (!GFX.snow) { GFX.snow = makeSnow(); GFX.scene.add(GFX.snow); }
  GFX.snow.visible = !!def.outdoor;

  // things already picked up stay picked up
  for (const it of W.interactables) {
    if (G.taken.has(it.id) && it.mesh) it.mesh.visible = false;
  }
  // an opened gate stays open
  if (zoneId === 'village' && G.keys.crestLeft && G.keys.crestRight && W.gateMesh) openGateVisual();

  // merchant
  if (W.merchantAt) {
    const ch = makeCharacter(0x2a2a34, 1.0, 0x0a0a12);
    ch.group.position.set(W.merchantAt.x, 0, W.merchantAt.z);
    ch.group.rotation.y = W.merchantAt.yaw;
    if (ch.eyeMat) ch.eyeMat.color.setHex(0xffcc55);
    playClip(ch, 'Idle', 0);
    W.group.add(ch.group);
    G.zone.npcs.push(ch);
  }

  // enemies that are not already dead
  for (const s of def.enemies || []) {
    if (G.killed.has(s.id)) continue;
    spawnEnemy(s.type, s.x, s.z, s.id, { patrol: s.patrol });
  }
  for (const w of def.waves || []) {
    if (!G.flags[w.flag]) continue;
    G.wavesFired.add(zoneId + ':' + w.flag);
    for (const s of w.spawns) {
      if (G.killed.has(s.id)) continue;
      spawnEnemy(s.type, s.x, s.z, s.id);
    }
  }

  const sp = W.spawns[spawnName] || W.spawns.start || { x: 0, z: 0, yaw: 0 };
  const P = G.player;
  P.x = sp.x; P.z = sp.z; P.yaw = sp.yaw; P.pitch = 0;
  P.vx = P.vz = 0; P.recoil = 0; P.recoilV = 0;
  GFX.rig.position.set(P.x, 0, P.z);
  GFX.rig.rotation.y = P.yaw;
  GFX.camera.rotation.set(0, 0, 0);

  if (!G.vm) G.vm = buildViewmodels();
  for (const k in G.vm.models) G.vm.models[k].visible = (k === P.equipped);

  showZoneName(def.name);
  updateObjective();
}

function disposeTree(root) {
  const shared = Object.values(MATS);
  root.traverse(n => {
    // skinned meshes share their geometry with the loaded rig, and decals share
    // one geometry/material pool — disposing either would break the next zone
    if (n.isSkinnedMesh) return;
    if (n.geometry && n.geometry !== _decalGeo) n.geometry.dispose();
    if (n.material) {
      const mats = Array.isArray(n.material) ? n.material : [n.material];
      for (const m of mats) {
        if (!m || m === _decalMat || shared.indexOf(m) >= 0) continue;
        m.dispose();
      }
    }
  });
}

function openGateVisual() {
  const g = G.zone.gateMesh;
  if (!g) return;
  g.rotation.y = 1.15;
  g.position.x = -2.6;
  // the gate no longer blocks the road
  G.zone.colliders = G.zone.colliders.filter(c => !(Math.abs(c.x) < 0.01 && Math.abs(c.z + 30) < 0.01 && c.hw > 2));
}

function travel(zoneId, spawnName) {
  SFX.play('door');
  fadeOut(() => {
    loadZone(zoneId, spawnName);
    fadeIn();
  });
}

// simple full-screen fade so zone swaps do not snap
let _fade = null;
function fadeEl() {
  if (!_fade) {
    _fade = el('div');
    _fade.style.cssText = 'position:fixed;inset:0;background:#000;opacity:0;pointer-events:none;' +
      'transition:opacity .32s ease;z-index:60';
    document.body.appendChild(_fade);
  }
  return _fade;
}
function fadeOut(cb) {
  const f = fadeEl();
  f.style.opacity = '1';
  setTimeout(cb, 330);
}
function fadeIn() {
  const f = fadeEl();
  setTimeout(() => { f.style.opacity = '0'; }, 60);
}

// ---------------------------------------------------------- interaction
let currentInteractable = null;

function updateInteraction() {
  const P = G.player;
  let best = null, bestScore = Infinity;
  for (const it of G.zone.interactables) {
    if (G.taken.has(it.id)) continue;
    const d = dist(P.x, P.z, it.x, it.z);
    if (d > TUNE.interactRange) continue;
    const ang = Math.abs(normalizeAngle(yawToward(it.x - P.x, it.z - P.z) - P.yaw));
    if (ang > 1.5) continue;
    const score = d * 0.6 + ang;
    if (score < bestScore) { bestScore = score; best = it; }
  }
  currentInteractable = best;

  if (!best) { setPrompt(''); return; }
  let label = best.label;
  if (best.kind === 'door' && best.lock && !G.keys[best.lock]) label = best.lockedText + ' 🔒';
  if (best.kind === 'gate') {
    const have = best.requires.every(k => G.keys[k]);
    label = have ? 'Вставить герб и открыть ворота' : 'Ворота усадьбы: не хватает половин герба 🔒';
  }
  setPrompt(`<b>E</b> — ${label}`);
}

function doInteract() {
  const it = currentInteractable;
  if (!it) return;
  const P = G.player;

  switch (it.kind) {
    case 'pickup': {
      const added = invAdd(G.inv, it.item, it.count);
      if (added <= 0) { toast('В кейсе нет места', true); SFX.play('deny'); return; }
      if (added < it.count) {
        it.count -= added;
        toast(`Взято ${ITEMS[it.item].name} ×${added} — остальное не влезло`, true);
      } else {
        toast(`Взято: ${ITEMS[it.item].name}${it.count > 1 ? ' ×' + it.count : ''}`);
        hideInteractable(it);
      }
      if (ITEMS[it.item].kind === 'weapon') G.player.owned[ITEMS[it.item].weapon] = true;
      SFX.play('pickup');
      updateHUD();
      break;
    }
    case 'keyPickup':
      G.keys[it.key] = true;
      toast(`Получено: ${KEY_ITEMS[it.key].name}`);
      SFX.play('pickup');
      hideInteractable(it);
      if (it.trigger) fireFlag(it.trigger);
      afterKeyGained();
      break;

    case 'note':
      openNote(it.note);
      break;

    case 'container': {
      let any = false;
      for (const [item, count] of it.loot) {
        const added = invAdd(G.inv, item, count);
        if (added > 0) { toast(`Найдено: ${ITEMS[item].name}${added > 1 ? ' ×' + added : ''}`); any = true; }
        if (added < count) { toast('В кейсе нет места', true); break; }
      }
      if (any) { SFX.play('pickup'); hideInteractable(it); updateHUD(); }
      else SFX.play('deny');
      break;
    }

    case 'shrine':
      saveGame();
      SFX.play('save');
      toast('Игра сохранена');
      break;

    case 'merchant':
      openShop();
      break;

    case 'lockbox':
      openLockbox(it);
      break;

    case 'door':
      if (it.lock && !G.keys[it.lock]) { SFX.play('deny'); toast(it.lockedText, true); return; }
      travel(it.to, it.spawn);
      break;

    case 'gate': {
      const have = it.requires.every(k => G.keys[k]);
      if (!have) { SFX.play('deny'); toast('Нужны обе половины герба', true); return; }
      if (!G.flags.gateOpen) {
        G.flags.gateOpen = true;
        SFX.play('door');
        openGateVisual();
        toast('Ворота усадьбы открыты');
        setPrompt('');
        return;
      }
      travel(it.to, it.spawn);
      break;
    }
  }
  updateObjective();
}

function hideInteractable(it) {
  G.taken.add(it.id);
  if (it.mesh) it.mesh.visible = false;
  currentInteractable = null;
  setPrompt('');
}

// Used by the lockbox once its code is entered.
function takeInteractable(it, giveLoot) {
  if (giveLoot) {
    for (const k of it.keys || []) {
      G.keys[k] = true;
      toast(`Получено: ${KEY_ITEMS[k].name}`);
    }
    for (const [item, count] of it.loot || []) {
      const added = invAdd(G.inv, item, count);
      if (added > 0) toast(`Найдено: ${ITEMS[item].name} ×${added}`);
    }
  }
  hideInteractable(it);
  fireFlag('lockboxOpen');
  afterKeyGained();
  updateHUD();
  updateObjective();
}

function afterKeyGained() {
  if (G.keys.crestLeft && G.keys.crestRight && !G.flags.bothCrests) {
    fireFlag('bothCrests');
    toast('Герб собран. Ворота ждут.');
  }
}

// Raising a flag can wake a wave in the current zone right away.
function fireFlag(flag) {
  if (G.flags[flag]) return;
  G.flags[flag] = true;
  const def = G.zone && G.zone.def;
  if (!def || !def.waves) return;
  for (const w of def.waves) {
    if (w.flag !== flag) continue;
    const key = G.zone.id + ':' + flag;
    if (G.wavesFired.has(key)) continue;
    G.wavesFired.add(key);
    for (const s of w.spawns) {
      if (G.killed.has(s.id)) continue;
      spawnEnemy(s.type, s.x, s.z, s.id);
    }
    SFX.play('bossRoar');
    toast('Они услышали', true);
  }
}

function checkZoneTrigger() {
  const t = G.zone.trigger;
  if (!t || G.flags[t.id]) return;
  if (G.player.z > t.z) return;
  G.flags[t.id] = true;
  for (const s of t.spawns) {
    if (G.killed.has(s.id)) { G.flags.moranaDead = true; continue; }
    spawnEnemy(s.type, s.x, s.z, s.id);
  }
}

function updateObjective() {
  const here = G.zone ? G.zone.id : '';
  if (G.flags.moranaDead) { setObjective('Найти дочь в подвале усадьбы'); return; }
  if (here === 'manor') { setObjective('Морана где-то в зале. Бей в сердце, когда откроется'); return; }
  if (here === 'crypt' && !G.keys.crestLeft) {
    setObjective('Найти сундук в дальнем зале. Код — в записке отца Никодима');
    return;
  }
  if (here === 'mill' && !G.keys.crestRight) { setObjective('Обыскать мучной ларь в дальней комнате'); return; }
  if (G.keys.crestLeft && G.keys.crestRight) {
    setObjective(G.flags.gateOpen ? 'Подняться к усадьбе по северной дороге' : 'Открыть ворота усадьбы гербом (север деревни)');
    return;
  }
  if (G.keys.crestLeft && !G.keys.crestRight) {
    setObjective(G.keys.millKey ? 'Обыскать мучной ларь на мельнице (восток)' : 'Найти вторую половину герба');
    return;
  }
  if (G.keys.cryptKey) { setObjective('Спуститься в крипту под церковью (юго-запад)'); return; }
  setObjective('Найти дорогу в усадьбу. Начни с церкви на юго-западе');
}

// --------------------------------------------------------------- saving
function saveGame() {
  const P = G.player;
  const data = {
    v: 1, zone: G.zone.id,
    pos: { x: P.x, z: P.z, yaw: P.yaw },
    hp: P.hp, stamina: P.stamina,
    equipped: P.equipped, owned: P.owned, mag: P.mag, upg: P.upg,
    inv: invSerialize(G.inv),
    keys: G.keys, flags: G.flags, money: G.money,
    taken: Array.from(G.taken), killed: Array.from(G.killed),
    waves: Array.from(G.wavesFired),
    stats: G.stats,
  };
  try {
    localStorage.setItem(SAVE_KEY, JSON.stringify(data));
    refreshContinueButton();
    return true;
  } catch (err) {
    toast('Не удалось сохранить', true);
    return false;
  }
}

function hasSave() {
  try { return !!localStorage.getItem(SAVE_KEY); } catch (_) { return false; }
}

function loadGame() {
  let data;
  try { data = JSON.parse(localStorage.getItem(SAVE_KEY)); } catch (_) { data = null; }
  if (!data) { toast('Сохранения нет', true); return false; }

  G.player = makePlayer();
  const P = G.player;
  P.hp = data.hp; P.stamina = data.stamina;
  P.equipped = data.equipped || 'revolver';
  P.owned = Object.assign({ knife: true, revolver: true, shotgun: false }, data.owned || {});
  P.mag = Object.assign({ revolver: 0, shotgun: 0 }, data.mag || {});
  P.upg = Object.assign({ revolver: [0, 0, 0], shotgun: [0, 0, 0] }, data.upg || {});

  G.inv = invDeserialize(data.inv || { w: 6, h: 5, slots: [] });
  G.keys = data.keys || {};
  G.flags = data.flags || {};
  G.money = data.money || 0;
  G.taken = new Set(data.taken || []);
  G.killed = new Set(data.killed || []);
  G.wavesFired = new Set(data.waves || []);
  G.stats = data.stats || { kills: 0, time: 0 };
  // a boss killed once stays killed; the fight trigger must not re-arm
  if (G.killed.has('mn_boss')) G.flags.moranaDead = true;

  startPlaying(data.zone || 'village', 'start');
  if (data.pos) {
    P.x = data.pos.x; P.z = data.pos.z; P.yaw = data.pos.yaw;
    GFX.rig.position.set(P.x, 0, P.z);
    GFX.rig.rotation.y = P.yaw;
  }
  updateHUD();
  return true;
}

function refreshContinueButton() {
  const b = $('btnContinue');
  if (b) b.disabled = !hasSave();
}

// -------------------------------------------------------------- flow UI
function toMenu() {
  G.mode = 'menu';
  Input.release();
  SFX.setTension(0);
  show($('hud'), false);
  show($('inventory'), false); show($('shop'), false); show($('note'), false);
  show($('lockbox'), false); show($('pause'), false); show($('death'), false);
  show($('victory'), false);
  show($('menu'), true);
  refreshContinueButton();
}

function pauseGame() {
  if (G.mode !== 'playing') return;
  G.mode = 'paused';
  Input.release();
  show($('pause'), true);
  show($('hud'), false);
}

function resumeGame() {
  if (G.mode !== 'paused') return;
  show($('pause'), false);
  show($('hud'), true);
  G.mode = 'playing';
}

function closeAnyPanel() {
  switch (G.mode) {
    case 'inventory': closeInventory(); return true;
    case 'shop': closeShop(); return true;
    case 'note': closeNote(); return true;
    case 'lockbox': closeLockbox(); return true;
    case 'paused': resumeGame(); return true;
  }
  return false;
}

// ------------------------------------------------------------- the loop
let lastT = 0, _hintShown = null;
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.06, (now - lastT) / 1000 || 0);
  lastT = now;
  G.time += dt;

  resizeRenderer($('stage'));

  if (G.mode === 'playing') {
    G.stats.time += dt;
    updatePlayer(dt);
    updateEnemies(dt);
    updateProjectiles(dt);
    updateInteraction();
    checkZoneTrigger();
    handlePlayKeys();

    // tension follows how many awake things are near you
    let threat = 0;
    for (const e of G.enemies) {
      if (!e.alive) continue;
      const d = dist(e.x, e.z, G.player.x, G.player.z);
      if (d < 22) threat += (e.boss ? 1.0 : 0.28) * (1 - d / 22) * (0.35 + e.awareness);
    }
    SFX.setTension(clamp((G.zone.def.tension || 0) + threat, 0, 1));
    SFX.update(dt, G.player.hp / G.player.hpMax);

    // the flash reads as "you were hit", not as "the screen is now red"
    $('damageFlash').style.opacity = String(clamp(G.player.hurtFlash * 0.6, 0, 0.6));
    $('crosshair').classList.toggle('hit', G.player.hitMark > 0);
    if (_hintShown !== Input.captured) { _hintShown = Input.captured; show($('pauseHint'), !Input.captured); }
    if (G.player.dead) $('damageFlash').style.opacity = '0.8';
  } else if (G.player && G.player.dead) {
    updatePlayer(dt);
  }

  // corpses and torches keep living even while a panel is open
  updateParticles(dt);
  if (G.zone) { updateTorches(G.zone, dt, G.time); updatePickups(G.zone.pickupMeshes, G.time); }
  if (G.zone && G.zone.gear) G.zone.gear.rotation.z += dt * 0.15;
  for (const npc of (G.zone ? G.zone.npcs : [])) if (npc.mixer) npc.mixer.update(dt);
  for (let i = G.fxLights.length - 1; i >= 0; i--) {
    const l = G.fxLights[i];
    l.life -= dt;
    l.light.intensity = l.base * Math.max(0, l.life / 0.5);
    if (l.life <= 0) { GFX.scene.remove(l.light); G.fxLights.splice(i, 1); }
  }
  if (G.player) updateSnow(dt, G.player.x, G.player.z, G.time);

  Input.endFrame();
  GFX.renderer.render(GFX.scene, GFX.camera);
}

function handlePlayKeys() {
  if (Input.pressed('KeyE')) doInteract();
  if (Input.pressed('Tab')) openInventory();
  const w = Input.wheel;
  if (w) {
    const order = ['knife', 'revolver', 'shotgun'].filter(k => G.player.owned[k]);
    let i = order.indexOf(G.player.equipped);
    i = (i + (w > 0 ? 1 : -1) + order.length) % order.length;
    equipWeapon(order[i]);
  }
}

// --------------------------------------------------------------- wiring
function wireUI() {
  $('btnNew').addEventListener('click', () => { SFX.resume(); newGame(); });
  $('btnContinue').addEventListener('click', () => { SFX.resume(); loadGame(); });
  $('btnControls').addEventListener('click', () => { show($('menu'), false); show($('controls'), true); });
  $('btnControlsBack').addEventListener('click', () => { show($('controls'), false); show($('menu'), true); });
  $('btnResume').addEventListener('click', resumeGame);
  $('btnQuit').addEventListener('click', toMenu);
  $('btnLoad').addEventListener('click', () => { show($('death'), false); if (!loadGame()) toMenu(); });
  $('btnDeathMenu').addEventListener('click', toMenu);
  $('btnVictoryMenu').addEventListener('click', toMenu);
  $('btnCloseInv').addEventListener('click', closeInventory);
  $('btnCloseShop').addEventListener('click', closeShop);
  $('btnCloseNote').addEventListener('click', closeNote);
  $('btnCloseLock').addEventListener('click', closeLockbox);
  $('btnLockTry').addEventListener('click', tryLock);
  document.querySelectorAll('#shop .tab').forEach(t => {
    t.addEventListener('click', () => { shopTab = t.dataset.tab; SFX.play('ui'); renderShop(); });
  });

  document.addEventListener('mousemove', e => {
    invUI.lastMouseX = e.clientX; invUI.lastMouseY = e.clientY;
    moveGhost(e.clientX, e.clientY);
  });

  document.addEventListener('keydown', e => {
    if (e.code === 'Escape') {
      if (closeAnyPanel()) { e.preventDefault(); return; }
      if (G.mode === 'playing') {
        if (Input.captured) Input.release();
        else pauseGame();
        e.preventDefault();
      }
      return;
    }
    if (e.code === 'Tab' && (G.mode === 'inventory')) { e.preventDefault(); closeInventory(); return; }
    if (e.code === 'KeyR' && G.mode === 'inventory') { e.preventDefault(); rotateHeld(); renderInventory(); return; }
  });

  // Clicking the world takes the mouse; clicking a panel must not.
  const canvas = $('view');
  Input.bind(canvas, on => {
    show($('pauseHint'), G.mode === 'playing' && !on);
    if (on) SFX.resume();
  });
  canvas.addEventListener('mousedown', () => { if (G.mode === 'playing') SFX.resume(); });
}

// ---------------------------------------------------------------- boot
function boot() {
  const canvas = $('view');
  initGraphics(canvas);
  wireUI();
  SFX.init();
  requestAnimationFrame(frame);

  loadSoldier(() => {
    show($('loading'), false);
    toMenu();
  });
  // never let a slow parse hold the menu hostage
  setTimeout(() => { if (G.mode === 'boot') { show($('loading'), false); toMenu(); } }, 9000);
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();
