#!/usr/bin/env bash
# Шаг 1. Docker на хосте, entrypoint, контейнер. Запускать со своей машины.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

have_host || die "HOST_ACCESS=no — этот шаг требует root на самом сервере.
   Если контейнер тебе выдали готовым, он не нужен: начинай с 03-install-hermes.sh."

step "Docker на хосте"
"${HOSTSSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  echo "   ставлю docker.io..."
  apt-get update -qq
  apt-get install -y -qq docker.io
else
  echo "   docker уже установлен"
fi
systemctl enable --now docker >/dev/null 2>&1 || true
docker version --format '   docker {{.Server.Version}} (сервер)'
REMOTE
ok "docker готов"

# Инструкция советовала `usermod -aG docker vokdub` — пользователь vokdub
# в ней больше нигде не встречается. Добавляем в группу того, под кем реально
# ходим, и только если это не root (root в группе docker не нуждается).
if [[ "$SERVER_SSH_USER" != "root" ]]; then
  step "Группа docker для ${SERVER_SSH_USER}"
  if "${HOSTSSH[@]}" "sudo usermod -aG docker '${SERVER_SSH_USER}'"; then
    ok "добавлен (перелогинься, чтобы применилось)"
  else
    warn "не удалось — docker будет требовать sudo"
  fi
fi

step "entrypoint на хосте: ${SRV_DIR}/entrypoint.sh"
# Порядок принципиален: файл обязан существовать ДО docker run.
# Если смонтировать несуществующий путь, docker создаст на его месте
# КАТАЛОГ, и контейнер не стартует с 'permission denied'.
"${HOSTSSH[@]}" bash -s -- "$SRV_DIR" <<'REMOTE'
set -euo pipefail
SRV_DIR="$1"
mkdir -p "$SRV_DIR"
# подчищаем каталог, если он остался от неудачной прошлой попытки
if [ -d "$SRV_DIR/entrypoint.sh" ]; then
  echo "   на месте entrypoint.sh был каталог (следы прошлого запуска) — удаляю"
  rmdir "$SRV_DIR/entrypoint.sh"
fi
cat > "$SRV_DIR/entrypoint.sh" <<'EOF'
#!/bin/bash
# Стартует sshd и, если hermes уже установлен, поднимает gateway от admin.
/usr/sbin/sshd -D -e &
if [ -x /home/admin/.local/bin/hermes ] && [ -f /home/admin/start-gateway.sh ]; then
  su -s /bin/sh admin -c '/home/admin/start-gateway.sh >> /home/admin/gateway.log 2>&1' &
fi
wait
EOF
chmod 755 "$SRV_DIR/entrypoint.sh"
test -f "$SRV_DIR/entrypoint.sh" && echo "   создан, права: $(stat -c '%a' "$SRV_DIR/entrypoint.sh")"
REMOTE
ok "entrypoint на месте"

step "Образ ${IMAGE}"
if "${HOSTSSH[@]}" "docker image inspect '${IMAGE}' >/dev/null 2>&1"; then
  ok "образ найден на сервере"
else
  warn "образа ${IMAGE} нет — собираю запасной из Dockerfile.fallback"
  "${HOSTSSH[@]}" "mkdir -p '${SRV_DIR}/build'"
  scp -o StrictHostKeyChecking=accept-new "$ROOT/Dockerfile.fallback" \
      "${SERVER_SSH_USER}@${SERVER_IP}:${SRV_DIR}/build/Dockerfile"
  "${HOSTSSH[@]}" "cd '${SRV_DIR}/build' && docker build -t '${IMAGE}' ."
  ok "образ ${IMAGE} собран"
fi

step "Контейнер ${CONTAINER}"
if "${HOSTSSH[@]}" "docker inspect '${CONTAINER}' >/dev/null 2>&1"; then
  warn "контейнер ${CONTAINER} уже существует"
  "${HOSTSSH[@]}" "docker start '${CONTAINER}' >/dev/null 2>&1 || true"
  ok "запущен (пересоздавать не стал — данные внутри сохранены)"
else
  "${HOSTSSH[@]}" bash -s -- "$CONTAINER" "$SSH_PORT" "$SRV_DIR" "$IMAGE" <<'REMOTE'
set -euo pipefail
CONTAINER="$1"; SSH_PORT="$2"; SRV_DIR="$3"; IMAGE="$4"
docker run -d --name "$CONTAINER" --restart unless-stopped \
  -p "${SSH_PORT}:22" \
  -v "${SRV_DIR}/entrypoint.sh:/usr/local/bin/node-entry.sh" \
  --entrypoint /usr/local/bin/node-entry.sh \
  "$IMAGE"
REMOTE
  ok "контейнер создан"
fi

step "Контейнер жив?"
sleep 3
state="$("${HOSTSSH[@]}" "docker inspect -f '{{.State.Status}}' '${CONTAINER}'")"
log "статус: ${state}"
if [[ "$state" != "running" ]]; then
  warn "контейнер не в состоянии running. Логи:"
  "${HOSTSSH[@]}" "docker logs --tail 40 '${CONTAINER}'" >&2 || true
  die "разберись с логами выше, дальше идти нельзя"
fi
if "${HOSTSSH[@]}" "docker exec '${CONTAINER}' pgrep -a sshd | head -3"; then
  ok "sshd внутри работает"
else
  die "sshd внутри не поднялся"
fi

printf '\n\033[32mШаг 1 готов. Дальше: scripts/02-ssh-access.sh\033[0m\n'
