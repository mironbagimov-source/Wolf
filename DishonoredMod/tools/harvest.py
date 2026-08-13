"""Снимает с установленной игры всё, что нужно для работы над модом.

Запускается один раз на машине, где стоит Dishonored, и складывает результат
в ``game-data/``. До этого шага любая правка конфигов — гадание: имена ключей
у Arkane свои, и придумывать их из головы бессмысленно.

    python tools/harvest.py
    python tools/harvest.py --game-dir "D:\\Steam\\steamapps\\common\\Dishonored"
    python tools/harvest.py --hash-upk          # ещё и sha256 пакетов, медленно

Собирается:

* копии всех ini из папки Config — эталон, от которого считаются правки;
* ``config-catalog.json`` — плоский каталог секций и ключей, по нему
  ``modekit.py`` проверяет, что режим не ссылается на несуществующую ручку;
* ``manifest.json`` — список пакетов ``.upk`` с размерами и данные экзешника
  (разрядность, дата сборки, sha256), чтобы привязать сигнатуры нативного
  слоя к конкретному билду.

Только стандартная библиотека.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ue3ini import IniFile  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
GAME_DATA = REPO_ROOT / "game-data"

CONTENT_SUBPATH = Path("DishonoredGame") / "CookedPCConsole"
CONFIG_SUBPATH = Path("My Games") / "Dishonored" / "DishonoredGame" / "Config"
EXE_SUBPATH = Path("Binaries") / "Win32" / "Dishonored.exe"

PE_MACHINE = {0x014C: "x86", 0x8664: "x64", 0x01C0: "arm", 0xAA64: "arm64"}


# --- поиск игры -----------------------------------------------------------

def find_game_dir(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_dir():
            raise SystemExit(f"Папка не найдена: {path}")
        return path

    for candidate in _steam_candidates():
        if (candidate / CONTENT_SUBPATH).is_dir():
            return candidate

    raise SystemExit(
        "Не нашёл установленную игру автоматически.\n"
        "Укажи путь явно: --game-dir \"...\\steamapps\\common\\Dishonored\""
    )


def _steam_candidates() -> list[Path]:
    """Пути, где может лежать Dishonored: библиотеки Steam плюс типовые места."""
    candidates: list[Path] = []

    for library in _steam_libraries():
        candidates.append(library / "steamapps" / "common" / "Dishonored")

    for drive in "CDEFG":
        for suffix in (
            r"Program Files (x86)\Steam\steamapps\common\Dishonored",
            r"Program Files\Steam\steamapps\common\Dishonored",
            r"SteamLibrary\steamapps\common\Dishonored",
            r"GOG Games\Dishonored",
            r"Games\Dishonored",
        ):
            candidates.append(Path(f"{drive}:\\") / suffix)

    unique: list[Path] = []
    seen: set[str] = set()
    for path in candidates:
        key = str(path).lower()
        if key not in seen:
            seen.add(key)
            unique.append(path)
    return unique


def _steam_libraries() -> list[Path]:
    steam_root = _steam_root()
    if steam_root is None:
        return []

    libraries = [steam_root]
    vdf = steam_root / "steamapps" / "libraryfolders.vdf"
    if vdf.is_file():
        try:
            text = vdf.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return libraries
        # Строки вида:  "path"    "D:\\SteamLibrary"
        for match in re.finditer(r'"path"\s*"([^"]+)"', text):
            libraries.append(Path(match.group(1).replace("\\\\", "\\")))
    return libraries


def _steam_root() -> Path | None:
    if sys.platform != "win32":
        return None
    try:
        import winreg
    except ImportError:
        return None

    for hive, key in (
        (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam"),
    ):
        for value_name in ("SteamPath", "InstallPath"):
            try:
                with winreg.OpenKey(hive, key) as handle:
                    return Path(winreg.QueryValueEx(handle, value_name)[0])
            except OSError:
                continue
    return None


# --- поиск конфигов -------------------------------------------------------

def find_config_dir(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_dir():
            raise SystemExit(f"Папка конфигов не найдена: {path}")
        return path

    for documents in _documents_dirs():
        candidate = documents / CONFIG_SUBPATH
        if candidate.is_dir():
            return candidate

    raise SystemExit(
        "Не нашёл папку конфигов. Обычно это\n"
        "  Документы\\My Games\\Dishonored\\DishonoredGame\\Config\n"
        "Укажи путь явно: --config-dir \"...\""
    )


def _documents_dirs() -> list[Path]:
    """Возможные расположения «Документов», включая переезд в OneDrive."""
    candidates: list[Path] = []

    if sys.platform == "win32":
        try:
            import winreg
            key = r"Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key) as handle:
                candidates.append(Path(winreg.QueryValueEx(handle, "Personal")[0]))
        except (ImportError, OSError):
            pass

    home = Path.home()
    candidates.extend([
        home / "Documents",
        home / "Документы",
        home / "OneDrive" / "Documents",
        home / "OneDrive" / "Документы",
    ])

    onedrive = os.environ.get("OneDrive")
    if onedrive:
        candidates.append(Path(onedrive) / "Documents")
        candidates.append(Path(onedrive) / "Документы")

    return candidates


# --- сбор -----------------------------------------------------------------

def collect_configs(config_dir: Path, out_dir: Path) -> dict:
    ini_paths = sorted(config_dir.glob("*.ini"))
    if not ini_paths:
        raise SystemExit(f"В {config_dir} нет ни одного .ini — папка та?")

    out_dir.mkdir(parents=True, exist_ok=True)
    catalog: dict[str, dict] = {}
    summary: list[dict] = []

    for source in ini_paths:
        destination = out_dir / source.name
        shutil.copy2(source, destination)
        # Снимаем «только чтение», если он остался от прошлой установки мода:
        # копия в репозитории должна быть свободно перезаписываемой.
        destination.chmod(destination.stat().st_mode | 0o600)

        ini = IniFile.load(source)
        sections = ini.catalog()
        catalog[source.name] = sections
        summary.append({
            "file": source.name,
            "encoding": ini.encoding,
            "sections": len(sections),
            "keys": sum(len(keys) for keys in sections.values()),
        })

    return {"catalog": catalog, "summary": summary}


def collect_packages(game_dir: Path, hash_upk: bool) -> list[dict]:
    content_dir = game_dir / CONTENT_SUBPATH
    if not content_dir.is_dir():
        return []

    packages = []
    for package in sorted(content_dir.glob("*.upk")):
        entry = {"name": package.name, "size": package.stat().st_size}
        if hash_upk:
            entry["sha256"] = _sha256(package)
        packages.append(entry)
    return packages


def collect_executable(game_dir: Path) -> dict | None:
    exe = game_dir / EXE_SUBPATH
    if not exe.is_file():
        matches = sorted(game_dir.rglob("Dishonored.exe"))
        if not matches:
            return None
        exe = matches[0]

    info = {
        "path": str(exe.relative_to(game_dir)),
        "size": exe.stat().st_size,
        "sha256": _sha256(exe),
    }
    info.update(_pe_info(exe))
    return info


def _pe_info(path: Path) -> dict:
    """Разрядность и дата сборки из PE-заголовка.

    Нужны, чтобы сигнатуры нативного слоя были привязаны к конкретному билду:
    сигнатура, снятая с другой версии экзешника, молча не найдётся.
    """
    try:
        with path.open("rb") as handle:
            if handle.read(2) != b"MZ":
                return {"pe": "не похоже на PE-файл"}
            handle.seek(0x3C)
            pe_offset = struct.unpack("<I", handle.read(4))[0]
            handle.seek(pe_offset)
            if handle.read(4) != b"PE\0\0":
                return {"pe": "повреждённая PE-сигнатура"}
            machine, _sections, timestamp = struct.unpack("<HHI", handle.read(8))
    except (OSError, struct.error) as error:
        return {"pe": f"не прочитался: {error}"}

    return {
        "arch": PE_MACHINE.get(machine, f"неизвестно (0x{machine:04X})"),
        "build_timestamp": datetime.fromtimestamp(timestamp, timezone.utc).isoformat(),
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# --- точка входа ----------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Собирает конфиги и метаданные установленной Dishonored в game-data/.")
    parser.add_argument("--game-dir", help="папка установки игры")
    parser.add_argument("--config-dir", help="папка с ini (Документы\\My Games\\...)")
    parser.add_argument("--hash-upk", action="store_true",
                        help="считать sha256 для .upk (несколько ГБ, долго)")
    args = parser.parse_args()

    game_dir = find_game_dir(args.game_dir)
    config_dir = find_config_dir(args.config_dir)

    print(f"Игра:    {game_dir}")
    print(f"Конфиги: {config_dir}")
    print()

    configs = collect_configs(config_dir, GAME_DATA / "config")
    packages = collect_packages(game_dir, args.hash_upk)
    executable = collect_executable(game_dir)

    GAME_DATA.mkdir(parents=True, exist_ok=True)
    (GAME_DATA / "config-catalog.json").write_text(
        json.dumps(configs["catalog"], indent=2, ensure_ascii=False), encoding="utf-8")

    manifest = {
        "harvested_at": datetime.now(timezone.utc).isoformat(),
        "game_dir": str(game_dir),
        "config_dir": str(config_dir),
        "executable": executable,
        "configs": configs["summary"],
        "packages": packages,
        "package_count": len(packages),
    }
    (GAME_DATA / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    total_keys = sum(item["keys"] for item in configs["summary"])
    print(f"Конфигов: {len(configs['summary'])}, ключей всего: {total_keys}")
    for item in configs["summary"]:
        print(f"  {item['file']:<24} секций {item['sections']:>4}   ключей {item['keys']:>5}")

    print(f"\nПакетов .upk: {len(packages)}")
    if executable:
        print(f"Экзешник: {executable.get('arch', '?')}, "
              f"сборка {executable.get('build_timestamp', '?')}")
    else:
        print("Экзешник не найден — нативный слой без него не привязать к билду.")

    print(f"\nГотово. Результат в {GAME_DATA}")
    print("Закоммить game-data/ — дальше всё строится на этих данных.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
