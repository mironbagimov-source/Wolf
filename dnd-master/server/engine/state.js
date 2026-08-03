// Table state: the single object that holds a campaign, plus the snapshot the
// AI DM is shown each turn and the JSON persistence behind it.

import fs from 'node:fs';
import path from 'node:path';
import { randomUUID, randomInt } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import * as srd from './srd.js';
import * as character from './character.js';
import * as combat from './combat.js';
import * as mapModule from './map.js';
import { CONDITION_RU } from './rules.js';

// В браузерной сборке файловой системы нет: сохранение живёт только на сервере.
const inNode = typeof process !== 'undefined' && Boolean(process.versions?.node);
const dataRoot = inNode ? path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'data', 'tables') : null;

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no look-alikes

export function makeTableCode() {
  return Array.from({ length: 5 }, () => CODE_ALPHABET[randomInt(0, CODE_ALPHABET.length)]).join('');
}

export const TONES = {
  героическое: 'Классическое героическое фэнтези: яркие герои, ясное зло, надежда побеждает.',
  тёмное: 'Мрачное фэнтези: цена есть у всего, победы неполные, мир равнодушен.',
  авантюрное: 'Плутовское приключение: интриги, обманы, смешные провалы и дерзкие планы.',
  расследование: 'Мистическое расследование: улики, свидетели, версии, разгадка в конце.',
  выживание: 'Выживание: ресурсы на счету, дорога опасна, каждый привал важен.',
};

export const DIFFICULTIES = {
  щадящая: 'Противники слабее партии, смерть маловероятна, провал двигает историю дальше.',
  обычная: 'Стандартный баланс 5e. Смерть возможна при плохих решениях.',
  жёсткая: 'Противники бьют в полную силу и играют умно. Отступление — нормальная тактика.',
};

export function createTable({ name = 'Новый стол', hostId = null, settings = {} } = {}) {
  const now = Date.now();
  return {
    id: randomUUID(),
    code: makeTableCode(),
    name,
    hostId,
    createdAt: now,
    updatedAt: now,

    players: [],
    party: [],
    npcs: [],

    scene: {
      location: 'Ещё не начато',
      time: 'вечер',
      weather: 'ясно',
      description: '',
    },
    quests: [],
    loot: [],
    journal: [],

    combat: { active: false, round: 0, turnIndex: 0, order: [] },
    map: null,

    transcript: [],
    dm: {
      messages: [],
      chronicle: '',
      busy: false,
      startedAt: null,
    },

    settings: {
      tone: settings.tone || 'героическое',
      difficulty: settings.difficulty || 'обычная',
      premise: settings.premise || '',
      rollsVisible: settings.rollsVisible !== false,
      ...settings,
    },
  };
}

// ------------------------------------------------------------- transcript

export function addMessage(state, message) {
  const entry = {
    id: randomUUID(),
    ts: Date.now(),
    type: 'system',
    ...message,
  };
  state.transcript.push(entry);
  state.updatedAt = entry.ts;
  // The transcript is the display log; the DM's own context is capped
  // separately in dm/agent.js, so this only bounds memory.
  if (state.transcript.length > 2000) state.transcript = state.transcript.slice(-1500);
  return entry;
}

// ---------------------------------------------------------------- players

export function addPlayer(state, { id, name }) {
  const existing = state.players.find((p) => p.id === id);
  if (existing) {
    existing.name = name || existing.name;
    existing.connected = true;
    return existing;
  }
  const player = { id, name, connected: true, characterId: null, joinedAt: Date.now() };
  state.players.push(player);
  return player;
}

export function playerCharacter(state, playerId) {
  const player = state.players.find((p) => p.id === playerId);
  if (!player?.characterId) return null;
  return state.party.find((c) => c.id === player.characterId) || null;
}

export function attachCharacter(state, playerId, ch) {
  const player = state.players.find((p) => p.id === playerId);
  if (!player) throw new Error('Игрок не за столом');
  // One character per player: replace the old one rather than stacking.
  if (player.characterId) {
    state.party = state.party.filter((c) => c.id !== player.characterId);
  }
  ch.playerId = playerId;
  ch.playerName = player.name;
  state.party.push(ch);
  player.characterId = ch.id;
  if (state.map) syncPartyTokens(state);
  return ch;
}

// ------------------------------------------------------------------ map

export function setMap(state, map) {
  state.map = map;
  syncPartyTokens(state);
  return map;
}

/** Puts a token on the map for every living party member that lacks one. */
export function syncPartyTokens(state) {
  if (!state.map) return;
  for (const ch of state.party) {
    const existing = state.map.tokens.find((t) => t.id === ch.id);
    if (existing) {
      existing.name = ch.name;
      existing.color = ch.portraitColor;
      continue;
    }
    mapModule.addToken(state.map, {
      id: ch.id,
      name: ch.name,
      kind: 'pc',
      color: ch.portraitColor || '#38bdf8',
      label: ch.name.slice(0, 2),
    });
  }
  // Drop tokens for characters and monsters that no longer exist.
  const liveIds = new Set([...state.party.map((c) => c.id), ...state.npcs.map((n) => n.id)]);
  state.map.tokens = state.map.tokens.filter((t) => t.kind === 'object' || liveIds.has(t.id));
}

// ---------------------------------------------------------------- context

/**
 * The snapshot handed to the DM at the start of every turn. Deliberately
 * dense: this is re-sent on each request, so every line has to earn its place.
 */
export function stateSnapshot(state) {
  const lines = [];

  lines.push(`## Сцена`);
  lines.push(`Место: ${state.scene.location}. Время: ${state.scene.time}. Погода: ${state.scene.weather}.`);
  if (state.scene.description) lines.push(state.scene.description);

  lines.push(`\n## Партия`);
  if (state.party.length === 0) lines.push('Персонажей ещё нет.');
  for (const ch of state.party) {
    const cls = srd.displayName(srd.classByIndex.get(ch.class));
    const race = srd.displayName(srd.raceByIndex.get(ch.race));
    const status = ch.dead
      ? 'МЁРТВ'
      : ch.hp.current === 0
        ? `при смерти (успехи ${ch.deathSaves.successes}/провалы ${ch.deathSaves.failures})`
        : `${ch.hp.current}/${ch.hp.max} хп`;
    const conditions = ch.conditions.length
      ? `, состояния: ${ch.conditions.map((c) => CONDITION_RU[c.name] || c.name).join(', ')}`
      : '';
    const slots = ch.spellcasting
      ? `, ячейки: ${Object.entries(ch.spellcasting.slots)
          .map(([lvl, max]) => `${lvl}кр ${max - (ch.spells.slotsUsed[lvl] || 0)}/${max}`)
          .join(' ') || '—'}`
      : '';
    // За одним экраном имя игрока совпадает с именем героя — повторять незачем.
    const who = ch.playerName && ch.playerName !== ch.name ? `, игрок ${ch.playerName}` : '';
    lines.push(
      `- ${ch.name} [${ch.id.slice(0, 8)}] — ${race} ${cls} ${ch.level} ур.${who}. ` +
        `КД ${ch.ac}, ${status}, пасс. Внимательность ${ch.passivePerception}${slots}${conditions}`,
    );
  }

  const activeNpcs = state.npcs.filter((n) => !n.dead);
  if (activeNpcs.length) {
    lines.push(`\n## Существа в сцене`);
    for (const npc of activeNpcs) {
      lines.push(
        `- ${npc.name} [${npc.id.slice(0, 8)}] — ${npc.hp.current}/${npc.hp.max} хп, КД ${npc.ac}` +
          `${npc.hostile === false ? ', не враждебен' : ''}` +
          `${npc.conditions?.length ? `, ${npc.conditions.map((c) => CONDITION_RU[c.name] || c.name).join(', ')}` : ''}`,
      );
    }
  }

  if (state.combat?.active) {
    lines.push(`\n## Бой`);
    lines.push(combat.combatSummary(state));
  }

  if (state.map) {
    lines.push(`\n## Карта`);
    lines.push(mapModule.asciiMap(state.map));
  }

  const openQuests = state.quests.filter((q) => q.status !== 'выполнен');
  if (openQuests.length) {
    lines.push(`\n## Задачи`);
    for (const q of openQuests) lines.push(`- ${q.title} (${q.status})${q.notes ? `: ${q.notes}` : ''}`);
  }

  if (state.loot.length) {
    lines.push(`\n## Общая добыча`);
    lines.push(state.loot.map((l) => `${l.name}${l.qty > 1 ? ` ×${l.qty}` : ''}`).join(', '));
  }

  return lines.join('\n');
}

/** Full sheets, sent once per turn only when the party changed. */
export function partySheets(state) {
  return state.party.map((ch) => character.sheetText(ch)).join('\n\n');
}

// ------------------------------------------------------------- client view

/** What a browser receives. Strips the DM's internal conversation. */
export function toClient(state, { playerId = null } = {}) {
  return {
    id: state.id,
    code: state.code,
    name: state.name,
    settings: state.settings,
    scene: state.scene,
    players: state.players.map((p) => ({
      id: p.id,
      name: p.name,
      connected: p.connected,
      characterId: p.characterId,
    })),
    party: state.party.map((ch) => publicCharacter(ch, ch.playerId === playerId)),
    npcs: state.npcs
      .filter((n) => n.visible !== false)
      .map((n) => ({
        id: n.id,
        name: n.name,
        hp: n.dead ? 'повержен' : combat.describeMonsterHealth(n),
        dead: !!n.dead,
        hostile: n.hostile !== false,
        conditions: n.conditions || [],
      })),
    combat: state.combat?.active
      ? {
          active: true,
          round: state.combat.round,
          turnIndex: state.combat.turnIndex,
          order: state.combat.order.map((entry) => ({
            id: entry.id,
            name: entry.name,
            kind: entry.kind,
            initiative: entry.initiative,
            surprised: entry.surprised,
          })),
        }
      : { active: false },
    map: mapModule.toClient(state.map),
    quests: state.quests,
    loot: state.loot,
    journal: state.journal,
    dmBusy: !!state.dm.busy,
  };
}

/** A character as other players see it; the owner also gets private details. */
export function publicCharacter(ch, isOwner = false) {
  const base = {
    id: ch.id,
    name: ch.name,
    playerId: ch.playerId,
    playerName: ch.playerName,
    race: ch.race,
    class: ch.class,
    level: ch.level,
    hp: ch.hp,
    ac: ch.ac,
    speed: ch.speed,
    conditions: ch.conditions,
    dead: !!ch.dead,
    deathSaves: ch.deathSaves,
    portraitColor: ch.portraitColor,
    initiative: ch.initiative,
    passivePerception: ch.passivePerception,
    inspiration: ch.inspiration,
    blurb: ch.blurb,
  };
  if (!isOwner) return base;
  return {
    ...base,
    abilities: ch.abilities,
    mods: ch.mods,
    saves: ch.saves,
    skills: ch.skills,
    skillMods: ch.skillMods,
    prof: ch.prof,
    attacks: ch.attacks,
    inventory: ch.inventory.map((i) => ({
      ...i,
      name: srd.displayName(srd.equipmentByIndex.get(i.index) || srd.magicItemByIndex.get(i.index)) || i.index,
    })),
    gold: ch.gold,
    spells: ch.spells,
    spellcasting: ch.spellcasting,
    hitDice: ch.hitDice,
    xp: ch.xp,
    background: ch.background,
    alignment: ch.alignment,
    hook: ch.hook,
    notes: ch.notes,
    exhaustion: ch.exhaustion,
  };
}

// ------------------------------------------------------------ persistence

export function ensureDataDir() {
  fs.mkdirSync(dataRoot, { recursive: true });
}

export function save(state) {
  ensureDataDir();
  const file = path.join(dataRoot, `${state.id}.json`);
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(state));
  fs.renameSync(tmp, file); // atomic-ish: a crash mid-write can't corrupt the save
  return file;
}

export function load(id) {
  const file = path.join(dataRoot, `${id}.json`);
  if (!fs.existsSync(file)) return null;
  const state = JSON.parse(fs.readFileSync(file, 'utf8'));
  // Recompute derived stats — the rules may have been fixed since the save.
  for (const ch of state.party) character.recompute(ch);
  for (const player of state.players) player.connected = false;
  state.dm.busy = false;
  return state;
}

export function listTables() {
  ensureDataDir();
  return fs
    .readdirSync(dataRoot)
    .filter((f) => f.endsWith('.json'))
    .map((f) => {
      try {
        const raw = JSON.parse(fs.readFileSync(path.join(dataRoot, f), 'utf8'));
        return {
          id: raw.id,
          code: raw.code,
          name: raw.name,
          players: raw.players?.length || 0,
          party: raw.party?.map((c) => c.name) || [],
          updatedAt: raw.updatedAt,
          location: raw.scene?.location,
        };
      } catch {
        return null;
      }
    })
    .filter(Boolean)
    .sort((a, b) => b.updatedAt - a.updatedAt);
}

export function deleteTable(id) {
  const file = path.join(dataRoot, `${id}.json`);
  if (fs.existsSync(file)) fs.unlinkSync(file);
}
