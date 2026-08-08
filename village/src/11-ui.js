'use strict';
// ---------------------------------------------------------------------
// HUD and the full-screen panels. The case is the interesting one: items
// have footprints, you pick them up with a click and drop them where they
// fit, and dropping one item onto another either stacks or crafts.
// ---------------------------------------------------------------------

const CELL = 56;
const invUI = { sel: null, held: null, rot: 0, ghost: null };

// ------------------------------------------------------------------ HUD
function updateHUD() {
  const P = G.player;
  const hpFrac = clamp(P.hp / P.hpMax, 0, 1);
  const hpFill = $('hpFill');
  hpFill.style.transform = `scaleX(${hpFrac})`;
  hpFill.classList.toggle('low', hpFrac < 0.34);
  $('hpText').textContent = Math.ceil(P.hp);
  $('stamFill').style.transform = `scaleX(${clamp(P.stamina / TUNE.staminaMax, 0, 1)})`;

  const def = WEAPONS[P.equipped];
  $('ammoWeapon').textContent = def.name;
  const count = $('ammoCount');
  if (def.kind === 'melee') {
    count.innerHTML = '∞';
    count.classList.remove('empty');
  } else {
    const bag = ammoInBag(P.equipped);
    count.innerHTML = `${P.mag[P.equipped]}<small> / ${bag}</small>`;
    count.classList.toggle('empty', P.mag[P.equipped] === 0);
  }
  $('reloadHint').textContent = P.reloadT > 0 ? 'Перезарядка…'
    : (def.kind === 'gun' && P.mag[P.equipped] === 0 && ammoInBag(P.equipped) > 0 ? 'R — перезарядить' : '');
}

function setObjective(text) {
  G.objective = text;
  $('objectiveText').textContent = text;
}

function showZoneName(name) {
  const n = $('zoneName');
  n.textContent = name;
  n.classList.add('show');
  clearTimeout(showZoneName._t);
  showZoneName._t = setTimeout(() => n.classList.remove('show'), 2600);
}

let _promptText = '';
function setPrompt(text) {
  if (text === _promptText) return;
  _promptText = text;
  const p = $('prompt');
  if (!text) { show(p, false); return; }
  p.innerHTML = text;
  show(p, true);
}

// --------------------------------------------------------------- case UI
function openInventory() {
  if (G.mode !== 'playing') return;
  G.mode = 'inventory';
  Input.release();
  invUI.sel = null; invUI.held = null; invUI.rot = 0;
  renderInventory();
  show($('inventory'), true);
  show($('hud'), false);
  SFX.play('ui');
}

function closeInventory() {
  if (G.mode !== 'inventory') return;
  dropGhost();
  show($('inventory'), false);
  show($('hud'), true);
  G.mode = 'playing';
  updateHUD();
}

function renderInventory() {
  const grid = $('caseGrid');
  const inv = G.inv;
  grid.style.width = inv.w * CELL + 'px';
  grid.style.height = inv.h * CELL + 'px';
  grid.innerHTML = '';

  for (let y = 0; y < inv.h; y++) {
    for (let x = 0; x < inv.w; x++) {
      const c = el('div', 'cell');
      c.style.cssText = `left:${x * CELL}px;top:${y * CELL}px;width:${CELL}px;height:${CELL}px`;
      c.dataset.x = x; c.dataset.y = y;
      c.addEventListener('click', () => onCellClick(x, y));
      grid.appendChild(c);
    }
  }

  for (const s of inv.slots) {
    if (invUI.held === s.uid) continue;
    const d = ITEMS[s.item];
    const size = slotSize(s);
    const n = el('div', 'slot' + (invUI.sel === s.uid ? ' sel' : '')
      + (d.kind === 'weapon' && G.player.equipped === d.weapon ? ' equipped' : ''));
    n.style.cssText = `left:${s.x * CELL + 2}px;top:${s.y * CELL + 2}px;` +
      `width:${size.w * CELL - 4}px;height:${size.h * CELL - 4}px`;
    n.appendChild(el('div', 'ic', d.icon));
    n.appendChild(el('div', 'nm', d.name));
    if (s.count > 1) n.appendChild(el('div', 'ct', String(s.count)));
    n.addEventListener('click', ev => { ev.stopPropagation(); onSlotClick(s); });
    grid.appendChild(n);
  }

  renderItemInfo();
  renderKeyItems();
  $('invStats').innerHTML =
    `Талеры: <b>${G.money}</b><br>Свободно ячеек: <b>${freeCells(inv)}</b> из ${inv.w * inv.h}` +
    `<br>Убито тварей: <b>${G.stats.kills}</b>`;
}

function onSlotClick(s) {
  if (invUI.held != null && invUI.held !== s.uid) {
    // dropping the carried item onto this one: stack, craft, or refuse
    const res = invCombine(G.inv, invUI.held, s.uid);
    if (res && res.text) toast(res.text, !!res.failed);
    if (res && !res.failed) SFX.play(res.crafted ? 'heal' : 'ui');
    else if (!res) { SFX.play('deny'); }
    invUI.held = null; invUI.rot = 0;
    dropGhost();
    renderInventory();
    updateHUD();
    return;
  }
  if (invUI.sel === s.uid) {
    invUI.held = s.uid;
    invUI.rot = s.rot;
    makeGhost(s);
    renderInventory();
    return;
  }
  invUI.sel = s.uid;
  SFX.play('ui');
  renderInventory();
}

function onCellClick(x, y) {
  if (invUI.held == null) { invUI.sel = null; renderInventory(); return; }
  const s = slotByUid(G.inv, invUI.held);
  if (!s) { invUI.held = null; dropGhost(); renderInventory(); return; }
  const size = sizeOf(s.item, invUI.rot);
  // place by the item's top-left, but let the click land anywhere inside it
  const tx = clamp(x - Math.floor((size.w - 1) / 2), 0, G.inv.w - size.w);
  const ty = clamp(y - Math.floor((size.h - 1) / 2), 0, G.inv.h - size.h);
  if (invMove(G.inv, s.uid, tx, ty, invUI.rot)) {
    invUI.held = null; invUI.rot = 0;
    dropGhost();
    SFX.play('ui');
  } else {
    SFX.play('deny');
  }
  renderInventory();
}

function makeGhost(s) {
  dropGhost();
  const d = ITEMS[s.item];
  const size = sizeOf(s.item, invUI.rot);
  const n = el('div', 'slot ghost');
  n.style.cssText = `position:fixed;width:${size.w * CELL - 4}px;height:${size.h * CELL - 4}px;opacity:.75`;
  n.appendChild(el('div', 'ic', d.icon));
  n.appendChild(el('div', 'nm', d.name));
  $('dragLayer').appendChild(n);
  invUI.ghost = n;
  moveGhost(invUI.lastMouseX || window.innerWidth / 2, invUI.lastMouseY || window.innerHeight / 2);
}

function moveGhost(mx, my) {
  if (!invUI.ghost) return;
  invUI.ghost.style.left = (mx - CELL / 2) + 'px';
  invUI.ghost.style.top = (my - CELL / 2) + 'px';
}

function dropGhost() {
  if (invUI.ghost) { invUI.ghost.remove(); invUI.ghost = null; }
}

function rotateHeld() {
  if (invUI.held == null) return;
  const s = slotByUid(G.inv, invUI.held);
  if (!s) return;
  const d = ITEMS[s.item];
  if (d.w === d.h) { SFX.play('deny'); return; }
  invUI.rot = invUI.rot ? 0 : 1;
  makeGhost(s);
  SFX.play('ui');
}

function renderItemInfo() {
  const host = $('itemInfo'), acts = $('itemActions');
  acts.innerHTML = '';
  const s = invUI.sel != null ? slotByUid(G.inv, invUI.sel) : null;
  if (!s) { host.innerHTML = '<span style="color:#6d6555">Ничего не выбрано</span>'; return; }
  const d = ITEMS[s.item];
  const kindName = { ammo: 'Боеприпас', heal: 'Лечение', mat: 'Материал', weapon: 'Оружие',
                     treasure: 'На продажу', throw: 'Метательное' }[d.kind] || '';
  host.innerHTML = `<div class="t">${d.name}${s.count > 1 ? ' ×' + s.count : ''}</div>` +
    `<div class="meta">${kindName} · ${d.w}×${d.h}${d.sell ? ' · продажа ' + d.sell : ''}</div>` +
    `<div>${d.desc}</div>`;

  const add = (label, fn) => {
    const b = el('button', 'btn small', label);
    b.addEventListener('click', fn);
    acts.appendChild(b);
  };
  if (d.kind === 'heal') add('Использовать', () => { invConsume(G.inv, s.item, 1); healPlayer(d.heal); renderInventory(); });
  if (d.kind === 'weapon') {
    if (G.player.equipped !== d.weapon) add('Взять в руки', () => { equipWeapon(d.weapon); renderInventory(); });
  }
  if (d.kind === 'ammo') {
    const wid = d.name.includes('обрез') ? 'shotgun' : 'revolver';
    if (G.player.owned[wid]) add('Зарядить', () => { equipWeapon(wid); startReload(); renderInventory(); });
  }
  const self = selfRecipe(s.item);
  if (self && s.count >= 2) {
    add(`Скомбинировать → ${self.name}`, () => {
      const res = invCombineSelf(G.inv, s.uid);
      if (res && res.text) toast(res.text, !!res.failed);
      SFX.play(res && res.crafted ? 'heal' : 'deny');
      invUI.sel = null;
      renderInventory();
    });
  }
  add('Повернуть', () => { if (invUI.held == null) { invUI.held = s.uid; invUI.rot = s.rot; makeGhost(s); } rotateHeld(); renderInventory(); });
  add('Выбросить', () => {
    if (d.kind === 'weapon' && G.player.equipped === d.weapon) { toast('Оружие в руках не бросишь', true); return; }
    invRemoveUid(G.inv, s.uid);
    invUI.sel = null;
    SFX.play('ui');
    renderInventory(); updateHUD();
  });
}

function renderKeyItems() {
  const host = $('keyItems');
  host.innerHTML = '';
  const owned = Object.keys(G.keys).filter(k => G.keys[k]);
  if (!owned.length) { host.innerHTML = '<span style="color:#6d6555">Пока ничего</span>'; return; }
  for (const k of owned) {
    const d = KEY_ITEMS[k];
    host.appendChild(el('div', '', `${d.name} — ${d.desc}`));
  }
}

// --------------------------------------------------------------- shop UI
let shopTab = 'buy';

function openShop() {
  if (G.mode !== 'playing') return;
  G.mode = 'shop';
  Input.release();
  shopTab = 'buy';
  $('shopSay').textContent = pick(SHOP_LINES);
  renderShop();
  show($('shop'), true);
  show($('hud'), false);
  SFX.play('ui');
}

function closeShop() {
  if (G.mode !== 'shop') return;
  show($('shop'), false);
  show($('hud'), true);
  G.mode = 'playing';
  updateHUD();
}

function renderShop() {
  $('shopMoney').textContent = G.money;
  document.querySelectorAll('#shop .tab').forEach(t => t.classList.toggle('on', t.dataset.tab === shopTab));
  const list = $('shopList');
  list.innerHTML = '';

  const row = (icon, name, sub, price, enabled, onClick) => {
    const r = el('div', 'row' + (enabled ? '' : ' off'));
    r.appendChild(el('div', 'ic', icon));
    const nm = el('div', 'nm');
    nm.appendChild(document.createTextNode(name));
    if (sub) nm.appendChild(el('small', '', sub));
    r.appendChild(nm);
    r.appendChild(el('div', 'pr', price));
    if (enabled) r.addEventListener('click', onClick);
    list.appendChild(r);
  };

  if (shopTab === 'buy') {
    for (const st of SHOP_STOCK) {
      if (st.once && G.flags[st.once]) continue;
      const d = ITEMS[st.item];
      const can = G.money >= st.price;
      row(d.icon, `${d.name}${st.count > 1 ? ' ×' + st.count : ''}`, d.desc, `${st.price}`, can, () => {
        if (G.money < st.price) { SFX.play('deny'); return; }
        const added = invAdd(G.inv, st.item, st.count);
        if (added < st.count) {
          if (added > 0) invConsume(G.inv, st.item, added);
          toast('В кейсе нет места', true); SFX.play('deny'); return;
        }
        G.money -= st.price;
        if (st.once) G.flags[st.once] = true;
        if (d.kind === 'weapon') { G.player.owned[d.weapon] = true; toast(`${d.name} — теперь твой`); }
        SFX.play('coin');
        renderShop(); updateHUD();
      });
    }
    for (const up of CASE_UPGRADES) {
      if (G.inv.h >= up.rows) continue;
      const can = G.money >= up.price;
      row('🧰', up.name, up.desc, `${up.price}`, can, () => {
        if (G.money < up.price) { SFX.play('deny'); return; }
        G.money -= up.price;
        G.inv.h = up.rows;
        SFX.play('coin');
        toast('Кейс стал вместительнее');
        renderShop();
      });
      break;   // one step at a time
    }
  }

  if (shopTab === 'sell') {
    const sellable = G.inv.slots.filter(s => (ITEMS[s.item].sell || 0) > 0 &&
      !(ITEMS[s.item].kind === 'weapon'));
    if (!sellable.length) list.appendChild(el('div', 'row off', 'Нечего продать'));
    for (const s of sellable) {
      const d = ITEMS[s.item];
      const total = d.sell;
      row(d.icon, `${d.name}${s.count > 1 ? ' ×' + s.count : ''}`, 'Продать одну штуку', `+${total}`, true, () => {
        invConsume(G.inv, s.item, 1);
        G.money += total;
        SFX.play('coin');
        renderShop(); updateHUD();
      });
    }
  }

  if (shopTab === 'up') {
    let any = false;
    for (const wid of ['revolver', 'shotgun']) {
      if (!G.player.owned[wid]) continue;
      UPGRADES[wid].forEach((up, idx) => {
        const lvl = G.player.upg[wid][idx] || 0;
        if (lvl >= up.prices.length) return;
        any = true;
        const price = up.prices[lvl];
        const can = G.money >= price;
        row(WEAPONS[wid].icon, `${WEAPONS[wid].name}: ${up.name}`,
            `${up.desc} · уровень ${lvl + 1} из ${up.prices.length}`, `${price}`, can, () => {
          if (G.money < price) { SFX.play('deny'); return; }
          G.money -= price;
          G.player.upg[wid][idx] = lvl + 1;
          if (up.stat === 'mag') G.player.mag[wid] = Math.min(G.player.mag[wid], wstat(wid, 'mag'));
          SFX.play('coin');
          toast(`${WEAPONS[wid].name}: ${up.name}`);
          renderShop(); updateHUD();
        });
      });
    }
    if (!any) list.appendChild(el('div', 'row off', 'Улучшать нечего'));
  }
}

// --------------------------------------------------------------- note UI
function openNote(noteId) {
  const n = NOTES[noteId];
  if (!n) return;
  G.mode = 'note';
  Input.release();
  const p = $('notePaper');
  p.innerHTML = '';
  p.appendChild(el('h3', '', n.title));
  for (const para of n.body) p.appendChild(el('p', '', para));
  if (n.sign) p.appendChild(el('p', 'sig', '— ' + n.sign));
  show($('note'), true);
  show($('hud'), false);
  SFX.play('ui');
}

function closeNote() {
  if (G.mode !== 'note') return;
  show($('note'), false);
  show($('hud'), true);
  G.mode = 'playing';
}

// ------------------------------------------------------------ lockbox UI
let lockTarget = null, lockDials = [0, 0, 0], lockIdx = 0;

function openLockbox(inter) {
  G.mode = 'lockbox';
  lockTarget = inter;
  lockDials = [0, 0, 0];
  Input.release();
  renderDials();
  show($('lockbox'), true);
  show($('hud'), false);
  SFX.play('ui');
}

function closeLockbox() {
  if (G.mode !== 'lockbox') return;
  show($('lockbox'), false);
  show($('hud'), true);
  G.mode = 'playing';
  lockTarget = null;
}

function renderDials() {
  const host = $('dials');
  host.innerHTML = '';
  lockDials.forEach((v, i) => {
    const d = el('div', 'dial');
    const val = el('div', 'v' + (i === lockIdx ? ' on' : ''), String(v));
    d.appendChild(val);
    const up = el('button', 'btn small', '▲');
    up.addEventListener('click', () => { lockDials[i] = (v + 1) % 10; lockIdx = i; SFX.play('ui'); renderDials(); });
    const dn = el('button', 'btn small', '▼');
    dn.addEventListener('click', () => { lockDials[i] = (v + 9) % 10; lockIdx = i; SFX.play('ui'); renderDials(); });
    d.appendChild(up); d.appendChild(dn);
    host.appendChild(d);
  });
}

function tryLock() {
  if (!lockTarget) return;
  const code = lockTarget.code;
  if (lockDials.every((v, i) => v === code[i])) {
    SFX.play('save');
    toast('Замок поддался');
    takeInteractable(lockTarget, true);
    closeLockbox();
  } else {
    SFX.play('deny');
    $('lockHint').textContent = 'Засов не идёт. Цифры не те.';
  }
}
