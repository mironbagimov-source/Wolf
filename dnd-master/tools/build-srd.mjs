// Builds the compact SRD dataset the game engine reads at runtime.
//
// Source: https://github.com/5e-bits/5e-database (MIT-licensed tooling around
// the D&D 5e SRD 5.1, which Wizards of the Coast released under CC-BY-4.0).
// We only use the 2014/ (SRD 5.1) tree — it is the edition most Russian tables
// know, and unlike 2024/ it ships the class level tables we need for spell
// slots and proficiency progression.
//
// The upstream JSON is ~6 MB of API-shaped records with url/index cross-refs we
// don't need. This script strips it to the fields the engine actually reads and
// folds in Russian names (partly from the upstream ru/ locale, partly from
// tools/ru-names.mjs), so the committed data stays small and loads instantly.
//
// Usage:
//   node tools/build-srd.mjs                 # clones the source into a temp dir
//   node tools/build-srd.mjs --src <path>    # reuses an existing clone

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import * as ru from './ru-names.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(here, '..', 'server', 'data', 'srd');
const REPO = 'https://github.com/5e-bits/5e-database.git';

function resolveSource() {
  const flag = process.argv.indexOf('--src');
  if (flag !== -1 && process.argv[flag + 1]) return process.argv[flag + 1];

  const tmp = path.join(os.tmpdir(), '5e-database');
  if (!fs.existsSync(path.join(tmp, 'src'))) {
    console.log(`Клонирую ${REPO} в ${tmp} ...`);
    execFileSync('git', ['clone', '--depth', '1', REPO, tmp], { stdio: 'inherit' });
  }
  return tmp;
}

const src = resolveSource();
const enDir = path.join(src, 'src', '2014', 'en');
const ruDir = path.join(src, 'src', '2014', 'ru');
if (!fs.existsSync(enDir)) {
  console.error(`Не нахожу ${enDir}. Укажи путь к клону 5e-database через --src.`);
  process.exit(1);
}

const read = (dir, file) => JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
const readEn = (file) => read(enDir, `5e-SRD-${file}.json`);
const readRu = (file) => {
  const p = path.join(ruDir, `5e-SRD-${file}.json`);
  return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : [];
};

/** Builds an index -> russian name map from an upstream ru/ locale file. */
function ruMap(file) {
  const out = {};
  for (const row of readRu(file)) out[row.index] = row.name;
  return out;
}

const nameOf = (ref) => (ref ? ref.name : undefined);
const indexOf = (ref) => (ref ? ref.index : undefined);
const compact = (obj) => {
  // Drops undefined / null / empty-array / empty-object fields so the emitted
  // JSON stays readable and small.
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    if (Array.isArray(v) && v.length === 0) continue;
    if (typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length === 0) continue;
    out[k] = v;
  }
  return out;
};

// ---------------------------------------------------------------- monsters

/** "30 ft." -> 30, "40 ft. (hover)" -> 40. Feet are the engine's unit. */
function feet(value) {
  if (typeof value === 'number') return value;
  if (typeof value !== 'string') return undefined;
  const m = value.match(/(\d+)/);
  return m ? Number(m[1]) : undefined;
}

function monsterSpeed(speed = {}) {
  const out = {};
  for (const [mode, value] of Object.entries(speed)) {
    const ft = feet(value);
    if (ft !== undefined) out[mode] = ft;
    else out[mode] = value; // e.g. hover: true
  }
  return out;
}

/** Splits the proficiencies array into saving throws and skills. */
function monsterProficiencies(list = []) {
  const saves = {};
  const skills = {};
  for (const p of list) {
    const idx = indexOf(p.proficiency) || '';
    if (idx.startsWith('saving-throw-')) saves[idx.replace('saving-throw-', '')] = p.value;
    else if (idx.startsWith('skill-')) skills[idx.replace('skill-', '')] = p.value;
  }
  return { saves, skills };
}

function damageEntries(list = []) {
  return list
    .map((d) => {
      if (d.damage_dice) {
        return compact({ dice: d.damage_dice, type: indexOf(d.damage_type) });
      }
      // Some actions nest damage under from/choose options; keep the raw notes.
      return null;
    })
    .filter(Boolean);
}

function monsterActions(list = []) {
  return list.map((a) =>
    compact({
      name: a.name,
      desc: a.desc,
      attackBonus: a.attack_bonus,
      damage: damageEntries(a.damage),
      dc: a.dc
        ? compact({ type: indexOf(a.dc.dc_type), value: a.dc.dc_value, success: a.dc.success_type })
        : undefined,
      usage: a.usage ? compact({ type: a.usage.type, times: a.usage.times, dice: a.usage.dice, minValue: a.usage.min_value }) : undefined,
      options: a.actions?.length ? a.actions.map((x) => x.action_name) : undefined,
      multiattackType: a.multiattack_type,
    }),
  );
}

function buildMonsters() {
  return readEn('Monsters').map((m) => {
    const { saves, skills } = monsterProficiencies(m.proficiencies);
    const acEntry = Array.isArray(m.armor_class) ? m.armor_class[0] : undefined;
    return compact({
      index: m.index,
      name: m.name,
      ru: ru.monsters[m.index],
      size: m.size,
      type: m.type,
      subtype: m.subtype,
      alignment: m.alignment,
      ac: acEntry?.value,
      acNote: acEntry?.type === 'armor' ? acEntry.armor?.map(nameOf).join(', ') : acEntry?.type,
      hp: m.hit_points,
      hitDice: m.hit_points_roll || m.hit_dice,
      speed: monsterSpeed(m.speed),
      abilities: {
        str: m.strength,
        dex: m.dexterity,
        con: m.constitution,
        int: m.intelligence,
        wis: m.wisdom,
        cha: m.charisma,
      },
      saves,
      skills,
      senses: m.senses,
      languages: m.languages,
      cr: m.challenge_rating,
      xp: m.xp,
      prof: m.proficiency_bonus,
      vulnerable: m.damage_vulnerabilities,
      resist: m.damage_resistances,
      immune: m.damage_immunities,
      condImmune: (m.condition_immunities || []).map(indexOf),
      traits: (m.special_abilities || []).map((t) =>
        compact({ name: t.name, desc: t.desc, usage: t.usage?.type ? compact({ type: t.usage.type, times: t.usage.times }) : undefined }),
      ),
      actions: monsterActions(m.actions),
      reactions: monsterActions(m.reactions),
      legendary: monsterActions(m.legendary_actions),
    });
  });
}

// ----------------------------------------------------------------- spells

function buildSpells() {
  return readEn('Spells').map((s) =>
    compact({
      index: s.index,
      name: s.name,
      ru: ru.spells[s.index],
      level: s.level,
      school: indexOf(s.school),
      castingTime: s.casting_time,
      range: s.range,
      components: s.components,
      material: s.material,
      duration: s.duration,
      concentration: s.concentration || undefined,
      ritual: s.ritual || undefined,
      desc: Array.isArray(s.desc) ? s.desc.join('\n') : s.desc,
      higher: Array.isArray(s.higher_level) ? s.higher_level.join('\n') : s.higher_level,
      classes: (s.classes || []).map(indexOf),
      attackType: s.attack_type,
      damage: s.damage
        ? compact({
            type: indexOf(s.damage.damage_type),
            atSlot: s.damage.damage_at_slot_level,
            atLevel: s.damage.damage_at_character_level,
          })
        : undefined,
      heal: s.heal_at_slot_level,
      dc: s.dc ? compact({ type: indexOf(s.dc.dc_type), success: s.dc.dc_success }) : undefined,
      area: s.area_of_effect ? compact({ type: s.area_of_effect.type, size: s.area_of_effect.size }) : undefined,
    }),
  );
}

// -------------------------------------------------------------- equipment

function buildEquipment() {
  return readEn('Equipment').map((e) => {
    const cat = indexOf(e.equipment_category);
    return compact({
      index: e.index,
      name: e.name,
      ru: ru.equipment[e.index],
      category: cat,
      gearCategory: indexOf(e.gear_category),
      weaponCategory: e.weapon_category,
      weaponRange: e.weapon_range,
      damage: e.damage
        ? compact({ dice: e.damage.damage_dice, type: indexOf(e.damage.damage_type) })
        : undefined,
      twoHandedDamage: e.two_handed_damage
        ? compact({ dice: e.two_handed_damage.damage_dice, type: indexOf(e.two_handed_damage.damage_type) })
        : undefined,
      range: e.range,
      throwRange: e.throw_range,
      properties: (e.properties || []).map(indexOf),
      armor: e.armor_class
        ? compact({
            base: e.armor_class.base,
            dexBonus: e.armor_class.dex_bonus,
            maxDex: e.armor_class.max_bonus,
            category: e.armor_category,
            strMin: e.str_minimum || undefined,
            stealthDisadvantage: e.stealth_disadvantage || undefined,
          })
        : undefined,
      cost: e.cost ? `${e.cost.quantity} ${e.cost.unit}` : undefined,
      weight: e.weight,
      desc: Array.isArray(e.desc) && e.desc.length ? e.desc.join('\n') : undefined,
      contents: (e.contents || []).map((c) => ({ item: indexOf(c.item), qty: c.quantity })),
    });
  });
}

// ------------------------------------------------------- classes & levels

function buildClasses() {
  const levels = readEn('Levels');
  const byClass = new Map();
  for (const lvl of levels) {
    const cls = indexOf(lvl.class);
    if (!cls || lvl.subclass) continue;
    if (!byClass.has(cls)) byClass.set(cls, []);
    byClass.get(cls).push(
      compact({
        level: lvl.level,
        prof: lvl.prof_bonus,
        features: (lvl.features || []).map(nameOf),
        asi: lvl.ability_score_bonuses || undefined,
        classSpecific: lvl.class_specific,
        spellcasting: lvl.spellcasting,
      }),
    );
  }

  return readEn('Classes').map((c) =>
    compact({
      index: c.index,
      name: c.name,
      ru: ru.classes[c.index],
      hitDie: c.hit_die,
      savingThrows: (c.saving_throws || []).map(indexOf),
      // Armour / weapon / tool proficiencies granted to everyone in the class.
      proficiencies: (c.proficiencies || []).map(nameOf),
      // The "choose N skills from ..." block, flattened to skill indexes.
      skillChoices: (c.proficiency_choices || [])
        .filter((ch) => ch.from?.options?.some((o) => indexOf(o.item)?.startsWith('skill-')))
        .map((ch) => ({
          choose: ch.choose,
          from: ch.from.options
            .map((o) => indexOf(o.item))
            .filter((i) => i?.startsWith('skill-'))
            .map((i) => i.replace('skill-', '')),
        })),
      startingEquipment: (c.starting_equipment || []).map((s) => ({
        item: indexOf(s.equipment),
        qty: s.quantity,
      })),
      spellcastingAbility: c.spellcasting ? indexOf(c.spellcasting.spellcasting_ability) : undefined,
      spellcastingLevel: c.spellcasting?.level,
      levels: byClass.get(c.index) || [],
    }),
  );
}

// -------------------------------------------------------- races & origins

function buildRaces() {
  const subraces = readEn('Subraces');
  return readEn('Races').map((r) =>
    compact({
      index: r.index,
      name: r.name,
      ru: ru.races[r.index],
      speed: r.speed,
      size: r.size,
      abilityBonuses: (r.ability_bonuses || []).map((b) => ({
        ability: indexOf(b.ability_score),
        bonus: b.bonus,
      })),
      abilityBonusOptions: r.ability_bonus_options
        ? {
            choose: r.ability_bonus_options.choose,
            from: (r.ability_bonus_options.from?.options || []).map((o) => indexOf(o.ability_score)),
          }
        : undefined,
      languages: (r.languages || []).map(nameOf),
      traits: (r.traits || []).map(nameOf),
      subraces: subraces
        .filter((s) => indexOf(s.race) === r.index)
        .map((s) =>
          compact({
            index: s.index,
            name: s.name,
            ru: ru.subraces[s.index],
            desc: s.desc,
            abilityBonuses: (s.ability_bonuses || []).map((b) => ({
              ability: indexOf(b.ability_score),
              bonus: b.bonus,
            })),
            traits: (s.racial_traits || []).map(nameOf),
          }),
        ),
    }),
  );
}

function buildBackgrounds() {
  return readEn('Backgrounds').map((b) =>
    compact({
      index: b.index,
      name: b.name,
      ru: ru.backgrounds[b.index],
      skills: (b.starting_proficiencies || [])
        .map(indexOf)
        .filter((i) => i?.startsWith('skill-'))
        .map((i) => i.replace('skill-', '')),
      equipment: (b.starting_equipment || []).map((s) => ({ item: indexOf(s.equipment), qty: s.quantity })),
      gold: b.starting_gold?.quantity,
      feature: b.feature ? { name: b.feature.name, desc: (b.feature.desc || []).join('\n') } : undefined,
    }),
  );
}

// --------------------------------------------------------------- lookups

function buildReference() {
  const conditionsRu = ruMap('Conditions');
  const skillsRu = ruMap('Skills');
  const abilitiesRu = ruMap('Ability-Scores');
  const damageRu = ruMap('Damage-Types');
  const alignmentsRu = ruMap('Alignments');
  const languagesRu = ruMap('Languages');
  const schoolsRu = ruMap('Magic-Schools');
  const propertiesRu = ruMap('Weapon-Properties');

  return {
    conditions: readEn('Conditions').map((c) =>
      compact({ index: c.index, name: c.name, ru: conditionsRu[c.index], desc: (c.desc || []).join('\n') }),
    ),
    skills: readEn('Skills').map((s) =>
      compact({
        index: s.index,
        name: s.name,
        ru: skillsRu[s.index],
        ability: indexOf(s.ability_score),
        desc: (s.desc || []).join('\n'),
      }),
    ),
    abilities: readEn('Ability-Scores').map((a) =>
      compact({ index: a.index, name: a.full_name, ru: abilitiesRu[a.index], skills: (a.skills || []).map(indexOf) }),
    ),
    damageTypes: readEn('Damage-Types').map((d) =>
      compact({ index: d.index, name: d.name, ru: damageRu[d.index] }),
    ),
    alignments: readEn('Alignments').map((a) =>
      compact({ index: a.index, name: a.name, ru: alignmentsRu[a.index], abbr: a.abbreviation }),
    ),
    languages: readEn('Languages').map((l) =>
      compact({ index: l.index, name: l.name, ru: languagesRu[l.index], type: l.type }),
    ),
    schools: readEn('Magic-Schools').map((s) =>
      compact({ index: s.index, name: s.name, ru: schoolsRu[s.index] || ru.schools[s.index], desc: s.desc }),
    ),
    weaponProperties: readEn('Weapon-Properties').map((p) =>
      compact({ index: p.index, name: p.name, ru: propertiesRu[p.index], desc: (p.desc || []).join('\n') }),
    ),
    creatureTypes: ru.creatureTypes,
    sizes: ru.sizes,
  };
}

function buildMagicItems() {
  return readEn('Magic-Items').map((m) =>
    compact({
      index: m.index,
      name: m.name,
      ru: ru.magicItems[m.index],
      category: indexOf(m.equipment_category),
      rarity: m.rarity?.name,
      variants: (m.variants || []).map(indexOf),
      desc: (m.desc || []).join('\n'),
    }),
  );
}

function buildRules() {
  const sections = readEn('Rule-Sections').map((s) =>
    compact({ index: s.index, name: s.name, desc: s.desc }),
  );
  return sections;
}

// ------------------------------------------------------------------ main

fs.mkdirSync(outDir, { recursive: true });

const bundles = {
  monsters: buildMonsters(),
  spells: buildSpells(),
  equipment: buildEquipment(),
  classes: buildClasses(),
  races: buildRaces(),
  backgrounds: buildBackgrounds(),
  'magic-items': buildMagicItems(),
  rules: buildRules(),
  reference: buildReference(),
};

for (const [name, data] of Object.entries(bundles)) {
  const file = path.join(outDir, `${name}.json`);
  fs.writeFileSync(file, JSON.stringify(data));
  const size = (fs.statSync(file).size / 1024).toFixed(0);
  const count = Array.isArray(data) ? data.length : Object.keys(data).length;
  console.log(`${name.padEnd(14)} ${String(count).padStart(4)} записей  ${size} КБ`);
}

fs.writeFileSync(
  path.join(outDir, 'LICENSE.md'),
  `# Источник данных

Файлы в этой папке собраны скриптом \`tools/build-srd.mjs\` из репозитория
[5e-bits/5e-database](https://github.com/5e-bits/5e-database) (MIT).

Сам игровой контент — System Reference Document 5.1 от Wizards of the Coast,
опубликованный под лицензией **Creative Commons Attribution 4.0 International
(CC-BY-4.0)**: https://creativecommons.org/licenses/by/4.0/legalcode

Требуемая атрибуция:

> This work includes material taken from the System Reference Document 5.1
> ("SRD 5.1") by Wizards of the Coast LLC and available at
> https://dnd.wizards.com/resources/systems-reference-document.
> The SRD 5.1 is licensed under the Creative Commons Attribution 4.0
> International License available at
> https://creativecommons.org/licenses/by/4.0/legalcode.

Русские названия из \`tools/ru-names.mjs\` — часть этого проекта.
`,
);

console.log(`\nГотово: ${outDir}`);
