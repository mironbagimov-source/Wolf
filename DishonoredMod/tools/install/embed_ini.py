#!/usr/bin/env python3
"""Вшивает native/native.ini в заголовок для установщика.

Конфиг отдельным файлом — лишний повод для поломки: Windows дописывает
расширение при скачивании, мессенджеры добавляют суффиксы, и установщик
честно не находит «native.ini», хотя рядом лежит «native.ini.txt». Файл,
которого не нужно, потерять нельзя.

Запускать после любой правки native/native.ini:
    python3 tools/install/embed_ini.py
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "native" / "native.ini"
TARGET = ROOT / "tools" / "install" / "native_ini.h"

HEADER = '''#pragma once

// Содержимое native.ini, вшитое в установщик.
//
// Отдельным файлом конфиг оказался лишним поводом для поломки: Windows
// дописывает расширение при скачивании, мессенджеры добавляют суффиксы, и
// установщик честно не находит «native.ini», хотя рядом лежит
// «native.ini.txt». Файл, которого не нужно, потерять нельзя.
//
// Этот текст ставится всегда, поверх всего, что лежало раньше. Выбора между
// ним и файлом рядом с установщиком больше нет: такой выбор один раз уже
// подсунул игре конфиг от первой версии, режим молча стал не тем, и сеанс
// игры ушёл впустую. Версия конфига теперь сходится с версией установщика по
// построению.
//
// Сгенерировано из native/native.ini скриптом tools/install/embed_ini.py —
// править надо там, а не здесь.

namespace dmk {{

inline const char* kEmbeddedNativeIni = R"{delimiter}({text}){delimiter}";

}}  // namespace dmk
'''


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")

    # Разделитель raw-строки обязан отсутствовать в тексте, иначе строка
    # оборвётся посреди конфига, а обломок хвоста попадёт в код — с шансом
    # собраться и записать в игру мусор.
    delimiter = "DMKINI"
    while f'){delimiter}"' in text:
        delimiter += "X"

    TARGET.write_text(HEADER.format(delimiter=delimiter, text=text),
                      encoding="utf-8")
    print(f"{TARGET.relative_to(ROOT)}: {len(text)} символов, "
          f"разделитель {delimiter}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
