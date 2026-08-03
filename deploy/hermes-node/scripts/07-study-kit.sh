#!/usr/bin/env bash
# Шаг 7 (опционально). Стартовый набор «ассистент для учёбы». Со своей машины.
# Файлы-шаблоны лежат в assets/ — отредактируй их под себя ПЕРЕД запуском.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

for f in SOUL.md MEMORY.md USER.md; do
  [[ -f "$ROOT/assets/$f" ]] || die "нет $ROOT/assets/$f"
done

step "Заливаю SOUL.md и файлы памяти"
"${NODESSH[@]}" "mkdir -p /home/admin/.hermes/memories"
scp -i "$KEY_PATH" -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
    "$ROOT/assets/SOUL.md" "admin@${SERVER_IP}:/home/admin/.hermes/SOUL.md"
scp -i "$KEY_PATH" -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
    "$ROOT/assets/MEMORY.md" "admin@${SERVER_IP}:/home/admin/.hermes/memories/MEMORY.md"
scp -i "$KEY_PATH" -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
    "$ROOT/assets/USER.md" "admin@${SERVER_IP}:/home/admin/.hermes/memories/USER.md"
ok "три файла на месте"

step "Права"
"${NODESSH[@]}" "sudo chown -R admin:admin /home/admin/.hermes && ls -la /home/admin/.hermes/memories | sed 's/^/   /'"

step "Включаю память в конфиге"
if "${NODESSH[@]}" bash -s <<REMOTE 2>/dev/null
${HERMES_ENV}
hermes config set memory.memory_enabled true
hermes config set memory.user_profile_enabled true
REMOTE
then
  ok "memory_enabled и user_profile_enabled включены"
else
  warn "hermes config set не принял ключи памяти."
  warn "Добавь вручную в /home/admin/.hermes/config.yaml:"
  warn "  memory:"
  warn "    memory_enabled: true"
  warn "    user_profile_enabled: true"
fi

step "Текущий config.yaml"
"${NODESSH[@]}" "cat /home/admin/.hermes/config.yaml 2>/dev/null | sed 's/^/   /'" || warn "config.yaml не прочитан"

step "Перезапуск gateway, чтобы подхватил персону"
"${HOSTSSH[@]}" "docker restart '${CONTAINER}'" >/dev/null
sleep 12
ok "контейнер перезапущен"

printf '\n\033[32mНабор установлен. Прогони проверку: scripts/06-verify.sh\033[0m\n'
