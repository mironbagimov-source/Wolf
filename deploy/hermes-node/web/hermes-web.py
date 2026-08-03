#!/usr/bin/env python3
"""Веб-интерфейс к hermes-agent.

Работает поверх CLI (`hermes -z`), а не поверх внутреннего API gateway:
это единственный интерфейс, который проверяется шагом 6 и точно существует.

Слушает 127.0.0.1 — наружу отдаётся SSH-туннелем, поэтому порт контейнера
публиковать не нужно (а без root на хосте и нельзя).

Зависимостей нет, только стандартная библиотека Python 3.
"""
import json
import os
import shutil
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERMES_HOME = os.environ.get("HERMES_HOME", "/home/admin/.hermes")
ENV_FILE = os.path.join(HERMES_HOME, ".env")
BIND = os.environ.get("WEB_BIND", "127.0.0.1")
PORT = int(os.environ.get("WEB_PORT", "8080"))
TIMEOUT = int(os.environ.get("WEB_TIMEOUT", "180"))
MAX_BODY = 256 * 1024


def hermes_bin():
    for c in (os.path.join(os.path.expanduser("~"), ".local/bin/hermes"),
              "/home/admin/.local/bin/hermes"):
        if os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    found = shutil.which("hermes")
    if found:
        return found
    return None


def build_env():
    """Окружение для hermes: PATH, HERMES_HOME и ключи из .hermes/.env."""
    env = dict(os.environ)
    env["HERMES_HOME"] = HERMES_HOME
    env["PATH"] = ("/home/admin/.local/bin:" + HERMES_HOME + "/node/bin:"
                   + env.get("PATH", "/usr/bin:/bin"))
    try:
        with open(ENV_FILE, "r", encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export "):]
                if "=" not in line:
                    continue
                key, val = line.split("=", 1)
                env[key.strip()] = val.strip().strip('"').strip("'")
    except OSError:
        pass
    return env


def work_dir():
    """Рабочий каталог для hermes. Без запасного варианта отсутствие
    /home/admin роняет запуск ещё до самой команды."""
    for candidate in ("/home/admin", os.path.expanduser("~")):
        if os.path.isdir(candidate):
            return candidate
    return None


def classify(code, out, err):
    """Разбор типовых отказов — те же случаи, что и в 06-verify.sh."""
    blob = (out + "\n" + err).lower()
    if "insufficient balance" in blob or "http 402" in blob:
        return ("Баланс DeepSeek исчерпан. Пополни на "
                "https://platform.deepseek.com/top_up — конфиг при этом верный.")
    if "access denied by security policy" in blob or "http 403" in blob:
        return ("HTTP 403: запрос ушёл мимо DeepSeek. Проверь model.base_url — "
                "он должен быть https://api.deepseek.com/v1")
    if "permission denied" in blob:
        return ("Permission denied при чтении конфига. Выполни: "
                "sudo chown -R admin:admin /home/admin/.hermes")
    if "not found" in blob and "model" in blob:
        return "Модель не найдена у провайдера. Проверь model.default в конфиге hermes."
    if code != 0 and not out:
        return err or f"hermes завершился с кодом {code} без вывода."
    return None


def ask(prompt):
    binary = hermes_bin()
    if not binary:
        return None, "Исполняемый файл hermes не найден. Установка не завершена?"
    try:
        # Список аргументов, без shell — иначе текст из браузера стал бы
        # командой оболочки.
        proc = subprocess.run(
            [binary, "-z", prompt],
            capture_output=True, text=True, timeout=TIMEOUT,
            env=build_env(), cwd=work_dir(),
        )
    except subprocess.TimeoutExpired:
        return None, f"hermes не ответил за {TIMEOUT} с."
    except OSError as exc:
        return None, f"Не удалось запустить hermes: {exc}"

    out = (proc.stdout or "").strip()
    problem = classify(proc.returncode, out, proc.stderr or "")
    if problem:
        return None, problem
    if not out:
        return None, "Пустой ответ от hermes."
    return out, None


def compose(message, history):
    """История в промпт: hermes -z одноразовый и сам контекст не помнит."""
    if not history:
        return message
    lines = []
    for turn in history[-8:]:
        role = "Пользователь" if turn.get("role") == "user" else "Ассистент"
        text = str(turn.get("content", "")).strip()
        if text:
            lines.append(f"{role}: {text}")
    if not lines:
        return message
    return ("Ниже предыдущие реплики диалога, они нужны только для контекста.\n\n"
            + "\n".join(lines)
            + f"\n\nПользователь: {message}\n\nОтветь на последнюю реплику.")


class Handler(BaseHTTPRequestHandler):
    server_version = "hermes-web"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        blob = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(blob)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(blob)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/":
            self._send(200, PAGE, "text/html; charset=utf-8")
        elif path == "/api/health":
            binary = hermes_bin()
            self._send(200, json.dumps({
                "ok": bool(binary),
                "hermes": binary or "",
                "env_file": os.path.isfile(ENV_FILE),
            }))
        else:
            self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/chat":
            self._send(404, json.dumps({"error": "not found"}))
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            self._send(400, json.dumps({"error": "Некорректный размер запроса"}))
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            message = str(payload.get("message", "")).strip()
            history = payload.get("history") or []
            if not isinstance(history, list):
                history = []
        except (ValueError, UnicodeDecodeError):
            self._send(400, json.dumps({"error": "Тело запроса не разобрано"}))
            return
        if not message:
            self._send(400, json.dumps({"error": "Пустое сообщение"}))
            return

        reply, problem = ask(compose(message, history))
        if problem:
            self._send(200, json.dumps({"error": problem}, ensure_ascii=False))
        else:
            self._send(200, json.dumps({"reply": reply}, ensure_ascii=False))


PAGE = r"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ассистент</title>
<style>
  :root{
    --bg:#f6f7f9; --panel:#fff; --ink:#16181d; --muted:#6b7280;
    --line:#e3e6ea; --me:#2563eb; --me-ink:#fff; --err:#b42318; --err-bg:#fef3f2;
  }
  @media (prefers-color-scheme:dark){
    :root{
      --bg:#0f1115; --panel:#171a21; --ink:#e8eaed; --muted:#9aa1ac;
      --line:#252932; --me:#3b82f6; --me-ink:#fff; --err:#ff9c92; --err-bg:#2a1614;
    }
  }
  *{box-sizing:border-box}
  html,body{height:100%}
  body{margin:0;background:var(--bg);color:var(--ink);
       font:16px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
       display:flex;flex-direction:column}
  header{padding:14px 18px;border-bottom:1px solid var(--line);background:var(--panel);
         display:flex;align-items:center;gap:10px;flex:none}
  header b{font-size:15px;font-weight:600}
  .dot{width:8px;height:8px;border-radius:50%;background:var(--muted);flex:none}
  .dot.on{background:#12b76a}.dot.off{background:#f04438}
  .status{font-size:13px;color:var(--muted);margin-left:auto}
  main{flex:1;overflow-y:auto;padding:20px}
  .wrap{max-width:760px;margin:0 auto;display:flex;flex-direction:column;gap:14px}
  .msg{display:flex}
  .msg.user{justify-content:flex-end}
  .bubble{max-width:min(80%,600px);padding:11px 14px;border-radius:14px;
          white-space:pre-wrap;overflow-wrap:anywhere}
  .bot .bubble{background:var(--panel);border:1px solid var(--line);border-bottom-left-radius:4px}
  .user .bubble{background:var(--me);color:var(--me-ink);border-bottom-right-radius:4px}
  .err .bubble{background:var(--err-bg);border:1px solid var(--err);color:var(--err)}
  .hint{color:var(--muted);text-align:center;padding:40px 12px;font-size:15px}
  footer{border-top:1px solid var(--line);background:var(--panel);padding:12px 18px;flex:none}
  .row{max-width:760px;margin:0 auto;display:flex;gap:10px;align-items:flex-end}
  textarea{flex:1;resize:none;border:1px solid var(--line);border-radius:12px;
           padding:11px 13px;font:inherit;background:var(--bg);color:var(--ink);
           max-height:180px;min-height:46px}
  textarea:focus{outline:2px solid var(--me);outline-offset:-1px}
  button{border:0;border-radius:12px;background:var(--me);color:var(--me-ink);
         padding:0 20px;height:46px;font:inherit;font-weight:600;cursor:pointer;flex:none}
  button:disabled{opacity:.5;cursor:default}
  .tip{max-width:760px;margin:8px auto 0;color:var(--muted);font-size:12px;text-align:center}
  /* На узком экране кнопка съедала ширину поля, и плейсхолдер переносился
     на вторую строку, обрезаясь по min-height. */
  @media (max-width:480px){
    main{padding:14px}
    footer{padding:10px 12px}
    button{padding:0 14px}
    .tip{font-size:11px}
    .bubble{max-width:88%}
  }
  .typing span{display:inline-block;width:6px;height:6px;margin-right:3px;border-radius:50%;
               background:var(--muted);animation:b 1.2s infinite}
  .typing span:nth-child(2){animation-delay:.2s}
  .typing span:nth-child(3){animation-delay:.4s}
  @keyframes b{0%,60%,100%{opacity:.25}30%{opacity:1}}
</style>
</head>
<body>
<header>
  <span class="dot" id="dot"></span>
  <b>Ассистент</b>
  <span class="status" id="status">проверяю…</span>
</header>

<main><div class="wrap" id="log">
  <div class="hint" id="hint">Задай вопрос — ответит ассистент на твоём сервере.</div>
</div></main>

<footer>
  <div class="row">
    <textarea id="box" rows="1" placeholder="Сообщение…" autofocus></textarea>
    <button id="send">Отправить</button>
  </div>
  <div class="tip">Enter — отправить, Shift+Enter — новая строка</div>
</footer>

<script>
const log = document.getElementById('log');
const box = document.getElementById('box');
const send = document.getElementById('send');
const dot = document.getElementById('dot');
const status = document.getElementById('status');
const hint = document.getElementById('hint');
let history = [];
let busy = false;

fetch('/api/health').then(r => r.json()).then(h => {
  dot.className = 'dot ' + (h.ok ? 'on' : 'off');
  status.textContent = h.ok ? 'на связи' : 'hermes не найден';
}).catch(() => { dot.className = 'dot off'; status.textContent = 'сервер недоступен'; });

function add(role, text) {
  if (hint) hint.remove();
  const row = document.createElement('div');
  row.className = 'msg ' + role;
  const b = document.createElement('div');
  b.className = 'bubble';
  b.textContent = text;
  row.appendChild(b);
  log.appendChild(row);
  row.scrollIntoView({block: 'end'});
  return row;
}

function typing() {
  if (hint) hint.remove();
  const row = document.createElement('div');
  row.className = 'msg bot';
  row.innerHTML = '<div class="bubble typing"><span></span><span></span><span></span></div>';
  log.appendChild(row);
  row.scrollIntoView({block: 'end'});
  return row;
}

async function submit() {
  const text = box.value.trim();
  if (!text || busy) return;
  busy = true; send.disabled = true;
  box.value = ''; box.style.height = 'auto';
  add('user', text);
  const wait = typing();
  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({message: text, history: history})
    });
    const data = await res.json();
    wait.remove();
    if (data.error) {
      add('err', data.error);
    } else {
      add('bot', data.reply);
      history.push({role: 'user', content: text});
      history.push({role: 'assistant', content: data.reply});
      history = history.slice(-16);
    }
  } catch (e) {
    wait.remove();
    add('err', 'Не достучался до сервера: ' + e.message);
  }
  busy = false; send.disabled = false; box.focus();
}

send.onclick = submit;
box.addEventListener('keydown', e => {
  if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); }
});
box.addEventListener('input', () => {
  box.style.height = 'auto';
  box.style.height = Math.min(box.scrollHeight, 180) + 'px';
});
</script>
</body>
</html>
"""


def main():
    if BIND not in ("127.0.0.1", "localhost", "::1"):
        sys.stderr.write(
            f"!! Слушаю {BIND} — это не loopback. Интерфейс без пароля,\n"
            "   так его увидит любой, кто дотянется до порта. Для личного\n"
            "   доступа надёжнее оставить 127.0.0.1 и пробросить SSH-туннелем.\n")
    srv = ThreadingHTTPServer((BIND, PORT), Handler)
    srv.daemon_threads = True
    sys.stderr.write(f"hermes-web слушает http://{BIND}:{PORT}\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
