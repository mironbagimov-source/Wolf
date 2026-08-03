// Loads the compact SRD bundles from server/data/srd and exposes lookup,
// bilingual search and stat-block formatting.
//
// Two consumers with different needs:
//   - the engine wants structured records (HP, AC, damage dice);
//   - the AI DM wants short text blocks it can read without burning context.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ABILITY_RU, SKILL_RU, DAMAGE_RU, abilityMod, formatMod } from './rules.js';

const dataDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'data', 'srd');

function load(name) {
  const file = path.join(dataDir, `${name}.json`);
  if (!fs.existsSync(file)) {
    throw new Error(
      `Нет файла ${file}. Собери базу SRD: npm run build:srd`,
    );
  }
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

export const monsters = load('monsters');
export const spells = load('spells');
export const equipment = load('equipment');
export const classes = load('classes');
export const races = load('races');
export const backgrounds = load('backgrounds');
export const magicItems = load('magic-items');
export const rules = load('rules');
export const reference = load('reference');

const byIndex = (list) => new Map(list.map((e) => [e.index, e]));

export const monsterByIndex = byIndex(monsters);
export const spellByIndex = byIndex(spells);
export const equipmentByIndex = byIndex(equipment);
export const classByIndex = byIndex(classes);
export const raceByIndex = byIndex(races);
export const backgroundByIndex = byIndex(backgrounds);
export const magicItemByIndex = byIndex(magicItems);
export const conditionByIndex = byIndex(reference.conditions);
export const skillByIndex = byIndex(reference.skills);

/** Display name: Russian when we have it, English otherwise. */
export function displayName(entry) {
  if (!entry) return '';
  return entry.ru || entry.name;
}

const normalize = (s) =>
  String(s || '')
    .toLowerCase()
    .replace(/ё/g, 'е')
    .replace(/[^a-zа-я0-9 ]/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();

function scoreMatch(entry, query) {
  const q = normalize(query);
  if (!q) return 0;
  const candidates = [entry.index, entry.name, entry.ru].filter(Boolean).map(normalize);
  let best = 0;
  for (const c of candidates) {
    if (c === q) return 100;
    if (c.startsWith(q)) best = Math.max(best, 80);
    else if (c.includes(q)) best = Math.max(best, 60);
    else {
      // Every query word present somewhere counts as a weak match.
      const words = q.split(' ');
      if (words.length > 1 && words.every((w) => c.includes(w))) best = Math.max(best, 40);
      // Russian inflects, so exact substrings miss a lot: «опутан» never
      // contains «опутывание». Matching on a shared stem catches those.
      else if (words.every((w) => sharesStem(w, c))) best = Math.max(best, 30);
      // Last resort: one matching stem out of several words. Noisy, but the
      // caller shows a few ranked results, and a miss is worse than noise.
      else if (words.some((w) => w.length >= 4 && sharesStem(w, c))) best = Math.max(best, 15);
    }
  }
  return best;
}

const STEM_LENGTH = 4;

/**
 * True when some word of `text` shares a leading stem with `word`. The stem is
 * capped by the shorter of the two, so «шара» still matches «шар».
 */
function sharesStem(word, text) {
  if (word.length < 3) return false;
  return text.split(' ').some((candidate) => {
    if (candidate.length < 3) return false;
    const length = Math.min(STEM_LENGTH, word.length, candidate.length);
    return word.slice(0, length) === candidate.slice(0, length);
  });
}

/** Bilingual fuzzy search over one bundle. */
export function search(list, query, limit = 8) {
  return list
    .map((entry) => ({ entry, score: scoreMatch(entry, query) }))
    .filter((r) => r.score > 0)
    .sort((a, b) => b.score - a.score || displayName(a.entry).length - displayName(b.entry).length)
    .slice(0, limit)
    .map((r) => r.entry);
}

export const findMonster = (q) => monsterByIndex.get(q) || search(monsters, q, 1)[0];
export const findSpell = (q) => spellByIndex.get(q) || search(spells, q, 1)[0];
export const findEquipment = (q) => equipmentByIndex.get(q) || search(equipment, q, 1)[0];
export const findMagicItem = (q) => magicItemByIndex.get(q) || search(magicItems, q, 1)[0];

/** Monsters within a challenge-rating band, for building encounters. */
export function monstersByCr(min, max) {
  return monsters.filter((m) => m.cr >= min && m.cr <= max);
}

const crLabel = (cr) => (cr === 0.125 ? '1/8' : cr === 0.25 ? '1/4' : cr === 0.5 ? '1/2' : String(cr));

const speedText = (speed = {}) =>
  Object.entries(speed)
    .map(([mode, value]) => {
      const label = { walk: '', fly: 'полёт ', swim: 'плавание ', climb: 'лазание ', burrow: 'копание ' }[mode] ?? `${mode} `;
      return typeof value === 'number' ? `${label}${value} фт.` : `${label}${value}`;
    })
    .join(', ');

/**
 * Compact stat block. Deliberately terse — the DM reads this mid-turn and
 * every extra line is context it pays for on the next request too.
 */
export function monsterBlock(m, { full = false } = {}) {
  if (!m) return '';
  const type = reference.creatureTypes[m.type] || m.type;
  const size = reference.sizes[m.size] || m.size;
  const lines = [
    `${displayName(m)} (${m.name}) — ${size} ${type}, ${m.alignment}`,
    `КД ${m.ac}${m.acNote ? ` (${m.acNote})` : ''} | ХП ${m.hp} (${m.hitDice}) | Скорость ${speedText(m.speed)}`,
    Object.entries(m.abilities)
      .map(([k, v]) => `${ABILITY_RU[k].slice(0, 3).toUpperCase()} ${v} (${formatMod(abilityMod(v))})`)
      .join('  '),
  ];

  if (m.saves && Object.keys(m.saves).length) {
    lines.push(`Спасброски: ${Object.entries(m.saves).map(([k, v]) => `${ABILITY_RU[k]} ${formatMod(v)}`).join(', ')}`);
  }
  if (m.skills && Object.keys(m.skills).length) {
    lines.push(`Навыки: ${Object.entries(m.skills).map(([k, v]) => `${SKILL_RU[k] || k} ${formatMod(v)}`).join(', ')}`);
  }
  const defences = [];
  if (m.vulnerable?.length) defences.push(`уязвимость: ${m.vulnerable.join(', ')}`);
  if (m.resist?.length) defences.push(`сопротивление: ${m.resist.join(', ')}`);
  if (m.immune?.length) defences.push(`иммунитет: ${m.immune.join(', ')}`);
  if (m.condImmune?.length) defences.push(`иммунитет к состояниям: ${m.condImmune.join(', ')}`);
  if (defences.length) lines.push(defences.join(' | '));

  if (m.senses) {
    lines.push(
      `Чувства: ${Object.entries(m.senses)
        .map(([k, v]) => `${k === 'passive_perception' ? 'пассивная Внимательность' : k} ${v}`)
        .join(', ')}`,
    );
  }
  lines.push(`Языки: ${m.languages || '—'} | ПО ${crLabel(m.cr)} (${m.xp} опыта) | БМ ${formatMod(m.prof)}`);

  const section = (title, items) => {
    if (!items?.length) return;
    lines.push(`${title}:`);
    for (const a of items) {
      const desc = full ? a.desc : a.desc?.split('. ').slice(0, 2).join('. ');
      lines.push(`  • ${a.name}. ${desc || ''}`);
    }
  };
  section('Особенности', m.traits);
  section('Действия', m.actions);
  section('Реакции', m.reactions);
  section('Легендарные действия', m.legendary);

  return lines.join('\n');
}

export function spellBlock(s, { full = true } = {}) {
  if (!s) return '';
  const school = reference.schools.find((x) => x.index === s.school);
  const level = s.level === 0 ? 'заговор' : `${s.level} круг`;
  const lines = [
    `${displayName(s)} (${s.name}) — ${level}, ${displayName(school) || s.school}${s.ritual ? ', ритуал' : ''}`,
    `Время: ${s.castingTime} | Дистанция: ${s.range} | Компоненты: ${(s.components || []).join(', ')}${s.material ? ` (${s.material})` : ''}`,
    `Длительность: ${s.concentration ? 'концентрация, ' : ''}${s.duration}`,
  ];
  if (s.damage?.type) {
    const at = s.damage.atSlot || s.damage.atLevel;
    const dice = at ? Object.entries(at).map(([k, v]) => `${k}: ${v}`).join(', ') : '';
    lines.push(`Урон (${DAMAGE_RU[s.damage.type] || s.damage.type}): ${dice}`);
  }
  if (s.dc) lines.push(`Спасбросок: ${ABILITY_RU[s.dc.type] || s.dc.type}${s.dc.success ? ` (при успехе — ${s.dc.success})` : ''}`);
  if (s.area) lines.push(`Область: ${s.area.type} ${s.area.size} фт.`);
  if (full) {
    lines.push(s.desc);
    if (s.higher) lines.push(`На больших кругах: ${s.higher}`);
  }
  lines.push(`Классы: ${(s.classes || []).map((c) => displayName(classByIndex.get(c)) || c).join(', ')}`);
  return lines.join('\n');
}

export function itemBlock(e) {
  if (!e) return '';
  const lines = [`${displayName(e)} (${e.name})`];
  if (e.damage) lines.push(`Урон: ${e.damage.dice} ${DAMAGE_RU[e.damage.type] || e.damage.type}${e.twoHandedDamage ? ` (двуручно ${e.twoHandedDamage.dice})` : ''}`);
  if (e.properties?.length) lines.push(`Свойства: ${e.properties.join(', ')}`);
  if (e.range) lines.push(`Дистанция: ${e.range.normal}${e.range.long ? `/${e.range.long}` : ''} фт.`);
  if (e.armor) {
    lines.push(
      `КД: ${e.armor.base}${e.armor.dexBonus ? ` + Лов${e.armor.maxDex ? ` (макс ${e.armor.maxDex})` : ''}` : ''}` +
        `${e.armor.strMin ? `, требуется Сила ${e.armor.strMin}` : ''}${e.armor.stealthDisadvantage ? ', помеха на Скрытность' : ''}`,
    );
  }
  if (e.rarity) lines.push(`Редкость: ${e.rarity}`);
  if (e.cost) lines.push(`Цена: ${e.cost}${e.weight ? `, вес ${e.weight} фнт.` : ''}`);
  if (e.desc) lines.push(e.desc.slice(0, 700));
  return lines.join('\n');
}

export function conditionBlock(c) {
  if (!c) return '';
  return `${displayName(c)} (${c.name})\n${c.desc}`;
}

/** Free-text lookup across every bundle — backs the DM's `lookup` tool. */
export function lookupAny(query, kind = 'any', limit = 5) {
  const buckets = {
    monster: { list: monsters, format: (e) => monsterBlock(e) },
    spell: { list: spells, format: (e) => spellBlock(e) },
    item: { list: equipment, format: itemBlock },
    magic: { list: magicItems, format: itemBlock },
    condition: { list: reference.conditions, format: conditionBlock },
    rule: { list: rules, format: (e) => `${e.name}\n${e.desc}` },
  };

  const selected = kind === 'any' ? Object.entries(buckets) : [[kind, buckets[kind]]].filter(([, v]) => v);
  const results = [];
  for (const [name, bucket] of selected) {
    for (const entry of search(bucket.list, query, limit)) {
      results.push({ kind: name, entry, text: bucket.format(entry) });
    }
  }
  return results.slice(0, limit);
}
