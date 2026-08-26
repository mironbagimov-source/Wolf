#!/usr/bin/env python3
"""Читает пакет Dishonored (.upk) и печатает, что в нём лежит.

Зачем. Таблица имён из живой игры показывает всё, что игра загрузила, но не
говорит, из какого пакета что взялось. Когда нужен ответ «есть ли в этом файле
анимации китобоя», спрашивать надо сам файл.

Почему это не одна строка. Пакеты Dishonored сжаты: заголовок разложен на
куски по 128 КБ, кодек LZO1X, и до таблиц не добраться, пока не распакуешь.
Смещения в сводке при этом указывают на исходный, несжатый файл, поэтому после
распаковки их приходится пересчитывать относительно начала сжатой области.

Нужен модуль lzo:
    apt-get install -y liblzo2-dev && pip install python-lzo

Примеры:
    python3 tools/upk.py DLC06_Slaughter_Int_Assassin.upk
    python3 tools/upk.py пакет.upk --names --grep assassin
    python3 tools/upk.py пакет.upk --names > имена.txt
"""

import argparse
import pathlib
import re
import struct
import sys

PACKAGE_TAG = 0x9E2A83C1


class PackageError(Exception):
    pass


def read_string(data, offset):
    """FString: длина со знаком, минус означает UTF-16."""
    (length,) = struct.unpack_from("<i", data, offset)
    offset += 4
    if length == 0:
        return "", offset
    if length > 0:
        return data[offset:offset + length - 1].decode("latin-1", "replace"), offset + length
    length = -length
    return data[offset:offset + 2 * length - 2].decode("utf-16-le", "replace"), offset + 2 * length


class Package:
    def __init__(self, path):
        self.path = pathlib.Path(path)
        self.raw = self.path.read_bytes()
        self._read_summary()
        self._load_header()
        self._read_names()

    def _read_summary(self):
        tag, self.version, self.licensee, self.header_size = struct.unpack_from(
            "<IhhI", self.raw, 0)
        if tag != PACKAGE_TAG:
            raise PackageError(
                f"не пакет UE3: сигнатура 0x{tag:08X}, ожидалась 0x{PACKAGE_TAG:08X}")

        self.folder, offset = read_string(self.raw, 12)
        (self.flags, self.name_count, self.name_offset, self.export_count,
         self.export_offset, self.import_count,
         self.import_offset) = struct.unpack_from("<7i", self.raw, offset)

    def _find_compressed_chunk(self):
        """Ищет заголовок сжатого куска — он начинается той же сигнатурой.

        Разбирать сводку до конца ради его смещения не выйдет: хвост зависит от
        версии и от правок Arkane. А вот сигнатура в пределах сводки встречается
        ровно дважды — в самом начале файла и здесь.
        """
        limit = min(len(self.raw), 65536)
        needle = struct.pack("<I", PACKAGE_TAG)
        position = self.raw.find(needle, 4, limit)
        return position if position > 0 else None

    def _load_header(self):
        """Отдаёт распакованный заголовок и смещение, которому он соответствует."""
        chunk = self._find_compressed_chunk()
        if chunk is None:
            self.header = self.raw
            self.base = 0
            self.compressed = False
            return

        try:
            import lzo
        except ImportError:
            raise PackageError(
                "заголовок сжат, а модуля lzo нет.\n"
                "  apt-get install -y liblzo2-dev && pip install python-lzo")

        _, block_size, _, total = struct.unpack_from("<4i", self.raw, chunk)
        offset = chunk + 16
        blocks = []
        for _ in range((total + block_size - 1) // block_size):
            blocks.append(struct.unpack_from("<2i", self.raw, offset))
            offset += 8

        out = bytearray()
        for packed, unpacked in blocks:
            out += lzo.decompress(self.raw[offset:offset + packed], False, unpacked)
            offset += packed

        if len(out) != total:
            raise PackageError(f"распаковано {len(out)} байт вместо {total}")

        self.header = bytes(out)
        # Сжатая область начинается ровно с таблицы имён: смещения в сводке
        # считаны от начала исходного файла, а распакованное — от неё.
        self.base = self.name_offset
        self.compressed = True

    def _read_names(self):
        offset = self.name_offset - self.base
        self.names = []
        for _ in range(self.name_count):
            name, offset = read_string(self.header, offset)
            offset += 8  # флаги записи, QWORD
            self.names.append(name)

        # Проверка на себя: таблица имён обязана кончиться там, где по сводке
        # начинаются импорты. Иначе разбор ушёл не туда, и всё дальнейшее —
        # правдоподобный мусор.
        expected = self.import_offset - self.base
        if offset != expected:
            raise PackageError(
                f"таблица имён кончилась на {offset + self.base}, "
                f"а импорты по сводке на {self.import_offset}")

    def imports(self):
        """Что пакет тянет извне: пары «класс, объект»."""
        offset = self.import_offset - self.base
        result = []
        for _ in range(self.import_count):
            _, _, class_index, _, _, name_index, _ = struct.unpack_from(
                "<7i", self.header, offset)
            offset += 28
            if 0 <= class_index < len(self.names) and 0 <= name_index < len(self.names):
                result.append((self.names[class_index], self.names[name_index]))
        return result

    def describe(self):
        return (
            f"{self.path.name}\n"
            f"  размер          {len(self.raw):,} байт\n"
            f"  версия          {self.version} / лицензиат {self.licensee}\n"
            f"  заголовок       {self.header_size:,} байт"
            f"{' (сжат LZO)' if self.compressed else ''}\n"
            f"  имён            {self.name_count:,}\n"
            f"  экспортов       {self.export_count:,}\n"
            f"  импортов        {self.import_count:,}\n"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("package", help="путь к .upk")
    parser.add_argument("--names", action="store_true",
                        help="напечатать таблицу имён")
    parser.add_argument("--imports", action="store_true",
                        help="напечатать импорты пакета")
    parser.add_argument("--grep", metavar="ОБРАЗЕЦ",
                        help="оставить только имена по образцу, без учёта регистра")
    args = parser.parse_args()

    try:
        package = Package(args.package)
    except PackageError as error:
        print(f"ошибка: {error}", file=sys.stderr)
        return 1

    if not args.names and not args.imports:
        print(package.describe(), end="")
        return 0

    pattern = re.compile(args.grep, re.IGNORECASE) if args.grep else None

    if args.names:
        for name in package.names:
            if pattern is None or pattern.search(name):
                print(name)

    if args.imports:
        for class_name, name in sorted(package.imports()):
            line = f"{class_name}\t{name}"
            if pattern is None or pattern.search(line):
                print(line)

    return 0


if __name__ == "__main__":
    sys.exit(main())
