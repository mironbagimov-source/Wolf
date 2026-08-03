// Заглушка локальной модели: отвечает и по-оллámовски, и в формате OpenAI.
//
// Нужна ровно за тем же, зачем mock-anthropic: прогнать цикл мастера целиком —
// через настоящие адаптеры, настоящий разбор потока и настоящие обработчики
// инструментов — не поднимая Ollama и не завися от железа.

import http from 'node:http';

/**
 * @param {Array} script последовательность ответов; каждый — { text, tools }
 * @param {Array} models какие модели «установлены»
 */
export async function startMockLocalLlm(script, models = ['qwen3:8b', 'llama3.1:8b']) {
  const requests = [];
  let index = 0;

  const cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
  };

  const server = http.createServer((req, res) => {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, cors);
      return res.end();
    }

    // Списки моделей: у Ollama свой формат, у OpenAI-совместимых — свой.
    if (req.url === '/api/tags') {
      res.writeHead(200, { ...cors, 'content-type': 'application/json' });
      return res.end(JSON.stringify({ models: models.map((name) => ({ name })) }));
    }
    if (req.url === '/v1/models') {
      res.writeHead(200, { ...cors, 'content-type': 'application/json' });
      return res.end(JSON.stringify({ object: 'list', data: models.map((id) => ({ id, object: 'model' })) }));
    }

    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      const parsed = body ? JSON.parse(body) : {};
      requests.push({ url: req.url, body: parsed });
      const step = script[Math.min(index, script.length - 1)];
      index += 1;

      if (req.url === '/api/chat') {
        res.writeHead(200, { ...cors, 'content-type': 'application/x-ndjson' });
        for (const line of ollamaLines(step)) res.write(`${JSON.stringify(line)}\n`);
        return res.end();
      }

      res.writeHead(200, { ...cors, 'content-type': 'text/event-stream' });
      for (const event of openaiEvents(step)) res.write(`data: ${JSON.stringify(event)}\n\n`);
      res.write('data: [DONE]\n\n');
      res.end();
    });
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();

  return {
    baseUrl: `http://127.0.0.1:${port}`,
    requests,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

/** Ollama шлёт построчный JSON, а вызовы инструментов — одним куском и без id. */
function* ollamaLines(step) {
  for (const chunk of (step.text || '').match(/.{1,12}/gs) || []) {
    yield { message: { role: 'assistant', content: chunk }, done: false };
  }
  if (step.tools?.length) {
    yield {
      message: {
        role: 'assistant',
        content: '',
        // Аргументы приходят объектом, а не строкой — это отличие от OpenAI.
        tool_calls: step.tools.map((t) => ({ function: { name: t.name, arguments: t.input } })),
      },
      done: false,
    };
  }
  yield { message: { role: 'assistant', content: '' }, done: true, done_reason: 'stop' };
}

/** OpenAI шлёт SSE, а аргументы инструмента — строкой и по кусочкам. */
function* openaiEvents(step) {
  for (const chunk of (step.text || '').match(/.{1,12}/gs) || []) {
    yield { choices: [{ index: 0, delta: { content: chunk }, finish_reason: null }] };
  }
  for (const [i, tool] of (step.tools || []).entries()) {
    yield {
      choices: [
        {
          index: 0,
          delta: { tool_calls: [{ index: i, id: `call_${i}`, type: 'function', function: { name: tool.name, arguments: '' } }] },
        },
      ],
    };
    // Рвём JSON пополам: клиент обязан склеить куски, а не разобрать первый.
    const json = JSON.stringify(tool.input);
    const half = Math.ceil(json.length / 2);
    for (const part of [json.slice(0, half), json.slice(half)]) {
      yield { choices: [{ index: 0, delta: { tool_calls: [{ index: i, function: { arguments: part } }] } }] };
    }
  }
  yield { choices: [{ index: 0, delta: {}, finish_reason: step.tools?.length ? 'tool_calls' : 'stop' }] };
}
