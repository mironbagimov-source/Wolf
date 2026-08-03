#!/usr/bin/env bash
# Шаг 0. Проверки до того, как что-то менять на сервере.
# Запускать со своей машины.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "Параметры"
log "контейнер  : admin@${SERVER_IP}:${SSH_PORT} (${CONTAINER}, нода ${NODE_NUM})"
if have_host; then
  log "хост       : ${SERVER_SSH_USER}@${SERVER_IP} (HOST_ACCESS=yes)"
else
  log "хост       : не используется (HOST_ACCESS=no)"
fi
log "модель     : ${DEEPSEEK_MODEL}"
log "base_url   : ${DEEPSEEK_BASE_URL}"

step "Ключ DeepSeek"
[[ -n "${DEEPSEEK_API_KEY:-}" ]] || die "DEEPSEEK_API_KEY пуст в config.env"
[[ "$DEEPSEEK_API_KEY" == sk-* ]] || die "Ключ должен начинаться с 'sk-', получено: '${DEEPSEEK_API_KEY:0:6}...'"
[[ "$DEEPSEEK_API_KEY" != *" "* ]] || die "В ключе пробел — скорее всего скопирован лишний текст"
ok "формат ключа похож на настоящий (${#DEEPSEEK_API_KEY} символов)"

step "Живая проверка ключа и модели через GET /models"
models_raw="$(curl -sS --max-time 25 -w '\n%{http_code}' \
  -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
  "${DEEPSEEK_BASE_URL%/}/models" 2>&1)" || die "curl не смог достучаться до ${DEEPSEEK_BASE_URL}"

http_code="$(tail -n1 <<<"$models_raw")"
body="$(sed '$d' <<<"$models_raw")"

case "$http_code" in
  200) ok "API отвечает, ключ принят" ;;
  401) die "HTTP 401 — ключ недействителен или отозван. Выпусти новый: https://platform.deepseek.com/api_keys" ;;
  402) warn "HTTP 402 Insufficient Balance — ключ валиден, но баланс нулевой."
       warn "Установка пройдёт до конца, финальный запрос упрётся в баланс."
       warn "Пополнить: https://platform.deepseek.com/top_up" ;;
  403) die "HTTP 403 — доступ закрыт. Проверь base_url (должен быть api.deepseek.com, не OpenRouter) и IP сервера." ;;
  *)   die "Неожиданный HTTP ${http_code} от ${DEEPSEEK_BASE_URL}/models. Ответ: ${body:0:400}" ;;
esac

if [[ "$http_code" == "200" ]]; then
  avail="$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' <<<"$body" | sed 's/.*"\([^"]*\)"$/\1/' | sort -u)"
  log "модели, доступные ключу:"
  while IFS= read -r m; do [[ -n "$m" ]] && log "  - $m"; done <<<"$avail"

  if grep -qx -- "$DEEPSEEK_MODEL" <<<"$avail"; then
    ok "модель '${DEEPSEEK_MODEL}' существует и доступна"
  else
    warn "модель '${DEEPSEEK_MODEL}' в списке ОТСУТСТВУЕТ."
    warn "Промпт требовал именно её, но API её не отдаёт — запросы будут падать."
    warn "Поправь DEEPSEEK_MODEL в config.env на одну из перечисленных выше и перезапусти."
    die  "остановлено до изменений на сервере"
  fi
fi

step "Ключ от контейнера"
require_key
log "ключ: ${KEY_PATH} (права $(stat -c '%a' "$KEY_PATH"))"
ssh-keygen -y -f "$KEY_PATH" >/dev/null 2>&1 || die "ключ нечитаем или повреждён"
ok "ключ валиден"

step "Вход в контейнер: admin@${SERVER_IP}:${SSH_PORT}"
who="$("${NODESSH[@]}" -o ConnectTimeout=20 -o BatchMode=yes whoami 2>&1)" \
  || die "не пускает в контейнер. Вывод: ${who}
   Проверь, что порт ${SSH_PORT} открыт и ключ соответствует контейнеру."
[[ "$who" == "admin" ]] || die "ожидался 'admin', получено '${who}'"
ok "вход работает, пользователь admin"

step "sudo внутри контейнера"
if "${NODESSH[@]}" -o BatchMode=yes 'sudo -n true' 2>/dev/null; then
  ok "sudo без пароля доступен"
else
  warn "sudo без пароля недоступен — шаги установки пакетов могут не пройти"
fi

if have_host; then
  step "Доступ на хост (HOST_ACCESS=yes)"
  if "${HOSTSSH[@]}" -o ConnectTimeout=15 -o BatchMode=yes true 2>/dev/null; then
    ok "${SERVER_SSH_USER}@${SERVER_IP} пускает по ключу"
  else
    warn "по ключу не пустило — скрипты будут спрашивать пароль на каждом вызове."
    read -r -p "   Продолжить? [y/N] " a
    [[ "$a" == [yY] ]] || die "остановлено"
  fi

  if "${HOSTSSH[@]}" 'command -v docker >/dev/null && docker info >/dev/null 2>&1'; then
    ok "docker на хосте отвечает"
  else
    warn "docker отсутствует или демон не запущен — 01-host-setup.sh это починит"
  fi

  if "${HOSTSSH[@]}" "docker image inspect '${IMAGE}' >/dev/null 2>&1"; then
    ok "образ ${IMAGE} на сервере есть"
  else
    warn "образа ${IMAGE} нет — 01-host-setup.sh соберёт запасной"
  fi
  printf '\n\033[32mПреflight пройден. Дальше: scripts/01-host-setup.sh\033[0m\n'
else
  log "HOST_ACCESS=no — шаги 01 и 02 не нужны, контейнер уже выдан готовым."
  printf '\n\033[32mПреflight пройден. Дальше: scripts/03-install-hermes.sh\033[0m\n'
fi
