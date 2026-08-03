// Ход мастера в однофайловой сборке: тот же промпт и те же инструменты, что на
// сервере, но запрос уходит прямо из браузера — к Claude по ключу или к модели,
// поднятой на своём компьютере. Кто именно отвечает, решает standalone/providers.

import { buildSystemPrompt, CHRONICLE_PROMPT } from '../server/dm/prompt.js';
import { TOOL_DEFS, handlers } from '../server/dm/tools.js';
import * as state from '../server/engine/state.js';
import * as providers from './providers/index.js';

const MAX_TOOL_ROUNDS = 24;
const HISTORY_CHAR_BUDGET = 90000;
const KEEP_RECENT_MESSAGES = 16;

export const settings = providers.settings;
export const configure = providers.configure;
export const isReady = providers.isReady;
export const listModels = providers.listModels;

// ------------------------------------------------------------------ ход

export async function runTurn(st, ctx) {
  if (st.dm.busy) return { skipped: true };
  if (!providers.isReady()) {
    const entry = state.addMessage(st, {
      type: 'system',
      text: `Мастер не настроен — он молчит. ${providers.readyHint()}`,
    });
    ctx.emit(entry);
    return { error: 'мастер не настроен' };
  }

  st.dm.busy = true;
  ctx.onStatus?.(true);
  const narration = [];

  try {
    await maybeCompact(st);

    for (let round = 0; round < MAX_TOOL_ROUNDS; round += 1) {
      const response = await providers.chat({
        system: buildSystemPrompt(st),
        snapshot: state.stateSnapshot(st),
        tools: TOOL_DEFS,
        messages: st.dm.messages,
        onDelta: ctx.onDelta,
      });

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

      // На stop_reason не полагаемся: локальные серверы ставят его как попало,
      // а вот наличие вызовов — факт, который либо есть, либо нет.
      const toolUses = response.content.filter((b) => b.type === 'tool_use');
      if (toolUses.length === 0) break;

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
    const response = await providers.chat({
      system: CHRONICLE_PROMPT,
      snapshot: null,
      tools: [],
      maxTokens: 2000,
      effort: 'low',
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'text',
              text: `Текущая хроника:\n${st.dm.chronicle || '(пусто)'}\n\nНовая часть расшифровки:\n${transcript}`,
            },
          ],
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
