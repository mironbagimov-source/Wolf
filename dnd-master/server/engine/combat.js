// Combat: monster instances, initiative order, turn tracking, and attack /
// save resolution shared by player characters and monsters.
//
// The AI DM decides *who attacks whom*; every number that follows — the d20,
// the damage, whether it hits — is decided here.

import { randomUUID } from 'node:crypto';
import * as dice from './dice.js';
import * as srd from './srd.js';
import * as character from './character.js';
import { abilityMod, formatMod, DAMAGE_RU, CONDITION_RU, gridDistance, actionNameRu } from './rules.js';

/**
 * Rolls up a live copy of a monster. `count` instances get numbered names so
 * players can tell "Гоблин 2" from "Гоблин 3".
 */
export function spawnMonsters(monsterQuery, count = 1, { averageHp = false, nameSuffix = null } = {}) {
  const stat = srd.findMonster(monsterQuery);
  if (!stat) throw new Error(`Не нашёл монстра: ${monsterQuery}`);

  const out = [];
  for (let i = 0; i < Math.max(1, Math.min(20, count)); i += 1) {
    const hp = averageHp || !stat.hitDice ? stat.hp : Math.max(1, dice.roll(stat.hitDice).total);
    out.push({
      id: randomUUID(),
      kind: 'npc',
      monsterIndex: stat.index,
      name: count > 1 ? `${srd.displayName(stat)} ${i + 1}` : srd.displayName(stat) + (nameSuffix ? ` ${nameSuffix}` : ''),
      ac: stat.ac,
      hp: { current: hp, max: hp, temp: 0 },
      abilities: stat.abilities,
      cr: stat.cr,
      xp: stat.xp,
      conditions: [],
      hostile: true,
      dead: false,
      visible: true,
    });
  }
  return out;
}

/** Anything that can act: a player character or a monster instance. */
export function findCombatant(state, id) {
  const pc = state.party.find((c) => c.id === id);
  if (pc) return { kind: 'pc', ref: pc };
  const npc = state.npcs.find((n) => n.id === id);
  if (npc) return { kind: 'npc', ref: npc };
  return null;
}

/** Loose name matching so the DM can say "гоблин 2" instead of a UUID. */
export function resolveTarget(state, query) {
  if (!query) return null;
  const direct = findCombatant(state, query);
  if (direct) return direct;

  const norm = (s) => String(s).toLowerCase().replace(/ё/g, 'е').trim();
  const q = norm(query);
  const all = [
    ...state.party.map((ref) => ({ kind: 'pc', ref })),
    ...state.npcs.map((ref) => ({ kind: 'npc', ref })),
  ];
  return (
    all.find((c) => norm(c.ref.name) === q) ||
    all.find((c) => norm(c.ref.name).startsWith(q)) ||
    all.find((c) => norm(c.ref.name).includes(q)) ||
    null
  );
}

function initiativeModifier(combatant) {
  if (combatant.kind === 'pc') return combatant.ref.initiative ?? 0;
  return abilityMod(combatant.ref.abilities?.dex ?? 10);
}

/** Rolls initiative for everyone present and sets up the turn order. */
export function startCombat(state, { surprised = [] } = {}) {
  const entries = [
    ...state.party.filter((c) => !c.dead).map((ref) => ({ kind: 'pc', ref })),
    ...state.npcs.filter((n) => !n.dead && n.hostile !== false).map((ref) => ({ kind: 'npc', ref })),
  ];
  if (entries.length === 0) throw new Error('Некому вступать в бой');

  const order = entries
    .map((c) => {
      const roll = dice.d20Test({ modifier: initiativeModifier(c) });
      return {
        id: c.ref.id,
        name: c.ref.name,
        kind: c.kind,
        initiative: roll.total,
        tiebreak: c.kind === 'pc' ? initiativeModifier(c) + 0.5 : initiativeModifier(c),
        roll,
        surprised: surprised.some((s) => String(s).toLowerCase() === String(c.ref.name).toLowerCase() || s === c.ref.id),
      };
    })
    .sort((a, b) => b.initiative - a.initiative || b.tiebreak - a.tiebreak);

  state.combat = {
    active: true,
    round: 1,
    turnIndex: 0,
    order,
    log: [],
    startedAt: Date.now(),
  };
  return state.combat;
}

export function currentTurn(state) {
  const c = state.combat;
  if (!c?.active) return null;
  return c.order[c.turnIndex] || null;
}

/** Advances the turn, skipping the dead, and rolls the round counter over. */
export function nextTurn(state) {
  const c = state.combat;
  if (!c?.active) return null;

  for (let step = 0; step < c.order.length + 1; step += 1) {
    c.turnIndex += 1;
    if (c.turnIndex >= c.order.length) {
      c.turnIndex = 0;
      c.round += 1;
      // Surprise only lasts through the first round.
      for (const entry of c.order) entry.surprised = false;
    }
    const entry = c.order[c.turnIndex];
    const combatant = findCombatant(state, entry.id);
    if (combatant && !combatant.ref.dead) return entry;
  }
  return null;
}

export function endCombat(state) {
  const combat = state.combat;
  state.combat = { active: false, round: 0, turnIndex: 0, order: [] };
  // Clear anything that only existed for the fight.
  for (const npc of state.npcs) npc.conditions = [];
  return combat;
}

/** Removes defeated monsters from the order so it stays readable. */
export function pruneDefeated(state) {
  if (!state.combat?.active) return;
  const before = state.combat.order.length;
  const currentId = state.combat.order[state.combat.turnIndex]?.id;
  state.combat.order = state.combat.order.filter((entry) => {
    const c = findCombatant(state, entry.id);
    return c && !(c.kind === 'npc' && c.ref.dead);
  });
  if (state.combat.order.length !== before) {
    const idx = state.combat.order.findIndex((e) => e.id === currentId);
    state.combat.turnIndex = idx >= 0 ? idx : 0;
  }
  if (!state.combat.order.some((e) => findCombatant(state, e.id)?.kind === 'npc')) {
    state.combat.allEnemiesDown = true;
  }
}

// ------------------------------------------------------------ resolution

const acOf = (c) => (c.kind === 'pc' ? c.ref.ac : c.ref.ac);

function damageMultiplier(target, damageType) {
  if (target.kind !== 'npc' || !damageType) return 1;
  const stat = srd.monsterByIndex.get(target.ref.monsterIndex);
  if (!stat) return 1;
  const has = (list) => (list || []).some((entry) => String(entry).toLowerCase().includes(damageType));
  if (has(stat.immune)) return 0;
  if (has(stat.resist)) return 0.5;
  if (has(stat.vulnerable)) return 2;
  return 1;
}

/** Applies damage to either kind of combatant, honouring resistances. */
export function dealDamage(state, target, amount, damageType = null, { crit = false } = {}) {
  const multiplier = damageMultiplier(target, damageType);
  const final = Math.floor(amount * multiplier);

  if (target.kind === 'pc') {
    const result = character.applyDamage(target.ref, final, crit && target.ref.hp.current === 0 ? 'crit' : damageType);
    return { ...result, multiplier, damageType, final };
  }

  const npc = target.ref;
  let remaining = final;
  const absorbed = Math.min(npc.hp.temp || 0, remaining);
  npc.hp.temp = (npc.hp.temp || 0) - absorbed;
  remaining -= absorbed;
  npc.hp.current = Math.max(0, npc.hp.current - remaining);
  const dead = npc.hp.current === 0;
  if (dead) npc.dead = true;
  return {
    damage: final,
    multiplier,
    damageType,
    absorbedByTemp: absorbed,
    hp: npc.hp.current,
    maxHp: npc.hp.max,
    dead,
    final,
  };
}

/**
 * A full attack: to-hit roll, crit handling, damage, and the resulting state
 * change. `attack` is either a character attack entry or a monster action.
 */
export function resolveAttack(state, attackerRef, targetRef, attack, opts = {}) {
  const { advantage = false, disadvantage = false, bonusDamage = null } = opts;
  const targetAc = acOf(targetRef);
  const attackBonus = attack.attackBonus ?? 0;

  const roll = dice.d20Test({ modifier: attackBonus, advantage, disadvantage });
  const hit = roll.crit || (!roll.fumble && roll.total >= targetAc);

  const result = {
    attacker: attackerRef.ref.name,
    target: targetRef.ref.name,
    attackName: attack.name,
    roll,
    targetAc,
    hit,
    crit: roll.crit,
    fumble: roll.fumble,
    damage: null,
    damageRolls: [],
  };
  if (!hit) return result;

  // Damage. Critical hits double the dice, not the modifier.
  const parts = attack.damage
    ? [{ dice: attack.damage, type: attack.damageType }]
    : (attack.damageEntries || []).map((d) => ({ dice: d.dice, type: d.type }));
  if (bonusDamage) parts.push({ dice: bonusDamage.dice, type: bonusDamage.type });

  let total = 0;
  let primaryType = null;
  for (const part of parts) {
    if (!part.dice) continue;
    const expression = roll.crit ? doubleDice(part.dice) : part.dice;
    const damageRoll = dice.roll(expression);
    total += Math.max(0, damageRoll.total);
    primaryType = primaryType || part.type;
    result.damageRolls.push({ expression, type: part.type, ...damageRoll });
  }

  const applied = dealDamage(state, targetRef, total, primaryType, { crit: roll.crit });
  result.damage = applied;
  return result;
}

/** "1d8+3" -> "2d8+3" for a critical hit. */
export function doubleDice(expression) {
  return String(expression).replace(/(\d*)d(\d+)/gi, (_, count, faces) => {
    const n = count === '' ? 1 : Number(count);
    return `${n * 2}d${faces}`;
  });
}

/** A saving throw for either kind of combatant. */
export function saveThrow(combatant, ability, dc, { advantage = false, disadvantage = false } = {}) {
  let modifier;
  if (combatant.kind === 'pc') {
    modifier = combatant.ref.saves[ability] ?? 0;
  } else {
    const stat = srd.monsterByIndex.get(combatant.ref.monsterIndex);
    modifier = stat?.saves?.[ability] ?? abilityMod(combatant.ref.abilities?.[ability] ?? 10);
  }
  const roll = dice.d20Test({ modifier, advantage, disadvantage });
  return {
    name: combatant.ref.name,
    ability,
    dc,
    roll,
    success: roll.total >= dc,
  };
}

/** An ability check or skill check for either kind of combatant. */
export function abilityCheck(combatant, { ability, skill, dc, advantage = false, disadvantage = false }) {
  let modifier = 0;
  if (combatant.kind === 'pc') {
    modifier = skill ? combatant.ref.skillMods[skill] ?? 0 : combatant.ref.mods[ability] ?? 0;
  } else {
    const stat = srd.monsterByIndex.get(combatant.ref.monsterIndex);
    modifier = skill && stat?.skills?.[skill] !== undefined
      ? stat.skills[skill]
      : abilityMod(combatant.ref.abilities?.[ability] ?? 10);
  }
  const roll = dice.d20Test({ modifier, advantage, disadvantage });
  return {
    name: combatant.ref.name,
    ability,
    skill,
    dc,
    roll,
    success: dc === null || dc === undefined ? null : roll.total >= dc,
  };
}

/** Turns a monster's SRD action into the shape resolveAttack expects. */
export function monsterAttack(monsterIndex, actionName) {
  const stat = srd.monsterByIndex.get(monsterIndex);
  if (!stat) return null;
  const norm = (s) => String(s).toLowerCase();
  const action =
    (stat.actions || []).find((a) => norm(a.name) === norm(actionName)) ||
    (stat.actions || []).find((a) => norm(a.name).includes(norm(actionName))) ||
    (stat.actions || []).find((a) => a.attackBonus !== undefined);
  if (!action) return null;
  return {
    // Стат-блоки SRD англоязычные: «Slam» посреди русского лога режет глаз.
    name: actionNameRu(action.name),
    attackBonus: action.attackBonus,
    damageEntries: action.damage || [],
    desc: action.desc,
    dc: action.dc,
  };
}

/** Short human summary of the initiative order, for the DM's context. */
export function combatSummary(state) {
  const c = state.combat;
  if (!c?.active) return 'Боя нет.';
  const lines = [`Бой, раунд ${c.round}.`];
  c.order.forEach((entry, i) => {
    const combatant = findCombatant(state, entry.id);
    if (!combatant) return;
    const ref = combatant.ref;
    const marker = i === c.turnIndex ? '▶' : ' ';
    const hp =
      combatant.kind === 'pc'
        ? `${ref.hp.current}/${ref.hp.max} хп`
        : ref.dead
          ? 'повержен'
          : `${describeMonsterHealth(ref)}`;
    const conditions = ref.conditions?.length
      ? ` [${ref.conditions.map((x) => CONDITION_RU[x.name] || x.name).join(', ')}]`
      : '';
    lines.push(`${marker} ${entry.initiative} — ${ref.name} (${hp})${conditions}${entry.surprised ? ' [застигнут врасплох]' : ''}`);
  });
  return lines.join('\n');
}

/**
 * Players see monster health as a description, not a number — keeps the mystery
 * without hiding information the DM needs.
 */
export function describeMonsterHealth(npc) {
  const ratio = npc.hp.current / npc.hp.max;
  if (npc.dead || ratio <= 0) return 'повержен';
  if (ratio > 0.9) return 'невредим';
  if (ratio > 0.6) return 'слегка ранен';
  if (ratio > 0.3) return 'ранен';
  if (ratio > 0.1) return 'тяжело ранен';
  return 'на последнем издыхании';
}

export { gridDistance, formatMod, DAMAGE_RU };
