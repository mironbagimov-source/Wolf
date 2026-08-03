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
import { initDmSettings, moveDmSettings, restoreSettings, refreshState } from './dm-settings.js';

let options = null;
let chatMode = 'say';

// ============================================================== загрузка

function boot() {
  options = buildOptions();

  restoreSettings();
  // ?api=... — для тех, кто ходит к Claude через свой прокси (и для прогонов).
  const apiBase = new URL(location.href).searchParams.get('api');
  if (apiBase) agent.configure({ apiBase: apiBase.replace(/\/$/, '') });

  hydrateIcons(document);
  buildLobby();
  initDmSettings({ onChange: refreshLinkStatus });
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

  qs('#create-btn').addEventListener('click', () => {
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

/** Огонёк в шапке: готов ли мастер отвечать и кто это вообще. */
function refreshLinkStatus() {
  const ok = agent.isReady();
  const status = qs('#link-status');
  status.textContent = !ok
    ? 'мастер не настроен'
    : agent.settings.provider === 'offline'
      ? 'встроенный мастер'
      : agent.settings.provider === 'claude'
        ? 'мастер на связи'
        : 'своя модель';
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
  if (st.dm.messages.length === 0 && agent.isReady()) {
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
  // Блок настройки мастера один на приложение и переезжает сюда из лобби.
  moveDmSettings('#dm-slot');
  refreshState();
  if (st) {
    qs('#dlg-tone').value = st.settings.tone;
    qs('#dlg-difficulty').value = st.settings.difficulty;
  }
  qs('#modal').classList.remove('hidden');
}

function closeModal() {
  moveDmSettings('#dm-home');
  refreshLinkStatus();
  if (table.current()) {
    table.dispatch({ t: 'settings', patch: { tone: qs('#dlg-tone').value, difficulty: qs('#dlg-difficulty').value } });
  }
  qs('#modal').classList.add('hidden');
}

boot();
