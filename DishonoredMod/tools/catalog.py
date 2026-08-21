"""Запросы к каталогу ключей, снятому harvest.py.

Каталог реальной игры велик, и пересылать его целиком незачем: для работы над
режимом нужны не все несколько тысяч ключей, а десяток относящихся к делу.
Инструмент позволяет спросить каталог о конкретном и получить компактный ответ,
который удобно скопировать в переписку.

    python tools/catalog.py stats                 сводка по файлам
    python tools/catalog.py sections Player.ini   секции файла
    python tools/catalog.py find mana             поиск по именам
    python tools/catalog.py find "regen|detect"   регулярное выражение
    python tools/catalog.py show Player.ini DishonoredGame.DisPlayerPawn

Поиск идёт по именам секций и ключей. Значения показываются рядом, потому что
без них непонятны единицы измерения; ключ --names их скрывает.

Только стандартная библиотека.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "game-data" / "config-catalog.json"
DEFAULT_CATALOG_PATH = REPO_ROOT / "game-data" / "config-default-catalog.json"


def load_catalog(defaults: bool = False) -> dict:
    path = DEFAULT_CATALOG_PATH if defaults else CATALOG_PATH
    if not path.is_file():
        if defaults:
            raise SystemExit(
                "Каталога шаблонов нет. Либо harvest ещё не запускался, либо в\n"
                "папке установки игры не нашлось Default*.ini."
            )
        raise SystemExit(
            "Каталога нет — сначала собери данные с машины с игрой:\n"
            "    python tools/harvest.py"
        )
    return json.loads(path.read_text(encoding="utf-8"))


def format_values(values: list[str], show_values: bool) -> str:
    if not show_values:
        return ""
    if len(values) == 1:
        return f" = {values[0]}"
    # Повторяющийся ключ — элемент массива. Показываем первые, чтобы было видно
    # форму значения, но не вываливаем длинные списки целиком.
    head = ", ".join(values[:3])
    tail = f", ... всего {len(values)}" if len(values) > 3 else ""
    return f" = [{head}{tail}]"


def command_stats(catalog: dict) -> None:
    total_sections = 0
    total_keys = 0
    print(f"{'файл':<28} {'секций':>7} {'ключей':>8}")
    print("-" * 45)
    for file_name in sorted(catalog):
        sections = catalog[file_name]
        key_count = sum(len(keys) for keys in sections.values())
        total_sections += len(sections)
        total_keys += key_count
        print(f"{file_name:<28} {len(sections):>7} {key_count:>8}")
    print("-" * 45)
    print(f"{'итого':<28} {total_sections:>7} {total_keys:>8}")


def command_sections(catalog: dict, file_name: str, limit: int) -> None:
    if file_name not in catalog:
        available = ", ".join(sorted(catalog))
        raise SystemExit(f"Файла '{file_name}' нет в каталоге.\nЕсть: {available}")

    sections = catalog[file_name]
    print(f"{file_name}: секций {len(sections)}\n")
    for index, section in enumerate(sorted(sections)):
        if index >= limit:
            print(f"  ... ещё {len(sections) - limit}, показать больше: --limit")
            break
        print(f"  [{section}]  ключей {len(sections[section])}")


def command_show(catalog: dict, file_name: str, section: str, show_values: bool) -> None:
    if file_name not in catalog:
        raise SystemExit(f"Файла '{file_name}' нет в каталоге.")
    if section not in catalog[file_name]:
        raise SystemExit(f"Секции [{section}] нет в {file_name}.")

    keys = catalog[file_name][section]
    print(f"{file_name} [{section}]  ключей {len(keys)}\n")
    for key in sorted(keys):
        print(f"  {key}{format_values(keys[key], show_values)}")


def command_find(catalog: dict, pattern: str, show_values: bool, limit: int) -> int:
    try:
        regex = re.compile(pattern, re.IGNORECASE)
    except re.error as error:
        raise SystemExit(f"Неверное регулярное выражение: {error}")

    matches: list[str] = []
    for file_name in sorted(catalog):
        for section in sorted(catalog[file_name]):
            keys = catalog[file_name][section]
            section_matches = regex.search(section) is not None
            for key in sorted(keys):
                # Секция считается совпавшей целиком: если искали по имени
                # класса, нужны все его ключи, а не только те, что повторяют
                # запрос в собственном имени.
                if section_matches or regex.search(key):
                    matches.append(
                        f"  {file_name} [{section}] {key}"
                        f"{format_values(keys[key], show_values)}")

    if not matches:
        print(f"По запросу '{pattern}' ничего не нашлось.")
        return 1

    print(f"Совпадений: {len(matches)}\n")
    for line in matches[:limit]:
        print(line)
    if len(matches) > limit:
        print(f"\n  ... ещё {len(matches) - limit}, показать больше: --limit")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Запросы к каталогу ключей конфигов Dishonored.")
    parser.add_argument("--names", action="store_true",
                        help="показывать только имена, без значений")
    parser.add_argument("--defaults", action="store_true",
                        help="искать в шаблонах Default*.ini из папки игры, "
                             "а не в пользовательских конфигах")
    parser.add_argument("--limit", type=int, default=60,
                        help="максимум строк в выводе (по умолчанию 60)")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("stats", help="сводка по файлам")

    sections_command = sub.add_parser("sections", help="секции файла")
    sections_command.add_argument("file")

    show_command = sub.add_parser("show", help="ключи одной секции")
    show_command.add_argument("file")
    show_command.add_argument("section")

    find_command = sub.add_parser("find", help="поиск по именам секций и ключей")
    find_command.add_argument("pattern")

    args = parser.parse_args()
    catalog = load_catalog(args.defaults)
    show_values = not args.names

    if args.command == "stats":
        command_stats(catalog)
    elif args.command == "sections":
        command_sections(catalog, args.file, args.limit)
    elif args.command == "show":
        command_show(catalog, args.file, args.section, show_values)
    elif args.command == "find":
        return command_find(catalog, args.pattern, show_values, args.limit)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
