// HTTP + WebSocket entry point.
//
// The HTTP side serves the static client and the character-creation reference
// data. Everything that happens during play goes over the WebSocket.

import http from 'node:http';
import path from 'node:path';
import fs from 'node:fs';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import express from 'express';
import { WebSocketServer } from 'ws';

import * as rooms from './rooms.js';
import * as state from './engine/state.js';
import * as characterModule from './engine/character.js';
import * as srd from './engine/srd.js';
import * as dice from './engine/dice.js';
import * as mapModule from './engine/map.js';
import { BACKGROUNDS } from './engine/kits.js';
import { SKILLS, SKILL_RU, ABILITY_RU } from './engine/rules.js';
import * as agent from './dm/agent.js';

loadDotEnv();

const here = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.join(here, '..', 'public');
const PORT = Number(process.env.PORT || 3000);

const app = express();
app.use(express.json({ limit: '1mb' }));
app.use(express.static(publicDir, { extensions: ['html'] }));

// ------------------------------------------------------------------ REST

app.get('/api/health', (req, res) => {
  res.json({ ok: true, dm: agent.hasApiKey(), model: agent.MODEL });
});

/** Everything the character creator needs, already in Russian. */
app.get('/api/options', (req, res) => {
  res.json({
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
    dmConfigured: agent.hasApiKey(),
  });
});

app.get('/api/tables', (req, res) => {
  res.json(rooms.listTables());
});

app.post('/api/tables', (req, res) => {
  const { name, settings } = req.body || {};
  const room = rooms.createTable({ name: name || 'Новый стол', settings: settings || {} });
  res.json({ id: room.state.id, code: room.state.code, name: room.state.name });
});

app.get('/api/roll/:expression', (req, res) => {
  try {
    const result = dice.roll(req.params.expression);
    res.json({ ...result, text: dice.describe(result) });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// ------------------------------------------------------------- WebSocket

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (socket) => {
  socket.isAlive = true;
  socket.on('pong', () => {
    socket.isAlive = true;
  });

  socket.on('message', async (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      return rooms.send(socket, { t: 'error', text: 'Некорректное сообщение' });
    }
    try {
      await handle(socket, msg);
    } catch (e) {
      console.error('Ошибка обработки', msg?.t, e);
      rooms.send(socket, { t: 'error', text: e.message });
    }
  });

  socket.on('close', () => {
    const room = socket.tableId ? rooms.getRoom(socket.tableId) : null;
    if (!room) return;
    room.sockets.delete(socket);
    const player = room.state.players.find((p) => p.id === socket.playerId);
    if (player) player.connected = false;
    rooms.pushState(room);
    rooms.scheduleSave(room);
  });
});

// Drop sockets that stopped answering, so the roster stays honest.
const heartbeat = setInterval(() => {
  for (const socket of wss.clients) {
    if (!socket.isAlive) {
      socket.terminate();
      continue;
    }
    socket.isAlive = false;
    socket.ping();
  }
}, 30000);
heartbeat.unref?.();

async function handle(socket, msg) {
  switch (msg.t) {
    case 'join':
      return handleJoin(socket, msg);
    case 'chat':
      return handleChat(socket, msg);
    case 'roll':
      return handleRoll(socket, msg);
    case 'pick-pregen':
      return handlePickPregen(socket, msg);
    case 'create-character':
      return handleCreateCharacter(socket, msg);
    case 'nudge':
      return withRoom(socket, (room) => rooms.nudgeDm(room, msg.text));
    case 'settings':
      return handleSettings(socket, msg);
    case 'move-token':
      return handleMoveToken(socket, msg);
    case 'update-notes':
      return handleNotes(socket, msg);
    case 'roll-abilities':
      return rooms.send(socket, { t: 'ability-roll', scores: characterModule.rollAbilityScores() });
    default:
      return rooms.send(socket, { t: 'error', text: `Неизвестная команда: ${msg.t}` });
  }
}

function withRoom(socket, fn) {
  const room = socket.tableId ? rooms.getRoom(socket.tableId) : null;
  if (!room) {
    rooms.send(socket, { t: 'error', text: 'Ты не за столом' });
    return null;
  }
  return fn(room);
}

function handleJoin(socket, msg) {
  const room = msg.code ? rooms.findByCode(msg.code) : msg.tableId ? rooms.getRoom(msg.tableId) : null;
  if (!room) return rooms.send(socket, { t: 'error', text: 'Стол не найден. Проверь код.' });

  const playerId = msg.playerId || randomUUID();
  const playerName = (msg.playerName || 'Игрок').slice(0, 40);
  state.addPlayer(room.state, { id: playerId, name: playerName });
  if (!room.state.hostId) room.state.hostId = playerId;

  socket.playerId = playerId;
  socket.tableId = room.state.id;
  room.sockets.add(socket);

  rooms.send(socket, {
    t: 'joined',
    playerId,
    tableId: room.state.id,
    code: room.state.code,
    isHost: room.state.hostId === playerId,
    transcript: room.state.transcript.slice(-200),
    dmConfigured: agent.hasApiKey(),
  });
  rooms.pushState(room);
  rooms.scheduleSave(room);

  const entry = state.addMessage(room.state, { type: 'system', text: `${playerName} за столом` });
  rooms.pushMessage(room, entry);
  return null;
}

function handleChat(socket, msg) {
  return withRoom(socket, (room) => {
    const text = String(msg.text || '').trim().slice(0, 2000);
    if (!text) return;

    // Slash commands never reach the DM.
    if (text.startsWith('/')) return handleCommand(socket, room, text);

    const player = room.state.players.find((p) => p.id === socket.playerId);
    const character = state.playerCharacter(room.state, socket.playerId);
    const mode = ['say', 'action', 'ooc'].includes(msg.mode) ? msg.mode : 'say';

    const entry = state.addMessage(room.state, {
      type: mode === 'ooc' ? 'ooc' : mode === 'action' ? 'action' : 'ic',
      authorId: socket.playerId,
      authorName: player?.name || 'Игрок',
      characterName: character?.name || null,
      characterColor: character?.portraitColor || null,
      text,
    });
    rooms.pushMessage(room, entry);
    rooms.scheduleSave(room);

    // Out-of-character chatter is table talk — the DM stays out of it.
    if (mode !== 'ooc') rooms.queueForDm(room, entry);
  });
}

function handleCommand(socket, room, text) {
  const [command, ...rest] = text.slice(1).split(/\s+/);
  const argument = rest.join(' ');

  if (command === 'roll' || command === 'r' || command === 'бросок') {
    return handleRoll(socket, { expression: argument || '1d20', reason: 'бросок игрока' });
  }
  if (command === 'мастер' || command === 'dm') {
    rooms.nudgeDm(room, argument || 'Продолжай сцену.');
    return null;
  }
  if (command === 'помощь' || command === 'help') {
    return rooms.send(socket, {
      t: 'message',
      message: {
        id: randomUUID(),
        ts: Date.now(),
        type: 'system',
        text: 'Команды: /roll 2d6+3 — бросок, /мастер <текст> — попросить мастера продолжить, /помощь — эта справка. Режим сообщения переключается кнопками слева от поля ввода.',
      },
    });
  }
  return rooms.send(socket, { t: 'error', text: `Неизвестная команда: /${command}` });
}

function handleRoll(socket, msg) {
  return withRoom(socket, (room) => {
    let result;
    try {
      result = dice.roll(msg.expression || '1d20');
    } catch (e) {
      return rooms.send(socket, { t: 'error', text: e.message });
    }
    const character = state.playerCharacter(room.state, socket.playerId);
    const player = room.state.players.find((p) => p.id === socket.playerId);
    const entry = state.addMessage(room.state, {
      type: 'roll',
      authorId: socket.playerId,
      authorName: character?.name || player?.name || 'Игрок',
      text: `${msg.reason || 'бросок'}: ${dice.describe(result)}`,
      data: { result, byPlayer: true },
    });
    rooms.pushMessage(room, entry);
    rooms.scheduleSave(room);
    // The DM should know what the table rolled, but a die on its own is not a
    // request for a scene — it rides along with the next thing someone says.
    rooms.queueContext(room, entry);
    return null;
  });
}

function handlePickPregen(socket, msg) {
  return withRoom(socket, (room) => {
    const player = room.state.players.find((p) => p.id === socket.playerId);
    const character = characterModule.createFromPregen(msg.pregenId, {
      playerId: socket.playerId,
      playerName: player?.name,
      name: msg.name,
    });
    state.attachCharacter(room.state, socket.playerId, character);
    announceCharacter(room, character);
  });
}

function handleCreateCharacter(socket, msg) {
  return withRoom(socket, (room) => {
    const player = room.state.players.find((p) => p.id === socket.playerId);
    const spec = msg.spec || {};
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
      playerId: socket.playerId,
      playerName: player?.name,
    });
    state.attachCharacter(room.state, socket.playerId, character);
    announceCharacter(room, character);
  });
}

function announceCharacter(room, character) {
  const cls = srd.displayName(srd.classByIndex.get(character.class));
  const race = srd.displayName(srd.raceByIndex.get(character.race));
  const entry = state.addMessage(room.state, {
    type: 'system',
    text: `🛡 ${character.name} — ${race} ${cls} ${character.level} ур. — присоединяется к партии`,
  });
  rooms.pushMessage(room, entry);
  rooms.pushState(room);
  rooms.saveNow(room);
}

function handleSettings(socket, msg) {
  return withRoom(socket, (room) => {
    if (room.state.hostId && room.state.hostId !== socket.playerId) {
      return rooms.send(socket, { t: 'error', text: 'Настройки меняет тот, кто создал стол' });
    }
    const patch = msg.patch || {};
    if (patch.tone && state.TONES[patch.tone]) room.state.settings.tone = patch.tone;
    if (patch.difficulty && state.DIFFICULTIES[patch.difficulty]) room.state.settings.difficulty = patch.difficulty;
    if (typeof patch.premise === 'string') room.state.settings.premise = patch.premise.slice(0, 2000);
    if (typeof patch.name === 'string') room.state.name = patch.name.slice(0, 60);
    rooms.pushState(room);
    rooms.scheduleSave(room);
    return null;
  });
}

function handleMoveToken(socket, msg) {
  return withRoom(socket, (room) => {
    const character = state.playerCharacter(room.state, socket.playerId);
    if (!character) return rooms.send(socket, { t: 'error', text: 'Сначала создай персонажа' });
    if (!room.state.map) return rooms.send(socket, { t: 'error', text: 'Карты сейчас нет' });

    const result = mapModule.moveToken(room.state.map, character.id, msg.x, msg.y);
    if (!result.ok) return rooms.send(socket, { t: 'error', text: result.reason });

    const entry = state.addMessage(room.state, {
      type: 'system',
      text: `${character.name} перемещается на (${result.to.x},${result.to.y}) — ${result.distance} фт.`,
      data: { move: true },
    });
    rooms.pushMessage(room, entry);
    rooms.pushState(room);
    rooms.scheduleSave(room);
    return null;
  });
}

function handleNotes(socket, msg) {
  return withRoom(socket, (room) => {
    const character = state.playerCharacter(room.state, socket.playerId);
    if (!character) return;
    character.notes = String(msg.notes || '').slice(0, 4000);
    rooms.scheduleSave(room);
    return null;
  });
}

// ------------------------------------------------------------------ boot

/** Minimal .env reader — avoids a dependency for three lines of parsing. */
function loadDotEnv() {
  const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '.env');
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/i);
    if (!match) continue;
    const value = match[2].replace(/^["']|["']$/g, '');
    if (!(match[1] in process.env)) process.env[match[1]] = value;
  }
}

state.ensureDataDir();

server.listen(PORT, () => {
  console.log(`\n  Мастер подземелий слушает http://localhost:${PORT}`);
  console.log(`  Модель: ${agent.MODEL} (усилие: ${agent.EFFORT})`);
  if (!agent.hasApiKey()) {
    console.log('  ⚠ ANTHROPIC_API_KEY не задан — AI-мастер отключён.');
    console.log('    Скопируй .env.example в .env и впиши ключ с console.anthropic.com\n');
  } else {
    console.log('  AI-мастер готов.\n');
  }
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    console.log('\nСохраняю столы...');
    for (const room of rooms.activeRooms()) rooms.saveNow(room);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}
