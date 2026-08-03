// Любой сервер с OpenAI-совместимым API: LM Studio, llama.cpp server, Jan,
// LocalAI, vLLM. Ключ не нужен — локальные серверы его не спрашивают, а если
// спрашивают, подойдёт тот же, что вписан для Claude.

import { toolsToFunctions, localSystem, messagesToChat, blocksFromChat } from './convert.js';
import { localFetch } from './local-transport.js';

export const isReady = (settings) => Boolean(settings.localBase && settings.localModel);

/** Адрес пишут и с /v1, и без — принимаем оба. */
const base = (settings) => {
  const clean = settings.localBase.replace(/\/+$/, '');
  return /\/v\d+$/.test(clean) ? clean : `${clean}/v1`;
};

const headers = (settings) => ({
  'content-type': 'application/json',
  ...(settings.apiKey ? { authorization: `Bearer ${settings.apiKey}` } : {}),
});

export async function chat(settings, { system, snapshot, tools, messages, maxTokens, onDelta }) {
  const body = {
    model: settings.localModel,
    stream: true,
    max_tokens: maxTokens || settings.maxTokens,
    messages: [
      { role: 'system', content: localSystem(system, snapshot) },
      ...messagesToChat(messages, { withIds: true }),
    ],
  };
  if (tools?.length) body.tools = toolsToFunctions(tools);

  const { response } = await localFetch(base(settings), '/chat/completions', {
    method: 'POST',
    headers: headers(settings),
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Сервер модели ответил ${response.status}: ${text.slice(0, 300)}`);
  }

  return readStream(response, onDelta);
}

async function readStream(response, onDelta) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const calls = []; // собираются по индексу: аргументы приходят по кусочкам
  let text = '';
  let finish = null;
  let buffer = '';

  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    const chunks = buffer.split('\n\n');
    buffer = chunks.pop() ?? '';

    for (const chunk of chunks) {
      const line = chunk.split('\n').find((l) => l.startsWith('data:'));
      if (!line) continue;
      const payload = line.slice(5).trim();
      if (payload === '[DONE]') continue;

      let event;
      try {
        event = JSON.parse(payload);
      } catch {
        continue;
      }
      if (event.error) throw new Error(`Сервер модели: ${event.error.message || event.error}`);

      const choice = event.choices?.[0];
      if (!choice) continue;
      finish = choice.finish_reason || finish;

      const delta = choice.delta || choice.message || {};
      if (delta.content) {
        text += delta.content;
        onDelta?.(delta.content);
      }
      for (const call of delta.tool_calls || []) {
        const index = call.index ?? calls.length;
        const slot = (calls[index] ||= { id: call.id, function: { name: '', arguments: '' } });
        if (call.id) slot.id = call.id;
        if (call.function?.name) slot.function.name = call.function.name;
        if (call.function?.arguments) slot.function.arguments += call.function.arguments;
      }
    }
  }

  const toolCalls = calls.filter(Boolean);
  return {
    content: blocksFromChat({ text: text.trim(), toolCalls }, (i) => `call_${Date.now()}_${i}`),
    stop_reason: toolCalls.length || finish === 'tool_calls' ? 'tool_use' : 'end_turn',
  };
}

export async function listModels(settings) {
  const { response } = await localFetch(base(settings), '/models', { headers: headers(settings), cache: 'no-store' });
  if (!response.ok) throw new Error(`Сервер модели ответил ${response.status} на список моделей`);
  const data = await response.json();
  return (data.data || []).map((m) => ({ id: m.id, name: m.id }));
}
