#!/usr/bin/env bash
# Шаг 4. Ключ, права, конфиг модели, плагин провайдера. Со своей машины.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_key

[[ -n "${DEEPSEEK_API_KEY:-}" ]] || die "DEEPSEEK_API_KEY пуст в config.env"

step "Ключ в /home/admin/.hermes/.env"
# Строка должна быть ровно одна и без пробела после '=' — 'export X= sk-...'
# оставит переменную пустой. Старые вхождения вычищаем, чтобы не было дублей.
"${NODESSH[@]}" bash -s -- "$DEEPSEEK_API_KEY" <<'REMOTE'
set -euo pipefail
KEY="$1"
mkdir -p /home/admin/.hermes
touch /home/admin/.hermes/.env
sed -i '/DEEPSEEK_API_KEY/d' /home/admin/.hermes/.env
printf 'export DEEPSEEK_API_KEY=%s\n' "$KEY" >> /home/admin/.hermes/.env
n=$(grep -c 'DEEPSEEK_API_KEY' /home/admin/.hermes/.env)
echo "   строк с DEEPSEEK_API_KEY: $n"
[ "$n" -eq 1 ] || { echo "!! ожидалась ровно одна" >&2; exit 1; }
REMOTE
ok "ключ записан одной строкой"

step "Владелец и права ~/.hermes"
# Иначе hermes ловит Permission denied при чтении .env и config.yaml.
"${NODESSH[@]}" bash -s <<'REMOTE'
set -euo pipefail
sudo chown -R admin:admin /home/admin/.hermes
chmod 600 /home/admin/.hermes/.env
echo "   .env  -> $(stat -c '%U:%G %a' /home/admin/.hermes/.env)"
echo "   .hermes -> $(stat -c '%U:%G %a' /home/admin/.hermes)"
REMOTE
ok "права выставлены"

step "Конфиг модели"
"${NODESSH[@]}" bash -s -- "$DEEPSEEK_MODEL" "$DEEPSEEK_BASE_URL" <<REMOTE
set -euo pipefail
${HERMES_ENV}
MODEL="\$1"; BASE_URL="\$2"
hermes config set model.default "\$MODEL"
hermes config set model.provider deepseek
# base_url — критично. Без него hermes уходит в OpenRouter (дефолт), а тот
# режет серверные IP: HTTP 403 {"error":"Access denied by security policy."}
hermes config set model.base_url "\$BASE_URL"
hermes config set agent.reasoning_effort low
echo "   записано"
REMOTE
ok "модель настроена"

step "Сверка записанного конфига"
"${NODESSH[@]}" bash -s <<REMOTE || warn "конфиг прочитать не удалось — проверь вручную"
${HERMES_ENV}
for k in model.default model.provider model.base_url agent.reasoning_effort; do
  printf '   %-24s = %s\n' "\$k" "\$(hermes config get "\$k" 2>&1 || echo '<не прочитан>')"
done
REMOTE

step "Плагин deepseek-provider"
# Провайдер встроен, но по умолчанию выключен.
"${NODESSH[@]}" bash -s <<REMOTE
set -euo pipefail
${HERMES_ENV}
hermes plugins enable deepseek-provider
REMOTE
ok "плагин включён"

step "hermes doctor"
"${NODESSH[@]}" bash -s <<REMOTE || warn "doctor вернул ненулевой код — смотри вывод"
${HERMES_ENV}
hermes doctor 2>&1 | sed 's/^/   /'
REMOTE

printf '\n\033[32mШаг 4 готов. Дальше: scripts/05-gateway.sh\033[0m\n'
