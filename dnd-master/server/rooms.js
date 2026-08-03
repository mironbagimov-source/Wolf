// Tables in memory: who is connected, what is queued for the DM, and when to
// save. One table = one campaign = one WebSocket room.

import * as state from './engine/state.js';
import * as agent from './dm/agent.js';

/** How long to wait after someone speaks before the DM answers, so several
 *  players can chime in first — the way they would round a real table. */
const DM_DEBOUNCE_MS = Number(process.env.DM_DEBOUNCE_MS || 1400);
const SAVE_DEBOUNCE_MS = 1500;

const tables = new Map(); // id -> room

function makeRoom(tableState) {
  return {
    state: tableState,
    sockets: new Set(),
    pending: [], // player messages waiting for the DM
    dmTimer: null,
    saveTimer: null,
    rerun: false, // someone spoke while the DM was mid-turn
  };
}

export function createTable(options) {
  const tableState = state.createTable(options);
  const room = makeRoom(tableState);
  tables.set(tableState.id, room);
  scheduleSave(room);
  return room;
}

export function getRoom(id) {
  if (tables.has(id)) return tables.get(id);
  const loaded = state.load(id);
  if (!loaded) return null;
  const room = makeRoom(loaded);
  tables.set(id, room);
  return room;
}

export function findByCode(code) {
  const wanted = String(code || '').trim().toUpperCase();
  if (!wanted) return null;
  for (const room of tables.values()) {
    if (room.state.code === wanted) return room;
  }
  for (const summary of state.listTables()) {
    if (summary.code === wanted) return getRoom(summary.id);
  }
  return null;
}

export function listTables() {
  return state.listTables();
}

// ------------------------------------------------------------- broadcast

export function send(socket, payload) {
  if (socket.readyState === 1) socket.send(JSON.stringify(payload));
}

export function broadcast(room, payload) {
  for (const socket of room.sockets) send(socket, payload);
}

/** Full state, tailored per socket so each player sees their own sheet. */
export function pushState(room) {
  for (const socket of room.sockets) {
    send(socket, { t: 'state', state: state.toClient(room.state, { playerId: socket.playerId }) });
  }
}

export function pushMessage(room, message) {
  broadcast(room, { t: 'message', message });
}

// ------------------------------------------------------------------ save

export function scheduleSave(room) {
  clearTimeout(room.saveTimer);
  room.saveTimer = setTimeout(() => {
    try {
      state.save(room.state);
    } catch (e) {
      console.error('Не удалось сохранить стол:', e.message);
    }
  }, SAVE_DEBOUNCE_MS);
}

export function saveNow(room) {
  clearTimeout(room.saveTimer);
  try {
    state.save(room.state);
  } catch (e) {
    console.error('Не удалось сохранить стол:', e.message);
  }
}

// -------------------------------------------------------------- DM turns

/** Context handed to the agent so it can talk to the table while it works. */
function dmContext(room) {
  return {
    state: room.state,
    emit: (message) => {
      pushMessage(room, message);
      pushState(room);
    },
    onDelta: (delta) => broadcast(room, { t: 'dm-delta', text: delta }),
    onStatus: (busy) => broadcast(room, { t: 'dm-status', busy }),
  };
}

/** Queues a player message and starts the debounce timer. */
export function queueForDm(room, message) {
  room.pending.push(message);
  scheduleDmTurn(room);
}

/**
 * Queues something the DM should know about without waking it up — a player
 * rolling a die is context for the next turn, not a request for one.
 */
export function queueContext(room, message) {
  room.pending.push(message);
  if (room.pending.length > 40) room.pending.splice(0, room.pending.length - 40);
}

export function scheduleDmTurn(room, delay = DM_DEBOUNCE_MS) {
  clearTimeout(room.dmTimer);
  room.dmTimer = setTimeout(() => runDmTurn(room), delay);
}

export async function runDmTurn(room) {
  if (room.state.dm.busy) {
    // Whatever arrived during this turn gets picked up right after it.
    room.rerun = true;
    return;
  }
  if (!agent.hasApiKey()) {
    const entry = state.addMessage(room.state, {
      type: 'system',
      text: 'AI-мастер не настроен: не задан ANTHROPIC_API_KEY. Игра работает, но вести партию придётся самим.',
    });
    pushMessage(room, entry);
    room.pending = [];
    return;
  }

  const batch = room.pending.splice(0, room.pending.length);
  if (batch.length > 0) agent.pushPlayerMessages(room.state, batch);

  broadcast(room, { t: 'dm-start' });
  await agent.runTurn(room.state, dmContext(room));
  pushState(room);
  saveNow(room);

  if (room.rerun || room.pending.length > 0) {
    room.rerun = false;
    scheduleDmTurn(room, 200);
  }
}

/** "Continue without us" — the DM acts on the world with no player input. */
export function nudgeDm(room, directive) {
  agent.pushDirective(room.state, directive || 'Продолжай сцену.');
  scheduleDmTurn(room, 100);
}

export function closeRoom(id) {
  const room = tables.get(id);
  if (!room) return;
  saveNow(room);
  clearTimeout(room.dmTimer);
  tables.delete(id);
}

export function activeRooms() {
  return [...tables.values()];
}
