#!/usr/bin/env bash
# Шаг 8 (опционально). Веб-интерфейс к ассистенту. Со своей машины.
#
# Сервер слушает 127.0.0.1 ВНУТРИ контейнера и наружу не публикуется:
# у контейнера опубликован только порт SSH, добавить ещё один без root
# на хосте нельзя. Доступ — через SSH-туннель, он же и защищает интерфейс,
# у которого нет своей авторизации.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_key

[[ -f "$ROOT/web/hermes-web.py" ]] || die "нет $ROOT/web/hermes-web.py"

step "Python в контейнере"
pyv="$("${NODESSH[@]}" 'python3 --version 2>&1' || true)"
if [[ "$pyv" != Python\ 3* ]]; then
  warn "python3 не найден, ставлю"
  "${NODESSH[@]}" 'sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3' \
    || die "не удалось поставить python3"
  pyv="$("${NODESSH[@]}" 'python3 --version 2>&1')"
fi
log "$pyv"
ok "python3 на месте (внешних зависимостей интерфейс не требует)"

step "Заливаю hermes-web.py"
scp -i "$KEY_PATH" -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
    "$ROOT/web/hermes-web.py" "admin@${SERVER_IP}:/home/admin/hermes-web.py"
"${NODESSH[@]}" 'chmod 755 /home/admin/hermes-web.py'
ok "залит"

step "Скрипт запуска"
"${NODESSH[@]}" bash -s -- "$WEB_PORT" <<'REMOTE'
set -euo pipefail
PORT="$1"
cat > /home/admin/start-web.sh <<EOF
#!/bin/bash
export HERMES_HOME=/home/admin/.hermes
export PATH=/home/admin/.local/bin:/home/admin/.hermes/node/bin:\$PATH
export WEB_BIND=127.0.0.1
export WEB_PORT=${PORT}
exec /usr/bin/python3 /home/admin/hermes-web.py
EOF
chmod 755 /home/admin/start-web.sh
echo "   $(stat -c '%U:%G %a' /home/admin/start-web.sh) /home/admin/start-web.sh"
REMOTE
ok "создан"

step "Запуск"
# Старый экземпляр обязательно снять: иначе новый упадёт с
# 'Address already in use', а в браузере останется прежняя версия.
# Шаблон в скобках, чтобы pkill не убил сам себя по своей же командной строке.
"${NODESSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
pkill -u admin -f '[h]ermes-web.py' 2>/dev/null || true
sleep 1
setsid nohup /home/admin/start-web.sh >> /home/admin/web.log 2>&1 < /dev/null &
disown || true
sleep 4
REMOTE

step "Проверка изнутри контейнера"
health="$("${NODESSH[@]}" "curl -sS --max-time 10 http://127.0.0.1:${WEB_PORT}/api/health" 2>&1 || true)"
if [[ "$health" != *'"ok"'* ]]; then
  warn "интерфейс не ответил. Лог:"
  "${NODESSH[@]}" "tail -n 30 /home/admin/web.log 2>/dev/null || echo '(лога нет)'" >&2
  die "веб-интерфейс не поднялся"
fi
log "$health"
if [[ "$health" == *'"ok": true'* ]]; then
  ok "интерфейс работает и видит hermes"
else
  warn "интерфейс поднялся, но hermes не найден — сначала пройди шаги 03-06"
fi

cat <<EOF

$(printf '\033[1;32m')Готово. Как пользоваться:$(printf '\033[0m')

  1. В отдельном окне терминала подними туннель (пусть висит открытым):

       ssh -i ${KEY_PATH} -p ${SSH_PORT} \\
           -L ${WEB_PORT}:127.0.0.1:${WEB_PORT} admin@${SERVER_IP}

  2. Открой в браузере:

       http://localhost:${WEB_PORT}

Интерфейс доступен только через этот туннель — снаружи порт закрыт,
пароля у страницы нет и он не нужен, пока вход только по ssh-ключу.

Перезапуск после рестарта контейнера: прогони этот шаг заново.
Лог интерфейса: /home/admin/web.log
EOF
