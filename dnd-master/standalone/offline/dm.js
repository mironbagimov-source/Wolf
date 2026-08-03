// Встроенный мастер: ведёт партию без всякой сети.
//
// Нейросети здесь нет. Есть поход, разложенный по комнатам сгенерированной
// карты, разбор написанного игроком по смыслу и те же самые инструменты, через
// которые мир меняет AI-мастер, — так что кубики, бой, урон и смерть считаются
// ровно так же, как в остальных сборках. Разница только в том, кто принимает
// решения: не модель, а несколько сотен строк правил.
//
// Он не выдумает вам ответвление сюжета. Зато открывается двойным щелчком,
// работает офлайн и ничего не стоит.

import * as dice from '../../server/engine/dice.js';
import * as srd from '../../server/engine/srd.js';
import * as combat from '../../server/engine/combat.js';
import * as mapModule from '../../server/engine/map.js';
import * as state from '../../server/engine/state.js';
import { handlers } from '../../server/dm/tools.js';
import { randomInt } from '../shims/crypto.js';
import * as prose from './prose.js';

// Только темы, которые рождают несколько комнат: храм и трактир генерятся
// одним залом, а поход по одной комнате — не поход.
const THEMES = ['dungeon', 'crypt', 'cave', 'ruins'];
const MIN_ROOMS = 4;

// Скот, вьючные и мелкая живность: формально это подходящие по ПО существа, но
// «на вас нападает верблюд» — не та строчка, ради которой садятся играть.
const NOT_A_THREAT = new Set([
  'camel', 'cat', 'cow', 'deer', 'donkey', 'draft-horse', 'elk', 'goat', 'mule', 'ox',
  'pony', 'riding-horse', 'warhorse', 'mastiff', 'commoner', 'noble', 'frog', 'lizard',
  'rat', 'raven', 'owl', 'hawk', 'eagle', 'crab', 'octopus', 'quipper', 'seahorse',
  'sea-horse', 'weasel', 'badger', 'bat', 'spider', 'baboon', 'jackal', 'vulture', 'goat',
]);

// Кто где водится. Мягкое предпочтение: если подходящих по теме не нашлось,
// берём кого угодно — пустая комната хуже нетипичного зверя.
const FAUNA = {
  dungeon: ['humanoid', 'beast', 'monstrosity'],
  crypt: ['undead', 'construct', 'fiend'],
  cave: ['beast', 'monstrosity', 'ooze', 'aberration'],
  ruins: ['humanoid', 'beast', 'plant', 'fey'],
};

// Сколько «опасности» вываливать на партию. Считается бюджетом, а не полосой
// ПО: два противника по ПО 1/2 против двух героев первого уровня — это уже
// почти гарантированный труп, хотя каждый по отдельности выглядит безобидно.
const DIFFICULTY = { щадящая: 0.2, обычная: 0.4, жёсткая: 0.7 };

const rnd = (n) => randomInt(0, n);
const NUMERAL = ['', 'один', 'двое', 'трое', 'четверо', 'пятеро', 'шестеро'];
const capitalize = (text) => (text ? text[0].toUpperCase() + text.slice(1) : text);

/** Берёт фразу из набора, не повторяясь, пока не переберёт всё. */
function pick(st, bank, key) {
  if (!bank?.length) return '';
  const used = (st.offline.said[key] ||= []);
  if (used.length >= bank.length) used.length = 0;
  let index;
  do {
    index = rnd(bank.length);
  } while (used.includes(index));
  used.push(index);
  return bank[index];
}

const fill = (template, slots) =>
  Object.entries(slots).reduce((text, [key, value]) => text.replaceAll(`{${key}}`, value), template);

// ------------------------------------------------------------------ ход

export async function runTurn(st, ctx) {
  if (st.dm.busy) return { skipped: true };
  st.dm.busy = true;
  ctx.onStatus?.(true);

  try {
    const said = st.offline ? await react(st, ctx, lastPlayerText(st)) : await open(st, ctx);
    const text = said.trim();
    if (text) {
      ctx.emit(state.addMessage(st, { type: 'dm', authorName: 'Мастер', text }));
      // История нужна и здесь: по ней сборка понимает, что мастер уже начал.
      // Далёкое прошлое встроенному мастеру ни к чему, а место в браузере не резиновое.
      st.dm.messages.push({ role: 'assistant', content: [{ type: 'text', text }] });
      if (st.dm.messages.length > 40) st.dm.messages = st.dm.messages.slice(-40);
    }
    return { text };
  } catch (error) {
    const entry = state.addMessage(st, {
      type: 'system',
      text: `Мастер запнулся: ${error.message}`,
      data: { error: true },
    });
    ctx.emit(entry);
    return { error: error.message };
  } finally {
    st.dm.busy = false;
    ctx.onStatus?.(false);
  }
}

/** Последняя реплика игроков — на неё мастер и отвечает. */
function lastPlayerText(st) {
  for (let i = st.dm.messages.length - 1; i >= 0; i -= 1) {
    const message = st.dm.messages[i];
    if (message.role !== 'user') continue;
    const blocks = Array.isArray(message.content) ? message.content : [];
    const text = blocks.filter((b) => b.type === 'text').map((b) => b.text).join('\n');
    if (text) return unwrap(text);
  }
  return '';
}

/**
 * Реплики приезжают завёрнутыми: «Бранд говорит: „осматриваю зал“». Обёртку
 * надо снять до разбора, иначе служебное «говорит» перебьёт то, что человек
 * на самом деле сделал. Броски кубиков в разборе не участвуют вовсе.
 */
function unwrap(text) {
  return String(text)
    .split('\n')
    .filter((line) => !line.startsWith('[бросок игрока]'))
    .map((line) => {
      const said = line.match(/(?:говорит|делает)\s*:\s*«?(.+?)»?$/i);
      return said ? said[1] : line.replace(/^\[[^\]]*\]\s*/, '');
    })
    .join(' ')
    .trim();
}

// ------------------------------------------------------------- завязка

async function open(st, ctx) {
  const theme = THEMES[rnd(THEMES.length)];
  const place = prose.PLACE_NAMES[rnd(prose.PLACE_NAMES.length)];
  const quest = prose.QUESTS[rnd(prose.QUESTS.length)];
  const item = quest.items.length ? quest.items[rnd(quest.items.length)] : { nom: '', acc: '' };
  const words = { place, itemNom: item.nom, itemAcc: item.acc };

  st.offline = { theme, place, said: {}, at: 0, route: [], goal: fill(quest.title, words) };

  let map = mapModule.generateMap({ theme, width: 30, height: 22, title: place });
  // Генератор случайный: если комнат вышло мало, берём заведомо разветвлённое подземелье.
  if (map.rooms.length < MIN_ROOMS) {
    st.offline.theme = 'dungeon';
    map = mapModule.generateMap({ theme: 'dungeon', width: 30, height: 22, title: place });
  }
  state.setMap(st, map);
  buildRoute(st, map);

  await handlers.set_scene(st, { location: `${place}: ${roomName(st, 0)}`, time: 'сумерки', weather: 'пасмурно' }, ctx);
  await handlers.update_quest(st, { title: st.offline.goal, status: 'новая', notes: `Место: ${place}` }, ctx);
  mapModule.revealRoom(map, roomName(st, 0));

  // Своя завязка важнее выдуманной: если её написали, ведём от неё.
  const hook = st.settings.premise?.trim() || fill(quest.intro, words);

  return [
    hook,
    `${describeRoom(st, 0)} Отсюда ведут проходы дальше, вглубь.`,
    prose.OPENING_HELP,
    pick(st, prose.NUDGE, 'nudge'),
  ].join('\n\n');
}

/** Порядок комнат: от входа к дальней, она же логово. */
function buildRoute(st, map) {
  const entry = map.entry;
  const rooms = map.rooms.map((room, index) => ({
    index,
    name: room.name,
    dist: Math.abs(room.cx - entry.x) + Math.abs(room.cy - entry.y),
  }));
  rooms.sort((a, b) => a.dist - b.dist);

  const contents = ['fight', 'search', 'fight', 'trap', 'search', 'fight', 'empty'];
  st.offline.route = rooms.map((room, position) => ({
    ...room,
    content: position === 0 ? 'start' : position === rooms.length - 1 ? 'boss' : contents[(position - 1) % contents.length],
    done: position === 0,
  }));
}

const here = (st) => st.offline.route[st.offline.at];
const roomName = (st, at) => st.offline.route[at]?.name || 'зал';

function describeRoom(st, at) {
  const room = st.offline.route[at];
  const place = prose.PLACES[st.offline.theme] || prose.PLACES.dungeon;
  const parts = [capitalize(fill(pick(st, place.arrival, 'arrival'), { room: room.name.toLowerCase() }))];
  parts.push(pick(st, place.detail, 'detail'));
  // Настроение стола подмешивается изредка, чтобы не превратиться в присказку.
  if (rnd(3) === 0) {
    const color = prose.TONE_COLOR[st.settings.tone];
    if (color) parts.push(pick(st, color, 'tone'));
  }
  return parts.join(' ');
}

// -------------------------------------------------------------- реакция

// Основы слов, по которым узнаётся намерение. Сравниваются с началом слова, а
// не с любым куском строки: иначе «ид» находится в «видел», а «бей» — в «обеих».
// Порядок важен — он же и приоритет, если человек написал сразу про несколько дел.
const STEMS = {
  attack: ['атак', 'бью', 'бей', 'бить', 'удар', 'руб', 'реж', 'колю', 'стрел', 'мечом', 'топор', 'кастую', 'заклин', 'дерусь', 'нападаю', 'напада', 'добива'],
  back: ['назад', 'отступ', 'бегу', 'убега', 'ухожу', 'уходим', 'сматыва'],
  sneak: ['крад', 'прячу', 'прячем', 'тихо', 'скрыт', 'незамет', 'подкрад'],
  rest: ['отдых', 'отдыха', 'привал', 'лагер', 'сплю', 'спим', 'ночу', 'перевяз', 'лечу', 'лечим'],
  look: ['осмотр', 'осматр', 'смотр', 'гляж', 'глян', 'исслед', 'ищу', 'ищем', 'ища', 'обыск', 'обыскив', 'изуч', 'провер', 'загляд', 'обшар', 'разгляд', 'осмотреть'],
  take: ['бер', 'подним', 'забир', 'хвата', 'вскрыв', 'открыв'],
  move: ['иду', 'идем', 'идём', 'идти', 'пойд', 'шаг', 'вперед', 'вперёд', 'дальше', 'двиг', 'вхожу', 'входим', 'войд', 'спуска', 'поднима', 'продолжа', 'следующ'],
  talk: ['говор', 'спраш', 'кричу', 'зову', 'скаж', 'обраща', 'убежд', 'угрож', 'торгу', 'здравств', 'привет'],
  wait: ['жду', 'ждем', 'ждём', 'ничего', 'стою', 'слуша'],
};

function classify(text) {
  const words = String(text)
    .toLowerCase()
    .replace(/ё/g, 'е')
    .split(/[^а-яa-z0-9]+/)
    .filter(Boolean);

  for (const [intent, stems] of Object.entries(STEMS)) {
    const hit = stems.some((stem) => {
      const needle = stem.replace(/ё/g, 'е');
      return words.some((word) => word.startsWith(needle));
    });
    if (hit) return intent;
  }
  return 'other';
}

async function react(st, ctx, text) {
  const intent = classify(text);

  if (st.combat?.active) return fight(st, ctx, intent, text);

  switch (intent) {
    case 'move':
      return advance(st, ctx);
    case 'back':
      return `${pick(st, prose.MOVE.back, 'back')} ${pick(st, prose.NUDGE, 'nudge')}`;
    case 'look':
    case 'take':
      return search(st, ctx);
    case 'sneak':
      return sneak(st, ctx);
    case 'talk':
      return talk(st, ctx);
    case 'rest':
      return rest(st, ctx, text);
    case 'attack':
      return attackOutOfCombat(st, ctx, text);
    default:
      return `${describeRoom(st, st.offline.at)} ${pick(st, prose.NUDGE, 'nudge')}`;
  }
}

// ------------------------------------------------------------ движение

async function advance(st, ctx) {
  const next = st.offline.at + 1;
  if (next >= st.offline.route.length) {
    return `Дальше хода нет — вы уже в самой дальней части. ${pick(st, prose.NUDGE, 'nudge')}`;
  }

  st.offline.at = next;
  const room = here(st);
  mapModule.revealRoom(st.map, room.name);
  movePartyTo(st, room);
  await handlers.set_scene(st, { location: `${st.offline.place}: ${room.name}` }, ctx);

  // «Вы идёте дальше» тут лишнее: описание комнаты и так начинается с прихода.
  const lines = [describeRoom(st, next)];

  if (room.content === 'fight' || room.content === 'boss') {
    lines.push(await ambush(st, ctx, room.content === 'boss'));
    return lines.join(' ');
  }
  if (room.content === 'trap') {
    lines.push(await trap(st, ctx));
    return `${lines.join(' ')} ${pick(st, prose.NUDGE, 'nudge')}`;
  }
  if (room.content === 'empty') {
    const place = prose.PLACES[st.offline.theme] || prose.PLACES.dungeon;
    lines.push(pick(st, place.empty, 'empty'));
  }
  return `${lines.join(' ')} ${pick(st, prose.NUDGE, 'nudge')}`;
}

/** Двигает фишки партии в новую комнату, чтобы карта не отставала от текста. */
function movePartyTo(st, room) {
  if (!st.map) return;
  for (const ch of st.party) {
    mapModule.moveToken(st.map, ch.id, room.cx ?? st.map.entry.x, room.cy ?? st.map.entry.y, { force: true });
  }
  mapModule.revealCircle(st.map, room.cx ?? st.map.entry.x, room.cy ?? st.map.entry.y, 6);
}

// ------------------------------------------------------------------ бой

/**
 * Подбирает встречу по бюджету: сначала кто, потом сколько их влезает. Логово
 * стоит вдвое дороже — там должно быть страшно.
 */
function chooseEncounter(st, boss) {
  const share = DIFFICULTY[st.settings.difficulty] ?? DIFFICULTY.обычная;
  const heroes = Math.max(1, st.party.filter((c) => !c.dead).length);
  const level = Math.max(1, st.party[0]?.level || 1);
  const budget = heroes * level * share * (boss ? 2 : 1);

  // Без русского имени существо выдаёт сборку с головой: «Giant Rat (Diseased)»
  // посреди русского текста читается хуже, чем любая другая мелочь.
  const pool = srd
    .monstersByCr(0.125, Math.max(0.25, budget))
    .filter((m) => m.actions?.length && m.ru && !NOT_A_THREAT.has(m.index));
  if (!pool.length) return { monster: srd.findMonster('goblin'), count: 1 };

  const themed = pool.filter((m) => (FAUNA[st.offline.theme] || []).includes(m.type));
  const choices = themed.length ? themed : pool;
  const monster = choices[rnd(choices.length)];
  const cr = Math.max(0.125, monster.cr || 0.125);
  const room = Math.floor(budget / cr);
  const count = boss ? 1 : Math.max(1, Math.min(4, heroes, room));
  return { monster, count };
}

async function ambush(st, ctx, boss) {
  const { monster, count } = chooseEncounter(st, boss);

  const result = await handlers.spawn_creatures(st, { monster: monster.index, count, hostile: true }, ctx);
  if (result.error) return 'Впереди тихо. Слишком тихо.';

  const alive = st.npcs.filter((n) => !n.dead).length;
  const line = capitalize(fill(pick(st, prose.COMBAT.ambush, 'ambush'), {
    foes: count > 1 ? `${srd.displayName(monster).toLowerCase()} — и не один` : srd.displayName(monster).toLowerCase(),
  }));
  const howMany = alive > 1 ? ` Их ${NUMERAL[alive] || alive}.` : '';

  await handlers.start_combat(st, {}, ctx);
  const opener = await passTurnsToParty(st, ctx);
  return `${line}${howMany}${opener ? ` ${opener}` : ''} ${pick(st, prose.NUDGE, 'nudge')}`;
}

async function attackOutOfCombat(st, ctx, text) {
  const enemies = st.npcs.filter((n) => !n.dead && n.hostile !== false);
  if (!enemies.length) return `Бить некого. ${pick(st, prose.NUDGE, 'nudge')}`;
  await handlers.start_combat(st, {}, ctx);
  return fight(st, ctx, 'attack', text);
}

async function fight(st, ctx, intent, text) {
  if (intent === 'back') {
    await handlers.end_combat(st, { reason: 'партия отступила' }, ctx);
    return `Вы отходите, огрызаясь. Преследовать вас не стали — пока. ${pick(st, prose.NUDGE, 'nudge')}`;
  }
  if (intent === 'rest') return pick(st, prose.REST.unsafe, 'unsafe');

  const actor = currentPc(st);
  if (!actor) return finishFight(st, ctx);

  const lines = [];
  if (intent === 'attack' || intent === 'other' || intent === 'move') {
    // Сказали «иду дальше» посреди драки — значит, идут на противника.
    if (intent === 'move') lines.push('Вы сокращаете дистанцию.');
    const victim = chooseVictim(st, text);
    if (!victim) return finishFight(st, ctx);
    const result = await handlers.attack(st, { attacker: actor.id, target: victim.id }, ctx);
    if (result.error) lines.push('Удар уходит в пустоту.');
  } else if (intent === 'look') {
    await handlers.ability_check(st, { who: actor.id, skill: 'perception', dc: 12, reason: 'осмотреться в бою' }, ctx);
  } else if (intent === 'sneak') {
    await handlers.ability_check(st, { who: actor.id, skill: 'stealth', dc: 14, reason: 'разорвать дистанцию' }, ctx);
  } else {
    lines.push(pick(st, prose.COMBAT.hostileTalk, 'hostileTalk'));
  }

  if (!st.npcs.some((n) => !n.dead && n.hostile !== false)) return finishFight(st, ctx, lines.join(' '));

  await handlers.next_turn(st, {}, ctx);
  const monsters = await passTurnsToParty(st, ctx);
  if (monsters) lines.push(monsters);

  if (!st.party.some((c) => !c.dead && c.hp.current > 0)) {
    await handlers.end_combat(st, { reason: 'партия пала' }, ctx);
    return `${lines.join(' ')} Стоять больше некому. На этом поход обрывается.`;
  }
  return `${lines.join(' ')} ${pick(st, prose.NUDGE, 'nudge')}`;
}

/** Прогоняет ходы монстров, пока очередь снова не дойдёт до партии. */
async function passTurnsToParty(st, ctx) {
  const lines = [];
  for (let guard = 0; guard < 12 && st.combat?.active; guard += 1) {
    const entry = combat.currentTurn(st);
    if (!entry || entry.kind === 'pc') break;

    const monster = st.npcs.find((n) => n.id === entry.id && !n.dead);
    if (monster) {
      const victim = weakestPc(st);
      if (!victim) break;
      lines.push(fill(pick(st, prose.COMBAT.monsterTurn, 'monsterTurn'), { who: monster.name }));
      await handlers.attack(st, { attacker: monster.id, target: victim.id }, ctx);
    }
    await handlers.next_turn(st, {}, ctx);
  }
  return lines.join(' ');
}

async function finishFight(st, ctx, prefix = '') {
  const xp = st.npcs.filter((n) => n.dead).reduce((sum, n) => sum + (n.xp || 25), 0) || 50;
  await handlers.end_combat(st, { reason: 'противники повержены' }, ctx);
  await handlers.award_xp(st, { amount: Math.max(25, Math.round(xp / Math.max(1, st.party.length))), reason: 'бой' }, ctx);

  const room = here(st);
  room.done = true;
  const lines = [prefix, pick(st, prose.COMBAT.victory, 'victory')];

  if (room.content === 'boss') {
    await handlers.update_quest(st, { title: st.offline.goal, status: 'выполнен' }, ctx);
    await handlers.give_item(st, { gold: 50 + rnd(120) }, ctx);
    lines.push(`Дальше идти некуда — это была самая дальняя палата. Дело сделано: ${st.offline.goal.toLowerCase()}. Обратный путь свободен.`);
    return lines.filter(Boolean).join(' ');
  }
  lines.push(pick(st, prose.NUDGE, 'nudge'));
  return lines.filter(Boolean).join(' ');
}

const currentPc = (st) => {
  const entry = combat.currentTurn(st);
  const byTurn = entry && entry.kind === 'pc' ? st.party.find((c) => c.id === entry.id && !c.dead) : null;
  return byTurn || st.party.find((c) => !c.dead && c.hp.current > 0) || null;
};

/** Целью становится тот, кого назвали, иначе — самый потрёпанный враг. */
function chooseVictim(st, text) {
  const named = combat.resolveTarget(st, String(text).split(/\s+/).slice(-1)[0]);
  if (named?.kind === 'npc' && !named.ref.dead) return named.ref;
  const alive = st.npcs.filter((n) => !n.dead && n.hostile !== false);
  return alive.sort((a, b) => a.hp.current - b.hp.current)[0] || null;
}

const weakestPc = (st) => {
  const alive = st.party.filter((c) => !c.dead && c.hp.current > 0);
  return alive.sort((a, b) => a.hp.current - b.hp.current)[0] || null;
};

// ------------------------------------------------------ прочие действия

async function search(st, ctx) {
  const room = here(st);
  const actor = st.party.find((c) => !c.dead) || null;
  if (!actor) return 'Искать некому.';

  const check = await handlers.ability_check(
    st,
    { who: actor.id, skill: 'investigation', dc: 12, reason: `обыскать ${room.name.toLowerCase()}` },
    ctx,
  );
  const success = check.data?.success !== false;

  if (!success) return `${pick(st, prose.SEARCH.nothing, 'nothing')} ${pick(st, prose.NUDGE, 'nudge')}`;

  if (room.content === 'search' && !room.done) {
    room.done = true;
    await handlers.give_item(st, { gold: 15 + rnd(40) }, ctx);
    return `${pick(st, prose.SEARCH.loot, 'loot')} ${pick(st, prose.SEARCH.clue, 'clue')} ${pick(st, prose.NUDGE, 'nudge')}`;
  }
  return `${pick(st, prose.SEARCH.clue, 'clue')} ${pick(st, prose.NUDGE, 'nudge')}`;
}

async function trap(st, ctx) {
  const room = here(st);
  room.done = true;
  const victims = st.party.filter((c) => !c.dead).map((c) => c.id);
  const saves = await handlers.saving_throw(st, { targets: victims, ability: 'dex', dc: 12, reason: 'ловушка' }, ctx);
  const failed = (saves.data || []).filter((r) => r.success === false);

  if (!failed.length) return pick(st, prose.TRAP.spotted, 'spotted');

  await handlers.apply_damage(
    st,
    { targets: failed.map((miss) => miss.name), dice: '1d6', damage_type: 'piercing', reason: 'Ловушка сработала' },
    ctx,
  );
  return pick(st, prose.TRAP.sprung, 'sprung');
}

async function sneak(st, ctx) {
  const actor = st.party.find((c) => !c.dead);
  if (!actor) return 'Красться некому.';
  const check = await handlers.ability_check(st, { who: actor.id, skill: 'stealth', dc: 13, reason: 'пройти тихо' }, ctx);
  const ok = check.data?.success !== false;
  return `${pick(st, ok ? prose.SNEAK.ok : prose.SNEAK.fail, ok ? 'sneakOk' : 'sneakFail')} ${pick(st, prose.NUDGE, 'nudge')}`;
}

async function talk(st, ctx) {
  const hostile = st.npcs.find((n) => !n.dead && n.hostile !== false);
  if (hostile) return `${pick(st, prose.COMBAT.hostileTalk, 'hostileTalk')} ${pick(st, prose.NUDGE, 'nudge')}`;
  const friendly = st.npcs.find((n) => !n.dead && n.hostile === false);
  if (friendly) return `${pick(st, prose.TALK.friendly, 'friendly')} ${pick(st, prose.NUDGE, 'nudge')}`;
  return `${pick(st, prose.TALK.noone, 'noone')} ${pick(st, prose.NUDGE, 'nudge')}`;
}

async function rest(st, ctx, text) {
  const long = /ноч|сплю|продолж|длинн|лагер/i.test(text);
  await handlers.rest(st, { type: long ? 'продолжительный' : 'короткий' }, ctx);
  return `${pick(st, long ? prose.REST.long : prose.REST.short, long ? 'restLong' : 'restShort')} ${pick(st, prose.NUDGE, 'nudge')}`;
}
