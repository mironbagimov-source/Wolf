// Встроенные SVG-иконки: ни одного внешнего запроса, всё рисуется штрихом
// и наследует цвет текста через currentColor.

const svg = (paths, { size = 20, fill = false, viewBox = '0 0 24 24' } = {}) =>
  `<svg viewBox="${viewBox}" width="${size}" height="${size}" fill="${fill ? 'currentColor' : 'none'}" ` +
  `stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;

export const CLASS_ICONS = {
  fighter: '<path d="M14.5 3.5 20.5 3.5 20.5 9.5 10 20 4 14z"/><path d="M4 20 8 16"/>',
  barbarian: '<path d="M6 4c5 0 9 3 9 7 0 2-1 3-3 3H9"/><path d="M9 14 6 20"/><path d="M15 11c3 0 4-2 4-4"/>',
  bard: '<circle cx="9" cy="16" r="5"/><path d="M13 12 19 4"/><path d="M16 4h4v4"/><path d="M9 11v10"/>',
  cleric: '<path d="M12 3v18"/><path d="M6 8h12"/><circle cx="12" cy="14" r="4"/>',
  druid: '<path d="M12 21c0-6 3-11 9-13-1 8-4 11-9 13z"/><path d="M12 21C12 15 9 10 3 8c1 8 4 11 9 13z"/>',
  monk: '<circle cx="12" cy="12" r="9"/><path d="M8 14c2 2 6 2 8 0"/><path d="M8.5 9.5h.01M15.5 9.5h.01"/>',
  paladin: '<path d="M12 3 20 6v6c0 5-4 8-8 9-4-1-8-4-8-9V6z"/><path d="M12 8v8M9 11h6"/>',
  ranger: '<path d="M5 3c8 2 12 8 14 16"/><path d="M5 3 5 9M5 3 11 3"/><path d="M4 20 20 4"/>',
  rogue: '<path d="M12 3 15 12 12 15 9 12z"/><path d="M12 15v6"/><path d="M9 18h6"/>',
  sorcerer: '<path d="M12 2 14 9 21 11 14 13 12 20 10 13 3 11 10 9z"/>',
  warlock: '<path d="M2 12s4-6 10-6 10 6 10 6-4 6-10 6-10-6-10-6z"/><circle cx="12" cy="12" r="3"/>',
  wizard: '<path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z"/><path d="M5 17h14"/><path d="M9 8h6"/>',
};

export const ICONS = {
  d20: '<path d="M12 2 21 7.5v9L12 22 3 16.5v-9z"/><path d="m12 2 5 8-5 12-5-12z"/><path d="M3 7.5 17 10M21 7.5 7 10"/>',
  speech: '<path d="M20 12a7 7 0 0 1-7 7H8l-4 3v-4.5A7 7 0 0 1 4 12a7 7 0 0 1 7-7h2a7 7 0 0 1 7 7z"/>',
  action: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  ooc: '<path d="M8 5h12v10h-5l-4 3v-3H8z"/><path d="M4 9v10h4"/>',
  send: '<path d="M4 12 21 4l-8 17-2-7z"/><path d="m11 14 10-10"/>',
  hourglass: '<path d="M7 3h10M7 21h10"/><path d="M8 3c0 5 8 4 8 9s-8 4-8 9"/><path d="M16 3c0 5-8 4-8 9s8 4 8 9"/>',
  map: '<path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14M15 6v14"/>',
  scroll: '<path d="M6 3h11a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6"/><path d="M6 3a2 2 0 0 0 0 4h3"/><path d="M10 11h6M10 15h6"/>',
  swords: '<path d="M14 3h7v7"/><path d="M21 3 10 14"/><path d="M3 21l4-4"/><path d="m7 17 3 3"/><path d="M3 3h4l11 11-3 3z"/>',
  heart: '<path d="M12 20s-8-4.6-8-10a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 10c0 5.4-8 10-8 10z"/>',
  shield: '<path d="M12 3 20 6v6c0 5-4 8-8 9-4-1-8-4-8-9V6z"/>',
  skull: '<path d="M12 3a8 8 0 0 0-5 14v3h10v-3a8 8 0 0 0-5-14z"/><circle cx="9.5" cy="12" r="1.5"/><circle cx="14.5" cy="12" r="1.5"/>',
  bag: '<path d="M6 8h12l1 12H5z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>',
  crown: '<path d="m3 8 4 4 5-8 5 8 4-4-2 12H5z"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0"/><path d="M16 5.2a3.5 3.5 0 0 1 0 5.6M18 20a6.5 6.5 0 0 0-2.5-5.1"/>',
  link: '<path d="M10 13a5 5 0 0 0 7 0l2-2a5 5 0 0 0-7-7l-1 1"/><path d="M14 11a5 5 0 0 0-7 0l-2 2a5 5 0 0 0 7 7l1-1"/>',
};

/** Возвращает готовый DOM-узел с иконкой. */
export function icon(name, options) {
  const markup = ICONS[name] || CLASS_ICONS[name];
  if (!markup) return document.createComment(`нет иконки ${name}`);
  const wrapper = document.createElement('span');
  wrapper.className = 'icon';
  wrapper.innerHTML = svg(markup, options);
  return wrapper;
}

export function classIcon(classIndex, options) {
  return icon(CLASS_ICONS[classIndex] ? classIndex : 'shield', options);
}

/** Грань кубика как маленький значок: d20 — многоугольник, d6 — квадрат с точками. */
export function dieGlyph(faces, size = 18) {
  if (faces === 6) {
    return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.6">
      <rect x="4" y="4" width="16" height="16" rx="3"/><circle cx="9" cy="9" r="1.2" fill="currentColor" stroke="none"/>
      <circle cx="15" cy="15" r="1.2" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.2" fill="currentColor" stroke="none"/></svg>`;
  }
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor"
    stroke-width="1.5" stroke-linejoin="round"><path d="M12 2 21 7.5v9L12 22 3 16.5v-9z"/><path d="m12 2 5 8-5 12-5-12z"/></svg>`;
}
