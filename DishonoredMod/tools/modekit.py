"""Сборка, установка и откат игровых режимов, собранных на INI-слое.

Режим здесь — это данные, а не код: JSON-файл в ``modes/`` со списком правок
конфигов. Инструмент проверяет правки против реального каталога ключей,
собранного ``harvest.py``, накладывает их на эталонные конфиги и ставит
результат в игру, предварительно сохранив то, что там было.

    python tools/modekit.py list
    python tools/modekit.py validate iron-ghost
    python tools/modekit.py build iron-ghost
    python tools/modekit.py apply iron-ghost
    python tools/modekit.py status
    python tools/modekit.py restore

Главное правило: ни одна правка не уезжает в игру, пока её ключ не найден в
каталоге. Придуманное имя секции или ключа игра проглотит молча — просто
проигнорирует строку, и режим будет «работать», ничего не меняя. Такую тишину
ловить потом дороже всего, поэтому проверка жёсткая по умолчанию.

Только стандартная библиотека.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harvest import find_config_dir  # noqa: E402
from ue3ini import IniFile  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
MODES_DIR = REPO_ROOT / "modes"
GAME_DATA = REPO_ROOT / "game-data"
ORIGINAL_CONFIG = GAME_DATA / "config"
CATALOG_PATH = GAME_DATA / "config-catalog.json"
DIST_DIR = REPO_ROOT / "dist"
BACKUP_DIR = REPO_ROOT / "backups"
STATE_PATH = REPO_ROOT / "dist" / "state.json"


class ModeError(Exception):
    """Ошибка, которую имеет смысл показать пользователю без трассировки."""


# --- загрузка -------------------------------------------------------------

def load_mode(mode_id: str) -> dict:
    path = MODES_DIR / f"{mode_id}.json"
    if not path.is_file():
        available = ", ".join(sorted(p.stem for p in MODES_DIR.glob("*.json")
                                     if not p.stem.startswith("_"))) or "пока ни одного"
        raise ModeError(f"Режим '{mode_id}' не найден.\nЕсть: {available}")

    mode = json.loads(path.read_text(encoding="utf-8"))
    for required in ("id", "name", "overrides"):
        if required not in mode:
            raise ModeError(f"{path.name}: нет обязательного поля '{required}'")
    if mode["id"] != mode_id:
        raise ModeError(f"{path.name}: поле id = '{mode['id']}', а файл называется '{mode_id}'")
    return mode


def load_catalog() -> dict:
    if not CATALOG_PATH.is_file():
        raise ModeError(
            "Нет каталога ключей — сначала собери данные с машины с игрой:\n"
            "    python tools/harvest.py"
        )
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


# --- проверка -------------------------------------------------------------

def validate(mode: dict, catalog: dict, allow_unverified: bool) -> list[str]:
    """Возвращает список проблем. Пустой список — режим готов к сборке."""
    problems: list[str] = []

    for index, override in enumerate(mode["overrides"]):
        label = f"правка #{index + 1}"
        missing_field = next((f for f in ("file", "section", "key", "value")
                              if f not in override), None)
        if missing_field:
            problems.append(f"{label}: нет поля '{missing_field}'")
            continue

        file_name = override["file"]
        section = override["section"]
        key = override["key"]
        label = f"{file_name} [{section}] {key}"

        if file_name not in catalog:
            problems.append(f"{label}: такого файла нет в собранных конфигах")
            continue

        sections = catalog[file_name]
        if section not in sections:
            problems.append(f"{label}: секции [{section}] нет в {file_name}")
            continue

        if key not in sections[section]:
            if override.get("unverified") and allow_unverified:
                continue
            hint = ""
            if override.get("unverified"):
                hint = " (помечена unverified — можно продавить флагом --allow-unverified)"
            problems.append(f"{label}: ключа нет в секции{hint}")

    return problems


# --- сборка ---------------------------------------------------------------

def build(mode: dict, allow_unverified: bool) -> Path:
    if not ORIGINAL_CONFIG.is_dir():
        raise ModeError(
            "Нет эталонных конфигов — сначала собери данные с машины с игрой:\n"
            "    python tools/harvest.py"
        )

    problems = validate(mode, load_catalog(), allow_unverified)
    if problems:
        raise ModeError("Режим не проходит проверку:\n  " + "\n  ".join(problems))

    out_dir = DIST_DIR / mode["id"] / "Config"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)

    touched: dict[str, IniFile] = {}
    changes: list[str] = []

    for override in mode["overrides"]:
        file_name = override["file"]
        if file_name not in touched:
            touched[file_name] = IniFile.load(ORIGINAL_CONFIG / file_name)

        ini = touched[file_name]
        before = ini.get(override["section"], override["key"])
        outcome = ini.set_value(override["section"], override["key"], str(override["value"]))
        changes.append(
            f"{file_name} [{override['section']}] {override['key']}: "
            f"{before if before is not None else '—'} -> {override['value']} ({outcome})"
        )

    # Кладём в сборку все конфиги, а не только изменённые: игре нужен
    # целостный набор, а нам — возможность поставить папку одним движением.
    for source in sorted(ORIGINAL_CONFIG.glob("*.ini")):
        if source.name in touched:
            touched[source.name].save(out_dir / source.name)
        else:
            shutil.copy2(source, out_dir / source.name)

    manifest = {
        "mode": mode["id"],
        "name": mode["name"],
        "built_at": datetime.now().isoformat(timespec="seconds"),
        "changes": changes,
    }
    (DIST_DIR / mode["id"] / "build.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"Собран режим '{mode['name']}' — {len(changes)} правок в {len(touched)} файлах:")
    for change in changes:
        print(f"  {change}")
    print(f"\n{out_dir}")
    return out_dir


# --- установка ------------------------------------------------------------

def apply(mode: dict, config_dir: Path, allow_unverified: bool) -> None:
    built = build(mode, allow_unverified)

    backup = _backup(config_dir)
    print(f"\nБэкап текущих конфигов: {backup}")

    for source in sorted(built.glob("*.ini")):
        destination = config_dir / source.name
        _clear_readonly(destination)
        shutil.copy2(source, destination)
        _set_readonly(destination)

    _write_state({
        "mode": mode["id"],
        "name": mode["name"],
        "applied_at": datetime.now().isoformat(timespec="seconds"),
        "backup": backup.name,
        "config_dir": str(config_dir),
    })

    print(f"Режим '{mode['name']}' установлен в {config_dir}")
    print("Файлы помечены «только чтение» — иначе игра перезапишет их при запуске.")
    print("Откат: python tools/modekit.py restore")


def restore(name: str | None) -> None:
    state = _read_state()
    if not BACKUP_DIR.is_dir() or not any(BACKUP_DIR.iterdir()):
        raise ModeError("Бэкапов нет — восстанавливать нечего.")

    if name:
        backup = BACKUP_DIR / name
        if not backup.is_dir():
            raise ModeError(f"Бэкап '{name}' не найден.")
    else:
        backup = max((p for p in BACKUP_DIR.iterdir() if p.is_dir()),
                     key=lambda p: p.name)

    config_dir = Path(state["config_dir"]) if state.get("config_dir") else find_config_dir(None)

    for source in sorted(backup.glob("*.ini")):
        destination = config_dir / source.name
        _clear_readonly(destination)
        shutil.copy2(source, destination)
        _clear_readonly(destination)

    _write_state({})
    print(f"Восстановлено из {backup.name} в {config_dir}")
    print("Атрибут «только чтение» снят — игра снова управляет конфигами сама.")


def status() -> None:
    state = _read_state()
    if not state.get("mode"):
        print("Ни один режим не установлен.")
    else:
        print(f"Установлен: {state['name']} ({state['mode']})")
        print(f"  когда:  {state.get('applied_at', '?')}")
        print(f"  куда:   {state.get('config_dir', '?')}")
        print(f"  бэкап:  {state.get('backup', '?')}")

    backups = sorted((p.name for p in BACKUP_DIR.iterdir() if p.is_dir()), reverse=True) \
        if BACKUP_DIR.is_dir() else []
    print(f"\nБэкапов: {len(backups)}")
    for item in backups[:5]:
        print(f"  {item}")


def _backup(config_dir: Path) -> Path:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    target = BACKUP_DIR / stamp
    target.mkdir(parents=True, exist_ok=True)
    for source in sorted(config_dir.glob("*.ini")):
        destination = target / source.name
        shutil.copy2(source, destination)
        _clear_readonly(destination)
    return target


def _set_readonly(path: Path) -> None:
    if path.exists():
        path.chmod(stat.S_IREAD | stat.S_IRGRP | stat.S_IROTH)


def _clear_readonly(path: Path) -> None:
    if path.exists():
        path.chmod(path.stat().st_mode | stat.S_IWRITE)


def _read_state() -> dict:
    if not STATE_PATH.is_file():
        return {}
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def _write_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2, ensure_ascii=False), encoding="utf-8")


# --- список ---------------------------------------------------------------

def list_modes() -> None:
    paths = sorted(p for p in MODES_DIR.glob("*.json") if not p.stem.startswith("_"))
    if not paths:
        print("В modes/ пока пусто.")
        return

    catalog = None
    try:
        catalog = load_catalog()
    except ModeError:
        pass

    print(f"Режимов: {len(paths)}\n")
    for path in paths:
        mode = json.loads(path.read_text(encoding="utf-8"))
        print(f"  {mode['id']:<16} {mode['name']}")
        if mode.get("description"):
            print(f"  {'':<16} {mode['description']}")
        count = len(mode.get("overrides", []))
        if catalog is None:
            state = f"{count} правок, проверить нельзя — нет каталога"
        else:
            problems = validate(mode, catalog, allow_unverified=False)
            state = f"{count} правок, проверку проходит" if not problems \
                else f"{count} правок, проблем: {len(problems)}"
        print(f"  {'':<16} {state}\n")


# --- точка входа ----------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Режимы Dishonored на INI-слое.")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="показать доступные режимы")
    sub.add_parser("status", help="что сейчас установлено")

    for name, help_text in (("validate", "проверить режим против каталога ключей"),
                            ("build", "собрать конфиги режима в dist/"),
                            ("apply", "собрать и установить режим в игру")):
        command = sub.add_parser(name, help=help_text)
        command.add_argument("mode")
        command.add_argument("--allow-unverified", action="store_true",
                             help="разрешить правки, помеченные unverified")
        if name == "apply":
            command.add_argument("--config-dir", help="папка конфигов игры")

    restore_command = sub.add_parser("restore", help="вернуть конфиги из бэкапа")
    restore_command.add_argument("backup", nargs="?", help="имя бэкапа, по умолчанию последний")

    args = parser.parse_args()

    try:
        if args.command == "list":
            list_modes()
        elif args.command == "status":
            status()
        elif args.command == "restore":
            restore(args.backup)
        elif args.command == "validate":
            problems = validate(load_mode(args.mode), load_catalog(), args.allow_unverified)
            if problems:
                print(f"Проблем: {len(problems)}")
                for problem in problems:
                    print(f"  {problem}")
                return 1
            print("Проверку проходит.")
        elif args.command == "build":
            build(load_mode(args.mode), args.allow_unverified)
        elif args.command == "apply":
            apply(load_mode(args.mode), find_config_dir(args.config_dir), args.allow_unverified)
    except ModeError as error:
        print(f"\n{error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
