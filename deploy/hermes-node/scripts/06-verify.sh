#!/usr/bin/env bash
# Шаг 6. Финальная проверка живым запросом. Со своей машины.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_key

step "Живой запрос: hermes -z \"Reply with exactly: OK\""
set +e
out="$("${NODESSH[@]}" bash -s <<REMOTE 2>&1
${HERMES_ENV}
set -a; source /home/admin/.hermes/.env; set +a
hermes -z "Reply with exactly: OK"
REMOTE
)"
rc=$?
set -e

echo "--- ответ ассистента ---"
printf '%s\n' "$out"
echo "------------------------"

# Классификация по фактическому ответу. Ничего не додумываем.
if grep -qiE '(^|[^A-Za-z])OK([^A-Za-z]|$)' <<<"$out" && (( rc == 0 )); then
  printf '\n\033[32m✅ Ассистент отвечает. Установка завершена.\033[0m\n'
  exit 0
fi

if grep -qiE 'HTTP 402|Insufficient Balance' <<<"$out"; then
  printf '\n\033[33m⚠ HTTP 402 Insufficient Balance\033[0m\n'
  echo "   Конфиг и ключ корректны — на аккаунте DeepSeek нет средств."
  echo "   Пополни: https://platform.deepseek.com/top_up  и запусти 06-verify.sh снова."
  exit 2
fi

if grep -qiE 'HTTP 403|Access denied by security policy' <<<"$out"; then
  printf '\n\033[31m✗ HTTP 403 Access denied\033[0m\n'
  echo "   Почти наверняка слетел model.base_url и запрос ушёл в OpenRouter."
  echo "   Чиню и показываю текущее значение:"
  "${NODESSH[@]}" bash -s <<REMOTE
${HERMES_ENV}
hermes config set model.base_url "${DEEPSEEK_BASE_URL}"
echo "   model.base_url = \$(hermes config get model.base_url 2>&1)"
REMOTE
  echo "   Запусти 06-verify.sh ещё раз."
  exit 3
fi

if grep -qiE 'Permission denied' <<<"$out"; then
  printf '\n\033[31m✗ Permission denied\033[0m\n'
  echo "   Права на ~/.hermes. Чиню:"
  "${NODESSH[@]}" "sudo chown -R admin:admin /home/admin/.hermes && chmod 600 /home/admin/.hermes/.env && echo '   готово'"
  echo "   Запусти 06-verify.sh ещё раз."
  exit 4
fi

if grep -qiE 'model.*(not found|does not exist|invalid)' <<<"$out"; then
  printf '\n\033[31m✗ Модель не принята провайдером\033[0m\n'
  echo "   DEEPSEEK_MODEL='${DEEPSEEK_MODEL}' не существует у DeepSeek."
  echo "   Посмотри реальный список: scripts/00-preflight.sh — и поправь config.env."
  exit 5
fi

printf '\n\033[31m✗ Непредвиденный ответ (код выхода %s). Разбирай по выводу выше.\033[0m\n' "$rc"
exit 1
