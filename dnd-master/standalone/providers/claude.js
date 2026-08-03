// Claude через Messages API, запрос уходит прямо из браузера.
//
// Это возможно благодаря заголовку anthropic-dangerous-direct-browser-access:
// без него браузер не пустит запрос из-за CORS. Ключ при этом никуда, кроме
// api.anthropic.com, не уходит и хранится только в localStorage этого браузера.

// Серверные подстраховки: если ключу недоступна бета, выключаем её и повторяем.
let useFallbacks = true;

export const isReady = (settings) => Boolean(settings.apiKey);

export async function chat(settings, { system, snapshot, tools, messages, maxTokens, effort, onDelta }) {
  const body = {
    model: settings.model,
    max_tokens: maxTokens || settings.maxTokens,
    output_config: { effort: effort || settings.effort },
    system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
    messages: withSnapshot(messages, snapshot),
  };
  if (tools?.length) body.tools = tools;
  return request(settings, body, onDelta);
}

/**
 * Снимок состояния уходит последним сообщением: мастер всегда видит текущие
 * хиты, а закэшированная часть запроса остаётся байт в байт прежней.
 */
function withSnapshot(messages, snapshot) {
  const out = messages.map((m, i) => (i === messages.length - 1 ? withCacheControl(m) : m));
  if (snapshot) out.push({ role: 'system', content: `# Состояние стола\n\n${snapshot}` });
  return out;
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

async function request(settings, body, onDelta) {
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
  });

  if (!response.ok) {
    const message = await errorText(response);
    // Ключ без доступа к бете — не повод ронять ход.
    if (useFallbacks && /fallback|beta/i.test(message)) {
      useFallbacks = false;
      return request(settings, body, onDelta);
    }
    if (response.status === 401) throw new Error('Ключ не принят. Проверь его в настройках стола.');
    if (response.status === 429) throw new Error('Слишком много запросов подряд — подожди немного.');
    throw new Error(`API ответил ${response.status}: ${message}`);
  }

  return readStream(response, onDelta);
}

async function errorText(response) {
  const text = await response.text();
  try {
    return JSON.parse(text).error?.message || text;
  } catch {
    return text;
  }
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

/** У Anthropic нет открытого списка моделей — показываем те, что умеем вести. */
export async function listModels() {
  return [
    { id: 'claude-opus-5', name: 'Opus 5 — лучший мастер' },
    { id: 'claude-sonnet-5', name: 'Sonnet 5 — быстрее и дешевле' },
    { id: 'claude-haiku-4-5-20251001', name: 'Haiku 4.5 — самый быстрый' },
  ];
}
