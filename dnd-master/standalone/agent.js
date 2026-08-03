// Мастер для однофайловой сборки: тот же промпт и те же инструменты, что на
// сервере, но запрос уходит из браузера напрямую в Messages API.
//
// Это возможно благодаря заголовку anthropic-dangerous-direct-browser-access:
// без него браузер не пустит запрос из-за CORS. Ключ при этом никуда, кроме
// api.anthropic.com, не уходит и хранится только в localStorage этого браузера.

import { buildSystemPrompt, CHRONICLE_PROMPT } from '../server/dm/prompt.js';
import { TOOL_DEFS, handlers } from '../server/dm/tools.js';
import * as state from '../server/engine/state.js';

const MAX_TOOL_ROUNDS = 24;
const HISTORY_CHAR_BUDGET = 90000;
const KEEP_RECENT_MESSAGES = 16;

export const settings = {
  apiKey: '',
  model: 'claude-opus-5',
  effort: 'medium',
  maxTokens: 16000,
  // Меняется только в тестах и для тех, кто ходит через свой прокси.
  apiBase: 'https://api.anthropic.com',
};

// Серверные подстраховки: если ключу недоступна бета, выключаем её и повторяем.
let useFallbacks = true;

export function configure(patch) {
  Object.assign(settings, patch);
}

export function hasApiKey() {
  return Boolean(settings.apiKey);
}

// --------------------------------------------------------------- запрос

async function request(body, { onDelta, signal } = {}) {
  const headers = {
    'content-type': 'application/json',
    'x-api-key': settings.apiKey,
    'anthropic-version': '2023-06-01',
    'anthropic-dangerous-direct-browser-access': 'true',
  };
  const payload = { ...body, stream: true };
  if (useFallbacks) {
    headers['anthropic-beta'] = 'server-side-fallback-2026-07-01';
    payload.fallbacks = 'default';
  }

  const response = await fetch(`${settings.apiBase}/v1/messages`, {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
    signal,
  });

  if (!response.ok) {
    const text = await response.text();
    let message = text;
    try {
      message = JSON.parse(text).error?.message || text;
    } catch {
      /* оставляем как есть */
    }
    // Ключ без доступа к бете — не повод ронять ход.
    if (useFallbacks && /fallback|beta/i.test(message)) {
      useFallbacks = false;
      return request(body, { onDelta, signal });
    }
    if (response.status === 401) throw new Error('Ключ не принят. Проверь ANTHROPIC_API_KEY в настройках.');
    if (response.status === 429) throw new Error('Слишком много запросов подряд — подожди немного.');
    throw new Error(`API ответил ${response.status}: ${message}`);
  }

  return readStream(response, onDelta);
}

/** Собирает сообщение из потока SSE так же, как это делает SDK на сервере. */
async function readStream(response, onDelta) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const blocks = [];
  let stopReason = null;
  let buffer = '';

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    // События разделены пустой строкой; последний кусок может быть неполным.
    const chunks = buffer.split('\n\n');
    buffer = chunks.pop() ?? '';

    for (const chunk of chunks) {
      const line = chunk.split('\n').find((l) => l.startsWith('data:'));
      if (!line) continue;
      let event;
      try {
        event = JSON.parse(line.slice(5).trim());
      } catch {
        continue;
      }

      if (event.type === 'content_block_start') {
        blocks[event.index] = { ...event.content_block, __json: '' };
      } else if (event.type === 'content_block_delta') {
        const block = blocks[event.index];
        if (!block) continue;
        if (event.delta.type === 'text_delta') {
          block.text = (block.text || '') + event.delta.text;
          if (block.type === 'text') onDelta?.(event.delta.text);
        } else if (event.delta.type === 'input_json_delta') {
          block.__json += event.delta.partial_json;
        } else if (event.delta.type === 'thinking_delta') {
          block.thinking = (block.thinking || '') + event.delta.thinking;
        }
      } else if (event.type === 'content_block_stop') {
        const block = blocks[event.index];
        if (block?.type === 'tool_use') {
          try {
            block.input = block.__json ? JSON.parse(block.__json) : {};
          } catch {
            block.input = {};
          }
        }
      } else if (event.type === 'message_delta') {
        stopReason = event.delta?.stop_reason ?? stopReason;
      } else if (event.type === 'error') {
        throw new Error(event.error?.message || 'Поток оборвался с ошибкой');
      }
    }
  }

  const content = blocks.filter(Boolean).map(({ __json, ...block }) => block);
  return { content, stop_reason: stopReason };
}

// ------------------------------------------------------------------ ход

export async function runTurn(st, ctx) {
  if (st.dm.busy) return { skipped: true };
  if (!hasApiKey()) {
    const entry = state.addMessage(st, {
      type: 'system',
      text: 'Не задан ключ API — мастер молчит. Открой настройки и впиши ключ.',
    });
    ctx.emit(entry);
    return { error: 'нет ключа' };
  }

  st.dm.busy = true;
  ctx.onStatus?.(true);
  const narration = [];

  try {
    await maybeCompact(st);

    for (let round = 0; round < MAX_TOOL_ROUNDS; round += 1) {
      const response = await request(
        {
          model: settings.model,
          max_tokens: settings.maxTokens,
          output_config: { effort: settings.effort },
          system: [
            { type: 'text', text: buildSystemPrompt(st), cache_control: { type: 'ephemeral' } },
          ],
          tools: TOOL_DEFS,
          messages: buildMessages(st),
        },
        { onDelta: ctx.onDelta },
      );

      if (response.stop_reason === 'refusal') {
        const entry = state.addMessage(st, {
          type: 'system',
          text: 'Мастер не может продолжить эту сцену — модель отказалась отвечать. Попробуйте свернуть тему или переформулировать.',
        });
        ctx.emit(entry);
        break;
      }

      st.dm.messages.push({ role: 'assistant', content: response.content });

      const text = response.content
        .filter((b) => b.type === 'text')
        .map((b) => b.text)
        .join('')
        .trim();
      if (text) narration.push(text);

      const toolUses = response.content.filter((b) => b.type === 'tool_use');
      if (response.stop_reason !== 'tool_use' || toolUses.length === 0) break;

      const results = [];
      for (const call of toolUses) {
        const handler = handlers[call.name];
        let payload;
        if (!handler) {
          payload = { summary: `Нет такого инструмента: ${call.name}`, error: true };
        } else {
          try {
            payload = await handler(st, call.input || {}, ctx);
          } catch (e) {
            payload = { summary: `Ошибка инструмента ${call.name}: ${e.message}`, error: true };
          }
        }
        results.push({
          type: 'tool_result',
          tool_use_id: call.id,
          content: String(payload.summary ?? ''),
          ...(payload.error ? { is_error: true } : {}),
        });
      }
      st.dm.messages.push({ role: 'user', content: results });
    }
  } catch (error) {
    const entry = state.addMessage(st, {
      type: 'system',
      text: `Мастер споткнулся: ${error.message}`,
      data: { error: true },
    });
    ctx.emit(entry);
    return { error: error.message };
  } finally {
    st.dm.busy = false;
    ctx.onStatus?.(false);
  }

  const full = narration.join('\n\n').trim();
  if (full) ctx.emit(state.addMessage(st, { type: 'dm', authorName: 'Мастер', text: full }));
  return { text: full };
}

/**
 * Снимок состояния уходит последним сообщением на каждом запросе: мастер
 * всегда видит текущие хиты, а закэшированная часть остаётся неизменной.
 */
function buildMessages(st) {
  const history = st.dm.messages;
  const messages = history.map((m, i) => (i === history.length - 1 ? withCacheControl(m) : m));
  messages.push({ role: 'system', content: `# Состояние стола\n\n${state.stateSnapshot(st)}` });
  return messages;
}

function withCacheControl(message) {
  const content = Array.isArray(message.content)
    ? message.content
    : [{ type: 'text', text: String(message.content) }];
  if (content.length === 0) return message;
  return {
    ...message,
    content: content.map((block, i) =>
      i === content.length - 1 ? { ...block, cache_control: { type: 'ephemeral' } } : block,
    ),
  };
}

export function pushPlayerMessages(st, messages) {
  if (messages.length === 0) return;
  const text = messages
    .map((m) => {
      const who = m.characterName ? `${m.characterName} (${m.authorName})` : m.authorName;
      if (m.type === 'roll') return `[бросок игрока] ${m.authorName}: ${m.text}`;
      if (m.type === 'ooc') return `[вне игры] ${who}: ${m.text}`;
      if (m.type === 'action') return `${who} делает: ${m.text}`;
      return `${who} говорит: «${m.text}»`;
    })
    .join('\n');
  st.dm.messages.push({ role: 'user', content: [{ type: 'text', text }] });
}

export function pushDirective(st, text) {
  st.dm.messages.push({ role: 'user', content: [{ type: 'text', text: `[указание стола] ${text}` }] });
}

// ------------------------------------------------------------- контекст

async function maybeCompact(st) {
  const messages = st.dm.messages;
  if (JSON.stringify(messages).length < HISTORY_CHAR_BUDGET) return;

  const cut = safeCutPoint(messages, Math.max(0, messages.length - KEEP_RECENT_MESSAGES));
  if (cut <= 0) return;

  const transcript = messages
    .slice(0, cut)
    .map((m) => {
      const blocks = Array.isArray(m.content) ? m.content : [{ type: 'text', text: m.content }];
      const text = blocks
        .filter((b) => b.type === 'text' || b.type === 'tool_result')
        .map((b) => (b.type === 'text' ? b.text : `[результат: ${b.content}]`))
        .join(' ');
      return text ? `${m.role === 'user' ? 'Игроки' : 'Мастер'}: ${text}` : '';
    })
    .filter(Boolean)
    .join('\n')
    .slice(-60000);

  try {
    const response = await request({
      model: settings.model,
      max_tokens: 2000,
      output_config: { effort: 'low' },
      system: CHRONICLE_PROMPT,
      messages: [
        {
          role: 'user',
          content: `Текущая хроника:\n${st.dm.chronicle || '(пусто)'}\n\nНовая часть расшифровки:\n${transcript}`,
        },
      ],
    });
    const summary = response.content
      .filter((b) => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim();
    if (summary) st.dm.chronicle = summary;
  } catch {
    st.dm.chronicle = `${st.dm.chronicle}\n(часть истории не удалось пересказать)`.trim();
  }

  st.dm.messages = [
    {
      role: 'user',
      content: [
        {
          type: 'text',
          text:
            `[хроника предыдущих сессий]\n${st.dm.chronicle}\n\n` +
            `${st.journal.length ? `Записи дневника:\n${st.journal.map((j) => `- ${j.text}`).join('\n')}\n\n` : ''}` +
            'Продолжай игру с этого места.',
        },
      ],
    },
    ...messages.slice(cut),
  ];
}

function safeCutPoint(messages, preferred) {
  for (let i = preferred; i < messages.length; i += 1) {
    const m = messages[i];
    if (m.role !== 'user') continue;
    const blocks = Array.isArray(m.content) ? m.content : [];
    if (blocks.some((b) => b.type === 'tool_result')) continue;
    return i;
  }
  return 0;
}
