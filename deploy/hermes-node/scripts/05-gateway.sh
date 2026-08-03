#!/usr/bin/env bash
# Шаг 5. Автозапуск gateway и перезапуск контейнера. Со своей машины.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "/home/admin/start-gateway.sh"
"${NODESSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
cat > /home/admin/start-gateway.sh <<'EOF'
#!/bin/bash
export PATH=/home/admin/.local/bin:/home/admin/.hermes/node/bin:$PATH
export HERMES_HOME=/home/admin/.hermes
set -a; source /home/admin/.hermes/.env; set +a
exec /home/admin/.local/bin/hermes gateway run --replace
EOF
sudo chown admin:admin /home/admin/start-gateway.sh
chmod 755 /home/admin/start-gateway.sh
echo "   $(stat -c '%U:%G %a' /home/admin/start-gateway.sh) /home/admin/start-gateway.sh"
REMOTE
ok "скрипт запуска создан"

# entrypoint на хосте уже создан шагом 01 и подхватит gateway при старте.
step "Проверка entrypoint на хосте"
if "${HOSTSSH[@]}" "test -f '${SRV_DIR}/entrypoint.sh' && grep -q start-gateway '${SRV_DIR}/entrypoint.sh'"; then
  ok "entrypoint содержит автозапуск gateway"
else
  die "${SRV_DIR}/entrypoint.sh отсутствует или без автозапуска — перезапусти 01-host-setup.sh"
fi

step "Перезапуск контейнера"
"${HOSTSSH[@]}" "docker restart '${CONTAINER}'" >/dev/null
log "жду 12 секунд, пока поднимется gateway..."
sleep 12

step "Процесс gateway"
procs="$("${HOSTSSH[@]}" "docker exec '${CONTAINER}' ps aux | grep -E 'hermes[[:space:]]+gateway' || true")"
if [[ -z "$procs" ]]; then
  warn "процесс gateway не найден. Последние строки лога:"
  "${HOSTSSH[@]}" "docker exec '${CONTAINER}' tail -n 40 /home/admin/gateway.log 2>/dev/null || echo '(лога нет)'" >&2
  die "gateway не поднялся"
fi
printf '%s\n' "$procs" | sed 's/^/   /'
if printf '%s' "$procs" | awk '{print $1}' | grep -q '^admin$'; then
  ok "gateway работает от пользователя admin"
else
  warn "gateway работает НЕ от admin — проверь su в entrypoint.sh"
fi

step "Лог gateway"
"${HOSTSSH[@]}" "docker exec '${CONTAINER}' tail -n 15 /home/admin/gateway.log 2>/dev/null || true" | sed 's/^/   /'
log "строка 'No messaging platforms enabled' — норма: платформы не подключены, работает CLI."

printf '\n\033[32mШаг 5 готов. Дальше: scripts/06-verify.sh\033[0m\n'
