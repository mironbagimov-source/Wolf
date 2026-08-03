// Character sheets: creation, derived statistics, damage, healing and rests.
//
// A sheet is a plain serialisable object. Everything derived from it (AC, attack
// bonuses, spell slots, passive scores) is recomputed by `recompute` rather than
// stored by hand, so the AI DM can never leave a sheet in an inconsistent state
// by editing one number.

import { randomUUID } from 'node:crypto';
import * as srd from './srd.js';
import * as dice from './dice.js';
import {
  ABILITIES,
  SKILLS,
  SKILL_RU,
  ABILITY_RU,
  DAMAGE_RU,
  CONDITION_RU,
  abilityMod,
  proficiencyBonus,
  formatMod,
  armorClass,
  passiveScore,
  spellSaveDc,
  spellAttackBonus,
  hpPerLevel,
  levelForXp,
} from './rules.js';
import {
  CLASS_KITS,
  CLASS_SPELLS,
  ABILITY_PRIORITY,
  AUTO_EQUIP,
  PREGENS,
  BACKGROUNDS,
  BACKGROUND_BY_INDEX,
} from './kits.js';

export const STANDARD_ARRAY = [15, 14, 13, 12, 10, 8];

/** 4d6 keep highest 3, six times — the classic roll-up. */
export function rollAbilityScores() {
  return Array.from({ length: 6 }, () => dice.roll('4d6kh3').total);
}

/** Assigns an array of scores to abilities following the class's priority. */
export function assignScores(klass, scores) {
  const order = ABILITY_PRIORITY[klass] || ABILITIES;
  const sorted = [...scores].sort((a, b) => b - a);
  const out = {};
  order.forEach((ability, i) => {
    out[ability] = sorted[i] ?? 10;
  });
  return out;
}

function weaponProficiencySet(klass, race) {
  const set = { simple: false, martial: false, specific: new Set() };
  const entries = [...(klass?.proficiencies || [])];
  for (const trait of race?.traits || []) entries.push(trait);

  for (const raw of entries) {
    const name = String(raw).toLowerCase();
    if (name.includes('simple weapon')) set.simple = true;
    else if (name.includes('martial weapon')) set.martial = true;
    else set.specific.add(name.replace(/s$/, ''));
  }

  // Racial weapon training the SRD expresses as a trait name only.
  if (race?.index === 'dwarf') ['battleaxe', 'handaxe', 'light hammer', 'warhammer'].forEach((w) => set.specific.add(w));
  if (race?.index === 'elf') ['longsword', 'shortsword', 'shortbow', 'longbow'].forEach((w) => set.specific.add(w));
  return set;
}

function isProficientWithWeapon(item, profs) {
  if (!item || item.category !== 'weapon') return false;
  const cat = (item.weaponCategory || '').toLowerCase();
  if (cat === 'simple' && profs.simple) return true;
  if (cat === 'martial' && profs.martial) return true;
  const name = item.name.toLowerCase();
  for (const p of profs.specific) {
    if (name.includes(p) || p.includes(name)) return true;
  }
  return false;
}

function armorProficiencies(klass) {
  const list = (klass?.proficiencies || []).map((p) => String(p).toLowerCase());
  return {
    light: list.some((p) => p.includes('light armor')),
    medium: list.some((p) => p.includes('medium armor')),
    heavy: list.some((p) => p.includes('heavy armor')),
    shields: list.some((p) => p.includes('shield')),
  };
}

/** Spell slots for a class at a given level, straight out of the SRD table. */
export function spellSlots(classIndex, level) {
  const cls = srd.classByIndex.get(classIndex);
  const row = cls?.levels?.find((l) => l.level === level);
  const sc = row?.spellcasting;
  if (!sc) return {};
  const slots = {};
  for (let i = 1; i <= 9; i += 1) {
    const count = sc[`spell_slots_level_${i}`];
    if (count > 0) slots[i] = count;
  }
  return slots;
}

/**
 * Builds a fresh character. `spec` is what the creation UI collects; everything
 * else is derived.
 */
export function createCharacter(spec = {}) {
  const classIndex = spec.class || 'fighter';
  const raceIndex = spec.race || 'human';
  const cls = srd.classByIndex.get(classIndex);
  const race = srd.raceByIndex.get(raceIndex);
  if (!cls) throw new Error(`Неизвестный класс: ${classIndex}`);
  if (!race) throw new Error(`Неизвестная раса: ${raceIndex}`);

  const level = Math.max(1, Math.min(20, spec.level || 1));
  const base = spec.abilities || assignScores(classIndex, STANDARD_ARRAY);

  // Racial ability bonuses. Human's "+1 to everything" comes through the same
  // ability_bonuses list, so no special case is needed.
  const abilities = { ...base };
  for (const bonus of race.abilityBonuses || []) {
    abilities[bonus.ability] = (abilities[bonus.ability] || 10) + bonus.bonus;
  }
  const subrace = (race.subraces || []).find((s) => s.index === spec.subrace);
  for (const bonus of subrace?.abilityBonuses || []) {
    abilities[bonus.ability] = (abilities[bonus.ability] || 10) + bonus.bonus;
  }

  const background = BACKGROUND_BY_INDEX.get(spec.background) || BACKGROUND_BY_INDEX.get('acolyte');
  const allowedSkills = cls.skillChoices?.[0]?.from || Object.keys(SKILLS);
  const chosenSkills = (spec.skills || [])
    .filter((s) => SKILLS[s])
    .slice(0, (cls.skillChoices?.[0]?.choose || 2) + (background?.skills?.length || 0) + 2);
  const skills = new Set([...chosenSkills, ...(background?.skills || [])]);
  // Fill up to the class allowance if the player under-picked.
  const want = cls.skillChoices?.[0]?.choose || 2;
  for (const s of allowedSkills) {
    if ([...skills].filter((x) => allowedSkills.includes(x)).length >= want) break;
    skills.add(s);
  }

  const kit = CLASS_KITS[classIndex] || { equipment: [], gold: 10 };
  const inventory = kit.equipment.map(([index, qty]) => ({
    index,
    qty,
    equipped: AUTO_EQUIP.has(index),
  }));
  for (const [index, qty] of background?.equipment || []) {
    inventory.push({ index, qty, equipped: false });
  }

  const spellList = CLASS_SPELLS[classIndex] || { cantrips: [], known: [] };

  const character = {
    id: spec.id || randomUUID(),
    playerId: spec.playerId || null,
    playerName: spec.playerName || null,
    name: spec.name || 'Безымянный',
    pronouns: spec.pronouns || null,
    race: raceIndex,
    subrace: spec.subrace || null,
    class: classIndex,
    background: background?.index || null,
    alignment: spec.alignment || 'нейтральный',
    level,
    xp: spec.xp || 0,
    abilities,
    skills: [...skills],
    expertise: spec.expertise || [],
    inventory,
    gold: spec.gold ?? (kit.gold || 0) + (background?.gold || 0),
    spells: {
      cantrips: [...spellList.cantrips],
      known: [...spellList.known],
      slotsUsed: {},
    },
    hp: { current: 0, max: 0, temp: 0 },
    hitDice: { die: cls.hitDie, total: level, spent: 0 },
    conditions: [],
    exhaustion: 0,
    deathSaves: { successes: 0, failures: 0 },
    inspiration: false,
    concentration: null,
    portraitColor: spec.portraitColor || '#6b7280',
    blurb: spec.blurb || '',
    hook: spec.hook || '',
    notes: spec.notes || '',
  };

  recompute(character);
  character.hp.current = character.hp.max;
  return character;
}

/** Recomputes every derived number on the sheet. Safe to call at any time. */
export function recompute(ch) {
  const cls = srd.classByIndex.get(ch.class);
  const race = srd.raceByIndex.get(ch.race);
  const prof = proficiencyBonus(ch.level);
  ch.prof = prof;

  const mods = {};
  for (const a of ABILITIES) mods[a] = abilityMod(ch.abilities[a] ?? 10);
  ch.mods = mods;

  // Hit points: max hit die at level 1, average per level after.
  const conMod = mods.con;
  ch.hp.max = cls.hitDie + conMod + (ch.level - 1) * hpPerLevel(cls.hitDie, conMod);
  ch.hp.max = Math.max(1, ch.hp.max);
  ch.hp.current = Math.min(ch.hp.current ?? ch.hp.max, ch.hp.max);
  ch.hitDice.die = cls.hitDie;
  ch.hitDice.total = ch.level;

  // Armour class from what is actually worn.
  const equipped = ch.inventory.filter((i) => i.equipped).map((i) => srd.equipmentByIndex.get(i.index));
  const body = equipped.find((e) => e?.armor && e.armor.category !== 'Shield');
  const shield = equipped.some((e) => e?.index === 'shield');
  let ac = armorClass(body, mods.dex, shield);
  if (!body) {
    // Unarmoured defence for the two SRD classes that get it.
    if (ch.class === 'barbarian') ac = Math.max(ac, 10 + mods.dex + mods.con + (shield ? 2 : 0));
    if (ch.class === 'monk' && !shield) ac = Math.max(ac, 10 + mods.dex + mods.wis);
  }
  ch.ac = ac;
  ch.armorWorn = body ? srd.displayName(body) : 'без доспехов';

  ch.speed = race?.speed ?? 30;
  ch.initiative = mods.dex;
  ch.saves = {};
  for (const a of ABILITIES) {
    ch.saves[a] = mods[a] + ((cls.savingThrows || []).includes(a) ? prof : 0);
  }
  ch.skillMods = {};
  for (const [skill, ability] of Object.entries(SKILLS)) {
    const trained = ch.skills.includes(skill);
    const expert = ch.expertise?.includes(skill);
    ch.skillMods[skill] = mods[ability] + (trained ? prof : 0) + (expert ? prof : 0);
  }
  ch.passivePerception = passiveScore(ch.skillMods.perception);
  ch.passiveInvestigation = passiveScore(ch.skillMods.investigation);

  // Spellcasting.
  const ability = cls.spellcastingAbility;
  if (ability && ch.level >= (cls.spellcastingLevel || 1)) {
    ch.spellcasting = {
      ability,
      dc: spellSaveDc(prof, mods[ability]),
      attack: spellAttackBonus(prof, mods[ability]),
      slots: spellSlots(ch.class, ch.level),
    };
  } else {
    ch.spellcasting = null;
  }

  ch.attacks = buildAttacks(ch, { cls, race, mods, prof });
  return ch;
}

function buildAttacks(ch, { cls, race, mods, prof }) {
  const profs = weaponProficiencySet(cls, race);
  const out = [];
  const seen = new Set();

  for (const slot of ch.inventory) {
    const item = srd.equipmentByIndex.get(slot.index);
    if (!item || item.category !== 'weapon' || seen.has(item.index)) continue;
    seen.add(item.index);

    const props = item.properties || [];
    const ranged = item.weaponRange === 'Ranged';
    const finesse = props.includes('finesse');
    // Finesse and ranged weapons use Dexterity when it is the better score.
    const useDex = ranged || (finesse && mods.dex > mods.str);
    const abilityUsed = useDex ? 'dex' : 'str';
    const proficient = isProficientWithWeapon(item, profs);
    const mod = mods[abilityUsed];

    out.push({
      name: srd.displayName(item),
      index: item.index,
      ability: abilityUsed,
      proficient,
      attackBonus: mod + (proficient ? prof : 0),
      damage: item.damage ? `${item.damage.dice}${mod ? (mod > 0 ? `+${mod}` : mod) : ''}` : null,
      damageType: item.damage?.type,
      versatile: item.twoHandedDamage
        ? `${item.twoHandedDamage.dice}${mod ? (mod > 0 ? `+${mod}` : mod) : ''}`
        : null,
      range: item.range ? `${item.range.normal}${item.range.long ? `/${item.range.long}` : ''} фт.` : '5 фт.',
      properties: props,
    });
  }

  // Monks and anyone else can always punch.
  const unarmedDie = ch.class === 'monk' ? '1d4' : '1';
  out.push({
    name: 'Безоружный удар',
    index: 'unarmed',
    ability: 'str',
    proficient: true,
    attackBonus: mods.str + prof,
    damage: `${unarmedDie}${mods.str ? (mods.str > 0 ? `+${mods.str}` : mods.str) : ''}`,
    damageType: 'bludgeoning',
    range: '5 фт.',
    properties: [],
  });

  return out;
}

// ------------------------------------------------------------ hit points

/**
 * Applies damage. Returns what actually happened so the caller can narrate it
 * without re-deriving the rules.
 */
export function applyDamage(ch, amount, type = null) {
  const raw = Math.max(0, Math.floor(amount));
  let remaining = raw;
  let absorbed = 0;

  if (ch.hp.temp > 0) {
    absorbed = Math.min(ch.hp.temp, remaining);
    ch.hp.temp -= absorbed;
    remaining -= absorbed;
  }

  const before = ch.hp.current;
  ch.hp.current = Math.max(0, ch.hp.current - remaining);

  const result = {
    damage: raw,
    absorbedByTemp: absorbed,
    hp: ch.hp.current,
    maxHp: ch.hp.max,
    type,
    wasConscious: before > 0,
    unconscious: false,
    dead: false,
  };

  // Massive damage: leftover damage equal to the HP maximum kills outright.
  if (before > 0 && remaining - before >= ch.hp.max) {
    result.dead = true;
    markDead(ch);
    return result;
  }

  if (ch.hp.current === 0 && before > 0) {
    result.unconscious = true;
    addCondition(ch, 'unconscious', 'при 0 хитов');
    ch.deathSaves = { successes: 0, failures: 0 };
    ch.concentration = null;
  } else if (ch.hp.current === 0 && before === 0) {
    // Damage while already down is an automatic failed death save (two on a crit,
    // which the caller signals by passing a `crit` type marker).
    ch.deathSaves.failures += type === 'crit' ? 2 : 1;
    if (ch.deathSaves.failures >= 3) {
      result.dead = true;
      markDead(ch);
    }
  }

  if (ch.concentration && ch.hp.current > 0 && raw > 0) {
    result.concentrationDc = Math.max(10, Math.floor(raw / 2));
  }

  return result;
}

export function heal(ch, amount) {
  const before = ch.hp.current;
  const wasDown = before === 0;
  ch.hp.current = Math.min(ch.hp.max, ch.hp.current + Math.max(0, Math.floor(amount)));
  if (wasDown && ch.hp.current > 0) {
    removeCondition(ch, 'unconscious');
    ch.deathSaves = { successes: 0, failures: 0 };
    ch.dead = false;
  }
  return { healed: ch.hp.current - before, hp: ch.hp.current, maxHp: ch.hp.max, revived: wasDown && ch.hp.current > 0 };
}

export function addTempHp(ch, amount) {
  // Temporary hit points don't stack — you keep the better pool.
  ch.hp.temp = Math.max(ch.hp.temp, Math.max(0, Math.floor(amount)));
  return ch.hp.temp;
}

function markDead(ch) {
  ch.dead = true;
  ch.hp.current = 0;
  addCondition(ch, 'unconscious', 'мёртв');
}

/** One death saving throw. 20 wakes you at 1 HP; 1 counts as two failures. */
export function deathSave(ch) {
  const r = dice.d20Test({});
  const out = { roll: r, stabilized: false, dead: false, revived: false };

  if (r.natural === 20) {
    ch.deathSaves = { successes: 0, failures: 0 };
    heal(ch, 1);
    out.revived = true;
    return out;
  }
  if (r.natural === 1) ch.deathSaves.failures += 2;
  else if (r.total >= 10) ch.deathSaves.successes += 1;
  else ch.deathSaves.failures += 1;

  if (ch.deathSaves.successes >= 3) {
    ch.deathSaves = { successes: 0, failures: 0 };
    ch.stable = true;
    out.stabilized = true;
  }
  if (ch.deathSaves.failures >= 3) {
    markDead(ch);
    out.dead = true;
  }
  return out;
}

export function stabilize(ch) {
  ch.stable = true;
  ch.deathSaves = { successes: 0, failures: 0 };
}

// ------------------------------------------------------------ conditions

export function addCondition(ch, name, source = null, duration = null) {
  if (!ch.conditions.some((c) => c.name === name)) {
    ch.conditions.push({ name, source, duration });
  }
  return ch.conditions;
}

export function removeCondition(ch, name) {
  ch.conditions = ch.conditions.filter((c) => c.name !== name);
  return ch.conditions;
}

export function hasCondition(ch, name) {
  return ch.conditions.some((c) => c.name === name);
}

// ---------------------------------------------------------------- rests

/** Short rest: spend hit dice to heal. Returns each die rolled. */
export function shortRest(ch, diceToSpend = 1) {
  const available = ch.hitDice.total - ch.hitDice.spent;
  const spend = Math.max(0, Math.min(diceToSpend, available));
  const rolls = [];
  let healed = 0;
  for (let i = 0; i < spend; i += 1) {
    const r = dice.roll(`1d${ch.hitDice.die}`);
    const gain = Math.max(1, r.total + ch.mods.con);
    healed += gain;
    rolls.push({ roll: r.total, gain });
  }
  ch.hitDice.spent += spend;
  heal(ch, healed);
  // Warlocks recover their slots on a short rest.
  if (ch.class === 'warlock') ch.spells.slotsUsed = {};
  return { spent: spend, rolls, healed, hp: ch.hp.current };
}

export function longRest(ch) {
  ch.hp.current = ch.hp.max;
  ch.hp.temp = 0;
  // You regain up to half your total hit dice.
  ch.hitDice.spent = Math.max(0, ch.hitDice.spent - Math.max(1, Math.floor(ch.hitDice.total / 2)));
  ch.spells.slotsUsed = {};
  ch.deathSaves = { successes: 0, failures: 0 };
  ch.exhaustion = Math.max(0, ch.exhaustion - 1);
  ch.dead = false;
  ch.stable = false;
  removeCondition(ch, 'unconscious');
  return { hp: ch.hp.current, hitDiceAvailable: ch.hitDice.total - ch.hitDice.spent };
}

// ------------------------------------------------------------ spellcasting

export function useSpellSlot(ch, level) {
  if (!ch.spellcasting) return { ok: false, reason: 'персонаж не заклинатель' };
  const max = ch.spellcasting.slots[level] || 0;
  const used = ch.spells.slotsUsed[level] || 0;
  if (used >= max) return { ok: false, reason: `нет свободных ячеек ${level} круга` };
  ch.spells.slotsUsed[level] = used + 1;
  return { ok: true, remaining: max - used - 1 };
}

export function grantXp(ch, amount) {
  ch.xp += Math.max(0, Math.floor(amount));
  const newLevel = levelForXp(ch.xp);
  if (newLevel > ch.level) {
    const from = ch.level;
    ch.level = newLevel;
    const beforeMax = ch.hp.max;
    recompute(ch);
    heal(ch, ch.hp.max - beforeMax);
    return { leveledUp: true, from, to: newLevel };
  }
  return { leveledUp: false };
}

// ------------------------------------------------------------- rendering

/** Compact sheet for the DM's context — one screen, no filler. */
export function sheetText(ch) {
  const cls = srd.classByIndex.get(ch.class);
  const race = srd.raceByIndex.get(ch.race);
  const lines = [
    `${ch.name} — ${srd.displayName(race)} ${srd.displayName(cls)} ${ch.level} ур. (${ch.alignment})`,
    `ХП ${ch.hp.current}/${ch.hp.max}${ch.hp.temp ? ` (+${ch.hp.temp} врем.)` : ''} | КД ${ch.ac} | Скорость ${ch.speed} фт. | Инициатива ${formatMod(ch.initiative)} | БМ ${formatMod(ch.prof)}`,
    ABILITIES.map((a) => `${ABILITY_RU[a].slice(0, 3)} ${ch.abilities[a]} (${formatMod(ch.mods[a])})`).join('  '),
    `Спасброски: ${ABILITIES.map((a) => `${ABILITY_RU[a].slice(0, 3)} ${formatMod(ch.saves[a])}`).join(', ')}`,
    `Навыки (владение): ${ch.skills.map((s) => `${SKILL_RU[s]} ${formatMod(ch.skillMods[s])}`).join(', ') || '—'}`,
    `Пассивная Внимательность ${ch.passivePerception}`,
    `Атаки: ${ch.attacks
      .filter((a) => a.index !== 'unarmed')
      .map((a) => `${a.name} ${formatMod(a.attackBonus)}, урон ${a.damage} ${DAMAGE_RU[a.damageType] || ''}`)
      .join('; ') || '—'}`,
  ];
  if (ch.spellcasting) {
    const slots = Object.entries(ch.spellcasting.slots)
      .map(([lvl, max]) => `${lvl}кр: ${max - (ch.spells.slotsUsed[lvl] || 0)}/${max}`)
      .join(', ');
    lines.push(
      `Магия: ${ABILITY_RU[ch.spellcasting.ability]}, СЛ спасброска ${ch.spellcasting.dc}, атака ${formatMod(ch.spellcasting.attack)} | Ячейки: ${slots || '—'}`,
    );
    const named = (list) => list.map((i) => srd.displayName(srd.spellByIndex.get(i)) || i).join(', ');
    if (ch.spells.cantrips.length) lines.push(`Заговоры: ${named(ch.spells.cantrips)}`);
    if (ch.spells.known.length) lines.push(`Заклинания: ${named(ch.spells.known)}`);
  }
  if (ch.conditions.length) {
    lines.push(`Состояния: ${ch.conditions.map((c) => CONDITION_RU[c.name] || c.name).join(', ')}`);
  }
  if (ch.exhaustion) lines.push(`Истощение: ${ch.exhaustion}`);
  if (ch.hp.current === 0 && !ch.dead) {
    lines.push(`При смерти: успехи ${ch.deathSaves.successes}, провалы ${ch.deathSaves.failures}`);
  }
  if (ch.dead) lines.push('МЁРТВ');
  if (ch.hook) lines.push(`Зацепка: ${ch.hook}`);
  const carried = ch.inventory
    .map((i) => {
      const item = srd.equipmentByIndex.get(i.index) || srd.magicItemByIndex.get(i.index);
      return `${srd.displayName(item) || i.index}${i.qty > 1 ? ` ×${i.qty}` : ''}${i.equipped ? ' (надето)' : ''}`;
    })
    .join(', ');
  lines.push(`Снаряжение: ${carried || '—'} | ${ch.gold} зм`);
  return lines.join('\n');
}

/** Ready-to-use pre-made characters. */
export function pregens() {
  return PREGENS.map((p) => ({
    ...p,
    preview: {
      className: srd.displayName(srd.classByIndex.get(p.class)),
      raceName: srd.displayName(srd.raceByIndex.get(p.race)),
    },
  }));
}

export function createFromPregen(pregenId, { playerId, playerName, name } = {}) {
  const template = PREGENS.find((p) => p.id === pregenId);
  if (!template) throw new Error(`Нет такого готового персонажа: ${pregenId}`);
  return createCharacter({ ...template, id: undefined, name: name || template.name, playerId, playerName });
}
