// Игровой экран: лента чата, партия, инициатива, задачи и лист персонажа.

import { el, qs, clear, renderRich } from './dom.js';
import * as net from './net.js';
import { icon, classIcon, dieGlyph } from './icons.js';
import { render as renderMap } from './battlemap.js';

const ABILITY_RU = { str: 'Сила', dex: 'Ловкость', con: 'Телосложение', int: 'Интеллект', wis: 'Мудрость', cha: 'Харизма' };
const ABILITY_SHORT = { str: 'сил', dex: 'лов', con: 'тел', int: 'инт', wis: 'муд', cha: 'хар' };
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

let streamNode = null;

// ================================================================== чат

export function appendMessage(message) {
  const log = qs('#log');
  const inner = qs('#log-inner');
  const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 140;

  // Пришла настоящая реплика мастера — убираем потоковую заглушку.
  if (message.type === 'dm' && streamNode) {
    streamNode.remove();
    streamNode = null;
  }

  inner.append(buildMessage(message));
  if (atBottom) log.scrollTop = log.scrollHeight;
}

function buildMessage(message) {
  if (message.type === 'dm') {
    return el('div', { class: 'msg msg-dm' }, [renderRich(message.text)]);
  }
  if (message.type === 'roll') {
    return el('div', { class: 'msg' }, [buildRoll(message)]);
  }
  if (message.type === 'system') {
    const text = stripEmoji(message.text);
    const marked = /^[⚔🗺📍📜⭐☠🛡💰🎒✨🌙]/u.test(message.text || '');
    const danger = /^[☠]/u.test(message.text || '');
    const banner = marked && text.length <= 48;
    return el(
      'div',
      { class: `msg msg-system${banner ? ' important' : marked ? ' marked' : ''}${danger ? ' danger' : ''}` },
      [el('span', {}, text)],
    );
  }

  const authorName = message.characterName || message.authorName || 'Кто-то';
  const cssClass = message.type === 'action' ? 'msg-action' : message.type === 'ooc' ? 'msg-ooc' : 'msg-ic';
  return el('div', { class: `msg ${cssClass}` }, [
    el(
      'span',
      { class: 'author', style: message.characterColor ? { color: message.characterColor } : {} },
      `${authorName}:`,
    ),
    el('span', { class: 'body' }, message.text),
  ]);
}

const stripEmoji = (text) => String(text || '').replace(/^[⚔🗺📍📜⭐☠🛡💰🎒✨🌙]\s*/u, '');

/**
 * Броски приходят строкой в нашем же формате («проверка: 2d6[4,6] +3 = 13»),
 * поэтому разбираем её обратно и показываем кости как кости, а не как текст.
 */
function parseRollText(text) {
  const match = String(text).match(/^(.*?):\s*([^=]*?)\s*=\s*([−-]?\d+)\s*(.*)$/s);
  if (!match) return null;

  const [, label, expression, totalRaw, extra] = match;
  const total = Number(totalRaw.replace('−', '-'));
  const groups = [];
  let sawD20 = false;
  let crit = false;
  let fumble = false;

  for (const token of expression.trim().split(/\s+/)) {
    const diceToken = token.match(/^([+−-]?)(\d+)d(\d+)\[(.*)\]$/);
    if (diceToken) {
      const faces = Number(diceToken[3]);
      const values = diceToken[4]
        .split(',')
        .filter(Boolean)
        .map((raw) => {
          const dropped = raw.startsWith('~~');
          const value = Number(raw.replace(/~/g, ''));
          return { value, dropped };
        });
      if (faces === 20) {
        sawD20 = true;
        for (const die of values) {
          if (die.dropped) continue;
          if (die.value === 20) crit = true;
          if (die.value === 1) fumble = true;
        }
      }
      groups.push({ kind: 'dice', faces, values, sign: diceToken[1] });
      continue;
    }
    const flat = token.match(/^([+−-]?)(\d+)$/);
    if (flat) groups.push({ kind: 'flat', text: token });
  }

  return { label: label.trim(), groups, total, extra: extra.trim(), crit: sawD20 && crit, fumble: sawD20 && fumble };
}

function buildRoll(message) {
  const parsed = parseRollText(message.text);
  if (!parsed) {
    return el('div', { class: 'roll' }, [
      el('span', { class: 'roll-die', innerHTML: dieGlyph(20) }),
      el('div', { class: 'roll-body' }, [el('div', { class: 'roll-reason' }, message.text)]),
    ]);
  }

  const primaryFaces = parsed.groups.find((g) => g.kind === 'dice')?.faces || 20;
  const detail = el('div', { class: 'roll-detail' });
  for (const group of parsed.groups) {
    if (group.kind === 'flat') {
      detail.append(el('span', {}, group.text));
      continue;
    }
    for (const die of group.values) {
      const extremes =
        die.dropped ? ' dropped' : die.value === group.faces ? ' max' : die.value === 1 ? ' min' : '';
      detail.append(el('span', { class: `face${extremes}` }, String(die.value)));
    }
  }

  const outcome = detectOutcome(parsed.extra);
  const body = el('div', { class: 'roll-body' }, [
    el('div', { class: 'roll-reason' }, [
      el('b', {}, parsed.label),
      outcome ? el('span', { class: `roll-outcome ${outcome.ok ? 'ok' : 'no'}` }, outcome.text) : null,
    ]),
    detail,
  ]);

  return el(
    'div',
    { class: `roll${parsed.crit ? ' crit' : ''}${parsed.fumble ? ' fumble' : ''}` },
    [
      el('span', { class: 'roll-die', innerHTML: dieGlyph(primaryFaces) }),
      body,
      parsed.crit ? el('span', { class: 'roll-badge' }, 'крит') : null,
      parsed.fumble ? el('span', { class: 'roll-badge' }, 'провал') : null,
      el('span', { class: 'roll-total' }, String(parsed.total)),
    ],
  );
}

/** Хвост строки после итога: «— успех», «— промах», «против КД 13 — попадание». */
function detectOutcome(extra) {
  if (!extra) return null;
  const lower = extra.toLowerCase();
  if (/успех|попадание|крит/.test(lower)) return { ok: true, text: extra.replace(/^—\s*/, '') };
  if (/провал|промах|мимо/.test(lower)) return { ok: false, text: extra.replace(/^—\s*/, '') };
  return { ok: true, text: extra.replace(/^—\s*/, '') };
}

export function startStream() {
  const log = qs('#log');
  streamNode = el('div', { class: 'msg msg-dm' }, '');
  qs('#log-inner').append(streamNode);
  log.scrollTop = log.scrollHeight;
}

export function appendDelta(text) {
  if (!streamNode) startStream();
  streamNode.textContent += text;
  const log = qs('#log');
  if (log.scrollHeight - log.scrollTop - log.clientHeight < 220) log.scrollTop = log.scrollHeight;
}

export function setTyping(busy) {
  qs('#dm-typing').classList.toggle('hidden', !busy);
  if (!busy && streamNode && !streamNode.textContent.trim()) {
    streamNode.remove();
    streamNode = null;
  }
}

// ============================================================== панели

export function renderState(next, playerId) {
  qs('#campaign-name').textContent = next.name || 'Кампания';
  qs('#scene-location').textContent = next.scene.location || '—';
  qs('#scene-time').textContent = [next.scene.time, next.scene.weather].filter(Boolean).join(', ');
  qs('#game-table-code').textContent = next.code;

  renderInitiative(next);
  renderParty(next, playerId);
  renderFoes(next);
  renderQuests(next);

  const mine = next.party.find((c) => c.playerId === playerId);
  renderSheet(mine);
  renderMap(next.map, mine?.id || null);
}

function sectionTitle(iconName, text, count) {
  return el('h3', { class: 'section-title' }, [
    icon(iconName, { size: 13 }),
    text,
    count !== undefined ? el('span', { class: 'count' }, String(count)) : null,
  ]);
}

function renderInitiative(next) {
  const node = qs('#initiative');
  if (!next.combat?.active) {
    node.classList.add('hidden');
    return;
  }
  node.classList.remove('hidden');
  clear(node).append(
    sectionTitle('swords', `Бой · раунд ${next.combat.round}`),
    ...next.combat.order.map((entry, index) =>
      el('div', { class: `init-row${index === next.combat.turnIndex ? ' current' : ''}` }, [
        el('span', { class: 'init-dot' }),
        el('span', { class: 'init-name' }, entry.name),
        entry.surprised ? el('span', { class: 'init-surprise' }, 'врасплох') : null,
        el('span', { class: 'init-value' }, String(entry.initiative)),
      ]),
    ),
  );
}

/** Цвет полосы хитов: зелёный → янтарный → красный по мере ранений. */
function hpColor(ratio) {
  if (ratio > 0.6) return 'linear-gradient(90deg, #3f9c63, #5fd48a)';
  if (ratio > 0.3) return 'linear-gradient(90deg, #b3641f, #e07b39)';
  return 'linear-gradient(90deg, #8c1d1d, #ef4444)';
}

function avatar(character, size = 38) {
  const node = el('div', {
    class: 'avatar',
    style: { background: character.portraitColor || '#8d6f22', width: `${size}px`, height: `${size}px`, color: character.portraitColor || '#8d6f22' },
  });
  const glyph = classIcon(character.class, { size: Math.round(size * 0.55) });
  glyph.style.color = '#17130c';
  node.append(glyph);
  return node;
}

function renderParty(next, playerId) {
  const node = clear(qs('#party'));
  node.append(sectionTitle('users', 'Партия', next.party.length));

  if (next.party.length === 0) {
    node.append(el('div', { class: 'empty-note' }, 'За столом пока никого.'));
    return;
  }

  for (const character of next.party) {
    const ratio = Math.max(0, Math.min(1, character.hp.current / character.hp.max));
    const down = character.hp.current === 0 || character.dead;

    node.append(
      el(
        'div',
        {
          class: `pc${character.playerId === playerId ? ' mine' : ''}${down ? ' down' : ''}${character.dead ? ' dead' : ''}`,
        },
        [
          avatar(character),
          el('div', { class: 'pc-main' }, [
            el('div', { class: 'pc-head' }, [el('span', { class: 'pc-name' }, character.name)]),
            el('div', { class: 'hpbar' }, [
              el('div', { style: { width: `${ratio * 100}%`, background: hpColor(ratio) } }),
            ]),
            el('div', { class: 'pc-stats' }, [
              el('span', { class: 'stat' }, [
                icon('heart', { size: 12 }),
                character.dead ? 'мёртв' : `${character.hp.current}/${character.hp.max}`,
              ]),
              el('span', { class: 'stat' }, [icon('shield', { size: 12 }), String(character.ac)]),
              el('span', { class: 'stat' }, `${character.level} ур.`),
              el(
                'span',
                { class: character.playerId === playerId ? 'pc-you' : 'pc-player' },
                character.playerId === playerId ? 'ты' : character.playerName || '',
              ),
            ]),
            character.conditions?.length
              ? el(
                  'div',
                  { class: 'conditions' },
                  character.conditions.map((c) => el('span', { class: 'condition' }, CONDITION_RU[c.name] || c.name)),
                )
              : null,
            character.hp.current === 0 && !character.dead ? deathTrack(character.deathSaves) : null,
          ]),
        ],
      ),
    );
  }
}

function deathTrack(saves) {
  const pips = (count, cssClass) =>
    Array.from({ length: 3 }, (_, i) => el('span', { class: `pip${i < count ? ` ${cssClass}` : ''}` }));
  return el('div', { class: 'death-track' }, [
    'при смерти',
    ...pips(saves.successes, 'success'),
    el('span', { style: { opacity: 0.4 } }, '/'),
    ...pips(saves.failures, 'failure'),
  ]);
}

function renderFoes(next) {
  const node = qs('#foes');
  const hostiles = next.npcs.filter((n) => n.hostile && !n.dead);
  node.classList.toggle('hidden', hostiles.length === 0);
  if (hostiles.length === 0) return;

  clear(node).append(
    sectionTitle('skull', 'Противники', hostiles.length),
    ...hostiles.map((n) =>
      el('div', { class: 'foe' }, [
        el('span', { class: 'foe-dot' }),
        el('span', {}, n.name),
        el('span', { class: 'foe-health' }, n.hp),
      ]),
    ),
  );
}

function renderQuests(next) {
  const node = qs('#quests');
  const open = (next.quests || []).filter((q) => q.status !== 'выполнен');
  const loot = next.loot || [];
  node.classList.toggle('hidden', open.length === 0 && loot.length === 0);
  if (open.length === 0 && loot.length === 0) return;

  clear(node);
  if (open.length) {
    node.append(
      sectionTitle('scroll', 'Задачи', open.length),
      ...open.map((quest) =>
        el('div', { class: 'quest' }, [el('span', {}, quest.title), el('span', { class: 'status' }, quest.status)]),
      ),
    );
  }
  if (loot.length) {
    node.append(
      el('div', { style: { marginTop: open.length ? '14px' : '0' } }, [
        sectionTitle('bag', 'Общая добыча'),
        el(
          'div',
          { class: 'tag-list' },
          loot.map((l) => el('span', { class: 'tag' }, `${l.name}${l.qty > 1 ? ` ×${l.qty}` : ''}`)),
        ),
      ]),
    );
  }
}

// ==================================================== лист персонажа

function renderSheet(character) {
  const node = clear(qs('#sheet'));
  if (!character) {
    node.append(el('p', { class: 'empty-note' }, 'Персонаж не выбран.'));
    return;
  }

  const ratio = character.hp.current / character.hp.max;
  const hpClass = character.hp.current === 0 ? 'critical' : ratio <= 0.5 ? 'hurt' : '';

  node.append(
    el('div', { class: 'sheet-head' }, [
      avatar(character, 46),
      el('div', {}, [
        el('h3', {}, character.name),
        el('div', { class: 'sub' }, `${character.level} уровень · ${character.alignment || ''}`),
      ]),
    ]),
    el('div', { class: 'vitals' }, [
      el('div', { class: `vital hp ${hpClass}` }, [
        el('div', { class: 'label' }, 'хиты'),
        el('div', { class: 'value' }, `${character.hp.current}/${character.hp.max}`),
      ]),
      el('div', { class: 'vital' }, [
        el('div', { class: 'label' }, 'класс доспеха'),
        el('div', { class: 'value' }, String(character.ac)),
      ]),
      el('div', { class: 'vital' }, [
        el('div', { class: 'label' }, 'скорость'),
        el('div', { class: 'value' }, String(character.speed)),
      ]),
    ]),
    el(
      'div',
      { class: 'ability-grid' },
      Object.entries(ABILITY_RU).map(([key, label]) =>
        el(
          'button',
          { class: 'ability-pip', title: `${label}: проверка`, onclick: () => rollCheck(`проверка: ${label}`, character.mods[key]) },
          [
            el('div', { class: 'ab' }, ABILITY_SHORT[key]),
            el('div', { class: 'mod' }, mod(character.mods[key])),
            el('div', { class: 'raw' }, String(character.abilities[key])),
          ],
        ),
      ),
    ),
  );

  node.append(
    section('Спасброски', [
      el(
        'div',
        { class: 'saves-grid' },
        Object.entries(ABILITY_RU).map(([key, label]) =>
          el(
            'button',
            {
              class: `roll-row${character.saves[key] > character.mods[key] ? ' prof' : ''}`,
              onclick: () => rollCheck(`спасбросок: ${label}`, character.saves[key]),
            },
            [el('span', {}, label), el('span', { class: 'val' }, mod(character.saves[key]))],
          ),
        ),
      ),
    ]),
  );

  node.append(
    section(
      'Навыки',
      Object.entries(SKILL_RU).map(([key, label]) =>
        el(
          'button',
          {
            class: `roll-row${character.skills.includes(key) ? ' prof' : ''}`,
            onclick: () => rollCheck(`проверка: ${label}`, character.skillMods[key]),
          },
          [el('span', {}, label), el('span', { class: 'val' }, mod(character.skillMods[key]))],
        ),
      ),
    ),
  );

  if (character.attacks?.length) {
    node.append(
      section(
        'Атаки',
        character.attacks.map((attack) =>
          el('div', { class: 'attack-row' }, [
            el('span', { class: 'attack-name' }, attack.name),
            el(
              'button',
              { class: 'hit', title: 'бросок атаки', onclick: () => rollCheck(`атака: ${attack.name}`, attack.attackBonus) },
              mod(attack.attackBonus),
            ),
            attack.damage
              ? el(
                  'button',
                  {
                    class: 'dmg',
                    title: 'бросок урона',
                    onclick: () => net.send({ t: 'roll', expression: attack.damage, reason: `урон: ${attack.name}` }),
                  },
                  attack.damage,
                )
              : null,
          ]),
        ),
      ),
    );
  }

  if (character.spellcasting) {
    const slots = Object.entries(character.spellcasting.slots || {});
    node.append(
      section('Магия', [
        el('div', { class: 'kv' }, [el('span', {}, 'СЛ спасброска'), el('strong', {}, String(character.spellcasting.dc))]),
        el('div', { class: 'kv' }, [el('span', {}, 'Бонус атаки'), el('strong', {}, mod(character.spellcasting.attack))]),
        ...slots.map(([level, max]) => {
          const used = character.spells.slotsUsed?.[level] || 0;
          return el('div', { class: 'slot-row' }, [
            el('span', {}, `${level} круг`),
            el(
              'span',
              { class: 'slot-pips' },
              Array.from({ length: max }, (_, i) => el('span', { class: `slot-pip ${i < max - used ? 'free' : 'used'}` })),
            ),
          ]);
        }),
        character.spells.cantrips?.length
          ? el('div', { class: 'tag-list', style: { marginTop: '8px' } }, [
              ...character.spells.cantrips.map((s) => el('span', { class: 'tag' }, s)),
            ])
          : null,
      ]),
    );
  }

  node.append(
    section('Снаряжение', [
      el(
        'div',
        { class: 'tag-list' },
        [
          ...(character.inventory || []).map((item) =>
            el('span', { class: 'tag' }, `${item.name}${item.qty > 1 ? ` ×${item.qty}` : ''}`),
          ),
          el('span', { class: 'tag gold' }, `${character.gold} зм`),
        ],
      ),
    ]),
  );

  node.append(
    section('Заметки', [
      el('textarea', {
        rows: 4,
        value: character.notes || '',
        placeholder: 'Имена, обещания, подозрения…',
        onchange: (event) => net.send({ t: 'update-notes', notes: event.target.value }),
      }),
    ]),
  );
}

function section(title, children) {
  return el('div', { class: 'sheet-section' }, [el('h4', {}, title), ...[].concat(children)]);
}

function rollCheck(reason, modifier) {
  net.send({ t: 'roll', expression: `1d20${modifier >= 0 ? '+' : ''}${modifier}`, reason });
}
