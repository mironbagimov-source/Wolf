#!/usr/bin/env bash
# Шаг 5. Запуск gateway. Со своей машины.
# HOST_ACCESS=yes — автозапуск через entrypoint на хосте + docker restart.
# HOST_ACCESS=no  — запуск изнутри контейнера (переживает выход из ssh,
#                   но не переживает перезапуск самого контейнера).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_key

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
chmod 755 /home/admin/start-gateway.sh
echo "   $(stat -c '%U:%G %a' /home/admin/start-gateway.sh) /home/admin/start-gateway.sh"
REMOTE
ok "скрипт запуска создан"

if have_host; then
  step "Проверка entrypoint на хосте"
  if "${HOSTSSH[@]}" "test -f '${SRV_DIR}/entrypoint.sh' && grep -q start-gateway '${SRV_DIR}/entrypoint.sh'"; then
    ok "entrypoint содержит автозапуск gateway"
  else
    die "${SRV_DIR}/entrypoint.sh отсутствует или без автозапуска — прогони 01-host-setup.sh"
  fi

  step "Перезапуск контейнера"
  "${HOSTSSH[@]}" "docker restart '${CONTAINER}'" >/dev/null
  log "жду 12 секунд, пока поднимется gateway..."
  sleep 12
else
  step "Запуск gateway изнутри контейнера"
  # setsid + отвязка всех дескрипторов, иначе ssh не вернёт управление.
  "${NODESSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
pkill -u admin -f 'hermes gateway' 2>/dev/null || true
sleep 1
setsid nohup /home/admin/start-gateway.sh >> /home/admin/gateway.log 2>&1 < /dev/null &
disown || true
echo "   процесс запущен, жду 12 секунд..."
sleep 12
REMOTE
fi

step "Процесс gateway"
procs="$("${NODESSH[@]}" "ps -u admin -o user=,pid=,args= | grep -E 'hermes[[:alnum:][:space:]/-]*gateway' | grep -v grep || true")"
if [[ -z "$procs" ]]; then
  warn "процесс gateway не найден. Последние строки лога:"
  "${NODESSH[@]}" "tail -n 40 /home/admin/gateway.log 2>/dev/null || echo '(лога нет)'" >&2
  die "gateway не поднялся"
fi
printf '%s\n' "$procs" | sed 's/^/   /'
ok "gateway работает от пользователя admin"

step "Лог gateway"
"${NODESSH[@]}" "tail -n 15 /home/admin/gateway.log 2>/dev/null || true" | sed 's/^/   /'
log "строка 'No messaging platforms enabled' — норма: платформы не подключены, работает CLI."

if ! have_host; then
  cat <<EOF

   Замечание про автозапуск: без доступа к хосту gateway не переживёт
   перезапуск контейнера. Чтобы это починить, у администратора сервера
   должен появиться файл ${SRV_DIR}/entrypoint.sh:

     #!/bin/bash
     /usr/sbin/sshd -D -e &
     if [ -x /home/admin/.local/bin/hermes ] && [ -f /home/admin/start-gateway.sh ]; then
       su -s /bin/sh admin -c '/home/admin/start-gateway.sh >> /home/admin/gateway.log 2>&1' &
     fi
     wait

   смонтированный в контейнер как entrypoint. Пока его нет — после
   рестарта контейнера просто прогони этот шаг заново.
EOF
fi

printf '\n\033[32mШаг 5 готов. Дальше: scripts/06-verify.sh\033[0m\n'
