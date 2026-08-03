#!/usr/bin/env bash
# Шаг 3. Пакеты и установка hermes-agent внутрь контейнера. Со своей машины.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

INSTALL_URL="https://hermes-agent.nousresearch.com/install.sh"

step "Пакеты в контейнере"
# xz-utils и unzip обязательны: без первого установщик падает на tar.xz,
# без второго — на zip. Это самая частая причина обрыва установки.
"${NODESSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl git ca-certificates xz-utils unzip
for b in curl git xz unzip; do
  command -v "$b" >/dev/null || { echo "!! нет $b" >&2; exit 1; }
done
echo "   curl/git/xz/unzip на месте"
REMOTE
ok "пакеты установлены"

step "Установщик hermes"
# Домен отдаёт 403 с части серверных IP (Vercel WAF), поэтому сначала пробуем
# скачать на сервере, а при отказе — тянем локально и заливаем через scp.
if "${NODESSH[@]}" "curl -fsSL --max-time 60 '${INSTALL_URL}' -o /home/admin/install.sh" 2>/dev/null; then
  ok "скачан прямо на сервере"
else
  code="$("${NODESSH[@]}" "curl -s -o /dev/null -w '%{http_code}' --max-time 60 '${INSTALL_URL}'" 2>/dev/null || echo "000")"
  warn "с сервера не скачалось (HTTP ${code}) — пробую с этой машины"

  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  if ! curl -fsSL --max-time 60 "$INSTALL_URL" -o "$tmp/install.sh"; then
    die "install.sh не скачался и локально.
   Скачай вручную с машины, у которой есть доступ:
     curl -fsSL ${INSTALL_URL} -o install.sh
     scp -i ${KEY_PATH} -P ${SSH_PORT} install.sh admin@${SERVER_IP}:/home/admin/install.sh
   затем запусти этот скрипт снова."
  fi
  [[ -s "$tmp/install.sh" ]] || die "скачанный install.sh пуст"
  head -c 2 "$tmp/install.sh" | grep -q '#!' || warn "файл не похож на shell-скрипт — проверь содержимое"

  scp -i "$KEY_PATH" -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
      "$tmp/install.sh" "admin@${SERVER_IP}:/home/admin/install.sh"
  ok "залит через scp"
fi

"${NODESSH[@]}" "test -s /home/admin/install.sh" || die "install.sh в контейнере пуст или отсутствует"

step "Установка (--skip-setup --skip-browser)"
# Оба флага обязательны: без них установщик уходит в интерактивный мастер
# и висит вечно, потому что отвечать некому.
"${NODESSH[@]}" "bash /home/admin/install.sh --skip-setup --skip-browser" \
  || die "установщик вернул ошибку — смотри вывод выше"
ok "установщик отработал"

step "Проверка hermes"
ver="$("${NODESSH[@]}" "${HERMES_ENV} hermes --version" 2>&1)" \
  || die "hermes не запускается. Вывод: ${ver}"
log "hermes --version -> ${ver}"
ok "hermes на месте"

printf '\n\033[32mШаг 3 готов. Дальше: scripts/04-configure-deepseek.sh\033[0m\n'
