// Связь с сервером: сокет, автопереподключение и хранение личности игрока.

const listeners = new Map();
let socket = null;
let reconnectDelay = 500;
let queue = [];

export const identity = {
  get playerId() {
    return localStorage.getItem('dnd.playerId') || null;
  },
  set playerId(value) {
    localStorage.setItem('dnd.playerId', value);
  },
  get playerName() {
    return localStorage.getItem('dnd.playerName') || '';
  },
  set playerName(value) {
    localStorage.setItem('dnd.playerName', value);
  },
  get lastTable() {
    return localStorage.getItem('dnd.tableId') || null;
  },
  set lastTable(value) {
    if (value) localStorage.setItem('dnd.tableId', value);
    else localStorage.removeItem('dnd.tableId');
  },
};

export function on(type, handler) {
  if (!listeners.has(type)) listeners.set(type, new Set());
  listeners.get(type).add(handler);
  return () => listeners.get(type).delete(handler);
}

function emit(type, payload) {
  for (const handler of listeners.get(type) || []) handler(payload);
  for (const handler of listeners.get('*') || []) handler(type, payload);
}

export function connect() {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  socket = new WebSocket(`${protocol}//${location.host}/ws`);

  socket.addEventListener('open', () => {
    reconnectDelay = 500;
    emit('open');
    const pending = queue;
    queue = [];
    for (const message of pending) send(message);
  });

  socket.addEventListener('message', (event) => {
    let payload;
    try {
      payload = JSON.parse(event.data);
    } catch {
      return;
    }
    emit(payload.t, payload);
  });

  socket.addEventListener('close', () => {
    emit('closed');
    // Постепенно растущая пауза: не долбим сервер, если он лёг.
    setTimeout(connect, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 2, 10000);
  });

  socket.addEventListener('error', () => socket.close());
}

export function send(message) {
  if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
  else queue.push(message);
}

export function joinTable({ tableId, code, playerName }) {
  identity.playerName = playerName;
  send({ t: 'join', tableId, code, playerName, playerId: identity.playerId });
}

export async function api(path, options) {
  const response = await fetch(path, {
    headers: { 'content-type': 'application/json' },
    ...options,
  });
  if (!response.ok) throw new Error((await response.json().catch(() => ({}))).error || `Ошибка ${response.status}`);
  return response.json();
}
