#!/usr/bin/env python3
"""Ужать текстуры персонажей, распакованные импортёром из FBX.

Модели пришли с картами 4096×4096 на каждого — в сумме 140 МБ, и почти все
эти пиксели не видно: персонаж на экране редко крупнее пары сотен точек, а
ночь и туман съедают остальное. Из-за них сборка весила 242 МБ.

Скрипт уменьшает распакованные PNG до `--size` (по умолчанию 512) и не
трогает FBX: оригиналы остаются в моделях, вернуть полное разрешение можно
удалением PNG и папки `.godot` — импортёр распакует их заново.

    python3 tools/shrink_textures.py            # 512, как в готовых сборках
    python3 tools/shrink_textures.py --size 1024

После прогона нужно переимпортировать проект, иначе движок отдаст старое
из кеша:

    rm -rf .godot
    godot --headless --path . --editor --quit

Размер сборки: 4096 → 242 МБ, 1024 → 146 МБ, 512 → 103 МБ.
"""

import argparse
import pathlib
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("нужен Pillow:  pip install Pillow")

HERE = pathlib.Path(__file__).resolve().parent.parent
CHARS = HERE / "assets" / "characters"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=512, help="максимальная сторона")
    ap.add_argument("--dir", type=pathlib.Path, default=CHARS)
    args = ap.parse_args()

    files = sorted(args.dir.glob("*.png"))
    if not files:
        sys.exit(
            f"в {args.dir} нет PNG — сначала открой проект в Godot, "
            "импортёр распакует текстуры из FBX"
        )

    before = after = 0
    touched = 0
    for f in files:
        before += f.stat().st_size
        img = Image.open(f)
        if max(img.size) > args.size:
            img.thumbnail((args.size, args.size), Image.LANCZOS)
            img.save(f, optimize=True)
            touched += 1
        after += f.stat().st_size

    print(
        f"текстур: {len(files)}, ужато: {touched}, "
        f"{before / 1e6:.0f} МБ -> {after / 1e6:.0f} МБ"
    )
    print("дальше:  rm -rf .godot && godot --headless --path . --editor --quit")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
