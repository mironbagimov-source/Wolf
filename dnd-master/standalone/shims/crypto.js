// Замена node:crypto для однофайловой сборки.
//
// Источник случайности тот же по сути, что и в Node: системный ГСЧ, а не
// Math.random. Это важно не из педантизма — на кубиках держится доверие к
// столу, и распределение должно быть честным до последней грани.

const bytes = (count) => globalThis.crypto.getRandomValues(new Uint8Array(count));

/**
 * Целое из [min, max) с равномерным распределением. Простое `% range` сместило
 * бы вероятности к младшим значениям, поэтому хвост диапазона отбраковывается.
 */
export function randomInt(min, max) {
  if (max === undefined) {
    max = min;
    min = 0;
  }
  const range = max - min;
  if (!Number.isInteger(range) || range < 1) throw new Error(`Некорректный диапазон: [${min}, ${max})`);

  const size = Math.max(1, Math.ceil(Math.ceil(Math.log2(range)) / 8));
  const limit = Math.floor(256 ** size / range) * range;
  for (;;) {
    let value = 0;
    for (const byte of bytes(size)) value = value * 256 + byte;
    if (value < limit) return min + (value % range);
  }
}

export function randomUUID() {
  // На file:// не в каждом браузере есть crypto.randomUUID, поэтому запасной путь.
  if (globalThis.crypto.randomUUID) return globalThis.crypto.randomUUID();
  const raw = bytes(16);
  raw[6] = (raw[6] & 0x0f) | 0x40; // версия 4
  raw[8] = (raw[8] & 0x3f) | 0x80; // вариант 10x
  const hex = [...raw].map((b) => b.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export default { randomInt, randomUUID };
