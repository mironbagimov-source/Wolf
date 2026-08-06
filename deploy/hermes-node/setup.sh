#!/usr/bin/env bash
# Один вход вместо шести команд: ключ, конфиг, установка, веб-интерфейс.
# Запускать из распакованной папки: ./setup.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

c(){ printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
ok(){ printf '   \033[32mOK\033[0m  %s\n' "$*"; }
no(){ printf '\n\033[31m!! %s\033[0m\n' "$*" >&2; exit 1; }

[[ -f scripts/lib.sh && -f run-all.sh ]] || no "запускай из папки hermes-node (там, где лежит run-all.sh)"

c "Ключ от контейнера"
NODE_NUM="$(sed -n 's/^[[:space:]]*NODE_NUM=//p' config.env.example | tail -1)"
NODE_NUM="${NODE_NUM:-18}"
KEY="$HOME/.ssh/yc-nodes/yc_node${NODE_NUM}"
if [[ -f "$KEY" ]]; then
  ok "уже на месте: $KEY"
else
  # Ищем рядом: люди обычно кладут ключ туда же, куда распаковали архив.
  found=""
  for p in "./yc_node${NODE_NUM}" "../yc_node${NODE_NUM}" "$HOME/Downloads/yc_node${NODE_NUM}" \
           "$HOME/Загрузки/yc_node${NODE_NUM}" "$HOME/Desktop/yc_node${NODE_NUM}"; do
    [[ -f "$p" ]] && { found="$p"; break; }
  done
  [[ -n "$found" ]] || no "не нашёл файл yc_node${NODE_NUM}.
   Положи его рядом с этим скриптом и запусти снова, либо скопируй вручную:
     mkdir -p ~/.ssh/yc-nodes && cp yc_node${NODE_NUM} ~/.ssh/yc-nodes/"
  mkdir -p "$(dirname "$KEY")"; chmod 700 "$(dirname "$KEY")"
  cp "$found" "$KEY"; chmod 600 "$KEY"
  ok "скопирован из $found"
fi
ssh-keygen -y -f "$KEY" >/dev/null 2>&1 || no "ключ $KEY повреждён или защищён паролем"

c "Конфигурация"
[[ -f config.env ]] || { cp config.env.example config.env; ok "создан config.env"; }
key_now="$(sed -n 's/^[[:space:]]*DEEPSEEK_API_KEY=//p' config.env | tail -1)"
if [[ -z "$key_now" ]]; then
  echo "   Нужен ключ DeepSeek (https://platform.deepseek.com/api_keys)."
  echo "   Ввод не отображается — это нормально, просто вставь и нажми Enter."
  printf '   Ключ: '
  read -rs dskey; echo
  dskey="${dskey#"${dskey%%[![:space:]]*}"}"   # обрезаем пробелы по краям:
  dskey="${dskey%"${dskey##*[![:space:]]}"}"   # из буфера они прилетают часто
  [[ -n "$dskey" ]] || no "ключ не введён"
  [[ "$dskey" == sk-* ]] || no "ключ должен начинаться с 'sk-', получено '${dskey:0:6}...'"
  [[ "$dskey" != *[[:space:]]* ]] || no "внутри ключа пробел — скопировался лишний текст"
  # Через python, а не sed: в ключе могут быть символы, которые sed съест.
  KEYVAL="$dskey" python3 - <<'PY'
import os, re
path = "config.env"
val = os.environ["KEYVAL"]
with open(path, encoding="utf-8") as fh:
    text = fh.read()
text = re.sub(r"(?m)^[ \t]*DEEPSEEK_API_KEY=.*$", "DEEPSEEK_API_KEY=" + val, text)
with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY
  ok "ключ записан в config.env"
else
  ok "ключ DeepSeek уже вписан"
fi

c "Установка"
echo "   Это самая долгая часть, 5-15 минут. Прогон пишется в logs/."
./run-all.sh

c "Веб-интерфейс"
scripts/08-web-ui.sh
