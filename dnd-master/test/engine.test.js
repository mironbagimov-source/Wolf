import test from 'node:test';
import assert from 'node:assert/strict';

import * as dice from '../server/engine/dice.js';
import * as rules from '../server/engine/rules.js';
import * as character from '../server/engine/character.js';
import * as combat from '../server/engine/combat.js';
import * as mapModule from '../server/engine/map.js';
import * as state from '../server/engine/state.js';
import * as srd from '../server/engine/srd.js';

test('кубики: границы и разбор выражений', () => {
  for (let i = 0; i < 500; i += 1) {
    const value = dice.rollDie(20);
    assert.ok(value >= 1 && value <= 20, `d20 вне диапазона: ${value}`);
  }

  const flat = dice.roll('2d6+3');
  assert.equal(flat.parts.length, 2);
  assert.ok(flat.total >= 5 && flat.total <= 15);

  const minus = dice.roll('1d6-1');
  assert.ok(minus.total >= 0 && minus.total <= 5, `отрицательный член не вычелся: ${minus.total}`);

  assert.throws(() => dice.roll('привет'), /Не понимаю/);
  assert.throws(() => dice.roll('200d6'), /Слишком много/);
  assert.throws(() => dice.roll('1d1'), /грань/);
});

test('кубики: keep highest оставляет нужное количество', () => {
  const result = dice.roll('4d6kh3');
  const part = result.parts[0];
  assert.equal(part.values.length, 4);
  assert.equal(part.kept.length, 3);
  assert.equal(part.dropped.length, 1);
  const droppedValue = part.values[part.dropped[0]];
  for (const index of part.kept) {
    assert.ok(part.values[index] >= droppedValue, 'отброшена не наименьшая кость');
  }
  assert.equal(part.subtotal, part.kept.reduce((sum, i) => sum + part.values[i], 0));
});

test('кубики: преимущество и помеха берут нужную кость', () => {
  for (let i = 0; i < 50; i += 1) {
    const adv = dice.d20Test({ modifier: 0, advantage: true });
    assert.equal(adv.mode, 'adv');
    assert.equal(adv.parts[0].kept.length, 1);
    const dis = dice.d20Test({ modifier: 0, disadvantage: true });
    assert.equal(dis.mode, 'dis');
  }
  // Преимущество и помеха гасят друг друга.
  const both = dice.d20Test({ advantage: true, disadvantage: true });
  assert.equal(both.mode, null);
  assert.equal(both.parts[0].values.length, 1);
});

test('правила: модификаторы и бонус мастерства', () => {
  assert.equal(rules.abilityMod(10), 0);
  assert.equal(rules.abilityMod(8), -1);
  assert.equal(rules.abilityMod(17), 3);
  assert.equal(rules.proficiencyBonus(1), 2);
  assert.equal(rules.proficiencyBonus(5), 3);
  assert.equal(rules.proficiencyBonus(20), 6);
  assert.equal(rules.levelForXp(0), 1);
  assert.equal(rules.levelForXp(300), 2);
  assert.equal(rules.levelForXp(2699), 3);
  assert.equal(rules.levelForXp(2700), 4);
});

test('персонаж: производные значения листа считаются верно', () => {
  const fighter = character.createFromPregen('pregen-fighter');
  // Кольчуга даёт фиксированные 16, щит +2.
  assert.equal(fighter.ac, 18);
  assert.equal(fighter.hp.max, 10 + fighter.mods.con);
  assert.equal(fighter.saves.str, fighter.mods.str + fighter.prof);
  assert.equal(fighter.saves.dex, fighter.mods.dex);
  assert.ok(fighter.attacks.some((a) => a.index === 'longsword'));

  const wizard = character.createFromPregen('pregen-wizard');
  assert.ok(wizard.spellcasting, 'волшебник должен уметь колдовать');
  assert.equal(wizard.spellcasting.slots[1], 2);
  assert.equal(wizard.spellcasting.dc, 8 + wizard.prof + wizard.mods.int);

  const barbarian = character.createFromPregen('pregen-barbarian');
  // Защита без доспехов: 10 + Лов + Тел.
  assert.equal(barbarian.ac, 10 + barbarian.mods.dex + barbarian.mods.con);
});

test('персонаж: урон, потеря сознания и спасброски от смерти', () => {
  const ch = character.createFromPregen('pregen-fighter');
  const max = ch.hp.max;

  character.addTempHp(ch, 5);
  const soaked = character.applyDamage(ch, 3);
  assert.equal(soaked.absorbedByTemp, 3);
  assert.equal(ch.hp.current, max, 'временные хиты должны принять урон первыми');

  character.applyDamage(ch, 200);
  assert.ok(ch.dead, 'урон вдвое больше максимума хитов убивает сразу');

  const other = character.createFromPregen('pregen-cleric');
  const down = character.applyDamage(other, other.hp.max);
  assert.equal(down.unconscious, true);
  assert.equal(other.hp.current, 0);
  assert.ok(character.hasCondition(other, 'unconscious'));

  // Три провала — смерть; результат броска не подгоняем, а копим до исхода.
  let guard = 0;
  while (!other.dead && !other.stable && guard < 100) {
    character.deathSave(other);
    guard += 1;
  }
  assert.ok(other.dead || other.stable, 'спасброски от смерти должны к чему-то привести');
});

test('персонаж: отдых восстанавливает ресурсы', () => {
  const ch = character.createFromPregen('pregen-wizard');
  character.applyDamage(ch, 5);
  character.useSpellSlot(ch, 1);
  assert.equal(ch.spells.slotsUsed[1], 1);

  const short = character.shortRest(ch, 1);
  assert.equal(short.spent, 1);
  assert.ok(short.healed >= 1);

  character.longRest(ch);
  assert.equal(ch.hp.current, ch.hp.max);
  assert.deepEqual(ch.spells.slotsUsed, {});
});

test('персонаж: опыт поднимает уровень и хиты', () => {
  const ch = character.createFromPregen('pregen-rogue');
  const hpBefore = ch.hp.max;
  const result = character.grantXp(ch, 300);
  assert.equal(result.leveledUp, true);
  assert.equal(ch.level, 2);
  assert.ok(ch.hp.max > hpBefore);
});

test('SRD: поиск работает по русскому и английскому названию', () => {
  assert.equal(srd.findMonster('гоблин').index, 'goblin');
  assert.equal(srd.findMonster('goblin').index, 'goblin');
  assert.equal(srd.findSpell('огненный шар').index, 'fireball');
  assert.equal(srd.findEquipment('длинный меч').index, 'longsword');
  assert.ok(srd.monsterBlock(srd.findMonster('wolf')).includes('КД'));
});

test('SRD: поиск переживает падежи и множественное число', () => {
  // Мастер пишет по-русски и склоняет: точного совпадения строк не будет.
  assert.equal(srd.findMonster('гоблины').index, 'goblin');
  assert.equal(srd.findMonster('скелета').index, 'skeleton');
  assert.equal(srd.findSpell('огненного шара').index, 'fireball');
  assert.equal(srd.findEquipment('длинным мечом').index, 'longsword');
  assert.equal(srd.lookupAny('опутан', 'condition', 1)[0].entry.index, 'restrained');
  // Точное совпадение всё равно должно побеждать частичное.
  assert.equal(srd.findMonster('волк').index, 'wolf');
});

test('бой: инициатива, атака и снятие павших', () => {
  const st = state.createTable({ name: 'тест' });
  state.addPlayer(st, { id: 'p1', name: 'Игрок' });
  state.attachCharacter(st, 'p1', character.createFromPregen('pregen-fighter'));
  st.npcs.push(...combat.spawnMonsters('goblin', 2));

  const started = combat.startCombat(st);
  assert.equal(started.order.length, 3);
  // Порядок строго по убыванию инициативы.
  for (let i = 1; i < started.order.length; i += 1) {
    assert.ok(started.order[i - 1].initiative >= started.order[i].initiative);
  }

  const attacker = combat.resolveTarget(st, 'Бранд');
  const victim = combat.resolveTarget(st, 'Гоблин 1');
  assert.ok(attacker && victim);

  // Бьём, пока гоблин не падёт: проверяем именно применение урона.
  let guard = 0;
  while (!victim.ref.dead && guard < 50) {
    combat.resolveAttack(st, attacker, victim, attacker.ref.attacks[0]);
    guard += 1;
  }
  assert.ok(victim.ref.dead, 'гоблин должен был пасть');
  combat.pruneDefeated(st);
  assert.ok(!st.combat.order.some((e) => e.id === victim.ref.id), 'павший уходит из порядка ходов');

  const turn = combat.nextTurn(st);
  assert.ok(turn, 'ход должен перейти дальше');
  combat.endCombat(st);
  assert.equal(st.combat.active, false);
});

test('бой: сопротивление и иммунитет меняют урон', () => {
  const st = state.createTable({ name: 'тест' });
  // У скелета уязвимость к дробящему и иммунитет к яду.
  st.npcs.push(...combat.spawnMonsters('skeleton', 1));
  const skeleton = combat.resolveTarget(st, 'Скелет');
  skeleton.ref.hp.current = 100;
  skeleton.ref.hp.max = 100;

  const poison = combat.dealDamage(st, skeleton, 10, 'poison');
  assert.equal(poison.damage, 0, 'иммунитет к яду обнуляет урон');

  const bludgeoning = combat.dealDamage(st, skeleton, 10, 'bludgeoning');
  assert.equal(bludgeoning.damage, 20, 'уязвимость удваивает урон');
});

test('бой: критическое попадание удваивает кости, но не модификатор', () => {
  assert.equal(combat.doubleDice('1d8+3'), '2d8+3');
  assert.equal(combat.doubleDice('2d6'), '4d6');
  assert.equal(combat.doubleDice('1d6+1d4+2'), '2d6+2d4+2');
});

test('карта: генерация, проходимость и туман войны', () => {
  const map = mapModule.generateMap({ theme: 'dungeon', width: 30, height: 20 });
  assert.equal(map.grid.length, 20);
  assert.equal(map.grid[0].length, 30);
  assert.ok(map.rooms.length > 0, 'в подземелье должны быть комнаты');
  assert.ok(mapModule.isWalkable(map, map.entry.x, map.entry.y), 'вход должен быть проходим');

  // Начальная область открыта, дальний угол — нет.
  assert.equal(map.revealed[map.entry.y][map.entry.x], true);
  const unseen = map.revealed.flat().filter((v) => !v).length;
  assert.ok(unseen > 0, 'карта не должна открываться целиком сразу');

  const token = mapModule.addToken(map, { name: 'Тест', kind: 'pc', x: map.entry.x, y: map.entry.y });
  const second = mapModule.addToken(map, { name: 'Второй', kind: 'npc', x: map.entry.x, y: map.entry.y });
  assert.notEqual(`${token.x},${token.y}`, `${second.x},${second.y}`, 'фишки не должны вставать в одну клетку');

  const blocked = mapModule.moveToken(map, token.id, 0, 0);
  assert.equal(blocked.ok, false, 'в стену ходить нельзя');

  mapModule.revealAll(map);
  assert.ok(map.revealed.flat().every(Boolean));
  assert.ok(mapModule.asciiMap(map).includes('Легенда'));
});

test('состояние: снимок содержит всё, что нужно мастеру', () => {
  const st = state.createTable({ name: 'тест' });
  state.addPlayer(st, { id: 'p1', name: 'Игрок' });
  state.attachCharacter(st, 'p1', character.createFromPregen('pregen-cleric'));
  st.scene.location = 'Перекрёсток у мельницы';
  st.quests.push({ id: 1, title: 'Найти мельника', status: 'новая', notes: '' });
  state.setMap(st, mapModule.generateMap({ theme: 'wilderness', width: 20, height: 14 }));

  const snapshot = state.stateSnapshot(st);
  assert.ok(snapshot.includes('Перекрёсток у мельницы'));
  assert.ok(snapshot.includes('Мать Гелла'));
  assert.ok(snapshot.includes('Найти мельника'));
  assert.ok(snapshot.includes('Карта'));
});

test('состояние: клиенту не уходят чужие приватные данные', () => {
  const st = state.createTable({ name: 'тест' });
  state.addPlayer(st, { id: 'p1', name: 'Первый' });
  state.addPlayer(st, { id: 'p2', name: 'Второй' });
  state.attachCharacter(st, 'p1', character.createFromPregen('pregen-fighter'));
  state.attachCharacter(st, 'p2', character.createFromPregen('pregen-rogue'));

  const view = state.toClient(st, { playerId: 'p1' });
  const own = view.party.find((c) => c.playerId === 'p1');
  const other = view.party.find((c) => c.playerId === 'p2');
  assert.ok(own.inventory, 'свой лист виден целиком');
  assert.equal(other.inventory, undefined, 'чужой инвентарь не уходит клиенту');
  assert.equal(other.notes, undefined);
  assert.ok(other.hp, 'но хиты союзника видны');
});

test('состояние: один игрок — один персонаж', () => {
  const st = state.createTable({ name: 'тест' });
  state.addPlayer(st, { id: 'p1', name: 'Игрок' });
  state.attachCharacter(st, 'p1', character.createFromPregen('pregen-fighter'));
  state.attachCharacter(st, 'p1', character.createFromPregen('pregen-wizard'));
  assert.equal(st.party.length, 1, 'новый персонаж заменяет предыдущего');
  assert.equal(st.party[0].class, 'wizard');
});
