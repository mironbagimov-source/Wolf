// The DM's tool surface: everything the AI can do to the game world.
//
// The split is deliberate. The model decides *what happens next* — who attacks,
// what the DC is, which monster shows up. The handlers below decide *how it
// turns out*: every die is rolled here, every hit point is subtracted here, and
// every result is written to the shared log where players can see it. The model
// never gets to assert an outcome, only to ask for one.

import * as dice from '../engine/dice.js';
import * as srd from '../engine/srd.js';
import * as characterModule from '../engine/character.js';
import * as combat from '../engine/combat.js';
import * as mapModule from '../engine/map.js';
import * as state from '../engine/state.js';
import { SKILLS, SKILL_RU, ABILITY_RU, CONDITION_RU, DAMAGE_RU, ABILITIES, formatMod, xpForCr } from '../engine/rules.js';

const ok = (summary, data) => ({ summary, data, error: false });
const fail = (summary) => ({ summary, error: true });

/** Writes a message everyone at the table can see. */
function log(ctx, message) {
  const entry = state.addMessage(ctx.state, message);
  ctx.emit(entry);
  return entry;
}

function target(st, query) {
  const found = combat.resolveTarget(st, query);
  if (!found) throw new Error(`Не нашёл в сцене: «${query}». Проверь имя или id в снимке состояния.`);
  return found;
}

const nameOf = (c) => c.ref.name;

// --------------------------------------------------------------- schemas

export const TOOL_DEFS = [
  {
    name: 'roll_dice',
    description:
      'Бросить кубики. Любое случайное число в игре получается только так. Примеры выражений: 1d20+5, 2d6+3, 4d6kh3 (оставить 3 лучших), 8d6.',
    input_schema: {
      type: 'object',
      properties: {
        expression: { type: 'string', description: 'Выражение броска, например 2d6+3' },
        reason: { type: 'string', description: 'Что бросаем — покажется игрокам в логе' },
        secret: { type: 'boolean', description: 'Скрытый бросок: результат увидишь только ты' },
      },
      required: ['expression', 'reason'],
    },
  },
  {
    name: 'ability_check',
    description:
      'Проверка характеристики или навыка для персонажа или существа. Указывай skill (например stealth) или ability (str/dex/con/int/wis/cha). Без dc вернётся просто результат броска.',
    input_schema: {
      type: 'object',
      properties: {
        who: { type: 'string', description: 'Имя или id того, кто проверяет' },
        skill: { type: 'string', description: `Навык: ${Object.keys(SKILLS).join(', ')}` },
        ability: { type: 'string', enum: ABILITIES, description: 'Характеристика, если навык не подходит' },
        dc: { type: 'integer', description: 'Сложность (10 обыденно, 15 умело, 20 трудно, 25 на пределе)' },
        advantage: { type: 'boolean' },
        disadvantage: { type: 'boolean' },
        reason: { type: 'string', description: 'Что персонаж пытается сделать' },
      },
      required: ['who', 'reason'],
    },
  },
  {
    name: 'saving_throw',
    description: 'Спасбросок одного или нескольких существ против сложности.',
    input_schema: {
      type: 'object',
      properties: {
        targets: { type: 'array', items: { type: 'string' }, description: 'Имена или id' },
        ability: { type: 'string', enum: ABILITIES },
        dc: { type: 'integer' },
        reason: { type: 'string', description: 'Против чего спасбросок' },
        advantage: { type: 'boolean' },
        disadvantage: { type: 'boolean' },
      },
      required: ['targets', 'ability', 'dc', 'reason'],
    },
  },
  {
    name: 'attack',
    description:
      'Атака одного существа по другому: бросок атаки, критические попадания, урон и его применение — всё считается движком.',
    input_schema: {
      type: 'object',
      properties: {
        attacker: { type: 'string', description: 'Кто атакует (имя или id)' },
        target: { type: 'string', description: 'Кого атакует' },
        attack_name: { type: 'string', description: 'Чем именно: название оружия или действия из стат-блока' },
        advantage: { type: 'boolean' },
        disadvantage: { type: 'boolean' },
        bonus_damage: { type: 'string', description: 'Дополнительные кости урона, например 2d6 для скрытой атаки' },
        bonus_damage_type: { type: 'string' },
      },
      required: ['attacker', 'target'],
    },
  },
  {
    name: 'apply_damage',
    description:
      'Нанести урон напрямую — заклинания по области, ловушки, падение. Урон считается один раз и применяется ко всем целям; тем, кто в halved, достаётся половина.',
    input_schema: {
      type: 'object',
      properties: {
        targets: { type: 'array', items: { type: 'string' } },
        dice: { type: 'string', description: 'Выражение урона, например 8d6' },
        amount: { type: 'integer', description: 'Фиксированный урон вместо броска' },
        damage_type: { type: 'string', description: `Тип урона: ${Object.keys(DAMAGE_RU).join(', ')}` },
        halved: { type: 'array', items: { type: 'string' }, description: 'Кто прошёл спасбросок и получает половину' },
        reason: { type: 'string' },
      },
      required: ['targets', 'reason'],
    },
  },
  {
    name: 'heal',
    description: 'Вылечить существо или дать временные хиты.',
    input_schema: {
      type: 'object',
      properties: {
        target: { type: 'string' },
        dice: { type: 'string', description: 'Например 2d4+2' },
        amount: { type: 'integer' },
        temporary: { type: 'boolean', description: 'Временные хиты вместо лечения' },
        reason: { type: 'string' },
      },
      required: ['target', 'reason'],
    },
  },
  {
    name: 'set_condition',
    description: 'Наложить или снять состояние (отравлен, испуган, схвачен, без сознания и т.д.).',
    input_schema: {
      type: 'object',
      properties: {
        target: { type: 'string' },
        condition: { type: 'string', enum: Object.keys(CONDITION_RU) },
        remove: { type: 'boolean', description: 'true — снять состояние' },
        duration: { type: 'string', description: 'Например «до конца следующего хода»' },
        reason: { type: 'string' },
      },
      required: ['target', 'condition'],
    },
  },
  {
    name: 'spawn_creatures',
    description:
      'Вывести в сцену существ из SRD с настоящими характеристиками. Возвращает стат-блок и id. Всегда используй это вместо того, чтобы придумывать хиты и КД.',
    input_schema: {
      type: 'object',
      properties: {
        monster: { type: 'string', description: 'Название монстра по-русски или по-английски: гоблин, wolf, skeleton' },
        count: { type: 'integer', description: 'Сколько штук (по умолчанию 1)' },
        hostile: { type: 'boolean', description: 'false — существо не враждебно' },
        hidden: { type: 'boolean', description: 'true — игроки пока не видят его в списке' },
        x: { type: 'integer', description: 'Клетка на карте, если карта есть' },
        y: { type: 'integer' },
        rename: { type: 'string', description: 'Своё имя, например «Гурт, вожак стаи»' },
      },
      required: ['monster'],
    },
  },
  {
    name: 'start_combat',
    description: 'Начать бой: движок бросит инициативу всем, кто в сцене, и выстроит порядок ходов.',
    input_schema: {
      type: 'object',
      properties: {
        surprised: { type: 'array', items: { type: 'string' }, description: 'Кто застигнут врасплох' },
      },
    },
  },
  {
    name: 'next_turn',
    description: 'Передать ход следующему в порядке инициативы. Вызывай после того, как существо закончило свой ход.',
    input_schema: { type: 'object', properties: {} },
  },
  {
    name: 'end_combat',
    description: 'Закончить бой.',
    input_schema: {
      type: 'object',
      properties: { reason: { type: 'string' } },
    },
  },
  {
    name: 'death_save',
    description: 'Спасбросок от смерти для персонажа на 0 хитов. Вызывай в его ход.',
    input_schema: {
      type: 'object',
      properties: { character: { type: 'string' } },
      required: ['character'],
    },
  },
  {
    name: 'update_map',
    description:
      'Работа с боевой картой. create — сгенерировать новую, reveal — открыть область, move — переместить токен, place — поставить объект, remove — убрать, reveal_all — открыть всю карту, clear — убрать карту совсем.',
    input_schema: {
      type: 'object',
      properties: {
        action: { type: 'string', enum: ['create', 'reveal', 'move', 'place', 'remove', 'reveal_all', 'clear'] },
        theme: {
          type: 'string',
          enum: ['dungeon', 'cave', 'crypt', 'ruins', 'wilderness', 'interior', 'temple'],
          description: 'Для create',
        },
        title: { type: 'string', description: 'Название карты для create' },
        width: { type: 'integer' },
        height: { type: 'integer' },
        who: { type: 'string', description: 'Кого двигать или убрать (имя или id)' },
        x: { type: 'integer' },
        y: { type: 'integer' },
        radius: { type: 'integer', description: 'Радиус для reveal' },
        room: { type: 'string', description: 'Название или номер области для reveal' },
        label: { type: 'string', description: 'Название объекта для place' },
      },
      required: ['action'],
    },
  },
  {
    name: 'lookup',
    description:
      'Найти в SRD монстра, заклинание, предмет, магический предмет, состояние или правило. Используй, когда не уверен в точных числах или формулировке.',
    input_schema: {
      type: 'object',
      properties: {
        query: { type: 'string' },
        kind: { type: 'string', enum: ['any', 'monster', 'spell', 'item', 'magic', 'condition', 'rule'] },
      },
      required: ['query'],
    },
  },
  {
    name: 'set_scene',
    description: 'Обновить сцену: место, время суток, погоду, обстановку. Вызывай при смене локации.',
    input_schema: {
      type: 'object',
      properties: {
        location: { type: 'string' },
        time: { type: 'string' },
        weather: { type: 'string' },
        description: { type: 'string', description: 'Короткая заметка об обстановке для памяти' },
      },
    },
  },
  {
    name: 'update_quest',
    description: 'Завести, обновить или закрыть задачу партии.',
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string' },
        status: { type: 'string', enum: ['новая', 'в работе', 'выполнен', 'провален'] },
        notes: { type: 'string' },
      },
      required: ['title'],
    },
  },
  {
    name: 'give_item',
    description: 'Выдать предмет персонажу или в общую добычу партии. Также снимает предмет, если remove = true.',
    input_schema: {
      type: 'object',
      properties: {
        target: { type: 'string', description: 'Имя персонажа или «партия»' },
        item: { type: 'string', description: 'Название предмета (ищется в SRD, иначе запишется как есть)' },
        qty: { type: 'integer' },
        gold: { type: 'integer', description: 'Монеты вместо предмета (можно отрицательное число)' },
        remove: { type: 'boolean' },
      },
      required: ['target'],
    },
  },
  {
    name: 'award_xp',
    description: 'Выдать опыт всей партии. Повышение уровня движок посчитает сам.',
    input_schema: {
      type: 'object',
      properties: {
        amount: { type: 'integer' },
        reason: { type: 'string' },
      },
      required: ['amount', 'reason'],
    },
  },
  {
    name: 'rest',
    description: 'Короткий или продолжительный отдых партии.',
    input_schema: {
      type: 'object',
      properties: {
        type: { type: 'string', enum: ['короткий', 'продолжительный'] },
        hit_dice: { type: 'integer', description: 'Сколько костей хитов тратит каждый на коротком отдыхе' },
      },
      required: ['type'],
    },
  },
  {
    name: 'use_spell_slot',
    description: 'Потратить ячейку заклинаний персонажа.',
    input_schema: {
      type: 'object',
      properties: {
        character: { type: 'string' },
        level: { type: 'integer', description: 'Круг ячейки' },
        spell: { type: 'string', description: 'Название заклинания для лога' },
      },
      required: ['character', 'level'],
    },
  },
  {
    name: 'add_journal',
    description:
      'Записать в дневник кампании важный факт: обещание, имя, тайну, договор. Это переживёт сжатие истории — пиши сюда то, что нельзя забыть.',
    input_schema: {
      type: 'object',
      properties: { text: { type: 'string' } },
      required: ['text'],
    },
  },
];

// -------------------------------------------------------------- handlers

export const handlers = {
  async roll_dice(st, input, ctx) {
    let result;
    try {
      result = dice.roll(input.expression);
    } catch (e) {
      return fail(e.message);
    }
    const text = `${input.reason}: ${dice.describe(result)}`;
    if (!input.secret) {
      log(ctx, { type: 'roll', authorName: 'Мастер', text, data: { result, secret: false } });
    }
    return ok(`${text}${input.secret ? ' (скрытый бросок, игроки его не видят)' : ''}`, result);
  },

  async ability_check(st, input, ctx) {
    let who;
    try {
      who = target(st, input.who);
    } catch (e) {
      return fail(e.message);
    }
    const skill = input.skill && SKILLS[input.skill] ? input.skill : null;
    const ability = skill ? SKILLS[skill] : input.ability || 'dex';

    const result = combat.abilityCheck(who, {
      ability,
      skill,
      dc: input.dc,
      advantage: input.advantage,
      disadvantage: input.disadvantage,
    });

    const label = skill ? SKILL_RU[skill] : ABILITY_RU[ability];
    const verdict =
      result.success === null ? '' : result.success ? ' — успех' : ' — провал';
    const text = `${nameOf(who)}, ${label}${input.dc ? ` (СЛ ${input.dc})` : ''}: ${dice.describe(result.roll)}${verdict}`;
    log(ctx, { type: 'roll', authorName: 'Мастер', text, data: result });
    return ok(
      `${text}${result.roll.crit ? ' [натуральная 20]' : ''}${result.roll.fumble ? ' [натуральная 1]' : ''}. Повод: ${input.reason}`,
      result,
    );
  },

  async saving_throw(st, input, ctx) {
    const results = [];
    for (const name of input.targets) {
      let who;
      try {
        who = target(st, name);
      } catch (e) {
        results.push({ name, error: e.message });
        continue;
      }
      const r = combat.saveThrow(who, input.ability, input.dc, {
        advantage: input.advantage,
        disadvantage: input.disadvantage,
      });
      results.push(r);
      log(ctx, {
        type: 'roll',
        authorName: 'Мастер',
        text: `${r.name}, спасбросок ${ABILITY_RU[input.ability]} (СЛ ${input.dc}): ${dice.describe(r.roll)} — ${r.success ? 'успех' : 'провал'}`,
        data: r,
      });
    }
    const summary = results
      .map((r) => (r.error ? `${r.name}: ${r.error}` : `${r.name}: ${r.roll.total} — ${r.success ? 'успех' : 'провал'}`))
      .join('; ');
    return ok(`Спасброски против «${input.reason}». ${summary}`, results);
  },

  async attack(st, input, ctx) {
    let attacker;
    let victim;
    try {
      attacker = target(st, input.attacker);
      victim = target(st, input.target);
    } catch (e) {
      return fail(e.message);
    }
    if (victim.ref.dead) return fail(`${nameOf(victim)} уже повержен.`);

    // Build the attack from the attacker's sheet or stat block.
    let attackDef;
    if (attacker.kind === 'pc') {
      const list = attacker.ref.attacks || [];
      attackDef = input.attack_name
        ? list.find((a) => a.name.toLowerCase().includes(String(input.attack_name).toLowerCase())) || list[0]
        : list[0];
      if (!attackDef) return fail(`У ${nameOf(attacker)} нет доступных атак.`);
    } else {
      attackDef = combat.monsterAttack(attacker.ref.monsterIndex, input.attack_name || '');
      if (!attackDef) return fail(`У ${nameOf(attacker)} нет подходящего действия атаки в стат-блоке.`);
    }

    const result = combat.resolveAttack(st, attacker, victim, attackDef, {
      advantage: input.advantage,
      disadvantage: input.disadvantage,
      bonusDamage: input.bonus_damage ? { dice: input.bonus_damage, type: input.bonus_damage_type } : null,
    });

    const parts = [
      `${result.attacker} → ${result.target}, ${result.attackName}: ${dice.describe(result.roll)} против КД ${result.targetAc}`,
    ];
    if (result.crit) parts.push('КРИТ!');
    else if (result.fumble) parts.push('промах (натуральная 1)');
    else parts.push(result.hit ? 'попадание' : 'промах');
    if (result.damage) {
      parts.push(`урон ${result.damage.damage}${result.damage.multiplier !== 1 ? ` (×${result.damage.multiplier})` : ''}`);
    }
    const text = parts.join(' — ');
    log(ctx, { type: 'roll', authorName: 'Мастер', text, data: result });

    let after = '';
    if (result.damage) {
      after = describeAftermath(st, victim, result.damage, ctx);
    }
    return ok(`${text}. ${after}`, result);
  },

  async apply_damage(st, input, ctx) {
    let amount = input.amount;
    let rollResult = null;
    if (input.dice) {
      try {
        rollResult = dice.roll(input.dice);
      } catch (e) {
        return fail(e.message);
      }
      amount = rollResult.total;
    }
    if (!Number.isFinite(amount)) return fail('Нужно указать dice или amount.');

    if (rollResult) {
      log(ctx, {
        type: 'roll',
        authorName: 'Мастер',
        text: `${input.reason}: урон ${dice.describe(rollResult)}`,
        data: rollResult,
      });
    }

    const halved = new Set((input.halved || []).map((s) => String(s).toLowerCase()));
    const lines = [];
    for (const name of input.targets) {
      let who;
      try {
        who = target(st, name);
      } catch (e) {
        lines.push(`${name}: ${e.message}`);
        continue;
      }
      const isHalved = halved.has(String(name).toLowerCase()) || halved.has(nameOf(who).toLowerCase());
      const applied = combat.dealDamage(st, who, isHalved ? Math.floor(amount / 2) : amount, input.damage_type);
      const aftermath = describeAftermath(st, who, applied, ctx);
      lines.push(`${nameOf(who)}: −${applied.damage}${isHalved ? ' (половина)' : ''}. ${aftermath}`);
      log(ctx, {
        type: 'roll',
        authorName: 'Мастер',
        text: `${nameOf(who)} получает ${applied.damage} ${DAMAGE_RU[input.damage_type] || ''} урона${isHalved ? ' (половина)' : ''}`,
        data: applied,
      });
    }
    return ok(`${input.reason}. ${lines.join(' ')}`, null);
  },

  async heal(st, input, ctx) {
    let who;
    try {
      who = target(st, input.target);
    } catch (e) {
      return fail(e.message);
    }
    let amount = input.amount;
    let rollResult = null;
    if (input.dice) {
      try {
        rollResult = dice.roll(input.dice);
      } catch (e) {
        return fail(e.message);
      }
      amount = rollResult.total;
    }
    if (!Number.isFinite(amount)) return fail('Нужно указать dice или amount.');

    if (who.kind === 'pc') {
      if (input.temporary) {
        const temp = characterModule.addTempHp(who.ref, amount);
        log(ctx, { type: 'system', text: `${nameOf(who)} получает ${amount} временных хитов (${input.reason})` });
        return ok(`${nameOf(who)}: временные хиты ${temp}.`);
      }
      const result = characterModule.heal(who.ref, amount);
      log(ctx, {
        type: 'system',
        text: `${nameOf(who)} восстанавливает ${result.healed} хитов${rollResult ? ` (${dice.describe(rollResult)})` : ''} — ${result.hp}/${result.maxHp}${result.revived ? ', приходит в себя' : ''}`,
      });
      return ok(`${nameOf(who)}: ${result.hp}/${result.maxHp} хитов${result.revived ? ', пришёл в себя' : ''}.`, result);
    }

    who.ref.hp.current = Math.min(who.ref.hp.max, who.ref.hp.current + amount);
    who.ref.dead = false;
    log(ctx, { type: 'system', text: `${nameOf(who)} восстанавливает ${amount} хитов` });
    return ok(`${nameOf(who)}: ${who.ref.hp.current}/${who.ref.hp.max} хитов.`);
  },

  async set_condition(st, input, ctx) {
    let who;
    try {
      who = target(st, input.target);
    } catch (e) {
      return fail(e.message);
    }
    const label = CONDITION_RU[input.condition] || input.condition;
    if (input.remove) {
      if (who.kind === 'pc') characterModule.removeCondition(who.ref, input.condition);
      else who.ref.conditions = (who.ref.conditions || []).filter((c) => c.name !== input.condition);
      log(ctx, { type: 'system', text: `${nameOf(who)}: снято состояние «${label}»` });
      return ok(`${nameOf(who)} больше не ${label.toLowerCase()}.`);
    }
    if (who.kind === 'pc') characterModule.addCondition(who.ref, input.condition, input.reason, input.duration);
    else {
      who.ref.conditions = who.ref.conditions || [];
      if (!who.ref.conditions.some((c) => c.name === input.condition)) {
        who.ref.conditions.push({ name: input.condition, source: input.reason, duration: input.duration });
      }
    }
    log(ctx, {
      type: 'system',
      text: `${nameOf(who)}: состояние «${label}»${input.duration ? ` (${input.duration})` : ''}`,
    });
    return ok(`${nameOf(who)} теперь ${label.toLowerCase()}.`);
  },

  async spawn_creatures(st, input, ctx) {
    let creatures;
    try {
      creatures = combat.spawnMonsters(input.monster, input.count || 1, { nameSuffix: null });
    } catch (e) {
      return fail(e.message);
    }
    const stat = srd.monsterByIndex.get(creatures[0].monsterIndex);

    if (input.rename && creatures.length === 1) creatures[0].name = input.rename;
    for (const c of creatures) {
      c.hostile = input.hostile !== false;
      c.visible = !input.hidden;
      st.npcs.push(c);
      if (st.map) {
        mapModule.addToken(st.map, {
          id: c.id,
          name: c.name,
          kind: 'npc',
          color: c.hostile ? '#dc2626' : '#16a34a',
          x: input.x,
          y: input.y,
          label: c.name.slice(0, 2),
        });
      }
    }

    if (!input.hidden) {
      log(ctx, {
        type: 'system',
        text: `В сцене: ${creatures.map((c) => c.name).join(', ')}`,
      });
    }
    return ok(
      `Выведено: ${creatures.map((c) => `${c.name} [${c.id.slice(0, 8)}] ${c.hp.current} хп`).join(', ')}.\n\n${srd.monsterBlock(stat)}`,
      creatures.map((c) => ({ id: c.id, name: c.name })),
    );
  },

  async start_combat(st, input, ctx) {
    let result;
    try {
      result = combat.startCombat(st, { surprised: input.surprised || [] });
    } catch (e) {
      return fail(e.message);
    }
    log(ctx, {
      type: 'system',
      text: `⚔ Бой начался. Порядок: ${result.order.map((o) => `${o.name} (${o.initiative})`).join(' → ')}`,
      data: { combat: true },
    });
    return ok(combat.combatSummary(st));
  },

  async next_turn(st, input, ctx) {
    if (!st.combat?.active) return fail('Сейчас нет боя.');
    const entry = combat.nextTurn(st);
    combat.pruneDefeated(st);
    if (!entry) return ok('В бою не осталось действующих участников — заверши бой.');
    log(ctx, { type: 'system', text: `Ход: ${entry.name} (раунд ${st.combat.round})`, data: { turn: entry.id } });
    return ok(`Сейчас ход: ${entry.name}. ${combat.combatSummary(st)}`);
  },

  async end_combat(st, input, ctx) {
    if (!st.combat?.active) return fail('Боя и так нет.');
    combat.endCombat(st);
    // Corpses leave the board; survivors stay in the scene.
    const fallen = st.npcs.filter((n) => n.dead);
    st.npcs = st.npcs.filter((n) => !n.dead);
    if (st.map) for (const n of fallen) mapModule.removeToken(st.map, n.id);
    log(ctx, { type: 'system', text: `Бой окончен${input.reason ? `: ${input.reason}` : ''}` });
    return ok('Бой завершён.');
  },

  async death_save(st, input, ctx) {
    let who;
    try {
      who = target(st, input.character);
    } catch (e) {
      return fail(e.message);
    }
    if (who.kind !== 'pc') return fail('Спасброски от смерти делают только персонажи игроков.');
    if (who.ref.hp.current > 0) return fail(`${nameOf(who)} в сознании, спасбросок не нужен.`);

    const result = characterModule.deathSave(who.ref);
    let text = `${nameOf(who)}, спасбросок от смерти: ${dice.describe(result.roll)}`;
    if (result.revived) text += ' — натуральная 20, приходит в себя с 1 хитом!';
    else if (result.dead) text += ' — третий провал. Смерть.';
    else if (result.stabilized) text += ' — третий успех, стабилизирован.';
    else text += ` — успехи ${who.ref.deathSaves.successes}, провалы ${who.ref.deathSaves.failures}`;

    log(ctx, { type: 'roll', authorName: 'Мастер', text, data: result });
    return ok(text, result);
  },

  async update_map(st, input, ctx) {
    const action = input.action;

    if (action === 'create') {
      const map = mapModule.generateMap({
        theme: input.theme || 'dungeon',
        width: input.width || 30,
        height: input.height || 20,
        title: input.title,
      });
      state.setMap(st, map);
      log(ctx, { type: 'system', text: `🗺 Карта: ${map.title}`, data: { map: true } });
      return ok(`Карта создана.\n${mapModule.asciiMap(map)}`);
    }

    if (action === 'clear') {
      st.map = null;
      log(ctx, { type: 'system', text: 'Карта убрана' });
      return ok('Карта убрана.');
    }

    if (!st.map) return fail('Карты сейчас нет — сначала создай её (action: create).');

    if (action === 'reveal_all') {
      mapModule.revealAll(st.map);
      return ok('Карта открыта полностью.');
    }

    if (action === 'reveal') {
      if (input.room !== undefined) {
        const count = mapModule.revealRoom(st.map, Number.isNaN(Number(input.room)) ? input.room : Number(input.room));
        return ok(count ? `Открыто клеток: ${count}.` : 'Такой области нет.');
      }
      const count = mapModule.revealCircle(st.map, input.x ?? st.map.entry.x, input.y ?? st.map.entry.y, input.radius || 5);
      return ok(`Открыто клеток: ${count}.\n${mapModule.asciiMap(st.map)}`);
    }

    if (action === 'move') {
      let who;
      try {
        who = target(st, input.who);
      } catch (e) {
        return fail(e.message);
      }
      const result = mapModule.moveToken(st.map, who.ref.id, input.x, input.y);
      if (!result.ok) return fail(`Не могу переместить: ${result.reason}`);
      log(ctx, {
        type: 'system',
        text: `${nameOf(who)} перемещается в (${result.to.x},${result.to.y}) — ${result.distance} фт.`,
        data: { move: true },
      });
      return ok(`${nameOf(who)} прошёл ${result.distance} фт. и стоит на (${result.to.x},${result.to.y}).`);
    }

    if (action === 'place') {
      const token = mapModule.addToken(st.map, {
        name: input.label || 'Объект',
        kind: 'object',
        x: input.x,
        y: input.y,
        color: '#a16207',
        label: (input.label || 'Об').slice(0, 2),
      });
      return ok(`Объект «${token.name}» на (${token.x},${token.y}).`);
    }

    if (action === 'remove') {
      let who;
      try {
        who = target(st, input.who);
      } catch {
        // Might be a plain object token rather than a creature.
        const token = st.map.tokens.find((t) => t.name.toLowerCase() === String(input.who).toLowerCase());
        if (!token) return fail(`Не нашёл токен «${input.who}».`);
        mapModule.removeToken(st.map, token.id);
        return ok(`Токен «${token.name}» убран.`);
      }
      mapModule.removeToken(st.map, who.ref.id);
      return ok(`${nameOf(who)} убран с карты.`);
    }

    return fail(`Неизвестное действие карты: ${action}`);
  },

  async lookup(st, input) {
    const results = srd.lookupAny(input.query, input.kind || 'any', 3);
    if (results.length === 0) return ok(`В SRD ничего не найдено по запросу «${input.query}».`);
    return ok(results.map((r) => r.text).join('\n\n---\n\n'));
  },

  async set_scene(st, input, ctx) {
    const before = st.scene.location;
    if (input.location) st.scene.location = input.location;
    if (input.time) st.scene.time = input.time;
    if (input.weather) st.scene.weather = input.weather;
    if (input.description !== undefined) st.scene.description = input.description;
    if (input.location && input.location !== before) {
      log(ctx, { type: 'system', text: `📍 ${input.location}`, data: { scene: true } });
    }
    return ok(`Сцена: ${st.scene.location}, ${st.scene.time}, ${st.scene.weather}.`);
  },

  async update_quest(st, input, ctx) {
    const existing = st.quests.find((q) => q.title.toLowerCase() === input.title.toLowerCase());
    if (existing) {
      if (input.status) existing.status = input.status;
      if (input.notes) existing.notes = input.notes;
      log(ctx, { type: 'system', text: `Задача «${existing.title}»: ${existing.status}` });
      return ok(`Задача обновлена: ${existing.title} — ${existing.status}.`);
    }
    const quest = { id: st.quests.length + 1, title: input.title, status: input.status || 'новая', notes: input.notes || '' };
    st.quests.push(quest);
    log(ctx, { type: 'system', text: `📜 Новая задача: ${quest.title}` });
    return ok(`Задача добавлена: ${quest.title}.`);
  },

  async give_item(st, input, ctx) {
    const item = srd.findEquipment(input.item || '') || srd.findMagicItem(input.item || '');
    const label = input.item ? srd.displayName(item) || input.item : null;
    const qty = input.qty || 1;
    const toParty = !input.target || /парти|общ/i.test(input.target);

    if (input.gold) {
      if (toParty) {
        for (const ch of st.party) ch.gold += Math.round(input.gold / Math.max(1, st.party.length));
        log(ctx, { type: 'system', text: `💰 Партия делит ${input.gold} зм` });
        return ok(`Разделено ${input.gold} зм между партией.`);
      }
      let who;
      try {
        who = target(st, input.target);
      } catch (e) {
        return fail(e.message);
      }
      if (who.kind !== 'pc') return fail('Монеты можно выдать только персонажу игрока.');
      who.ref.gold += input.gold;
      log(ctx, { type: 'system', text: `💰 ${nameOf(who)}: ${input.gold > 0 ? '+' : ''}${input.gold} зм` });
      return ok(`${nameOf(who)}: ${who.ref.gold} зм.`);
    }

    if (!label) return fail('Укажи item или gold.');

    if (toParty) {
      if (input.remove) {
        st.loot = st.loot.filter((l) => l.name !== label);
        return ok(`«${label}» убрано из общей добычи.`);
      }
      const found = st.loot.find((l) => l.name === label);
      if (found) found.qty += qty;
      else st.loot.push({ name: label, index: item?.index || null, qty });
      log(ctx, { type: 'system', text: `🎒 В общую добычу: ${label}${qty > 1 ? ` ×${qty}` : ''}` });
      return ok(`В общей добыче: ${label} ×${(found?.qty ?? qty)}.`);
    }

    let who;
    try {
      who = target(st, input.target);
    } catch (e) {
      return fail(e.message);
    }
    if (who.kind !== 'pc') return fail('Предметы можно выдать только персонажу игрока.');

    if (input.remove) {
      who.ref.inventory = who.ref.inventory.filter((i) => (item ? i.index !== item.index : true));
      characterModule.recompute(who.ref);
      return ok(`У ${nameOf(who)} забрано: ${label}.`);
    }

    const slot = who.ref.inventory.find((i) => item && i.index === item.index);
    if (slot) slot.qty += qty;
    else who.ref.inventory.push({ index: item?.index || label, qty, equipped: false, custom: item ? undefined : label });
    characterModule.recompute(who.ref);
    log(ctx, { type: 'system', text: `🎒 ${nameOf(who)} получает: ${label}${qty > 1 ? ` ×${qty}` : ''}` });
    return ok(`${nameOf(who)} получил ${label}${qty > 1 ? ` ×${qty}` : ''}.`);
  },

  async award_xp(st, input, ctx) {
    const lines = [];
    for (const ch of st.party) {
      const result = characterModule.grantXp(ch, input.amount);
      if (result.leveledUp) {
        lines.push(`${ch.name}: ${result.from} → ${result.to} уровень!`);
        log(ctx, { type: 'system', text: `⭐ ${ch.name} получает ${result.to} уровень!`, data: { levelUp: true } });
      }
    }
    log(ctx, { type: 'system', text: `+${input.amount} опыта каждому: ${input.reason}` });
    return ok(`Опыт выдан (+${input.amount}). ${lines.join(' ') || 'Повышений уровня нет.'}`);
  },

  async rest(st, input, ctx) {
    const long = /продолж|длин|long/i.test(input.type);
    const lines = [];
    for (const ch of st.party) {
      if (long) {
        const r = characterModule.longRest(ch);
        lines.push(`${ch.name}: ${r.hp}/${ch.hp.max} хп`);
      } else {
        const r = characterModule.shortRest(ch, input.hit_dice ?? 1);
        lines.push(`${ch.name}: +${r.healed} хп (${r.hp}/${ch.hp.max})`);
      }
    }
    log(ctx, {
      type: 'system',
      text: `🌙 ${long ? 'Продолжительный' : 'Короткий'} отдых. ${lines.join('; ')}`,
    });
    return ok(`${long ? 'Продолжительный' : 'Короткий'} отдых завершён. ${lines.join('; ')}`);
  },

  async use_spell_slot(st, input, ctx) {
    let who;
    try {
      who = target(st, input.character);
    } catch (e) {
      return fail(e.message);
    }
    if (who.kind !== 'pc') return ok('У существ ячейки не отслеживаются — просто опиши эффект.');
    const result = characterModule.useSpellSlot(who.ref, input.level);
    if (!result.ok) return fail(`${nameOf(who)}: ${result.reason}.`);
    log(ctx, {
      type: 'system',
      text: `✨ ${nameOf(who)} тратит ячейку ${input.level} круга${input.spell ? ` — ${input.spell}` : ''} (осталось ${result.remaining})`,
    });
    return ok(`Ячейка потрачена, осталось ${result.remaining} на ${input.level} круге.`);
  },

  async add_journal(st, input) {
    st.journal.push({ ts: Date.now(), text: input.text });
    if (st.journal.length > 200) st.journal = st.journal.slice(-150);
    return ok('Записано в дневник кампании.');
  },
};

/** Shared post-damage bookkeeping: death, unconsciousness, token cleanup. */
function describeAftermath(st, victim, applied, ctx) {
  if (victim.kind === 'npc') {
    if (applied.dead) {
      log(ctx, { type: 'system', text: `${victim.ref.name} повержен` });
      if (st.map) mapModule.removeToken(st.map, victim.ref.id);
      combat.pruneDefeated(st);
      return `${victim.ref.name} повержен.`;
    }
    return `${victim.ref.name}: ${combat.describeMonsterHealth(victim.ref)}.`;
  }

  const ch = victim.ref;
  if (applied.dead) {
    log(ctx, { type: 'system', text: `☠ ${ch.name} погибает`, data: { death: true } });
    return `${ch.name} погибает.`;
  }
  if (applied.unconscious) {
    log(ctx, { type: 'system', text: `${ch.name} падает без сознания на 0 хитов`, data: { down: true } });
    return `${ch.name} без сознания на 0 хитов, начинает спасброски от смерти.`;
  }
  let text = `${ch.name}: ${ch.hp.current}/${ch.hp.max} хитов.`;
  if (applied.concentrationDc) {
    text += ` Если поддерживает концентрацию — спасбросок Телосложения СЛ ${applied.concentrationDc}.`;
  }
  return text;
}

export const TOOL_NAMES = new Set(TOOL_DEFS.map((t) => t.name));
