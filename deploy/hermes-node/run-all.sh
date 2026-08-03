#!/usr/bin/env bash
# Прогон по порядку. Останавливается на первой же ошибке.
# Шаг 7 (набор для учёбы) — отдельно и осознанно: scripts/07-study-kit.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$HERE/config.env" ]] || {
  echo "!! Нет config.env. Сделай: cp config.env.example config.env  и заполни." >&2
  exit 1
}

# Весь вывод дублируется в лог, чтобы его можно было отдать целиком, не
# собирая по кускам из терминала. Ключи вырезаются на лету: лог безопасно
# показывать и пересылать.
mkdir -p "$HERE/logs"
LOG="$HERE/logs/run-$(date +%Y%m%d-%H%M%S).log"
exec > >(sed -uE 's/sk-[A-Za-z0-9_-]{12,}/sk-***REDACTED***/g' | tee "$LOG") 2>&1
echo "Лог пишется в: $LOG"

# HOST_ACCESS=no — контейнер выдан готовым, создавать его и раскладывать
# ключ не нужно: шаги 01 и 02 пропускаются.
HOST_ACCESS="$(sed -n 's/^[[:space:]]*HOST_ACCESS=//p' "$HERE/config.env" | tail -1)"
HOST_ACCESS="${HOST_ACCESS:-no}"

if [[ "$HOST_ACCESS" == "yes" ]]; then
  STEPS=(00-preflight 01-host-setup 02-ssh-access 03-install-hermes
         04-configure-deepseek 05-gateway 06-verify)
else
  echo "HOST_ACCESS=no — контейнер уже готов, шаги 01 и 02 пропускаю."
  STEPS=(00-preflight 03-install-hermes 04-configure-deepseek 05-gateway 06-verify)
fi

for s in "${STEPS[@]}"; do
  printf '\n\033[1;44m  %s  \033[0m\n' "$s"
  # rc берём отдельной строкой: внутри `if ! cmd` переменная $? содержит
  # статус отрицания, а не самой команды, и код сбоя терялся бы.
  rc=0
  bash "$HERE/scripts/${s}.sh" || rc=$?
  if (( rc != 0 )); then
    printf '\n\033[31m!! Прервано на %s (код %s). Дальше не иду.\033[0m\n' "$s" "$rc" >&2
    printf 'Лог целиком: %s\n' "$LOG" >&2
    exit "$rc"
  fi
done

printf '\n\033[1;32mВсе шаги пройдены.\033[0m\n'
