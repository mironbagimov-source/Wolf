// Точка входа: лобби, создание персонажа и подключение игрового экрана.

import { el, qs, qsa, clear, toast, showScreen } from './dom.js';
import * as net from './net.js';
import * as game from './game.js';
import { icon } from './icons.js';
import { initMap } from './battlemap.js';
import { initCreator, setPool } from './creator.js';

let options = null;
let playerId = net.identity.playerId;
let currentTableId = null;
let chatMode = 'say';

// ============================================================== загрузка

async function boot() {
  options = await net.api('/api/options');

  hydrateIcons(document);
  buildLobby();
  buildCreator();
  wireGame();

  net.connect();
  wireSocket();

  const saved = net.identity.playerName;
  if (saved) {
    qs('#join-name').value = saved;
    qs('#host-name').value = saved;
  }
  const code = new URL(location.href).searchParams.get('code');
  if (code) qs('#join-code').value = code.toUpperCase();
}

/** Подставляет SVG в любые элементы с data-icon — разметка остаётся чистой. */
function hydrateIcons(root) {
  for (const node of root.querySelectorAll('[data-icon]')) {
    if (node.dataset.iconDone) continue;
    node.dataset.iconDone = '1';
    const size = node.classList.contains('mode') || node.tagName === 'H2' ? 14 : 15;
    node.prepend(icon(node.dataset.icon, { size }));
  }
}

// ================================================================= лобби

function buildLobby() {
  if (!options.dmConfigured) qs('#dm-warning').classList.remove('hidden');

  const tone = qs('#table-tone');
  for (const { key, desc } of options.tones) tone.append(el('option', { value: key, title: desc }, key));
  const difficulty = qs('#table-difficulty');
  for (const { key, desc } of options.difficulties) difficulty.append(el('option', { value: key, title: desc }, key));

  const describe = () => {
    qs('#tone-desc').textContent = options.tones.find((t) => t.key === tone.value)?.desc || '';
    qs('#difficulty-desc').textContent = options.difficulties.find((d) => d.key === difficulty.value)?.desc || '';
  };
  tone.addEventListener('change', describe);
  difficulty.addEventListener('change', describe);
  tone.value = 'героическое';
  difficulty.value = 'обычная';
  describe();

  qs('#create-btn').addEventListener('click', async () => {
    const name = qs('#host-name').value.trim();
    if (!name) return toast('Впиши своё имя');
    try {
      const table = await net.api('/api/tables', {
        method: 'POST',
        body: JSON.stringify({
          name: qs('#table-name').value.trim() || 'Новая кампания',
          settings: {
            tone: tone.value,
            difficulty: difficulty.value,
            premise: qs('#table-premise').value.trim(),
          },
        }),
      });
      net.joinTable({ tableId: table.id, playerName: name });
    } catch (e) {
      toast(e.message);
    }
  });

  qs('#join-btn').addEventListener('click', join);
  qs('#join-code').addEventListener('keydown', (e) => e.key === 'Enter' && join());
  qs('#join-name').addEventListener('keydown', (e) => e.key === 'Enter' && join());

  loadRecentTables();
}

function join() {
  const name = qs('#join-name').value.trim();
  const code = qs('#join-code').value.trim().toUpperCase();
  if (!name) return toast('Впиши своё имя');
  if (!code) return toast('Нужен код стола');
  net.joinTable({ code, playerName: name });
}

async function loadRecentTables() {
  try {
    const tables = await net.api('/api/tables');
    const node = clear(qs('#recent-tables'));
    if (!tables.length) return;
    node.append(el('div', { class: 'recent-label' }, 'Столы на этом сервере'));
    for (const table of tables.slice(0, 5)) {
      node.append(
        el(
          'button',
          {
            onclick: () => {
              const name = qs('#join-name').value.trim() || net.identity.playerName;
              if (!name) return toast('Впиши своё имя');
              net.joinTable({ tableId: table.id, playerName: name });
            },
          },
          [
            icon('users', { size: 14 }),
            el('span', {}, table.party.length ? `${table.name} — ${table.party.join(', ')}` : table.name),
            el('span', { class: 'recent-code' }, table.code),
          ],
        ),
      );
    }
  } catch {
    // Список последних столов — удобство, а не необходимость.
  }
}

// ==================================================== создание персонажа

function buildCreator() {
  initCreator({
    options,
    onPick: (pregenId) => net.send({ t: 'pick-pregen', pregenId }),
    onCreate: (spec) => net.send({ t: 'create-character', spec }),
    onRollAbilities: () => net.send({ t: 'roll-abilities' }),
  });
}

// ========================================================== игровой экран

function wireGame() {
  initMap({ onMove: (x, y) => net.send({ t: 'move-token', x, y }) });

  qsa('.mode').forEach((button) =>
    button.addEventListener('click', () => {
      chatMode = button.dataset.mode;
      qsa('.mode').forEach((b) => b.classList.toggle('active', b === button));
      qs('#input').focus();
    }),
  );

  qsa('.ptab').forEach((tab) =>
    tab.addEventListener('click', () => {
      qsa('.ptab').forEach((t) => t.classList.toggle('active', t === tab));
      qsa('.ptab-panel').forEach((p) => p.classList.toggle('active', p.id === `ptab-${tab.dataset.ptab}`));
    }),
  );

  qsa('.die-btn').forEach((button) =>
    button.addEventListener('click', () =>
      net.send({ t: 'roll', expression: button.dataset.die, reason: button.title || button.textContent.trim() }),
    ),
  );

  qsa('.mobile-nav button').forEach((button) =>
    button.addEventListener('click', () => {
      qsa('.mobile-nav button').forEach((b) => b.classList.toggle('active', b === button));
      qsa('.panel').forEach((p) => p.classList.toggle('mobile-active', p.dataset.mobile === button.dataset.target));
    }),
  );

  qs('#share-code').addEventListener('click', async () => {
    const url = `${location.origin}/?code=${qs('#game-table-code').textContent}`;
    try {
      await navigator.clipboard.writeText(url);
      toast('Ссылка на стол скопирована');
      qs('#toast').classList.add('good');
    } catch {
      toast(url);
    }
  });

  qs('#send-btn').addEventListener('click', sendChat);
  qs('#nudge-btn').addEventListener('click', () => net.send({ t: 'nudge' }));

  const input = qs('#input');
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      sendChat();
    }
  });
  // Поле растёт под текст, но не бесконечно.
  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = `${Math.min(input.scrollHeight, 180)}px`;
  });
}

function sendChat() {
  const input = qs('#input');
  const text = input.value.trim();
  if (!text) return;
  net.send({ t: 'chat', mode: chatMode, text });
  input.value = '';
  input.style.height = 'auto';
}

// ================================================================= сокет

function wireSocket() {
  net.on('joined', (payload) => {
    playerId = payload.playerId;
    net.identity.playerId = payload.playerId;
    net.identity.lastTable = payload.tableId;
    currentTableId = payload.tableId;

    qs('#char-table-code').textContent = payload.code;
    clear(qs('#log-inner'));
    for (const message of payload.transcript || []) game.appendMessage(message);
    history.replaceState(null, '', `?code=${payload.code}`);
  });

  net.on('state', (payload) => {
    const mine = payload.state.party.find((c) => c.playerId === playerId);
    showScreen(mine ? 'screen-game' : 'screen-character');
    game.renderState(payload.state, playerId);
  });

  net.on('message', (payload) => game.appendMessage(payload.message));
  net.on('dm-start', () => game.startStream());
  net.on('dm-delta', (payload) => game.appendDelta(payload.text));
  net.on('dm-status', (payload) => game.setTyping(payload.busy));
  net.on('ability-roll', (payload) => setPool(payload.scores));
  net.on('error', (payload) => {
    qs('#toast').classList.remove('good');
    toast(payload.text);
  });

  net.on('closed', () => {
    qs('#link-status').classList.add('offline');
    qs('#link-status').textContent = 'связь потеряна';
    game.setTyping(false);
  });
  net.on('open', () => {
    qs('#link-status').classList.remove('offline');
    qs('#link-status').textContent = 'на связи';
    // После переподключения возвращаемся за тот же стол.
    if (currentTableId && net.identity.playerName) {
      net.joinTable({ tableId: currentTableId, playerName: net.identity.playerName });
    }
  });
}

boot().catch((error) => {
  console.error(error);
  toast(`Не удалось загрузить приложение: ${error.message}`);
});
