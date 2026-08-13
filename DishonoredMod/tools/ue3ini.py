"""Парсер конфигов Unreal Engine 3, сохраняющий форматирование.

Штатный configparser здесь не годится по трём причинам:

* в UE3 повторяющиеся ключи в одной секции — норма, а не ошибка;
* есть префиксные операторы массивов (``+Key=``, ``-Key=``, ``.Key=``,
  ``!Key=``), которые configparser считает частью имени ключа;
* при перезаписи configparser нормализует пробелы, регистр и порядок строк,
  а нам нужен диф, где видно ровно то, что мы поменяли, и ничего больше.

Поэтому файл хранится как список строк с разметкой. Правка меняет одну строку
и не трогает остальные — комментарии, пустые строки и порядок секций доживают
до записи в неизменном виде.

Только стандартная библиотека: скрипт запускается на машине с игрой, где может
не быть ничего, кроме голого Python.
"""

from __future__ import annotations

import codecs
import re
from dataclasses import dataclass, field
from pathlib import Path

# BOM определяется по байтам, а не подбором кодека. Соблазн начать список с
# "utf-8-sig" выглядит безобидно, но этот кодек успешно декодирует и файл без
# BOM, а при записи BOM добавляет — то есть файл, который мы не должны были
# трогать, тихо меняется в первых трёх байтах.
#
# Порядок важен: BOM_UTF32_LE (FF FE 00 00) начинается с BOM_UTF16_LE (FF FE),
# поэтому 32-битные варианты обязаны проверяться первыми.
_BOMS = (
    (codecs.BOM_UTF8, "utf-8"),
    (codecs.BOM_UTF32_LE, "utf-32-le"),
    (codecs.BOM_UTF32_BE, "utf-32-be"),
    (codecs.BOM_UTF16_LE, "utf-16-le"),
    (codecs.BOM_UTF16_BE, "utf-16-be"),
)

# Догадки для файлов без BOM. cp1251 стоит перед latin-1, потому что latin-1
# декодирует вообще любой байт и, будучи первым, навсегда спрятал бы кириллицу
# в комментариях.
_FALLBACK_ENCODINGS = ("utf-8", "cp1251", "latin-1")

_SECTION_RE = re.compile(r"^\s*\[(?P<name>[^\]]*)\]\s*$")
_ENTRY_RE = re.compile(r"^(?P<indent>\s*)(?P<op>[+\-.!])?(?P<key>[^=;\s][^=]*?)\s*=(?P<value>.*)$")

SECTION = "section"
ENTRY = "entry"
OTHER = "other"


@dataclass
class Line:
    """Одна строка файла. ``raw`` — то, что уйдёт на диск, если не менять."""

    kind: str
    raw: str
    section: str | None = None
    op: str = ""
    key: str | None = None
    value: str | None = None

    def render(self) -> str:
        if self.kind != ENTRY:
            return self.raw
        indent = self._indent()
        return f"{indent}{self.op}{self.key}={self.value}"

    def _indent(self) -> str:
        match = _ENTRY_RE.match(self.raw)
        return match.group("indent") if match else ""


@dataclass
class IniFile:
    path: Path
    lines: list[Line] = field(default_factory=list)
    encoding: str = "utf-8"
    bom: bytes = b""
    newline: str = "\r\n"
    had_trailing_newline: bool = True

    # --- чтение -----------------------------------------------------------

    @classmethod
    def load(cls, path: Path) -> "IniFile":
        raw_bytes = path.read_bytes()
        text, encoding, bom = _decode(raw_bytes)
        newline = "\r\n" if "\r\n" in text else "\n"
        had_trailing_newline = text.endswith(("\n", "\r"))

        ini = cls(path=path, encoding=encoding, bom=bom, newline=newline,
                  had_trailing_newline=had_trailing_newline)

        current_section: str | None = None
        for raw in text.splitlines():
            section_match = _SECTION_RE.match(raw)
            if section_match:
                current_section = section_match.group("name")
                ini.lines.append(Line(kind=SECTION, raw=raw, section=current_section))
                continue

            stripped = raw.strip()
            if stripped and not stripped.startswith((";", "#")):
                entry_match = _ENTRY_RE.match(raw)
                if entry_match:
                    ini.lines.append(Line(
                        kind=ENTRY,
                        raw=raw,
                        section=current_section,
                        op=entry_match.group("op") or "",
                        key=entry_match.group("key").strip(),
                        value=entry_match.group("value").strip(),
                    ))
                    continue

            ini.lines.append(Line(kind=OTHER, raw=raw, section=current_section))

        return ini

    # --- чтение содержимого ----------------------------------------------

    def catalog(self) -> dict[str, dict[str, list[str]]]:
        """Каталог ``{секция: {ключ: [значения]}}``.

        Значений может быть несколько: в UE3 повторы легальны.
        """
        result: dict[str, dict[str, list[str]]] = {}
        for line in self.lines:
            if line.kind != ENTRY:
                continue
            section = line.section or ""
            result.setdefault(section, {}).setdefault(line.op + line.key, []).append(line.value)
        return result

    def has_key(self, section: str, key: str) -> bool:
        return any(
            line.kind == ENTRY and (line.section or "") == section and line.key == key
            for line in self.lines
        )

    def get(self, section: str, key: str) -> str | None:
        for line in self.lines:
            if line.kind == ENTRY and (line.section or "") == section and line.key == key:
                return line.value
        return None

    # --- правка -----------------------------------------------------------

    def set_value(self, section: str, key: str, value: str) -> str:
        """Меняет значение ключа. Возвращает, что произошло.

        Правится первое вхождение — остальные повторы не трогаются, потому что
        в UE3 повтор обычно означает элемент массива, и слепая замена всех
        вхождений сломала бы список.

        Возвращает ``"updated"``, ``"unchanged"``, ``"added"`` либо
        ``"added-section"``.
        """
        for line in self.lines:
            if line.kind == ENTRY and (line.section or "") == section and line.key == key:
                if line.value == value:
                    return "unchanged"
                line.value = value
                return "updated"

        insert_at = self._section_end(section)
        if insert_at is None:
            if self.lines and self.lines[-1].raw.strip():
                self.lines.append(Line(kind=OTHER, raw="", section=None))
            self.lines.append(Line(kind=SECTION, raw=f"[{section}]", section=section))
            self.lines.append(Line(kind=ENTRY, raw=f"{key}={value}", section=section,
                                   key=key, value=value))
            return "added-section"

        self.lines.insert(insert_at, Line(kind=ENTRY, raw=f"{key}={value}",
                                          section=section, key=key, value=value))
        return "added"

    def _section_end(self, section: str) -> int | None:
        """Индекс, куда вставлять новый ключ секции — после последней её записи."""
        start = None
        for index, line in enumerate(self.lines):
            if line.kind == SECTION and line.section == section:
                start = index
                break
        if start is None:
            return None

        end = len(self.lines)
        for index in range(start + 1, len(self.lines)):
            if self.lines[index].kind == SECTION:
                end = index
                break

        # Пятимся назад через хвостовые пустые строки, чтобы новый ключ
        # оказался внутри секции, а не в зазоре перед следующей.
        while end - 1 > start and self.lines[end - 1].kind == OTHER \
                and not self.lines[end - 1].raw.strip():
            end -= 1
        return end

    # --- запись -----------------------------------------------------------

    def render(self) -> str:
        text = self.newline.join(line.render() for line in self.lines)
        if self.had_trailing_newline:
            text += self.newline
        return text

    def render_bytes(self) -> bytes:
        return self.bom + self.render().encode(self.encoding)

    def save(self, path: Path | None = None) -> None:
        target = path or self.path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(self.render_bytes())


def _decode(raw_bytes: bytes) -> tuple[str, str, bytes]:
    """Возвращает ``(текст, кодировка для записи, байты BOM)``.

    BOM возвращается отдельно и дописывается при сохранении вручную — так файл
    без BOM остаётся без него, а файл с BOM сохраняет ровно свой.
    """
    for bom, encoding in _BOMS:
        if raw_bytes.startswith(bom):
            return raw_bytes[len(bom):].decode(encoding), encoding, bom

    for encoding in _FALLBACK_ENCODINGS:
        try:
            return raw_bytes.decode(encoding), encoding, b""
        except (UnicodeDecodeError, UnicodeError):
            continue
    return raw_bytes.decode("latin-1"), "latin-1", b""
