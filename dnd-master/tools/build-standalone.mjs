// Собирает всё приложение в один HTML-файл, который открывается двойным
// кликом с диска: движок, справочник SRD, интерфейс и мастер — внутри.
//
// Полноценный сборщик сюда тащить не за чем: модулей три десятка, все свои,
// синтаксис импортов однообразный. Поэтому здесь маленький собственный
// упаковщик — каждый модуль заворачивается в IIFE и возвращает свои экспорты,
// а импорты превращаются в обращения к соседним IIFE.
//
//   node tools/build-standalone.mjs   →   dnd-master.html
//
// Запуск: npm run build:standalone

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (...parts) => fs.readFileSync(path.join(root, ...parts), 'utf8');

const ENTRY = 'standalone/app.js';
const OUTPUT = 'dnd-master.html';

// Узлы, которых в браузере нет, и подмена сетевого модуля на локальный стол:
// благодаря второй строке game.js и battlemap.js едут в сборку без правок.
const ALIASES = {
  'node:crypto': 'standalone/shims/crypto.js',
  'node:fs': 'standalone/shims/fs.js',
  'node:path': 'standalone/shims/path.js',
  'node:url': 'standalone/shims/url.js',
  'public/js/net.js': 'standalone/net-local.js',
};

// Требование CC-BY: атрибуция обязана оставаться при данных, куда бы они ни уехали.
const ATTRIBUTION = `
  Мастер подземелий — D&D 5e в чате с мастером-нейросетью.
  Собрано из исходников: см. tools/build-standalone.mjs.

  Игровые данные — System Reference Document 5.1 (SRD 5.1) от Wizards of the
  Coast LLC, https://dnd.wizards.com/resources/systems-reference-document

  This work includes material taken from the System Reference Document 5.1
  ("SRD 5.1") by Wizards of the Coast LLC and available at
  https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is
  licensed under the Creative Commons Attribution 4.0 International License
  available at https://creativecommons.org/licenses/by/4.0/legalcode.

  JSON справочника собран из 5e-bits/5e-database (MIT).
  Карты генерируются кодом, изображений в файле нет.
`;

const SRD_BUNDLES = [
  'monsters',
  'spells',
  'equipment',
  'classes',
  'races',
  'backgrounds',
  'magic-items',
  'rules',
  'reference',
];

// ------------------------------------------------------------ разбор модуля

const moduleId = (file) => `__m_${file.replace(/[^a-zA-Z0-9]/g, '_')}`;

/** Куда на самом деле ведёт спецификатор импорта. */
function resolve(specifier, fromFile) {
  if (ALIASES[specifier]) return ALIASES[specifier];
  if (!specifier.startsWith('.')) {
    throw new Error(`Внешняя зависимость ${specifier} (в ${fromFile}) в однофайловую сборку не помещается`);
  }
  const resolved = path.posix.normalize(path.posix.join(path.posix.dirname(fromFile), specifier));
  return ALIASES[resolved] || resolved;
}

const IMPORT_RE = /^import\s+(?:([\s\S]*?)\s+from\s+)?['"]([^'"]+)['"];?[ \t]*$/gm;

/**
 * Переписывает импорты в обращения к уже собранным модулям и заодно собирает
 * список зависимостей. Живых связок здесь не нужно: модули идут в порядке
 * зависимостей, а циклов в проекте нет — сборщик их отдельно проверяет.
 */
function rewriteImports(source, file, deps) {
  return source.replace(IMPORT_RE, (whole, clause, specifier) => {
    const target = resolve(specifier, file);
    deps.push(target);
    const ref = moduleId(target);
    if (!clause) return `${ref};`;

    const parts = [];
    // import * as ns from '...'
    const namespace = clause.match(/^\*\s+as\s+([\w$]+)$/);
    if (namespace) return `const ${namespace[1]} = ${ref};`;

    // Смешанная форма: import def, { a, b as c } from '...'
    const braces = clause.match(/\{([\s\S]*)\}/);
    const beforeBraces = clause.replace(/\{[\s\S]*\}/, '').replace(/,\s*$/, '').trim();

    if (beforeBraces) {
      const star = beforeBraces.match(/^\*\s+as\s+([\w$]+)$/);
      if (star) parts.push(`const ${star[1]} = ${ref};`);
      else parts.push(`const ${beforeBraces} = ${ref}.default;`);
    }
    if (braces) {
      const named = braces[1]
        .split(',')
        .map((piece) => piece.trim())
        .filter(Boolean)
        .map((piece) => {
          const renamed = piece.match(/^([\w$]+)\s+as\s+([\w$]+)$/);
          return renamed ? `${renamed[1]}: ${renamed[2]}` : piece;
        });
      if (named.length) parts.push(`const { ${named.join(', ')} } = ${ref};`);
    }
    return parts.join(' ') || `${ref};`;
  });
}

/** Снимает ключевое слово export и запоминает, что именно модуль отдаёт. */
function rewriteExports(source, file) {
  const names = new Set();
  let out = source;

  // export { a, b as c };
  out = out.replace(/^export\s*\{([^}]*)\};?[ \t]*$/gm, (whole, body) => {
    for (const piece of body.split(',').map((s) => s.trim()).filter(Boolean)) {
      const renamed = piece.match(/^([\w$]+)\s+as\s+([\w$]+)$/);
      names.add(renamed ? `${renamed[2]}: ${renamed[1]}` : piece);
    }
    return '';
  });

  // export default <expr>;
  out = out.replace(/^export\s+default\s+/gm, () => {
    names.add('default: __default');
    return 'const __default = ';
  });

  // export function foo / export class Foo / export const a = ...
  // Несколько объявлений через запятую в одном export сборщик не разбирает —
  // в проекте таких нет, а поддержка потребовала бы настоящего парсера.
  out = out.replace(/^export\s+(async\s+function|function|class|const|let|var)\s+/gm, (whole, kind) => `${kind} `);
  for (const [, name] of source.matchAll(/^export\s+(?:async\s+function|function|class|const|let|var)\s+([\w$]+)/gm)) {
    names.add(name);
  }

  if (/^export[\s{*]/m.test(out)) {
    throw new Error(`Не разобран экспорт в ${file}:\n${out.match(/^export.*$/m)[0]}`);
  }

  // Страховка от тихой ошибки разбора: если сборщик придумал экспорт, которого
  // в модуле нет, страница упадёт в браузере с невнятным ReferenceError.
  for (const entry of names) {
    const local = entry.includes(':') ? entry.split(':')[1].trim() : entry;
    const declared =
      new RegExp(`(?:function|class|const|let|var)\\s+${local}\\b`).test(out) ||
      // Реэкспорт чужого: после переписывания импорт стал деструктуризацией.
      new RegExp(`const\\s*\\{[^}]*\\b${local}\\b[^}]*\\}\\s*=`).test(out);
    if (!declared) throw new Error(`В ${file} нет объявления «${local}», хотя он попал в экспорт`);
  }
  return { code: out, names: [...names] };
}

// ----------------------------------------------------------------- граф

const modules = new Map(); // file -> {code, names, deps}

function compile(file) {
  if (modules.has(file)) return;
  modules.set(file, null); // метка «в работе» — ловит циклы

  const deps = [];
  const source = read(file);
  const withoutImports = rewriteImports(source, file, deps);
  const { code, names } = rewriteExports(withoutImports, file);

  for (const dep of deps) {
    if (modules.has(dep) && modules.get(dep) === null) {
      throw new Error(`Циклический импорт: ${file} ↔ ${dep}`);
    }
    compile(dep);
  }
  modules.set(file, { code, names, deps });
}

compile(ENTRY);

/** Порядок вычисления: зависимость всегда раньше того, кто её просит. */
function ordered() {
  const done = new Set();
  const list = [];
  const visit = (file) => {
    if (done.has(file)) return;
    done.add(file);
    for (const dep of modules.get(file).deps) visit(dep);
    list.push(file);
  };
  visit(ENTRY);
  return list;
}

const bundle = ordered()
  .map((file) => {
    const { code, names } = modules.get(file);
    const exports = names.map((n) => (n.includes(':') ? n : `${n}`)).join(', ');
    return `// ─── ${file} ───────────────────────────────────────────────\nconst ${moduleId(file)} = (() => {\n${code}\nreturn { ${exports} };\n})();`;
  })
  .join('\n\n');

// ------------------------------------------------------------ содержимое

const srd = Object.fromEntries(
  SRD_BUNDLES.map((name) => {
    const file = path.join(root, 'server', 'data', 'srd', `${name}.json`);
    if (!fs.existsSync(file)) throw new Error(`Нет ${file}. Сначала: npm run build:srd`);
    return [name, JSON.parse(fs.readFileSync(file, 'utf8'))];
  }),
);

const styles = `${read('public', 'styles.css')}\n\n${read('standalone', 'parts', 'extra.css')}`;

// ------------------------------------------------------------------ HTML

/** Замена с проверкой: молча промахнуться мимо якоря — худшее, что тут может быть. */
function replaceOnce(html, pattern, replacement, what) {
  const matches = html.match(pattern instanceof RegExp ? pattern : new RegExp(escape(pattern), 'g'));
  if (!matches || matches.length !== 1) {
    throw new Error(`Не нашёл ровно один якорь «${what}» в public/index.html (нашёл ${matches?.length || 0})`);
  }
  return html.replace(pattern, () => replacement);
}

const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

let html = read('public', 'index.html');

html = replaceOnce(
  html,
  /<section id="screen-lobby"[\s\S]*?<\/section>/,
  read('standalone', 'parts', 'lobby.html').trim(),
  'экран лобби',
);

html = replaceOnce(
  html,
  /<header>[\s\S]*?<\/header>/,
  read('standalone', 'parts', 'creator-header.html').trim(),
  'шапка создания героя',
);

html = replaceOnce(
  html,
  /<div class="topbar-right">[\s\S]*?<\/div>\s*<\/div>/,
  `${read('standalone', 'parts', 'topbar-right.html').trim()}\n        </div>`,
  'правый угол верхней панели',
);

html = replaceOnce(
  html,
  '<div class="modes">',
  '<div id="who-bar" class="who-bar hidden"></div>\n                <div class="modes">',
  'переключатель режима реплики',
);

html = replaceOnce(
  html,
  '<button id="nudge-btn"',
  '<button id="add-hero" class="ghost" data-icon="plus" title="Добавить ещё одного героя за этот экран">\n                    Ещё герой\n                  </button>\n                  <button id="nudge-btn"',
  'кнопка «Мастер, дальше»',
);

html = replaceOnce(html, '<div id="toast" class="toast hidden"></div>', `${read('standalone', 'parts', 'modal.html').trim()}\n\n    <div id="toast" class="toast hidden"></div>`, 'всплывающее сообщение');

html = replaceOnce(
  html,
  '<link rel="stylesheet" href="/styles.css" />',
  `<style>\n${styles}\n</style>`,
  'подключение стилей',
);

html = replaceOnce(
  html,
  '<script type="module" src="/js/app.js"></script>',
  [
    '<script type="application/json" id="srd-data">',
    JSON.stringify(srd).replace(/</g, '\\u003c'),
    '</script>',
    '<script type="module">',
    '// Справочник SRD вшит в страницу: движок читает его отсюда вместо диска.',
    "globalThis.__SRD__ = JSON.parse(document.getElementById('srd-data').textContent);",
    bundle,
    '</script>',
  ].join('\n'),
  'подключение скрипта',
);

html = html.replace(
  '<title>Мастер подземелий — D&D в чате</title>',
  '<title>Мастер подземелий — D&D в чате</title>\n    <meta name="description" content="Настольная D&D 5e в чате с мастером-нейросетью. Один файл, всё внутри." />',
);

// Справочник уезжает вместе с файлом, поэтому атрибуция CC-BY должна ехать с ним.
html = `<!--\n${ATTRIBUTION.trim()}\n-->\n${html}`;

const outFile = path.join(root, OUTPUT);
fs.writeFileSync(outFile, html);

const kb = (bytes) => `${(bytes / 1024).toFixed(0)} КБ`;
console.log(`Собрано: ${OUTPUT} — ${kb(Buffer.byteLength(html))}`);
console.log(`  модулей: ${modules.size}, справочник SRD: ${kb(Buffer.byteLength(JSON.stringify(srd)))}`);
