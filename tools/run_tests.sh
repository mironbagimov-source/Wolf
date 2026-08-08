#!/usr/bin/env bash
# Полный прогон автотестов Wolf.
#
# Каждый тест — отдельный запуск игры без окна: харнесс в main.gd отыгрывает
# сценарий и печатает строку «TEST RESULT: …». Здесь только оркестровка и
# сводка. Тесты с параметрами (начинки, роли анимаций) прогоняются по всем
# значениям — иначе они проверяют лишь первое.
#
# Запуск:  tools/run_tests.sh [путь-к-godot]
set -u

GODOT="${1:-${WOLF_GODOT:-godot}}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)/godot"
LOG="${WOLF_TEST_LOG:-/tmp/wolf-tests}"
mkdir -p "$LOG"

# Без этой проверки забытый путь к Godot выглядел как ПОЛНЫЙ ПРОВАЛ ВСЕГО
# набора: каждый запуск падал мгновенно, строки результата не было, и сводка
# честно рапортовала «провалено 54 из 54». Час на поиск несуществующей
# регрессии — приятного мало.
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "Не найден Godot: '$GODOT'" >&2
	echo "Укажи путь аргументом или в WOLF_GODOT:" >&2
	echo "  tools/run_tests.sh /путь/к/Godot_v4.3-stable_linux.x86_64" >&2
	exit 2
fi

MODES=(menu look merc club rooms duel charged meet lift civwin agony bomb
       stairs bait loot implant dermal ghoul hub city mode demo hands
       respawn damage eaten civbomb slime revive interrogate grab loadout
       cast parry dash exec nostun corpse civsmart fit music)
# Начинки тел: у каждой свой эффект и своя сборка импланта.
DEVS=(bomb slime softener flare cryo emp singularity holo brood puppet)
# Клипы: те, что поставлены в Blender, и базовые из библиотеки.
CLIPS=(Idle Walk Feed Implant Activate)

pass=0; fail=0; failed=()

run() {
	local name="$1"; shift
	local out
	out="$(env "$@" timeout 600 xvfb-run -a "$GODOT" --path "$PROJ" \
		--rendering-driver opengl3 2>"$LOG/$name.err" | grep -E "TEST RESULT" | head -1)"
	if [ -z "$out" ]; then
		echo "  ПАДЕНИЕ  $name  (нет строки результата, см. $LOG/$name.err)"
		fail=$((fail+1)); failed+=("$name"); return
	fi
	echo "$out" > "$LOG/$name.out"
	if echo "$out" | grep -qiE "FAIL|ОШИБКА"; then
		echo "  ПРОВАЛ   $name :: $out"
		fail=$((fail+1)); failed+=("$name")
	else
		echo "  ок       $name :: ${out#TEST RESULT: }"
		pass=$((pass+1))
	fi
}

echo "=== Сценарии ==="
for m in "${MODES[@]}"; do run "$m" "WOLF_TEST=$m"; done

echo "=== Начинки тел ==="
for d in "${DEVS[@]}"; do run "civdev-$d" "WOLF_TEST=civdev" "WOLF_DEV=$d"; done

echo "=== Анимации ==="
for c in "${CLIPS[@]}"; do
	run "anim-$c-ghoul" "WOLF_TEST=anim" "WOLF_ANIM=$c" "WOLF_ANIM_ROLE=ghoul"
done

echo
echo "ИТОГО: прошло $pass, провалено $fail из $((pass+fail))"
if [ "$fail" -gt 0 ]; then
	echo "Провалились: ${failed[*]}"
	exit 1
fi
