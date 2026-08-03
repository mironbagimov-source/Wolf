// Точка входа: лобби, создание персонажа и подключение игрового экрана.

import { el, qs, qsa, clear, toast, showScreen } from './dom.js';
import * as net from './net.js';
import * as game from './game.js';
import { icon, classIcon } from './icons.js';
import { initMap } from './battlemap.js';

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

const creator = { pool: [], assignment: {}, chosenSkills: new Set() };

const CLASS_PRIORITY = {
  barbarian: ['str', 'con', 'dex', 'wis', 'cha', 'int'],
  bard: ['cha', 'dex', 'con', 'wis', 'int', 'str'],
  cleric: ['wis', 'con', 'str', 'cha', 'dex', 'int'],
  druid: ['wis', 'con', 'dex', 'int', 'cha', 'str'],
  fighter: ['str', 'con', 'dex', 'wis', 'cha', 'int'],
  monk: ['dex', 'wis', 'con', 'str', 'cha', 'int'],
  paladin: ['str', 'cha', 'con', 'wis', 'dex', 'int'],
  ranger: ['dex', 'wis', 'con', 'str', 'int', 'cha'],
  rogue: ['dex', 'int', 'con', 'wis', 'cha', 'str'],
  sorcerer: ['cha', 'con', 'dex', 'wis', 'int', 'str'],
  warlock: ['cha', 'con', 'dex', 'wis', 'int', 'str'],
  wizard: ['int', 'con', 'dex', 'wis', 'cha', 'str'],
};

const ABILITY_LABELS = { str: 'Сила', dex: 'Ловкость', con: 'Телосложение', int: 'Интеллект', wis: 'Мудрость', cha: 'Харизма' };
const formatMod = (value) => (value < 0 ? `−${Math.abs(value)}` : `+${value}`);

function buildCreator() {
  qsa('.tab').forEach((tab) =>
    tab.addEventListener('click', () => {
      qsa('.tab').forEach((t) => t.classList.toggle('active', t === tab));
      qsa('.tab-panel').forEach((p) => p.classList.toggle('active', p.id === `tab-${tab.dataset.tab}`));
    }),
  );

  const list = clear(qs('#pregen-list'));
  for (const pregen of options.pregens) {
    const sigil = el('div', { class: 'pregen-sigil', style: { color: pregen.portraitColor } });
    sigil.append(classIcon(pregen.class, { size: 20 }));
    list.append(
      el(
        'button',
        {
          class: 'pregen',
          style: { '--accent': pregen.portraitColor },
          onclick: () => net.send({ t: 'pick-pregen', pregenId: pregen.id }),
        },
        [
          el('div', { class: 'pregen-head' }, [
            sigil,
            el('div', {}, [
              el('h3', {}, pregen.name),
              el('div', { class: 'role' }, `${pregen.preview.raceName} · ${pregen.preview.className}`),
            ]),
          ]),
          el('p', {}, pregen.blurb),
          el('div', { class: 'hook' }, pregen.hook),
        ],
      ),
    );
  }

  const race = qs('#c-race');
  for (const r of options.races) race.append(el('option', { value: r.index }, `${r.name} (${r.bonuses.join(', ')})`));
  const klass = qs('#c-class');
  for (const c of options.classes) klass.append(el('option', { value: c.index }, `${c.name} · к${c.hitDie}`));
  const background = qs('#c-background');
  for (const b of options.backgrounds) background.append(el('option', { value: b.index }, `${b.name} — ${b.skills.join(', ')}`));

  race.addEventListener('change', refreshSubraces);
  klass.addEventListener('change', () => {
    refreshSkills();
    setPool(creator.pool);
  });
  background.addEventListener('change', refreshSkills);

  qs('#use-array').addEventListener('click', () => {
    qs('#use-array').classList.add('active');
    qs('#use-roll').classList.remove('active');
    setPool([...options.standardArray]);
  });
  qs('#use-roll').addEventListener('click', () => {
    qs('#use-roll').classList.add('active');
    qs('#use-array').classList.remove('active');
    net.send({ t: 'roll-abilities' });
  });

  qs('#create-character-btn').addEventListener('click', submitCharacter);

  refreshSubraces();
  refreshSkills();
  setPool([...options.standardArray]);
}

function refreshSubraces() {
  const race = options.races.find((r) => r.index === qs('#c-race').value);
  const select = clear(qs('#c-subrace'));
  select.append(el('option', { value: '' }, '— без разновидности —'));
  for (const sub of race?.subraces || []) select.append(el('option', { value: sub.index }, sub.name));
  select.disabled = !(race?.subraces || []).length;
}

const currentClass = () => options.classes.find((c) => c.index === qs('#c-class').value) || options.classes[0];

function refreshSkills() {
  const cls = currentClass();
  const allowed = new Set(cls.skillChoices.from);
  const limit = cls.skillChoices.choose;

  for (const skill of [...creator.chosenSkills]) {
    if (!allowed.has(skill)) creator.chosenSkills.delete(skill);
  }

  const list = clear(qs('#skill-list'));
  for (const skill of options.skills) {
    const selectable = allowed.has(skill.index);
    list.append(
      el('label', { class: `skill-item${selectable ? '' : ' disabled'}` }, [
        el('input', {
          type: 'checkbox',
          checked: creator.chosenSkills.has(skill.index),
          disabled: !selectable,
          onchange: (event) => {
            if (event.target.checked) {
              if (creator.chosenSkills.size >= limit) {
                event.target.checked = false;
                return toast(`${currentClass().name}: можно выбрать ${limit}`);
              }
              creator.chosenSkills.add(skill.index);
            } else {
              creator.chosenSkills.delete(skill.index);
            }
            updateSkillCounter();
          },
        }),
        el('span', {}, skill.name),
        el('span', { class: 'skill-ability' }, skill.ability.slice(0, 3)),
      ]),
    );
  }
  updateSkillCounter();
}

function updateSkillCounter() {
  const cls = currentClass();
  const bgSkills = options.backgrounds.find((b) => b.index === qs('#c-background').value)?.skills || [];
  qs('#skill-counter').textContent =
    `${creator.chosenSkills.size}/${cls.skillChoices.choose}` +
    (bgSkills.length ? ` · от предыстории: ${bgSkills.join(', ')}` : '');
}

function setPool(scores) {
  creator.pool = scores.length ? scores : [...options.standardArray];
  const sorted = [...creator.pool].sort((a, b) => b - a);
  const priority = CLASS_PRIORITY[qs('#c-class').value] || Object.keys(ABILITY_LABELS);
  creator.assignment = {};
  priority.forEach((ability, i) => {
    creator.assignment[ability] = sorted[i];
  });
  refreshAbilityRows();
}

function refreshAbilityRows() {
  const node = clear(qs('#ability-rows'));
  for (const [ability, label] of Object.entries(ABILITY_LABELS)) {
    const score = creator.assignment[ability] ?? 10;
    const select = el('select', {
      onchange: (event) => {
        const wanted = Number(event.target.value);
        // Значения из набора уникальны: если оно занято — меняемся местами.
        const holder = Object.keys(creator.assignment).find((k) => creator.assignment[k] === wanted && k !== ability);
        if (holder) creator.assignment[holder] = creator.assignment[ability];
        creator.assignment[ability] = wanted;
        refreshAbilityRows();
      },
    });
    for (const value of creator.pool) select.append(el('option', { value: String(value) }, String(value)));
    select.value = String(score);

    node.append(
      el('div', { class: 'ability-row' }, [
        el('div', { class: 'name' }, label),
        el('div', { class: 'score' }, String(score)),
        el('div', { class: 'mod' }, formatMod(Math.floor((score - 10) / 2))),
        select,
      ]),
    );
  }
}

function submitCharacter() {
  const name = qs('#c-name').value.trim();
  if (!name) return toast('У героя должно быть имя');
  const cls = currentClass();
  if (creator.chosenSkills.size !== cls.skillChoices.choose) {
    return toast(`Выбери ровно ${cls.skillChoices.choose} навыка для класса «${cls.name}»`);
  }
  net.send({
    t: 'create-character',
    spec: {
      name,
      race: qs('#c-race').value,
      subrace: qs('#c-subrace').value || null,
      class: qs('#c-class').value,
      background: qs('#c-background').value,
      alignment: qs('#c-alignment').value,
      skills: [...creator.chosenSkills],
      abilities: creator.assignment,
      portraitColor: qs('#c-color').value,
      blurb: qs('#c-blurb').value.trim(),
      hook: qs('#c-hook').value.trim(),
    },
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
