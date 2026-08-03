// То же, что отдаёт сервер по /api/options, только собирается прямо в браузере.
// Экран создания персонажа общий для двух сборок, поэтому и данные для него
// должны иметь одинаковую форму.

import * as srd from '../server/engine/srd.js';
import * as characterModule from '../server/engine/character.js';
import * as state from '../server/engine/state.js';
import { BACKGROUNDS } from '../server/engine/kits.js';
import { SKILLS, SKILL_RU, ABILITY_RU } from '../server/engine/rules.js';

export function buildOptions() {
  return {
    races: srd.races.map((r) => ({
      index: r.index,
      name: srd.displayName(r),
      speed: r.speed,
      bonuses: (r.abilityBonuses || []).map((b) => `${ABILITY_RU[b.ability]} +${b.bonus}`),
      subraces: (r.subraces || []).map((s) => ({ index: s.index, name: srd.displayName(s) })),
    })),
    classes: srd.classes.map((c) => ({
      index: c.index,
      name: srd.displayName(c),
      hitDie: c.hitDie,
      saves: (c.savingThrows || []).map((s) => ABILITY_RU[s]),
      skillChoices: c.skillChoices?.[0] || { choose: 2, from: Object.keys(SKILLS) },
      caster: Boolean(c.spellcastingAbility),
    })),
    backgrounds: BACKGROUNDS.map((b) => ({
      index: b.index,
      name: b.name,
      skills: b.skills.map((s) => SKILL_RU[s]),
      feature: b.feature,
    })),
    skills: Object.entries(SKILLS).map(([index, ability]) => ({
      index,
      name: SKILL_RU[index],
      ability: ABILITY_RU[ability],
    })),
    pregens: characterModule.pregens(),
    standardArray: characterModule.STANDARD_ARRAY,
    tones: Object.entries(state.TONES).map(([key, desc]) => ({ key, desc })),
    difficulties: Object.entries(state.DIFFICULTIES).map(([key, desc]) => ({ key, desc })),
  };
}
