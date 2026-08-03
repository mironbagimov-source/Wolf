// Мелкие помощники, чтобы не тащить фреймворк ради пары списков.

export const qs = (selector, root = document) => root.querySelector(selector);
export const qsa = (selector, root = document) => [...root.querySelectorAll(selector)];

/** el('div', {class:'x', onclick}, ['текст', el('b', {}, 'жирный')]) */
export function el(tag, props = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key === 'style' && typeof value === 'object') {
      for (const [property, setting] of Object.entries(value)) {
        // Пользовательские свойства (--accent) через присваивание не ставятся.
        if (property.startsWith('--')) node.style.setProperty(property, setting);
        else node.style[property] = setting;
      }
    }
    else if (key.startsWith('on') && typeof value === 'function') node.addEventListener(key.slice(2), value);
    else if (key === 'dataset') Object.assign(node.dataset, value);
    else if (key in node && key !== 'list') node[key] = value;
    else node.setAttribute(key, value);
  }
  for (const child of [].concat(children)) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

export function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
  return node;
}

let toastTimer = null;
export function toast(text) {
  const node = qs('#toast');
  node.textContent = text;
  node.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => node.classList.add('hidden'), 4000);
}

export function showScreen(id) {
  qsa('.screen').forEach((s) => s.classList.toggle('active', s.id === id));
}

/** Очень маленький разбор разметки: **жирный**, *курсив*, «реплики» уже есть в тексте. */
export function renderRich(text) {
  const fragment = document.createDocumentFragment();
  const pattern = /(\*\*[^*]+\*\*|\*[^*\n]+\*)/g;
  let last = 0;
  let match;
  while ((match = pattern.exec(text))) {
    if (match.index > last) fragment.append(text.slice(last, match.index));
    const token = match[0];
    if (token.startsWith('**')) fragment.append(el('strong', {}, token.slice(2, -2)));
    else fragment.append(el('em', {}, token.slice(1, -1)));
    last = match.index + token.length;
  }
  if (last < text.length) fragment.append(text.slice(last));
  return fragment;
}
