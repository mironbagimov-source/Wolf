// Static 5e arithmetic: modifiers, proficiency, DCs, XP tables. No state, no
// randomness — everything here is a pure function so it can be unit-tested and
// so the AI can never talk the engine out of a number.

export const ABILITIES = ['str', 'dex', 'con', 'int', 'wis', 'cha'];

export const ABILITY_RU = {
  str: 'Сила',
  dex: 'Ловкость',
  con: 'Телосложение',
  int: 'Интеллект',
  wis: 'Мудрость',
  cha: 'Харизма',
};

/** Skill -> governing ability, as in the SRD skill list. */
export const SKILLS = {
  acrobatics: 'dex',
  'animal-handling': 'wis',
  arcana: 'int',
  athletics: 'str',
  deception: 'cha',
  history: 'int',
  insight: 'wis',
  intimidation: 'cha',
  investigation: 'int',
  medicine: 'wis',
  nature: 'int',
  perception: 'wis',
  performance: 'cha',
  persuasion: 'cha',
  religion: 'int',
  'sleight-of-hand': 'dex',
  stealth: 'dex',
  survival: 'wis',
};

export const SKILL_RU = {
  acrobatics: 'Акробатика',
  'animal-handling': 'Уход за животными',
  arcana: 'Магия',
  athletics: 'Атлетика',
  deception: 'Обман',
  history: 'История',
  insight: 'Проницательность',
  intimidation: 'Запугивание',
  investigation: 'Анализ',
  medicine: 'Медицина',
  nature: 'Природа',
  perception: 'Внимательность',
  performance: 'Выступление',
  persuasion: 'Убеждение',
  religion: 'Религия',
  'sleight-of-hand': 'Ловкость рук',
  stealth: 'Скрытность',
  survival: 'Выживание',
};

export const CONDITION_RU = {
  blinded: 'Ослеплён',
  charmed: 'Очарован',
  deafened: 'Оглушён',
  frightened: 'Испуган',
  grappled: 'Схвачен',
  incapacitated: 'Недееспособен',
  invisible: 'Невидим',
  paralyzed: 'Парализован',
  petrified: 'Окаменел',
  poisoned: 'Отравлен',
  prone: 'Сбит с ног',
  restrained: 'Опутан',
  stunned: 'Ошеломлён',
  unconscious: 'Без сознания',
  exhaustion: 'Истощение',
};

export const DAMAGE_RU = {
  acid: 'кислотный',
  bludgeoning: 'дробящий',
  cold: 'холод',
  fire: 'огонь',
  force: 'силовой',
  lightning: 'электричество',
  necrotic: 'некротический',
  piercing: 'колющий',
  poison: 'яд',
  psychic: 'психический',
  radiant: 'излучение',
  slashing: 'рубящий',
  thunder: 'звук',
};

export function abilityMod(score) {
  return Math.floor((Number(score) - 10) / 2);
}

export function proficiencyBonus(level) {
  return 2 + Math.floor((Math.max(1, Math.min(20, level)) - 1) / 4);
}

/** "+3" / "−1" — the minus is a real minus sign so it reads right in the UI. */
export function formatMod(value) {
  return value < 0 ? `−${Math.abs(value)}` : `+${value}`;
}

/** Passive score = 10 + modifier (+5 advantage / −5 disadvantage). */
export function passiveScore(modifier, { advantage = false, disadvantage = false } = {}) {
  return 10 + modifier + (advantage ? 5 : 0) - (disadvantage ? 5 : 0);
}

export const DIFFICULTY = {
  очень_легко: 5,
  легко: 10,
  средне: 15,
  сложно: 20,
  очень_сложно: 25,
  почти_невозможно: 30,
};

/** XP needed to reach each level (index = level). */
export const XP_THRESHOLDS = [
  0, 0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000, 85000, 100000,
  120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000,
];

export function levelForXp(xp) {
  let level = 1;
  for (let i = 2; i < XP_THRESHOLDS.length; i += 1) {
    if (xp >= XP_THRESHOLDS[i]) level = i;
  }
  return level;
}

/** XP award per monster of a given challenge rating. */
export const CR_XP = {
  0: 10,
  0.125: 25,
  0.25: 50,
  0.5: 100,
  1: 200,
  2: 450,
  3: 700,
  4: 1100,
  5: 1800,
  6: 2300,
  7: 2900,
  8: 3900,
  9: 5000,
  10: 5900,
  11: 7200,
  12: 8400,
  13: 10000,
  14: 11500,
  15: 13000,
  16: 15000,
  17: 18000,
  18: 20000,
  19: 22000,
  20: 25000,
  21: 33000,
  22: 41000,
  23: 50000,
  24: 62000,
  30: 155000,
};

export function xpForCr(cr) {
  return CR_XP[cr] ?? 0;
}

/** Adventuring-day budget per character, used to size encounters. */
export const ENCOUNTER_BUDGET = {
  1: { easy: 25, medium: 50, hard: 75, deadly: 100 },
  2: { easy: 50, medium: 100, hard: 150, deadly: 200 },
  3: { easy: 75, medium: 150, hard: 225, deadly: 400 },
  4: { easy: 125, medium: 250, hard: 375, deadly: 500 },
  5: { easy: 250, medium: 500, hard: 750, deadly: 1100 },
  6: { easy: 300, medium: 600, hard: 900, deadly: 1400 },
  7: { easy: 350, medium: 750, hard: 1100, deadly: 1700 },
  8: { easy: 450, medium: 900, hard: 1400, deadly: 2100 },
  9: { easy: 550, medium: 1100, hard: 1600, deadly: 2400 },
  10: { easy: 600, medium: 1200, hard: 1900, deadly: 2800 },
};

/** Multiplier applied to encounter XP when several monsters act together. */
export function encounterMultiplier(monsterCount) {
  if (monsterCount <= 1) return 1;
  if (monsterCount === 2) return 1.5;
  if (monsterCount <= 6) return 2;
  if (monsterCount <= 10) return 2.5;
  if (monsterCount <= 14) return 3;
  return 4;
}

/** Carrying capacity and the hit-die-based hit points at level 1. */
export function startingHp(hitDie, conMod) {
  return hitDie + conMod;
}

/** Average HP gained per level after 1st (5e "take the average" option). */
export function hpPerLevel(hitDie, conMod) {
  return Math.floor(hitDie / 2) + 1 + conMod;
}

export function spellSaveDc(profBonus, abilityModifier) {
  return 8 + profBonus + abilityModifier;
}

export function spellAttackBonus(profBonus, abilityModifier) {
  return profBonus + abilityModifier;
}

/** Armour class from an SRD armour entry plus the wearer's Dex modifier. */
export function armorClass(armorEntry, dexMod, shield = false) {
  let ac = 10 + dexMod;
  if (armorEntry?.armor) {
    const { base, dexBonus, maxDex } = armorEntry.armor;
    ac = base;
    if (dexBonus) ac += maxDex === null || maxDex === undefined ? dexMod : Math.min(dexMod, maxDex);
  }
  return ac + (shield ? 2 : 0);
}

/** Distance in feet between two grid squares (5e diagonal = 5 ft.). */
export function gridDistance(a, b) {
  return Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y)) * 5;
}
