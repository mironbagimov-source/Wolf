// Игровой экран: лента чата, состав партии, инициатива, задачи и лист персонажа.

import { el, qs, clear, renderRich } from './dom.js';
import * as net from './net.js';
import { render as renderMap } from './battlemap.js';

const ABILITY_RU = { str: 'Сила', dex: 'Ловкость', con: 'Телосложение', int: 'Интеллект', wis: 'Мудрость', cha: 'Харизма' };
const SKILL_RU = {
  acrobatics: 'Акробатика',
  'animal-handling': 'Уход за животными',
  arcana: 'Магия',
  athletics: 'Атлетика',
  deception: 'Обман',
  history: 'История',
  insight: 'Проницательность',
  intimidation: 'Запугивание',
  investigation: 'Анализ',
  medicine: 'Медицина',
  nature: 'Природа',
  perception: 'Внимательность',
  performance: 'Выступление',
  persuasion: 'Убеждение',
  religion: 'Религия',
  'sleight-of-hand': 'Ловкость рук',
  stealth: 'Скрытность',
  survival: 'Выживание',
};
const CONDITION_RU = {
  blinded: 'Ослеплён',
  charmed: 'Очарован',
  deafened: 'Оглушён',
  frightened: 'Испуган',
  grappled: 'Схвачен',
  incapacitated: 'Недееспособен',
  invisible: 'Невидим',
  paralyzed: 'Парализован',
  petrified: 'Окаменел',
  poisoned: 'Отравлен',
  prone: 'Сбит с ног',
  restrained: 'Опутан',
  stunned: 'Ошеломлён',
  unconscious: 'Без сознания',
};

const mod = (value) => (value < 0 ? `−${Math.abs(value)}` : `+${value}`);

let tableState = null;
let streamNode = null;

// ------------------------------------------------------------------ чат

export function appendMessage(message) {
  const log = qs('#log');
  const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 120;

  // Настоящее сообщение мастера пришло — убираем потоковую заглушку.
  if (message.type === 'dm' && streamNode) {
    streamNode.remove();
    streamNode = null;
  }

  log.append(buildMessage(message));
  if (atBottom) log.scrollTop = log.scrollHeight;
}

function buildMessage(message) {
  if (message.type === 'dm') {
    return el('div', { class: 'msg msg-dm' }, [renderRich(message.text)]);
  }
  if (message.type === 'roll') {
    return el('div', { class: 'msg' }, [el('div', { class: 'msg-roll' }, `🎲 ${message.text}`)]);
  }
  if (message.type === 'system') {
    const important = /^[⚔🗺📍📜⭐☠🛡💰🎒✨🌙]/u.test(message.text || '');
    return el('div', { class: `msg msg-system${important ? ' important' : ''}` }, message.text);
  }

  const authorName = message.characterName || message.authorName || 'Кто-то';
  const cssClass = message.type === 'action' ? 'msg-action' : message.type === 'ooc' ? 'msg-ooc' : 'msg-ic';
  return el('div', { class: `msg ${cssClass}` }, [
    el('span', { class: 'author', style: message.characterColor ? { color: message.characterColor } : {} }, `${authorName}:`),
    el('span', { class: 'body' }, message.text),
  ]);
}

export function startStream() {
  const log = qs('#log');
  streamNode = el('div', { class: 'msg msg-dm' }, '');
  log.append(streamNode);
  log.scrollTop = log.scrollHeight;
}

export function appendDelta(text) {
  if (!streamNode) startStream();
  streamNode.textContent += text;
  const log = qs('#log');
  if (log.scrollHeight - log.scrollTop - log.clientHeight < 200) log.scrollTop = log.scrollHeight;
}

export function setTyping(busy) {
  qs('#dm-typing').classList.toggle('hidden', !busy);
  if (!busy && streamNode && !streamNode.textContent.trim()) {
    streamNode.remove();
    streamNode = null;
  }
}

// --------------------------------------------------------------- панели

export function renderState(next, playerId) {
  tableState = next;

  qs('#scene-location').textContent = next.scene.location || '—';
  qs('#scene-time').textContent = [next.scene.time, next.scene.weather].filter(Boolean).join(', ');
  qs('#game-table-code').textContent = next.code;

  renderInitiative(next);
  renderParty(next, playerId);
  renderQuests(next);

  const mine = next.party.find((c) => c.playerId === playerId);
  renderSheet(mine);
  renderMap(next.map, mine?.id || null);
}

function renderInitiative(next) {
  const node = qs('#initiative');
  if (!next.combat?.active) {
    node.classList.add('hidden');
    return;
  }
  node.classList.remove('hidden');
  clear(node).append(
    el('h3', {}, `Бой — раунд ${next.combat.round}`),
    ...next.combat.order.map((entry, index) =>
      el('div', { class: `init-row${index === next.combat.turnIndex ? ' current' : ''}` }, [
        el('span', {}, entry.name + (entry.surprised ? ' (врасплох)' : '')),
        el('span', { class: 'init-value' }, String(entry.initiative)),
      ]),
    ),
  );
}

function renderParty(next, playerId) {
  const node = clear(qs('#party'));

  for (const character of next.party) {
    const ratio = Math.max(0, Math.min(1, character.hp.current / character.hp.max));
    const down = character.hp.current === 0 || character.dead;
    node.append(
      el('div', { class: `pc${down ? ' down' : ''}` }, [
        el('div', { class: 'pc-head' }, [
          el('span', { class: 'pc-name', style: { color: character.portraitColor } }, character.name),
          el('span', { class: 'pc-meta' }, character.playerId === playerId ? 'ты' : character.playerName || ''),
        ]),
        el('div', { class: 'hpbar' }, [el('div', { style: { width: `${ratio * 100}%` } })]),
        el('div', { class: 'pc-stats' }, [
          el('span', {}, character.dead ? 'мёртв' : `${character.hp.current}/${character.hp.max} хп`),
          el('span', {}, `КД ${character.ac}`),
          el('span', {}, `${character.level} ур.`),
        ]),
        character.conditions?.length
          ? el(
              'div',
              { class: 'conditions' },
              character.conditions.map((c) => el('span', { class: 'condition' }, CONDITION_RU[c.name] || c.name)),
            )
          : null,
        character.hp.current === 0 && !character.dead
          ? el('div', { class: 'pc-stats' }, [
              el('span', {}, `при смерти: ✓${character.deathSaves.successes} ✗${character.deathSaves.failures}`),
            ])
          : null,
      ]),
    );
  }

  const hostiles = next.npcs.filter((n) => n.hostile && !n.dead);
  if (hostiles.length) {
    node.append(
      el('div', { class: 'quests' }, [
        el('h3', {}, 'Противники'),
        ...hostiles.map((n) =>
          el('div', { class: 'quest' }, [
            n.name,
            el('span', { class: 'status' }, ` — ${n.hp}`),
          ]),
        ),
      ]),
    );
  }
}

function renderQuests(next) {
  const node = clear(qs('#quests'));
  const open = (next.quests || []).filter((q) => q.status !== 'выполнен');
  if (open.length === 0 && !(next.loot || []).length) return;

  if (open.length) {
    node.append(el('h3', {}, 'Задачи'));
    for (const quest of open) {
      node.append(
        el('div', { class: 'quest' }, [quest.title, el('span', { class: 'status' }, ` — ${quest.status}`)]),
      );
    }
  }
  if ((next.loot || []).length) {
    node.append(
      el('h3', { style: { marginTop: '10px' } }, 'Общая добыча'),
      el('div', { class: 'quest' }, next.loot.map((l) => `${l.name}${l.qty > 1 ? ` ×${l.qty}` : ''}`).join(', ')),
    );
  }
}

// -------------------------------------------------------- лист персонажа

function renderSheet(character) {
  const node = clear(qs('#sheet'));
  if (!character) {
    node.append(el('p', { class: 'hint' }, 'Персонаж не выбран.'));
    return;
  }

  node.append(
    el('h3', {}, character.name),
    el('div', { class: 'sub' }, `${character.level} уровень · КД ${character.ac} · ${character.hp.current}/${character.hp.max} хп · скорость ${character.speed} фт.`),
  );

  node.append(
    el(
      'div',
      { class: 'sheet-row' },
      Object.entries(ABILITY_RU).map(([key, label]) =>
        el('button', { class: 'stat-box', onclick: () => rollCheck(`проверка: ${label}`, character.mods[key]) }, [
          el('div', { class: 'label' }, label.slice(0, 3)),
          el('div', { class: 'value' }, String(character.abilities[key])),
          el('div', { class: 'label' }, mod(character.mods[key])),
        ]),
      ),
    ),
  );

  node.append(
    section('Спасброски', [
      el(
        'div',
        { class: 'tag-list' },
        Object.entries(ABILITY_RU).map(([key, label]) =>
          el('button', { class: 'tag', onclick: () => rollCheck(`спасбросок: ${label}`, character.saves[key]) }, `${label.slice(0, 3)} ${mod(character.saves[key])}`),
        ),
      ),
    ]),
  );

  node.append(
    section(
      'Навыки',
      Object.entries(SKILL_RU).map(([key, label]) =>
        el('button', { class: `kv${character.skills.includes(key) ? ' prof' : ''}`, style: { width: '100%', background: 'none', border: 'none', padding: '2px 0' }, onclick: () => rollCheck(`проверка: ${label}`, character.skillMods[key]) }, [
          el('span', {}, label),
          el('strong', {}, mod(character.skillMods[key])),
        ]),
      ),
    ),
  );

  if (character.attacks?.length) {
    node.append(
      section(
        'Атаки',
        character.attacks.map((attack) =>
          el('div', { class: 'attack-row' }, [
            el('span', {}, attack.name),
            el('span', {}, [
              el('button', { onclick: () => rollCheck(`атака: ${attack.name}`, attack.attackBonus) }, mod(attack.attackBonus)),
              ' ',
              attack.damage
                ? el('button', { onclick: () => net.send({ t: 'roll', expression: attack.damage, reason: `урон: ${attack.name}` }) }, attack.damage)
                : null,
            ]),
          ]),
        ),
      ),
    );
  }

  if (character.spellcasting) {
    const slots = Object.entries(character.spellcasting.slots || {}).map(
      ([level, max]) => `${level} кр.: ${max - (character.spells.slotsUsed?.[level] || 0)}/${max}`,
    );
    node.append(
      section('Магия', [
        el('div', { class: 'kv' }, [el('span', {}, 'СЛ спасброска'), el('strong', {}, String(character.spellcasting.dc))]),
        el('div', { class: 'kv' }, [el('span', {}, 'Бонус атаки'), el('strong', {}, mod(character.spellcasting.attack))]),
        slots.length ? el('div', { class: 'kv' }, [el('span', {}, 'Ячейки'), el('strong', {}, slots.join(', '))]) : null,
        character.spells.cantrips?.length ? el('div', { class: 'hint', style: { margin: '6px 0 0' } }, `Заговоры: ${character.spells.cantrips.length}`) : null,
      ]),
    );
  }

  node.append(
    section('Снаряжение', [
      el(
        'div',
        { class: 'tag-list' },
        (character.inventory || []).map((item) =>
          el('span', { class: 'tag' }, `${item.name}${item.qty > 1 ? ` ×${item.qty}` : ''}`),
        ),
      ),
      el('div', { class: 'kv', style: { marginTop: '8px' } }, [el('span', {}, 'Монеты'), el('strong', {}, `${character.gold} зм`)]),
    ]),
  );

  const notes = el('textarea', {
    rows: 4,
    value: character.notes || '',
    placeholder: 'Заметки: имена, обещания, подозрения…',
    onchange: (event) => net.send({ t: 'update-notes', notes: event.target.value }),
  });
  node.append(section('Заметки', [notes]));
}

function section(title, children) {
  return el('div', { class: 'sheet-section' }, [el('h4', {}, title), ...[].concat(children)]);
}

function rollCheck(reason, modifier) {
  const expression = `1d20${modifier >= 0 ? '+' : ''}${modifier}`;
  net.send({ t: 'roll', expression, reason });
}
