#!/usr/bin/env bash
# Общие переменные и хелперы. Подключается всеми шагами, отдельно не запускается.
# SC2034: переменные ниже читают скрипты, которые сорсят этот файл.
# shellcheck disable=SC2034
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -f "$ROOT/config.env" ]]; then
  echo "!! Нет $ROOT/config.env — скопируй config.env.example и заполни." >&2
  exit 1
fi
# Разбор config.env ДО source. Строка вида 'KEY= значение' или 'KEY=abc def'
# роняет source с невнятным 'def: command not found', и понять причину
# по такому сообщению невозможно. Именно так была испорчена строка с ключом
# в исходной инструкции.
_bad="$(grep -nE '^[A-Za-z_][A-Za-z0-9_]*=[^"'"'"'[:space:]]*[[:space:]]+[^[:space:]]' "$ROOT/config.env" || true)"
if [[ -n "$_bad" ]]; then
  echo "!! В config.env значение с незакавыченным пробелом:" >&2
  printf '   %s\n' "$_bad" >&2
  echo "   Пиши KEY=значение без пробела после '=' (или возьми значение в кавычки)." >&2
  echo "   'KEY= sk-...' оставит переменную ПУСТОЙ — это самая частая ошибка здесь." >&2
  exit 1
fi

set -a; source "$ROOT/config.env"; set +a

: "${SERVER_IP:?SERVER_IP не задан в config.env}"
: "${NODE_NUM:?NODE_NUM не задан в config.env}"

if ! [[ "$NODE_NUM" =~ ^[0-9]+$ ]] || (( NODE_NUM < 1 || NODE_NUM > 30 )); then
  echo "!! NODE_NUM должен быть числом 1..30, получено: '$NODE_NUM'" >&2
  exit 1
fi

SERVER_SSH_USER="${SERVER_SSH_USER:-root}"
CONTAINER="${CONTAINER_NAME:-node${NODE_NUM}}"
IMAGE="${IMAGE:-vps-node:latest}"
SSH_PORT="22$(printf '%02d' "$NODE_NUM")"

HOST_ALIAS="yc-node${NODE_NUM}"
SRV_DIR="/srv/node${NODE_NUM}"

# Путь к ключу настраивается: контейнер обычно выдают уже готовым вместе с ним.
KEY_PATH="${SSH_KEY:-$HOME/.ssh/yc-nodes/yc_node${NODE_NUM}}"
KEY_PATH="${KEY_PATH/#\~/$HOME}"

# HOST_ACCESS=no — доступ только внутрь контейнера (обычный случай, когда
# контейнер выдали готовым). Тогда шаги 01/02 пропускаются, а gateway
# поднимается изнутри, без entrypoint на хосте.
HOST_ACCESS="${HOST_ACCESS:-no}"
have_host() { [[ "$HOST_ACCESS" == "yes" ]]; }

DEEPSEEK_MODEL="${DEEPSEEK_MODEL:-deepseek-chat}"
DEEPSEEK_BASE_URL="${DEEPSEEK_BASE_URL:-https://api.deepseek.com/v1}"

# Хост — по паролю/ключу пользователя; контейнер — только по выданному ключу.
HOSTSSH=("ssh" "-o" "StrictHostKeyChecking=accept-new" "${SERVER_SSH_USER}@${SERVER_IP}")
NODESSH=("ssh" "-o" "StrictHostKeyChecking=accept-new" "-i" "$KEY_PATH"
         "-p" "$SSH_PORT" "admin@${SERVER_IP}")

require_key() {
  [[ -f "$KEY_PATH" ]] || {
    echo "!! Нет ключа $KEY_PATH — положи файл yc_node${NODE_NUM} по этому пути" >&2
    echo "   или укажи свой путь в SSH_KEY внутри config.env." >&2
    exit 1
  }
  local perm; perm="$(stat -c '%a' "$KEY_PATH" 2>/dev/null || stat -f '%Lp' "$KEY_PATH")"
  if [[ "$perm" != "600" && "$perm" != "400" ]]; then
    chmod 600 "$KEY_PATH" 2>/dev/null || true
  fi
}

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
log()  { printf '   %s\n' "$*"; }
ok()   { printf '   \033[32mOK\033[0m  %s\n' "$*"; }
warn() { printf '   \033[33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\n\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# PATH внутри контейнера — hermes ставится в ~/.local/bin, его нет в дефолтном PATH.
# SC2016: одинарные кавычки намеренно — $PATH обязан раскрыться на удалённой
# стороне, а не здесь, иначе в контейнер уедет PATH этой машины.
# shellcheck disable=SC2016
HERMES_ENV='export PATH=/home/admin/.local/bin:/home/admin/.hermes/node/bin:$PATH; export HERMES_HOME=/home/admin/.hermes;'
