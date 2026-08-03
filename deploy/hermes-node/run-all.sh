#!/usr/bin/env bash
# Прогон по порядку. Останавливается на первой же ошибке.
# Шаг 7 (набор для учёбы) — отдельно и осознанно: scripts/07-study-kit.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$HERE/config.env" ]] || {
  echo "!! Нет config.env. Сделай: cp config.env.example config.env  и заполни." >&2
  exit 1
}

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
  if ! bash "$HERE/scripts/${s}.sh"; then
    rc=$?
    printf '\n\033[31m!! Прервано на %s (код %s). Дальше не иду.\033[0m\n' "$s" "$rc" >&2
    exit "$rc"
  fi
done

printf '\n\033[1;32mВсе шаги пройдены.\033[0m\n'
