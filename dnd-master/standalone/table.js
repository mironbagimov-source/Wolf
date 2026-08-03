// Стол, который целиком живёт в одной вкладке.
//
// На сервере эту роль играют rooms.js и index.js: там комната раздаёт состояние
// сокетам и придерживает ход мастера, пока договаривают игроки. Здесь то же
// самое, только «сокет» один и он же экран, а сохранение уходит в localStorage.
//
// Игра за одним экраном: каждый герой — отдельный «игрок» стола, а кто сейчас
// за клавиатурой, решает переключатель в поле ввода.

import * as state from '../server/engine/state.js';
import * as characterModule from '../server/engine/character.js';
import * as mapModule from '../server/engine/map.js';
import * as dice from '../server/engine/dice.js';
import * as srd from '../server/engine/srd.js';
import * as agent from './agent.js';
import { randomUUID } from './shims/crypto.js';
import * as net from './net-local.js';

const DM_DEBOUNCE_MS = 1200;
const SAVE_DEBOUNCE_MS = 1200;
const INDEX_KEY = 'dnd.solo.index';
const tableKey = (id) => `dnd.solo.table.${id}`;

const listeners = new Map();

let st = null;
let activePlayerId = null;
let pending = [];
let rerun = false;
let dmTimer = null;
let saveTimer = null;

// ------------------------------------------------------------- события

export function on(type, handler) {
  if (!listeners.has(type)) listeners.set(type, new Set());
  listeners.get(type).add(handler);
  return () => listeners.get(type).delete(handler);
}

function emit(type, payload) {
  for (const handler of listeners.get(type) || []) handler(payload);
}

const fail = (text) => emit('error', { text });

export const current = () => st;
export const activeId = () => activePlayerId;
export const activeCharacter = () => (st ? state.playerCharacter(st, activePlayerId) : null);

export function pushState() {
  if (st) emit('state', { state: state.toClient(st, { playerId: activePlayerId }), activePlayerId });
}

function pushMessage(message) {
  emit('message', { message });
}

// ------------------------------------------------------- жизнь кампании

export function createTable({ name, settings }) {
  st = state.createTable({ name: name || 'Новая кампания', settings: settings || {} });
  activePlayerId = null;
  pending = [];
  const entry = state.addMessage(st, {
    type: 'system',
    text: `📜 ${st.name} — кампания открыта. Соберите героев, и мастер начнёт.`,
  });
  saveNow();
  pushState();
  pushMessage(entry);
  return st;
}

export function openTable(id) {
  const restored = loadTable(id);
  if (!restored) return null;
  st = restored;
  activePlayerId = st.party[0]?.playerId || null;
  pending = [];
  return st;
}

/** Кто сейчас за клавиатурой. */
export function setActive(playerId) {
  if (!st.players.some((p) => p.id === playerId)) return;
  activePlayerId = playerId;
  pushState();
}

/**
 * Заводит нового «игрока» под ещё одного героя за этим же экраном. Имя не
 * спрашиваем: за столом сидит живой человек, а в летописи важно имя героя.
 */
export function addSeat(name) {
  const playerId = randomUUID();
  state.addPlayer(st, { id: playerId, name: name || 'Игрок' });
  if (!st.hostId) st.hostId = playerId;
  activePlayerId = playerId;
  return playerId;
}

// ------------------------------------------------------------- команды

/** Единственная дверь в стол: сюда приходит всё, что делает игрок. */
export function dispatch(message) {
  if (!st) return;
  switch (message.t) {
    case 'chat':
      return handleChat(message);
    case 'roll':
      return handleRoll(message);
    case 'nudge':
      return nudge(message.text);
    case 'move-token':
      return handleMoveToken(message);
    case 'update-notes':
      return handleNotes(message);
    case 'pick-pregen':
      return handlePickPregen(message);
    case 'create-character':
      return handleCreateCharacter(message);
    case 'roll-abilities':
      return emit('ability-roll', { scores: characterModule.rollAbilityScores() });
    case 'settings':
      return handleSettings(message);
    default:
      return fail(`Неизвестная команда: ${message.t}`);
  }
}

function handleChat(message) {
  const text = String(message.text || '').trim().slice(0, 2000);
  if (!text) return;
  if (text.startsWith('/')) return handleCommand(text);

  const player = st.players.find((p) => p.id === activePlayerId);
  const character = state.playerCharacter(st, activePlayerId);
  const mode = ['say', 'action', 'ooc'].includes(message.mode) ? message.mode : 'say';

  const entry = state.addMessage(st, {
    type: mode === 'ooc' ? 'ooc' : mode === 'action' ? 'action' : 'ic',
    authorId: activePlayerId,
    authorName: player?.name || 'Игрок',
    characterName: character?.name || null,
    characterColor: character?.portraitColor || null,
    text,
  });
  pushMessage(entry);
  scheduleSave();

  // Разговор за столом мастера не касается.
  if (mode !== 'ooc') {
    pending.push(entry);
    scheduleDmTurn();
  }
}

function handleCommand(text) {
  const [command, ...rest] = text.slice(1).split(/\s+/);
  const argument = rest.join(' ');

  if (command === 'roll' || command === 'r' || command === 'бросок') {
    return handleRoll({ expression: argument || '1d20', reason: 'бросок игрока' });
  }
  if (command === 'мастер' || command === 'dm') return nudge(argument || 'Продолжай сцену.');
  if (command === 'помощь' || command === 'help') {
    return pushMessage({
      id: randomUUID(),
      ts: Date.now(),
      type: 'system',
      text: 'Команды: /roll 2d6+3 — бросок, /мастер <текст> — попросить мастера продолжить, /помощь — эта справка. Кто говорит — выбирается слева от поля ввода.',
    });
  }
  return fail(`Неизвестная команда: /${command}`);
}

function handleRoll(message) {
  let result;
  try {
    result = dice.roll(message.expression || '1d20');
  } catch (e) {
    return fail(e.message);
  }
  const character = state.playerCharacter(st, activePlayerId);
  const player = st.players.find((p) => p.id === activePlayerId);
  const entry = state.addMessage(st, {
    type: 'roll',
    authorId: activePlayerId,
    authorName: character?.name || player?.name || 'Игрок',
    text: `${message.reason || 'бросок'}: ${dice.describe(result)}`,
    data: { result, byPlayer: true },
  });
  pushMessage(entry);
  scheduleSave();
  // Кость сама по себе — не просьба к мастеру: она поедет с ближайшей репликой.
  pending.push(entry);
  if (pending.length > 40) pending.splice(0, pending.length - 40);
}

function handleMoveToken(message) {
  const character = state.playerCharacter(st, activePlayerId);
  if (!character) return fail('Сначала собери персонажа');
  if (!st.map) return fail('Карты сейчас нет');

  const result = mapModule.moveToken(st.map, character.id, message.x, message.y);
  if (!result.ok) return fail(result.reason);

  const entry = state.addMessage(st, {
    type: 'system',
    text: `${character.name} перемещается на (${result.to.x},${result.to.y}) — ${result.distance} фт.`,
    data: { move: true },
  });
  pushMessage(entry);
  pushState();
  scheduleSave();
}

function handleNotes(message) {
  const character = state.playerCharacter(st, activePlayerId);
  if (!character) return;
  character.notes = String(message.notes || '').slice(0, 4000);
  scheduleSave();
}

function handlePickPregen(message) {
  const playerId = addSeat(message.playerName);
  const character = characterModule.createFromPregen(message.pregenId, {
    playerId,
    name: message.name,
  });
  // За одним экраном «место за столом» и есть герой, так что имя у них общее.
  seatName(playerId, message.playerName || character.name);
  state.attachCharacter(st, playerId, character);
  announceCharacter(character);
}

function seatName(playerId, name) {
  const player = st.players.find((p) => p.id === playerId);
  if (player) player.name = name;
}

function handleCreateCharacter(message) {
  const spec = message.spec || {};
  const playerId = addSeat(message.playerName || spec.name);
  const player = st.players.find((p) => p.id === playerId);
  const character = characterModule.createCharacter({
    name: String(spec.name || 'Безымянный').slice(0, 40),
    race: spec.race,
    subrace: spec.subrace,
    class: spec.class,
    background: spec.background,
    alignment: spec.alignment,
    skills: Array.isArray(spec.skills) ? spec.skills : [],
    abilities: spec.abilities,
    portraitColor: spec.portraitColor,
    blurb: String(spec.blurb || '').slice(0, 400),
    hook: String(spec.hook || '').slice(0, 400),
    playerId,
    playerName: player?.name,
  });
  state.attachCharacter(st, playerId, character);
  announceCharacter(character);
}

function announceCharacter(character) {
  const cls = srd.displayName(srd.classByIndex.get(character.class));
  const race = srd.displayName(srd.raceByIndex.get(character.race));
  const entry = state.addMessage(st, {
    type: 'system',
    text: `🛡 ${character.name} — ${race} ${cls} ${character.level} ур. — присоединяется к партии`,
  });
  pushMessage(entry);
  pushState();
  emit('party', { character });
  saveNow();
}

function handleSettings(message) {
  const patch = message.patch || {};
  if (patch.tone && state.TONES[patch.tone]) st.settings.tone = patch.tone;
  if (patch.difficulty && state.DIFFICULTIES[patch.difficulty]) st.settings.difficulty = patch.difficulty;
  if (typeof patch.premise === 'string') st.settings.premise = patch.premise.slice(0, 2000);
  if (typeof patch.name === 'string') st.name = patch.name.slice(0, 60);
  pushState();
  scheduleSave();
}

// ------------------------------------------------------------ ход мастера

function dmContext() {
  return {
    state: st,
    emit: (message) => {
      pushMessage(message);
      pushState();
    },
    onDelta: (delta) => emit('dm-delta', { text: delta }),
    onStatus: (busy) => emit('dm-status', { busy }),
  };
}

export function scheduleDmTurn(delay = DM_DEBOUNCE_MS) {
  clearTimeout(dmTimer);
  dmTimer = setTimeout(runDmTurn, delay);
}

export async function runDmTurn() {
  if (!st) return;
  if (st.dm.busy) {
    // Пока мастер думает, реплики копятся — разберём их сразу после хода.
    rerun = true;
    return;
  }

  const batch = pending.splice(0, pending.length);
  if (batch.length > 0) agent.pushPlayerMessages(st, batch);

  emit('dm-start');
  await agent.runTurn(st, dmContext());
  pushState();
  saveNow();

  if (rerun || pending.length > 0) {
    rerun = false;
    scheduleDmTurn(200);
  }
}

/** «Мастер, дальше» — ход без реплики игроков. */
export function nudge(directive) {
  agent.pushDirective(st, directive || 'Продолжай сцену.');
  scheduleDmTurn(100);
}

// --------------------------------------------------------- сохранения

/**
 * Кампания целиком лежит в localStorage. Места там немного, поэтому при
 * переполнении сначала подрезаем ленту и память мастера, а не теряем стол.
 */
function serialize(table, { trim = 0 } = {}) {
  const copy = { ...table, dm: { ...table.dm, busy: false } };
  if (trim >= 1) copy.transcript = copy.transcript.slice(-250);
  if (trim >= 2) copy.dm = { ...copy.dm, messages: copy.dm.messages.slice(-20) };
  if (trim >= 3) copy.dm = { ...copy.dm, messages: [] };
  return JSON.stringify(copy);
}

let storageWarned = false;

export function saveNow() {
  clearTimeout(saveTimer);
  if (!st) return;
  st.updatedAt = Date.now();

  for (let trim = 0; trim <= 3; trim += 1) {
    try {
      localStorage.setItem(tableKey(st.id), serialize(st, { trim }));
      writeIndex();
      return;
    } catch {
      // Скорее всего кончилось место — пробуем сохранить хотя бы меньшее.
    }
  }
  if (!storageWarned) {
    storageWarned = true;
    fail('Не удалось сохранить кампанию в этом браузере — игра идёт, но продолжить после закрытия не выйдет.');
  }
}

function scheduleSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveNow, SAVE_DEBOUNCE_MS);
}

function writeIndex() {
  const rest = listTables().filter((t) => t.id !== st.id);
  const summary = {
    id: st.id,
    name: st.name,
    updatedAt: st.updatedAt,
    party: st.party.map((c) => c.name),
    location: st.scene.location,
  };
  localStorage.setItem(INDEX_KEY, JSON.stringify([summary, ...rest].slice(0, 12)));
}

export function listTables() {
  try {
    const raw = JSON.parse(localStorage.getItem(INDEX_KEY) || '[]');
    return Array.isArray(raw) ? raw.sort((a, b) => b.updatedAt - a.updatedAt) : [];
  } catch {
    return [];
  }
}

function loadTable(id) {
  let raw;
  try {
    raw = localStorage.getItem(tableKey(id));
  } catch {
    return null;
  }
  if (!raw) return null;
  try {
    const table = JSON.parse(raw);
    // Правила могли поправить со времён сохранения — пересчитываем производное.
    for (const ch of table.party) characterModule.recompute(ch);
    table.dm.busy = false;
    return table;
  } catch {
    return null;
  }
}

/** Кампания одним файлом — на случай, если браузер чистит своё хранилище. */
export function exportTable() {
  return serialize(st);
}

export function importTable(raw) {
  const table = typeof raw === 'string' ? JSON.parse(raw) : raw;
  if (!table?.id || !Array.isArray(table.party) || !Array.isArray(table.transcript)) {
    throw new Error('Это не файл кампании');
  }
  for (const ch of table.party) characterModule.recompute(ch);
  table.dm = { messages: [], chronicle: '', busy: false, startedAt: null, ...table.dm, busy: false };
  st = table;
  activePlayerId = st.party[0]?.playerId || null;
  pending = [];
  saveNow();
  return st;
}

export function deleteTable(id) {
  try {
    localStorage.removeItem(tableKey(id));
    localStorage.setItem(INDEX_KEY, JSON.stringify(listTables().filter((t) => t.id !== id)));
  } catch {
    /* нечего чистить */
  }
}

// Игровой экран говорит со столом через тот же net.send, что и в сетевой сборке.
net.setHandler(dispatch);
