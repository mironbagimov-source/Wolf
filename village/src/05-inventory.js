'use strict';
// ---------------------------------------------------------------------
// The case: a Resident-Evil-style grid where every item has a footprint,
// can be rotated, and space itself is a resource. Nothing here touches the
// DOM — the UI module renders whatever this model says.
// ---------------------------------------------------------------------

let _uid = 1;

function makeInventory(w, h) {
  return { w, h, slots: [] };
}

function itemDef(id) { return ITEMS[id]; }

function slotSize(slot) {
  const d = ITEMS[slot.item];
  return slot.rot ? { w: d.h, h: d.w } : { w: d.w, h: d.h };
}

function sizeOf(itemId, rot) {
  const d = ITEMS[itemId];
  return rot ? { w: d.h, h: d.w } : { w: d.w, h: d.h };
}

function overlaps(ax, ay, aw, ah, bx, by, bw, bh) {
  return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
}

function fits(inv, itemId, rot, x, y, ignoreUid) {
  const s = sizeOf(itemId, rot);
  if (x < 0 || y < 0 || x + s.w > inv.w || y + s.h > inv.h) return false;
  for (const sl of inv.slots) {
    if (sl.uid === ignoreUid) continue;
    const ss = slotSize(sl);
    if (overlaps(x, y, s.w, s.h, sl.x, sl.y, ss.w, ss.h)) return false;
  }
  return true;
}

// Row-major scan, unrotated first — keeps the case tidy without the player
// having to think about packing until it actually gets tight.
function findSpot(inv, itemId) {
  for (const rot of [0, 1]) {
    const s = sizeOf(itemId, rot);
    if (s.w === sizeOf(itemId, 0).w && rot === 1 && s.h === sizeOf(itemId, 0).h) continue; // square: skip dup pass
    for (let y = 0; y <= inv.h - s.h; y++) {
      for (let x = 0; x <= inv.w - s.w; x++) {
        if (fits(inv, itemId, rot, x, y)) return { x, y, rot };
      }
    }
  }
  return null;
}

function countOf(inv, itemId) {
  let n = 0;
  for (const s of inv.slots) if (s.item === itemId) n += s.count;
  return n;
}

function freeCells(inv) {
  let used = 0;
  for (const s of inv.slots) { const ss = slotSize(s); used += ss.w * ss.h; }
  return inv.w * inv.h - used;
}

// Returns how many actually went in (stacking into partial slots first).
function invAdd(inv, itemId, count) {
  const d = ITEMS[itemId];
  if (!d) return 0;
  let left = count == null ? 1 : count;
  let added = 0;

  if (d.stack > 1) {
    for (const s of inv.slots) {
      if (left <= 0) break;
      if (s.item !== itemId || s.count >= d.stack) continue;
      const room = d.stack - s.count;
      const take = Math.min(room, left);
      s.count += take; left -= take; added += take;
    }
  }
  while (left > 0) {
    const spot = findSpot(inv, itemId);
    if (!spot) break;
    const take = Math.min(d.stack, left);
    inv.slots.push({ uid: _uid++, item: itemId, count: take, x: spot.x, y: spot.y, rot: spot.rot });
    left -= take; added += take;
  }
  return added;
}

function invRemoveUid(inv, uid) {
  const i = inv.slots.findIndex(s => s.uid === uid);
  if (i >= 0) return inv.slots.splice(i, 1)[0];
  return null;
}

// Spends `count` of an item across slots; returns how many were actually spent.
function invConsume(inv, itemId, count) {
  let need = count == null ? 1 : count, spent = 0;
  for (let i = inv.slots.length - 1; i >= 0 && need > 0; i--) {
    const s = inv.slots[i];
    if (s.item !== itemId) continue;
    const take = Math.min(s.count, need);
    s.count -= take; need -= take; spent += take;
    if (s.count <= 0) inv.slots.splice(i, 1);
  }
  return spent;
}

function slotAt(inv, x, y) {
  for (const s of inv.slots) {
    const ss = slotSize(s);
    if (x >= s.x && x < s.x + ss.w && y >= s.y && y < s.y + ss.h) return s;
  }
  return null;
}

function slotByUid(inv, uid) { return inv.slots.find(s => s.uid === uid) || null; }

function invMove(inv, uid, x, y, rot) {
  const s = slotByUid(inv, uid);
  if (!s) return false;
  if (!fits(inv, s.item, rot, x, y, uid)) return false;
  s.x = x; s.y = y; s.rot = rot;
  return true;
}

// Dropping A onto B: same item merges the stacks, otherwise a recipe may fire.
// Returns a string describing what happened, or null when nothing applies.
// A recipe whose two ingredients are the same item (herb + herb). Those stack
// into a single slot, so there is no second slot to drag onto — the case UI
// offers a button instead, and it lands here.
function selfRecipe(itemId) {
  return RECIPES.find(r => r.a === itemId && r.b === itemId) || null;
}

function invCombineSelf(inv, uid) {
  const s = slotByUid(inv, uid);
  if (!s) return null;
  const r = selfRecipe(s.item);
  if (!r || s.count < 2) return null;

  const saved = { ...s };
  s.count -= 2;
  if (s.count <= 0) invRemoveUid(inv, s.uid);
  const added = invAdd(inv, r.out, r.count);
  if (added >= r.count) return { crafted: true, text: `Собрано: ${r.name} ×${added}` };

  if (added > 0) invConsume(inv, r.out, added);
  restoreSlot(inv, saved);
  return { failed: true, text: 'В кейсе нет места' };
}

function invCombine(inv, uidA, uidB) {
  if (uidA === uidB) return invCombineSelf(inv, uidA);
  const a = slotByUid(inv, uidA), b = slotByUid(inv, uidB);
  if (!a || !b || a === b) return null;

  if (a.item === b.item) {
    const d = ITEMS[a.item];
    if (d.stack <= 1) return null;
    const room = d.stack - b.count;
    if (room <= 0) return null;
    const move = Math.min(room, a.count);
    b.count += move; a.count -= move;
    if (a.count <= 0) invRemoveUid(inv, a.uid);
    return { merged: true, text: null };
  }

  for (const r of RECIPES) {
    const match = (r.a === a.item && r.b === b.item) || (r.a === b.item && r.b === a.item);
    if (!match) continue;
    // Both ingredients are spent one unit at a time; craft as many as fit.
    const x = a.item === r.a ? a : b;
    const y = a.item === r.a ? b : a;
    const batches = Math.min(x.count, y.count);
    if (batches < 1) return null;

    let made = 0, used = 0;
    for (let i = 0; i < batches; i++) {
      const got = invAddAfterFreeing(inv, r.out, r.count, x, y);
      if (!got) break;
      made += r.count; used++;
    }
    if (!used) return { failed: true, text: 'В кейсе нет места' };
    return { crafted: true, text: `Собрано: ${r.name} ×${made}` };
  }
  return null;
}

// Crafting consumes before it produces, so the freed cells count as space —
// otherwise two herbs in a full case could never become a brew.
function invAddAfterFreeing(inv, outId, outCount, x, y) {
  const savedX = { ...x }, savedY = { ...y };
  x.count--; if (x.count <= 0) invRemoveUid(inv, x.uid);
  y.count--; if (y.count <= 0) invRemoveUid(inv, y.uid);

  const added = invAdd(inv, outId, outCount);
  if (added >= outCount) return true;

  // Roll back: put the ingredients where they were.
  if (added > 0) invConsume(inv, outId, added);
  restoreSlot(inv, savedX);
  restoreSlot(inv, savedY);
  return false;
}

function restoreSlot(inv, saved) {
  const live = slotByUid(inv, saved.uid);
  if (live) { live.count = saved.count; return; }
  if (fits(inv, saved.item, saved.rot, saved.x, saved.y)) {
    inv.slots.push({ ...saved });
  } else {
    invAdd(inv, saved.item, saved.count);
  }
}

function invSerialize(inv) {
  return { w: inv.w, h: inv.h, slots: inv.slots.map(s => ({ i: s.item, c: s.count, x: s.x, y: s.y, r: s.rot })) };
}
function invDeserialize(data) {
  const inv = makeInventory(data.w, data.h);
  inv.slots = (data.slots || [])
    .filter(s => ITEMS[s.i])
    .map(s => ({ uid: _uid++, item: s.i, count: s.c, x: s.x, y: s.y, rot: s.r }));
  return inv;
}
