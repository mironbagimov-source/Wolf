// The AI dungeon master: one turn = one Claude conversation round, with the
// tool loop, streaming narration, prompt caching and history compaction.
//
// The division of labour that makes this trustworthy: Claude decides what
// happens next and how to describe it; every die, hit point and position comes
// from the engine via tools.js, and lands in the shared log where players can
// check it.

import Anthropic from '@anthropic-ai/sdk';
import { buildSystemPrompt, CHRONICLE_PROMPT } from './prompt.js';
import { TOOL_DEFS, handlers } from './tools.js';
import * as state from '../engine/state.js';

const MODEL = process.env.DM_MODEL || 'claude-opus-5';
const EFFORT = process.env.DM_EFFORT || 'medium';
const MAX_TOKENS = Number(process.env.DM_MAX_TOKENS || 16000);
const MAX_TOOL_ROUNDS = 24;

// Compact the conversation once it grows past this many characters. Rough
// proxy for tokens, but it only has to be in the right ballpark.
const HISTORY_CHAR_BUDGET = Number(process.env.DM_HISTORY_BUDGET || 90000);
const KEEP_RECENT_MESSAGES = 16;

let client = null;
// The API can decline a request (`stop_reason: "refusal"`); server-side
// fallbacks re-run it on another model in the same call. If the beta isn't
// available to this key we turn it off after the first rejection.
let useFallbacks = true;
// Mid-conversation system messages carry the live state snapshot. Supported on
// Opus 5; on other models we fold the snapshot into the user turn instead.
let useSystemMessages = true;

export function hasApiKey() {
  return Boolean(process.env.ANTHROPIC_API_KEY);
}

function getClient() {
  if (!client) {
    if (!hasApiKey()) {
      throw new Error(
        'Не задан ANTHROPIC_API_KEY. Скопируй .env.example в .env и впиши ключ с console.anthropic.com.',
      );
    }
    client = new Anthropic();
  }
  return client;
}

// ------------------------------------------------------------------ turn

/**
 * Runs one DM turn.
 *
 * @param {object} st          table state
 * @param {object} ctx
 * @param {(msg:object)=>void} ctx.emit        broadcast a transcript entry
 * @param {(delta:string)=>void} ctx.onDelta   stream narration to clients
 * @param {(busy:boolean)=>void} ctx.onStatus  DM thinking indicator
 */
export async function runTurn(st, ctx) {
  if (st.dm.busy) return { skipped: true };
  st.dm.busy = true;
  ctx.onStatus?.(true);

  const narration = [];
  try {
    await maybeCompact(st);

    for (let round = 0; round < MAX_TOOL_ROUNDS; round += 1) {
      const response = await callModel(st, ctx);

      if (response.stop_reason === 'refusal') {
        const entry = state.addMessage(st, {
          type: 'system',
          text: 'Мастер не может продолжить эту сцену — модель отказалась отвечать. Попробуйте свернуть тему или переформулировать.',
        });
        ctx.emit(entry);
        break;
      }

      // Keep the assistant turn verbatim: thinking blocks and tool_use blocks
      // must be echoed back unchanged on the next request.
      st.dm.messages.push({ role: 'assistant', content: response.content });

      const text = response.content
        .filter((b) => b.type === 'text')
        .map((b) => b.text)
        .join('')
        .trim();
      if (text) narration.push(text);

      const toolUses = response.content.filter((b) => b.type === 'tool_use');
      if (response.stop_reason !== 'tool_use' || toolUses.length === 0) break;

      // Run every requested tool, then return all results in one user turn.
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
  if (full) {
    const entry = state.addMessage(st, { type: 'dm', authorName: 'Мастер', text: full });
    ctx.emit(entry);
  }
  return { text: full };
}

async function callModel(st, ctx) {
  const api = getClient();
  const snapshot = state.stateSnapshot(st);

  const request = {
    model: MODEL,
    max_tokens: MAX_TOKENS,
    output_config: { effort: EFFORT },
    system: [
      {
        type: 'text',
        text: buildSystemPrompt(st),
        // Caches the tool definitions and the system prompt together — they are
        // identical on every turn of a session.
        cache_control: { type: 'ephemeral' },
      },
    ],
    tools: TOOL_DEFS,
    messages: buildMessages(st, snapshot),
  };

  const betas = [];
  if (useFallbacks) {
    betas.push('server-side-fallback-2026-07-01');
    request.fallbacks = 'default';
  }

  const send = () =>
    betas.length
      ? api.beta.messages.stream({ ...request, betas })
      : api.messages.stream(request);

  let stream;
  try {
    stream = send();
    return await consume(stream, ctx);
  } catch (error) {
    const message = String(error?.message || '');
    // Degrade gracefully if this key/model doesn't have the newer request
    // features, rather than failing the whole turn.
    if (useFallbacks && /fallback|beta/i.test(message)) {
      useFallbacks = false;
      delete request.fallbacks;
      return consume(api.messages.stream(request), ctx);
    }
    if (useSystemMessages && /role 'system'|system.*not supported/i.test(message)) {
      useSystemMessages = false;
      request.messages = buildMessages(st, snapshot);
      return consume(api.messages.stream(request), ctx);
    }
    throw error;
  }
}

async function consume(stream, ctx) {
  if (ctx.onDelta) {
    stream.on('text', (delta) => ctx.onDelta(delta));
  }
  return stream.finalMessage();
}

/**
 * The stored history never contains the state snapshot — it is appended fresh
 * on every request so the DM always reads current hit points, and so the cached
 * prefix in front of it stays byte-identical between turns.
 */
function buildMessages(st, snapshot) {
  const history = st.dm.messages;
  const messages = history.map((m, i) =>
    i === history.length - 1 ? withCacheControl(m) : m,
  );

  if (useSystemMessages) {
    messages.push({ role: 'system', content: `# Состояние стола\n\n${snapshot}` });
  } else if (messages.length) {
    // Fold the snapshot into the last user turn for models without the
    // mid-conversation system role.
    const last = messages[messages.length - 1];
    if (last.role === 'user') {
      const content = Array.isArray(last.content) ? [...last.content] : [{ type: 'text', text: last.content }];
      content.push({ type: 'text', text: `<состояние>\n${snapshot}\n</состояние>` });
      messages[messages.length - 1] = { ...last, content };
    }
  }
  return messages;
}

/** Marks the end of the stable prefix so each turn reuses the cached history. */
function withCacheControl(message) {
  const content = Array.isArray(message.content)
    ? message.content
    : [{ type: 'text', text: String(message.content) }];
  if (content.length === 0) return message;
  const copy = content.map((block, i) =>
    i === content.length - 1 ? { ...block, cache_control: { type: 'ephemeral' } } : block,
  );
  return { ...message, content: copy };
}

// ------------------------------------------------------------- player input

/**
 * Queues what the players said as one user turn. Batching means several people
 * can speak before the DM answers, the way they would at a real table.
 */
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

/** A nudge with no player input — "the world keeps moving". */
export function pushDirective(st, text) {
  st.dm.messages.push({ role: 'user', content: [{ type: 'text', text: `[указание стола] ${text}` }] });
}

// ---------------------------------------------------------------- context

function historySize(messages) {
  return JSON.stringify(messages).length;
}

/**
 * Folds the older half of the conversation into a prose chronicle when the
 * history gets long. The cut never lands between a tool call and its result.
 */
async function maybeCompact(st) {
  const messages = st.dm.messages;
  if (historySize(messages) < HISTORY_CHAR_BUDGET) return;

  const cut = safeCutPoint(messages, Math.max(0, messages.length - KEEP_RECENT_MESSAGES));
  if (cut <= 0) return;

  const older = messages.slice(0, cut);
  const transcript = older
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
    const api = getClient();
    const response = await api.messages.create({
      model: MODEL,
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
    // If summarising fails we still trim, just with a coarser memory.
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

/**
 * Finds an index at or after `preferred` where cutting is safe: the message
 * there must be a user turn that is not a batch of tool results.
 */
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

export { MODEL, EFFORT };
