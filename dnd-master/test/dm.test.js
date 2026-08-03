// Прогон цикла мастера целиком: настоящий SDK и настоящие обработчики
// инструментов, но вместо API — локальная заглушка со сценарием ответов.

import test from 'node:test';
import assert from 'node:assert/strict';

import { startMockApi } from './helpers/mock-anthropic.js';
import * as state from '../server/engine/state.js';
import * as character from '../server/engine/character.js';

/** Мастер создаётся лениво, поэтому переменные окружения ставим до импорта. */
async function withMockDm(script, run) {
  const mock = await startMockApi(script);
  process.env.ANTHROPIC_API_KEY = 'test-key';
  process.env.ANTHROPIC_BASE_URL = mock.baseUrl;
  // Свежий модуль на каждый тест: у агента внутри кэш клиента и флаги.
  const agent = await import(`../server/dm/agent.js?t=${Date.now()}`);
  try {
    return await run(agent, mock);
  } finally {
    await mock.close();
  }
}

function makeTable() {
  const st = state.createTable({ name: 'Проверка', settings: { tone: 'тёмное' } });
  state.addPlayer(st, { id: 'p1', name: 'Миша' });
  state.attachCharacter(st, 'p1', character.createFromPregen('pregen-fighter'));
  return st;
}

/** Последний пакет результатов инструментов в запросе (не снимок состояния). */
function lastToolResults(messages) {
  for (let i = messages.length - 1; i >= 0; i -= 1) {
    const content = messages[i].content;
    if (Array.isArray(content) && content.some((b) => b.type === 'tool_result')) return content;
  }
  throw new Error('в запросе нет результатов инструментов');
}

function collector() {
  const messages = [];
  const deltas = [];
  const statuses = [];
  return {
    messages,
    deltas,
    statuses,
    ctx: {
      emit: (m) => messages.push(m),
      onDelta: (d) => deltas.push(d),
      onStatus: (b) => statuses.push(b),
    },
  };
}

test('мастер: текстовый ход стримится и попадает в ленту', async () => {
  await withMockDm(
    [{ text: 'Дверь скрипит и подаётся. За ней — темнота и запах сырого камня.' }],
    async (agent) => {
      const st = makeTable();
      const sink = collector();
      agent.pushPlayerMessages(st, [
        { type: 'action', authorName: 'Миша', characterName: 'Бранд', text: 'Толкаю дверь' },
      ]);

      const result = await agent.runTurn(st, sink.ctx);

      assert.ok(result.text.includes('Дверь скрипит'));
      assert.ok(sink.deltas.length > 1, 'ответ должен приходить кусками');
      assert.equal(sink.deltas.join(''), result.text);
      assert.deepEqual(sink.statuses, [true, false]);

      const dmMessage = sink.messages.find((m) => m.type === 'dm');
      assert.ok(dmMessage, 'реплика мастера должна попасть в ленту');
      assert.equal(st.dm.busy, false);
    },
  );
});

test('мастер: цикл инструментов меняет мир, а не только текст', async () => {
  const script = [
    {
      text: 'Из темноты выступают фигуры.',
      tools: [
        { id: 'tool_1', name: 'spawn_creatures', input: { monster: 'goblin', count: 2 } },
        { id: 'tool_2', name: 'set_scene', input: { location: 'Нижний коридор', time: 'ночь' } },
      ],
    },
    {
      tools: [{ id: 'tool_3', name: 'start_combat', input: {} }],
    },
    { text: 'Гоблины бросаются вперёд. Бранд, твой ход.' },
  ];

  await withMockDm(script, async (agent, mock) => {
    const st = makeTable();
    const sink = collector();
    agent.pushPlayerMessages(st, [
      { type: 'say', authorName: 'Миша', characterName: 'Бранд', text: 'Иду дальше' },
    ]);

    await agent.runTurn(st, sink.ctx);

    assert.equal(st.npcs.length, 2, 'инструмент должен был вывести двух гоблинов');
    assert.equal(st.npcs[0].hp.max > 0, true);
    assert.equal(st.scene.location, 'Нижний коридор');
    assert.equal(st.combat.active, true);
    assert.equal(st.combat.order.length, 3, 'в бою персонаж и два гоблина');

    // Три обращения к API: два хода с инструментами и финальный текст.
    assert.equal(mock.requests.length, 3);

    // Результаты инструментов вернулись модели в правильном формате.
    // Последнее сообщение запроса — снимок состояния, поэтому ищем по типу.
    const toolResults = lastToolResults(mock.requests[1].body.messages);
    assert.equal(toolResults.length, 2);
    assert.equal(toolResults[0].type, 'tool_result');
    assert.equal(toolResults[0].tool_use_id, 'tool_1');

    // Текст обоих ходов склеился в одну реплику мастера.
    const dmMessage = sink.messages.filter((m) => m.type === 'dm').at(-1);
    assert.ok(dmMessage.text.includes('Из темноты'));
    assert.ok(dmMessage.text.includes('твой ход'));
  });
});

test('мастер: снимок состояния уходит последним и не копится в истории', async () => {
  await withMockDm([{ text: 'Хорошо.' }, { text: 'И снова хорошо.' }], async (agent, mock) => {
    const st = makeTable();
    const sink = collector();

    agent.pushPlayerMessages(st, [{ type: 'say', authorName: 'Миша', text: 'Раз' }]);
    await agent.runTurn(st, sink.ctx);
    agent.pushPlayerMessages(st, [{ type: 'say', authorName: 'Миша', text: 'Два' }]);
    await agent.runTurn(st, sink.ctx);

    for (const request of mock.requests) {
      const messages = request.body.messages;
      const systemMessages = messages.filter((m) => m.role === 'system');
      assert.equal(systemMessages.length, 1, 'снимок состояния ровно один на запрос');
      assert.equal(messages.at(-1).role, 'system', 'и он последний');
      assert.ok(systemMessages[0].content.includes('Бранд'), 'снимок содержит партию');
    }

    // В сохранённой истории снимков нет — иначе они копились бы и старели.
    assert.ok(st.dm.messages.every((m) => m.role !== 'system'));

    // Кэш промпта: системный блок помечен, и последняя реплика истории тоже.
    const last = mock.requests.at(-1).body;
    assert.equal(last.system[0].cache_control.type, 'ephemeral');
    const cachedInHistory = last.messages.filter((m) =>
      Array.isArray(m.content) ? m.content.some((b) => b.cache_control) : false,
    );
    assert.equal(cachedInHistory.length, 1, 'ровно одна точка кэша в истории');
  });
});

test('мастер: ошибка инструмента возвращается модели, а не роняет ход', async () => {
  const script = [
    { tools: [{ id: 'tool_1', name: 'attack', input: { attacker: 'Никто', target: 'Тоже никто' } }] },
    { text: 'Прошу прощения, там никого нет.' },
  ];

  await withMockDm(script, async (agent, mock) => {
    const st = makeTable();
    const sink = collector();
    agent.pushPlayerMessages(st, [{ type: 'say', authorName: 'Миша', text: 'Бей!' }]);

    const result = await agent.runTurn(st, sink.ctx);

    const toolResult = lastToolResults(mock.requests[1].body.messages)[0];
    assert.equal(toolResult.is_error, true);
    assert.match(toolResult.content, /Не нашёл/);
    assert.ok(result.text.includes('никого нет'), 'ход должен завершиться нормально');
  });
});

test('мастер: отказ модели не ломает стол', async () => {
  await withMockDm([{ text: '', stopReason: 'refusal' }], async (agent) => {
    const st = makeTable();
    const sink = collector();
    agent.pushPlayerMessages(st, [{ type: 'say', authorName: 'Миша', text: '...' }]);

    await agent.runTurn(st, sink.ctx);

    const systemMessage = sink.messages.find((m) => m.type === 'system');
    assert.ok(systemMessage.text.includes('отказалась'));
    assert.equal(st.dm.busy, false);
  });
});

test('мастер: реплики нескольких игроков склеиваются в один ход', async () => {
  await withMockDm([{ text: 'Понял вас обоих.' }], async (agent, mock) => {
    const st = makeTable();
    const sink = collector();
    agent.pushPlayerMessages(st, [
      { type: 'say', authorName: 'Миша', characterName: 'Бранд', text: 'Прикрой меня' },
      { type: 'action', authorName: 'Аня', characterName: 'Сельма', text: 'поднимает посох' },
      { type: 'roll', authorName: 'Сельма', text: 'проверка: Магия: 1d20[14] +4 = 18' },
    ]);

    await agent.runTurn(st, sink.ctx);

    const userTurn = mock.requests[0].body.messages.find((m) => m.role === 'user');
    const text = userTurn.content[0].text;
    assert.ok(text.includes('Бранд (Миша) говорит: «Прикрой меня»'));
    assert.ok(text.includes('Сельма (Аня) делает: поднимает посох'));
    assert.ok(text.includes('[бросок игрока]'));
  });
});
