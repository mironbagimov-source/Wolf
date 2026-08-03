// Перевод между форматом Anthropic (в нём хранится история стола) и форматом
// чата OpenAI, на котором говорят и Ollama, и LM Studio, и llama.cpp.
//
// Разница невелика, но принципиальна в двух местах: у Anthropic сообщение —
// список блоков, а результат инструмента едет отдельным блоком внутри реплики
// игрока; в OpenAI сообщение плоское, а результат инструмента — отдельная
// реплика с ролью tool.

export function toolsToFunctions(tools = []) {
  return tools.map((tool) => ({
    type: 'function',
    function: { name: tool.name, description: tool.description, parameters: tool.input_schema },
  }));
}

/**
 * Локальные модели ведут разговор по шаблону, и не всякий шаблон переживает
 * системное сообщение в середине. Поэтому снимок стола приклеивается к концу
 * системного промпта — кэшировать всё равно нечего.
 */
export function localSystem(system, snapshot) {
  return snapshot ? `${system}\n\n# Состояние стола\n\n${snapshot}` : system;
}

const textOf = (blocks) =>
  blocks
    .filter((b) => b.type === 'text')
    .map((b) => b.text)
    .join('')
    .trim();

/**
 * @param {boolean} withIds OpenAI связывает результат с вызовом через
 *   tool_call_id; у Ollama идентификаторов нет, там связь — порядок сообщений.
 */
export function messagesToChat(messages, { withIds = true } = {}) {
  const out = [];
  const nameById = new Map();

  for (const message of messages) {
    const blocks = Array.isArray(message.content)
      ? message.content
      : [{ type: 'text', text: String(message.content) }];

    if (message.role === 'system') {
      out.push({ role: 'system', content: textOf(blocks) || String(message.content) });
      continue;
    }

    if (message.role === 'assistant') {
      const calls = blocks.filter((b) => b.type === 'tool_use');
      for (const call of calls) nameById.set(call.id, call.name);
      const entry = { role: 'assistant', content: textOf(blocks) };
      if (calls.length) {
        entry.tool_calls = calls.map((call) => ({
          ...(withIds ? { id: call.id, type: 'function' } : {}),
          function: {
            name: call.name,
            arguments: withIds ? JSON.stringify(call.input || {}) : call.input || {},
          },
        }));
      }
      out.push(entry);
      continue;
    }

    // Реплика игроков либо пачка результатов инструментов — в OpenAI это
    // разные роли, поэтому одно сообщение может развернуться в несколько.
    const results = blocks.filter((b) => b.type === 'tool_result');
    if (results.length) {
      for (const result of results) {
        out.push({
          role: 'tool',
          ...(withIds
            ? { tool_call_id: result.tool_use_id }
            : { tool_name: nameById.get(result.tool_use_id) || 'tool' }),
          content: String(result.content ?? ''),
        });
      }
      continue;
    }
    out.push({ role: 'user', content: textOf(blocks) });
  }
  return out;
}

/** Ответ модели обратно в блоки Anthropic — движок дальше знает только их. */
export function blocksFromChat({ text, toolCalls }, makeId) {
  const content = [];
  if (text) content.push({ type: 'text', text });
  for (const [index, call] of (toolCalls || []).entries()) {
    content.push({
      type: 'tool_use',
      id: call.id || makeId(index),
      name: call.function?.name || call.name,
      input: parseArguments(call.function?.arguments ?? call.arguments),
    });
  }
  return content;
}

/** Ollama отдаёт аргументы объектом, OpenAI — строкой JSON. */
function parseArguments(raw) {
  if (raw === undefined || raw === null || raw === '') return {};
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(raw);
  } catch {
    // Маленькие модели иногда роняют кавычку — лучше пустой ввод, чем сорванный ход.
    return {};
  }
}

/**
 * Локальный сервер не отвечает — почти всегда это одно из двух: он не запущен
 * либо не пускает страницу, открытую с диска. Ошибка должна сразу говорить, что
 * делать, иначе игрок останется один на один с «Failed to fetch».
 */
export function connectionError(base, cause) {
  return new Error(
    `Не достучался до локальной модели по адресу ${base}. ` +
      'Проверь, что сервер запущен и что он пускает страницы, открытые с диска: ' +
      'для Ollama — OLLAMA_ORIGINS="*" ollama serve, для LM Studio — включить CORS в настройках сервера. ' +
      `(${cause})`,
  );
}
