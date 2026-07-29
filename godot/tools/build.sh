#!/usr/bin/env bash
# Собирает готовый к запуску билд: build/windows/Считалка.exe и
# build/linux/Считалка.x86_64. Один файл, внутри всё — движок, код, модели,
# скины. Скачал, запустил, играешь.
#
#     godot/tools/build.sh            # обе платформы
#     godot/tools/build.sh Windows    # только одна
#
# Нужны шаблоны экспорта того же выпуска, что и сам Godot:
# https://godotengine.org/download — «Export templates», кладутся в
# ~/.local/share/godot/export_templates/<версия>/
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
targets=("${@:-Windows Linux}")
read -ra targets <<< "${targets[*]}"

cd "$root"
mkdir -p build/windows build/linux

# Классы с `class_name` регистрируются при импорте, а не при экспорте: без этого
# первый экспорт на чистом клоне падает на «Identifier not found».
godot --headless --path godot --import >/dev/null

for target in "${targets[@]}"; do
	echo "== $target"
	godot --headless --path godot --export-release "$target"
done

ls -la build/*/
