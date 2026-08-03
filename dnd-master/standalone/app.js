// Точка входа однофайловой сборки.
//
// Отличий от сетевой версии два: стол стоит прямо здесь (standalone/table.js),
// и мастера зовёт сам браузер по ключу, который игрок вписал в настройках.
// Игровой экран, лист персонажа, карта и создание героя — те же самые модули.

import { el, qs, qsa, clear, toast, showScreen } from '../public/js/dom.js';
import * as game from '../public/js/game.js';
import { icon } from '../public/js/icons.js';
import { initMap } from '../public/js/battlemap.js';
import { initCreator, setPool } from '../public/js/creator.js';

import { buildOptions } from './options.js';
import * as table from './table.js';
import * as agent from './agent.js';

const MODELS = [
  { id: 'claude-opus-5', name: 'Opus 5 — лучший мастер' },
  { id: 'claude-sonnet-5', name: 'Sonnet 5 — быстрее и дешевле' },
  { id: 'claude-haiku-4-5-20251001', name: 'Haiku 4.5 — самый быстрый' },
];

const EFFORTS = [
  { id: 'low', name: 'коротко — ходы быстрые' },
  { id: 'medium', name: 'обычно' },
  { id: 'high', name: 'вдумчиво — мастер думает дольше' },
];

const STORE = { key: 'dnd.solo.key', model: 'dnd.solo.model', effort: 'dnd.solo.effort' };

const remember = (name, value) => {
  try {
    localStorage.setItem(name, value);
  } catch {
    /* приватный режим — переживём */
  }
};
const recall = (name, fallback = '') => {
  try {
    return localStorage.getItem(name) || fallback;
  } catch {
    return fallback;
  }
};

let options = null;
let chatMode = 'say';

// ============================================================== загрузка

function boot() {
  options = buildOptions();

  agent.configure({
    apiKey: recall(STORE.key),
    model: recall(STORE.model, 'claude-opus-5'),
    effort: recall(STORE.effort, 'medium'),
  });
  // ?api=... — для тех, кто ходит к API через свой прокси (и для прогонов).
  const apiBase = new URL(location.href).searchParams.get('api');
  if (apiBase) agent.configure({ apiBase: apiBase.replace(/\/$/, '') });

  hydrateIcons(document);
  buildLobby();
  buildCreator();
  buildModal();
  wireGame();
  wireTable();
}

function hydrateIcons(root) {
  for (const node of root.querySelectorAll('[data-icon]')) {
    if (node.dataset.iconDone) continue;
    node.dataset.iconDone = '1';
    const size = node.classList.contains('mode') || node.tagName === 'H2' ? 14 : 15;
    node.prepend(icon(node.dataset.icon, { size }));
  }
}

const fillSelect = (node, items, selected) => {
  clear(node);
  for (const item of items) node.append(el('option', { value: item.id, selected: item.id === selected }, item.name));
};

// ================================================================= лобби

function buildLobby() {
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

  fillSelect(qs('#api-model'), MODELS, agent.settings.model);
  fillSelect(qs('#api-effort'), EFFORTS, agent.settings.effort);
  qs('#api-key').value = agent.settings.apiKey;

  const saveKey = () => {
    agent.configure({
      apiKey: qs('#api-key').value.trim(),
      model: qs('#api-model').value,
      effort: qs('#api-effort').value,
    });
    remember(STORE.key, agent.settings.apiKey);
    remember(STORE.model, agent.settings.model);
    remember(STORE.effort, agent.settings.effort);
    refreshKeyState();
  };
  qs('#api-key').addEventListener('change', saveKey);
  qs('#api-model').addEventListener('change', saveKey);
  qs('#api-effort').addEventListener('change', saveKey);
  refreshKeyState();

  qs('#create-btn').addEventListener('click', () => {
    saveKey();
    table.createTable({
      name: qs('#table-name').value.trim() || 'Новая кампания',
      settings: {
        tone: tone.value,
        difficulty: difficulty.value,
        premise: qs('#table-premise').value.trim(),
      },
    });
    mountTable();
    showScreen('screen-character');
    renderRoster();
  });

  renderSavedTables();
}

function refreshKeyState() {
  const node = qs('#key-state');
  const ok = agent.hasApiKey();
  node.textContent = ok ? 'Ключ сохранён в этом браузере — мастер готов вести.' : 'Без ключа мастер молчать будет, а правила и кубики работают.';
  node.classList.toggle('good', ok);
  const status = qs('#link-status');
  status.textContent = ok ? 'мастер на связи' : 'ключ не задан';
  status.classList.toggle('offline', !ok);
}

function renderSavedTables() {
  const node = clear(qs('#saved-tables'));
  const saved = table.listTables();
  if (!saved.length) return;

  node.append(el('div', { class: 'recent-label' }, 'Сохранённые кампании'));
  for (const summary of saved) {
    node.append(
      el('button', { onclick: () => resume(summary.id) }, [
        icon('scroll', { size: 14 }),
        el('span', {}, summary.party.length ? `${summary.name} — ${summary.party.join(', ')}` : summary.name),
        el('span', { class: 'recent-code' }, summary.location || ''),
      ]),
    );
  }
}

function resume(id) {
  if (!table.openTable(id)) return toast('Не получилось открыть эту кампанию');
  mountTable();
  if (table.current().party.length) enterGame();
  else {
    showScreen('screen-character');
    renderRoster();
  }
}

/** Перерисовывает ленту с нуля — после открытия или загрузки кампании. */
function mountTable() {
  const st = table.current();
  clear(qs('#log-inner'));
  for (const message of st.transcript.slice(-300)) game.appendMessage(message);
  qs('#char-campaign').textContent = st.name;
  table.pushState();
  renderSavedTables();
}

// ==================================================== создание персонажа

function buildCreator() {
  initCreator({
    options,
    onPick: (pregenId) => table.dispatch({ t: 'pick-pregen', pregenId }),
    onCreate: (spec) => table.dispatch({ t: 'create-character', spec }),
    onRollAbilities: () => table.dispatch({ t: 'roll-abilities' }),
  });

  qs('#start-play').addEventListener('click', enterGame);
}

function renderRoster() {
  const st = table.current();
  const node = clear(qs('#roster'));
  const party = st?.party || [];

  qs('#start-play').disabled = party.length === 0;
  qs('#roster-hint').textContent = party.length
    ? 'Можно добавить ещё героев — за одним экраном играет вся компания.'
    : 'Возьмите готового героя или соберите своего. Героев может быть сколько угодно.';

  for (const character of party) {
    node.append(
      el('span', { class: 'roster-chip', style: { '--accent': character.portraitColor } }, [
        el('span', { class: 'roster-dot' }),
        character.name,
      ]),
    );
  }
}

// ========================================================== игровой экран

function enterGame() {
  const st = table.current();
  if (!st?.party.length) return toast('Сначала нужен хотя бы один герой');
  showScreen('screen-game');
  table.pushState();

  // Партия собралась, а мастер ещё не сказал ни слова — пусть открывает сцену.
  if (st.dm.messages.length === 0 && agent.hasApiKey()) {
    table.nudge('Партия собралась. Открой сцену: где они, что видят, чем пахнет воздух — и дай зацепку, за которую можно потянуть.');
  }
}

function wireGame() {
  initMap({ onMove: (x, y) => table.dispatch({ t: 'move-token', x, y }) });

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
      table.dispatch({ t: 'roll', expression: button.dataset.die, reason: button.title || button.textContent.trim() }),
    ),
  );

  qsa('.mobile-nav button').forEach((button) =>
    button.addEventListener('click', () => {
      qsa('.mobile-nav button').forEach((b) => b.classList.toggle('active', b === button));
      qsa('.panel').forEach((p) => p.classList.toggle('mobile-active', p.dataset.mobile === button.dataset.target));
    }),
  );

  qs('#add-hero').addEventListener('click', () => {
    showScreen('screen-character');
    renderRoster();
  });
  qs('#settings-btn').addEventListener('click', openModal);

  qs('#send-btn').addEventListener('click', sendChat);
  qs('#nudge-btn').addEventListener('click', () => table.dispatch({ t: 'nudge' }));

  const input = qs('#input');
  input.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      sendChat();
    }
  });
  input.addEventListener('input', () => {
    input.style.height = 'auto';
    input.style.height = `${Math.min(input.scrollHeight, 180)}px`;
  });
}

function sendChat() {
  const input = qs('#input');
  const text = input.value.trim();
  if (!text) return;
  table.dispatch({ t: 'chat', mode: chatMode, text });
  input.value = '';
  input.style.height = 'auto';
}

/** Кто сейчас за клавиатурой: без этого за одним экраном не разойтись. */
function renderWhoBar(next, activePlayerId) {
  const node = clear(qs('#who-bar'));
  if (next.party.length <= 1) {
    node.classList.add('hidden');
    return;
  }
  node.classList.remove('hidden');
  node.append(el('span', { class: 'who-label' }, 'ходит'));
  for (const character of next.party) {
    node.append(
      el(
        'button',
        {
          class: `who${character.playerId === activePlayerId ? ' active' : ''}`,
          style: { '--accent': character.portraitColor },
          onclick: () => table.setActive(character.playerId),
        },
        character.name,
      ),
    );
  }
}

// ================================================================== стол

function wireTable() {
  table.on('state', ({ state: next, activePlayerId }) => {
    game.renderState(next, activePlayerId);
    renderWhoBar(next, activePlayerId);
    renderRoster();
    // Только имя, без прозвища: полное в одну строку поля ввода не влезает.
    const acting = next.party.find((c) => c.playerId === activePlayerId);
    qs('#input').placeholder = acting ? `Что делает ${acting.name.split(' ')[0]}?` : 'Что ты делаешь?';
  });

  table.on('message', ({ message }) => game.appendMessage(message));
  table.on('dm-start', () => game.startStream());
  table.on('dm-delta', ({ text }) => game.appendDelta(text));
  table.on('dm-status', ({ busy }) => game.setTyping(busy));
  table.on('ability-roll', ({ scores }) => setPool(scores));
  table.on('error', ({ text }) => {
    qs('#toast').classList.remove('good');
    toast(text);
  });
}

// ============================================================ настройки

function buildModal() {
  fillSelect(qs('#dlg-model'), MODELS, agent.settings.model);
  fillSelect(qs('#dlg-effort'), EFFORTS, agent.settings.effort);
  for (const { key, desc } of options.tones) qs('#dlg-tone').append(el('option', { value: key, title: desc }, key));
  for (const { key, desc } of options.difficulties) {
    qs('#dlg-difficulty').append(el('option', { value: key, title: desc }, key));
  }

  qs('#dlg-close').addEventListener('click', closeModal);
  qs('#modal').addEventListener('click', (event) => {
    if (event.target.id === 'modal') closeModal();
  });

  qs('#dlg-export').addEventListener('click', () => {
    const st = table.current();
    if (!st) return;
    const blob = new Blob([table.exportTable()], { type: 'application/json' });
    const link = el('a', { href: URL.createObjectURL(blob), download: `${st.name.replace(/[^\wа-яА-Я -]/g, '')}.dnd.json` });
    link.click();
    URL.revokeObjectURL(link.href);
    toast('Кампания сохранена в файл');
    qs('#toast').classList.add('good');
  });

  qs('#dlg-import').addEventListener('click', () => qs('#dlg-file').click());
  qs('#dlg-file').addEventListener('change', async (event) => {
    const file = event.target.files?.[0];
    if (!file) return;
    try {
      table.importTable(await file.text());
      closeModal();
      mountTable();
      if (table.current().party.length) enterGame();
      else showScreen('screen-character');
      toast('Кампания загружена');
      qs('#toast').classList.add('good');
    } catch (e) {
      toast(`Не удалось загрузить: ${e.message}`);
    }
    event.target.value = '';
  });
}

function openModal() {
  const st = table.current();
  qs('#dlg-key').value = agent.settings.apiKey;
  qs('#dlg-model').value = agent.settings.model;
  qs('#dlg-effort').value = agent.settings.effort;
  if (st) {
    qs('#dlg-tone').value = st.settings.tone;
    qs('#dlg-difficulty').value = st.settings.difficulty;
  }
  qs('#modal').classList.remove('hidden');
}

function closeModal() {
  agent.configure({
    apiKey: qs('#dlg-key').value.trim(),
    model: qs('#dlg-model').value,
    effort: qs('#dlg-effort').value,
  });
  remember(STORE.key, agent.settings.apiKey);
  remember(STORE.model, agent.settings.model);
  remember(STORE.effort, agent.settings.effort);
  refreshKeyState();

  if (table.current()) {
    table.dispatch({ t: 'settings', patch: { tone: qs('#dlg-tone').value, difficulty: qs('#dlg-difficulty').value } });
  }
  qs('#modal').classList.add('hidden');
}

boot();
