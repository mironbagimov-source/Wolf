"""Проверки парсера конфигов. Запуск: python tools/test_ue3ini.py

Ключевое требование к парсеру — файл, который мы не правили, обязан
сохраниться байт в байт. Иначе диф правки тонет в шуме из переехавших
переводов строк, добавленных BOM и переформатированных комментариев,
и понять, что именно мод меняет в игре, становится нельзя.
"""

from __future__ import annotations

import codecs
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ue3ini import IniFile

PASSED = 0
FAILED = 0


def check(name: str, condition: bool, detail: str = "") -> None:
    global PASSED, FAILED
    if condition:
        PASSED += 1
        print(f"  ok    {name}")
    else:
        FAILED += 1
        print(f"  ПРОВАЛ {name}" + (f"\n         {detail}" if detail else ""))


def roundtrip(raw: bytes, name: str) -> IniFile:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "test.ini"
        path.write_bytes(raw)
        ini = IniFile.load(path)
        rendered = ini.render_bytes()
        check(f"round-trip байт в байт: {name}", rendered == raw,
              f"было {raw[:60]!r}\n         стало {rendered[:60]!r}")
        return ini


def main() -> int:
    print("Round-trip без правок")
    plain = b"; comment\r\n[Sec]\r\nKey=1.0\r\n"
    roundtrip(plain, "CRLF без BOM")
    roundtrip(b"[Sec]\nKey=1.0\n", "LF без BOM")
    roundtrip(codecs.BOM_UTF8 + plain, "UTF-8 с BOM")
    roundtrip(codecs.BOM_UTF16_LE + plain.decode().encode("utf-16-le"), "UTF-16 LE с BOM")
    roundtrip(b"[Sec]\r\nKey=1.0", "без хвостового перевода строки")
    roundtrip("; коммент\r\n[Sec]\r\nKey=1.0\r\n".encode("cp1251"), "cp1251, кириллица")

    print("\nСохранность структуры")
    source = (
        "; Player tuning\r\n"
        "[A]\r\n"
        "Key=1.0\r\n"
        "\r\n"
        "[B]\r\n"
        "+List=one\r\n"
        "+List=two\r\n"
        "Other=5\r\n"
    ).encode()
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "t.ini"
        path.write_bytes(source)
        ini = IniFile.load(path)

        catalog = ini.catalog()
        check("массив +List собран как один ключ с двумя значениями",
              catalog["B"]["+List"] == ["one", "two"], str(catalog))
        check("секции разделены", set(catalog) == {"A", "B"}, str(set(catalog)))

        check("правка существующего ключа", ini.set_value("A", "Key", "2.0") == "updated")
        check("повторная запись того же значения — unchanged",
              ini.set_value("A", "Key", "2.0") == "unchanged")
        check("новый ключ в существующей секции", ini.set_value("A", "New", "9") == "added")
        check("новая секция", ini.set_value("C", "Fresh", "1") == "added-section")

        result = ini.render()
        check("комментарий на месте", result.startswith("; Player tuning"))
        check("массив не тронут", "+List=one\r\n+List=two" in result)
        check("новый ключ попал внутрь секции A, а не в чужую",
              result.index("New=9") < result.index("[B]"), result)
        check("значение обновилось", "Key=2.0" in result and "Key=1.0" not in result)
        check("CRLF сохранился", "\n" in result and "\r\n" in result
              and result.count("\n") == result.count("\r\n"))

    print("\nПропуск неоднозначных строк")
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "t.ini"
        path.write_bytes(b"[S]\r\n; Key=commented\r\nReal=1\r\n")
        ini = IniFile.load(path)
        check("закомментированный ключ не считается ключом",
              not ini.has_key("S", "Key") and ini.has_key("S", "Real"),
              str(ini.catalog()))

    print(f"\nПройдено {PASSED}, провалено {FAILED}")
    return 1 if FAILED else 0


if __name__ == "__main__":
    raise SystemExit(main())
