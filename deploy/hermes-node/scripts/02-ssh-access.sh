#!/usr/bin/env bash
# Шаг 2. Ключ, доступ в контейнер, запись в ~/.ssh/config. Со своей машины.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "Ключ ${KEY_PATH}"
mkdir -p "$(dirname "$KEY_PATH")"
chmod 700 "$(dirname "$KEY_PATH")"
if [[ -f "$KEY_PATH" ]]; then
  ok "ключ уже есть, генерировать заново не буду"
else
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "admin@node${NODE_NUM}" >/dev/null
  ok "ключ создан"
fi
chmod 600 "$KEY_PATH"
PUBKEY="$(cat "${KEY_PATH}.pub")"
log "публичная часть: ${PUBKEY:0:48}..."

step "Кладу ключ в контейнер"
# Идемпотентно: grep -qF не даст задвоить строку при повторном запуске.
"${HOSTSSH[@]}" bash -s -- "$CONTAINER" "$PUBKEY" <<'REMOTE'
set -euo pipefail
CONTAINER="$1"; PUBKEY="$2"
docker exec -i "$CONTAINER" sh -s <<EOF
set -e
mkdir -p /home/admin/.ssh
touch /home/admin/.ssh/authorized_keys
if grep -qF '${PUBKEY}' /home/admin/.ssh/authorized_keys; then
  echo "   ключ уже в authorized_keys"
else
  echo '${PUBKEY}' >> /home/admin/.ssh/authorized_keys
  echo "   ключ добавлен"
fi
chown -R admin:admin /home/admin/.ssh
chmod 700 /home/admin/.ssh
chmod 600 /home/admin/.ssh/authorized_keys
EOF
REMOTE
ok "authorized_keys обновлён"

step "Запись в ~/.ssh/config"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/config"; chmod 600 "$HOME/.ssh/config"
if grep -qE "^[[:space:]]*Host[[:space:]]+${HOST_ALIAS}[[:space:]]*$" "$HOME/.ssh/config"; then
  ok "запись Host ${HOST_ALIAS} уже есть — не трогаю"
else
  cat >> "$HOME/.ssh/config" <<EOF

Host ${HOST_ALIAS}
    HostName ${SERVER_IP}
    Port ${SSH_PORT}
    User admin
    IdentityFile ${KEY_PATH}
    StrictHostKeyChecking accept-new
EOF
  ok "запись Host ${HOST_ALIAS} добавлена"
fi

step "Проверка: ssh ${HOST_ALIAS} whoami"
who="$("${NODESSH[@]}" -o ConnectTimeout=15 whoami 2>&1)" \
  || die "не пускает в контейнер. Вывод: ${who}"
log "ответ: ${who}"
[[ "$who" == "admin" ]] || die "ожидался 'admin', получено '${who}'"
ok "вход в контейнер работает"

printf '\n\033[32mШаг 2 готов. Дальше: scripts/03-install-hermes.sh\033[0m\n'
