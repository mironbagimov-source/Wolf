// Заглушка Messages API: отдаёт заранее записанные ответы в формате SSE.
//
// Нужна, чтобы прогонять цикл мастера целиком — через настоящий SDK,
// настоящий разбор потока и настоящие обработчики инструментов — не тратя
// токены и не завися от сети.

import http from 'node:http';

/**
 * @param {Array} script последовательность ответов; каждый — { text, tools, stopReason }
 */
export async function startMockApi(script) {
  const requests = [];
  let index = 0;

  // Однофайловую сборку прогоняем с диска, то есть с origin «null»: без этих
  // заголовков браузер не отпустит запрос дальше проверки CORS.
  const cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': 'POST, OPTIONS',
  };

  const server = http.createServer((req, res) => {
    if (req.method === 'OPTIONS') {
      res.writeHead(204, cors);
      return res.end();
    }

    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      const parsed = body ? JSON.parse(body) : {};
      requests.push({ url: req.url, body: parsed, headers: req.headers });

      const step = script[Math.min(index, script.length - 1)];
      index += 1;

      // Шаг может быть отказом — так проверяется, что клиент гасит
      // неподдерживаемую возможность и повторяет запрос, а не роняет ход.
      if (step.status) {
        res.writeHead(step.status, { ...cors, 'content-type': 'application/json' });
        return res.end(JSON.stringify({ type: 'error', error: { type: 'invalid_request_error', message: step.error } }));
      }

      if (!parsed.stream) {
        res.writeHead(200, { ...cors, 'content-type': 'application/json' });
        res.end(JSON.stringify(nonStreamed(step)));
        return;
      }

      res.writeHead(200, {
        ...cors,
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'keep-alive',
      });
      for (const event of streamEvents(step)) {
        res.write(`event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
      }
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

function blocks(step) {
  const out = [];
  if (step.text) out.push({ type: 'text', text: step.text });
  for (const tool of step.tools || []) {
    out.push({ type: 'tool_use', id: tool.id, name: tool.name, input: tool.input });
  }
  return out;
}

function nonStreamed(step) {
  return {
    id: 'msg_mock',
    type: 'message',
    role: 'assistant',
    model: 'claude-opus-5',
    content: blocks(step),
    stop_reason: step.stopReason || (step.tools?.length ? 'tool_use' : 'end_turn'),
    stop_sequence: null,
    usage: { input_tokens: 100, output_tokens: 50 },
  };
}

function* streamEvents(step) {
  yield {
    type: 'message_start',
    message: {
      id: 'msg_mock',
      type: 'message',
      role: 'assistant',
      model: 'claude-opus-5',
      content: [],
      stop_reason: null,
      stop_sequence: null,
      usage: { input_tokens: 100, output_tokens: 1 },
    },
  };

  let index = 0;
  if (step.text) {
    yield { type: 'content_block_start', index, content_block: { type: 'text', text: '' } };
    // Режем текст на куски, чтобы проверить накопление дельт на клиенте.
    for (const chunk of step.text.match(/.{1,12}/gs) || []) {
      yield { type: 'content_block_delta', index, delta: { type: 'text_delta', text: chunk } };
    }
    yield { type: 'content_block_stop', index };
    index += 1;
  }

  for (const tool of step.tools || []) {
    yield {
      type: 'content_block_start',
      index,
      content_block: { type: 'tool_use', id: tool.id, name: tool.name, input: {} },
    };
    yield {
      type: 'content_block_delta',
      index,
      delta: { type: 'input_json_delta', partial_json: JSON.stringify(tool.input) },
    };
    yield { type: 'content_block_stop', index };
    index += 1;
  }

  yield {
    type: 'message_delta',
    delta: { stop_reason: step.stopReason || (step.tools?.length ? 'tool_use' : 'end_turn'), stop_sequence: null },
    usage: { output_tokens: 60 },
  };
  yield { type: 'message_stop' };
}
