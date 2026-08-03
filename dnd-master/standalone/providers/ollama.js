// Модель на своём компьютере через Ollama (родное API /api/chat).
//
// Родное API выбрано вместо OpenAI-совместимого ради одной строчки: num_ctx.
// Описание инструментов и системный промпт — это около 4600 токенов ещё до
// первой реплики, а Ollama по умолчанию даёт модели куда более узкое окно и
// молча срезает всё, что не влезло. Мастер при этом не падает — он начинает
// нести чушь, и понять почему невозможно.

import { toolsToFunctions, localSystem, messagesToChat, blocksFromChat } from './convert.js';
import { localFetch } from './local-transport.js';

export const isReady = (settings) => Boolean(settings.localBase && settings.localModel);

const base = (settings) => settings.localBase.replace(/\/+$/, '');

export async function chat(settings, { system, snapshot, tools, messages, onDelta }) {
  const body = {
    model: settings.localModel,
    stream: true,
    options: { num_ctx: settings.numCtx },
    messages: [
      { role: 'system', content: localSystem(system, snapshot) },
      ...messagesToChat(messages, { withIds: false }),
    ],
  };
  if (tools?.length) body.tools = toolsToFunctions(tools);

  const { response, base: worked } = await localFetch(base(settings), '/api/chat', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  settings.localBase = worked;

  if (!response.ok) {
    const text = await response.text();
    if (response.status === 404) {
      throw new Error(`Ollama не знает модель «${settings.localModel}». Скачай её: ollama pull ${settings.localModel}`);
    }
    throw new Error(`Ollama ответила ${response.status}: ${text.slice(0, 300)}`);
  }

  return readStream(response, onDelta);
}

/** Поток Ollama — не SSE, а построчный JSON: одна строка на кусок ответа. */
async function readStream(response, onDelta) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const toolCalls = [];
  let text = '';
  let buffer = '';

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';

    for (const line of lines) {
      if (!line.trim()) continue;
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        continue;
      }
      if (event.error) throw new Error(`Ollama: ${event.error}`);

      const chunk = event.message?.content;
      if (chunk) {
        text += chunk;
        onDelta?.(chunk);
      }
      // Вызовы инструментов Ollama отдаёт целиком, а не по кусочкам.
      for (const call of event.message?.tool_calls || []) toolCalls.push(call);
    }
  }

  return {
    content: blocksFromChat({ text: text.trim(), toolCalls }, (i) => `ollama_${Date.now()}_${i}`),
    stop_reason: toolCalls.length ? 'tool_use' : 'end_turn',
  };
}

export async function listModels(settings) {
  const { response, base: worked } = await localFetch(base(settings), '/api/tags', { cache: 'no-store' });
  settings.localBase = worked;
  if (!response.ok) throw new Error(`Ollama ответила ${response.status} на список моделей`);
  const data = await response.json();
  return (data.models || []).map((m) => ({ id: m.name, name: m.name }));
}
