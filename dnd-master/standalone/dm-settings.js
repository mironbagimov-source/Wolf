// Настройка мастера: кто ведёт партию и как до него достучаться.
//
// Блок один на всё приложение и физически переезжает между лобби и окном
// настроек стола. Так у полей одни и те же идентификаторы и один набор
// обработчиков — а игрок видит настройку там, где она ему понадобилась:
// при первом запуске в лобби, посреди игры — в настройках.

import { el, qs, clear } from '../public/js/dom.js';
import { icon } from '../public/js/icons.js';
import * as agent from './agent.js';

const PROVIDERS = [
  {
    id: 'offline',
    name: 'Встроенный мастер — работает сразу',
    hint:
      'Ведёт партию сам файл: генерирует поход, водит бой, считает кубики. Нейросети в нём нет, ' +
      'поэтому он не выдумает поворот сюжета — зато не требует ни ключа, ни установки, ни сети. ' +
      'Понимает, что вы делаете, по смыслу написанного: «иду дальше», «осматриваю», «бью его», «привал».',
  },
  {
    id: 'ollama',
    name: 'Своя модель через Ollama — бесплатно',
    base: 'http://localhost:11434',
    hint:
      'Поставь Ollama (ollama.com), скачай модель с поддержкой инструментов — например ' +
      '«ollama pull qwen3:8b» — и запусти сервер так, чтобы он пускал страницы с диска: ' +
      'OLLAMA_ORIGINS="*" ollama serve',
  },
  {
    id: 'openai',
    name: 'Своя модель через LM Studio и подобные',
    base: 'http://localhost:1234/v1',
    hint:
      'Подойдёт любой сервер с OpenAI-совместимым API: LM Studio, llama.cpp server, Jan, ' +
      'LocalAI. Включи в нём CORS, иначе страница с диска до него не достучится.',
  },
  {
    id: 'claude',
    name: 'Claude по ключу Anthropic — лучший мастер',
    hint:
      'Ключ берётся на console.anthropic.com → API keys. Он хранится только в этом браузере ' +
      'и уходит только на api.anthropic.com. Токены платные.',
  },
];

const EFFORTS = [
  { id: 'low', name: 'коротко — ходы быстрые' },
  { id: 'medium', name: 'обычно' },
  { id: 'high', name: 'вдумчиво — мастер думает дольше' },
];

const STORE = {
  provider: 'dnd.solo.provider',
  key: 'dnd.solo.key',
  model: 'dnd.solo.model',
  effort: 'dnd.solo.effort',
  localBase: 'dnd.solo.localBase',
  localModel: 'dnd.solo.localModel',
  numCtx: 'dnd.solo.numCtx',
};

export const remember = (name, value) => {
  try {
    localStorage.setItem(name, String(value));
  } catch {
    /* приватный режим — переживём */
  }
};
const recall = (name, fallback = '') => {
  try {
    return localStorage.getItem(name) ?? fallback;
  } catch {
    return fallback;
  }
};

let onChange = () => {};
let modelsLoaded = null; // для какого адреса уже тянули список

/** Поднимает сохранённые настройки до того, как что-то нарисуется. */
export function restoreSettings() {
  agent.configure({
    provider: recall(STORE.provider, 'offline'),
    apiKey: recall(STORE.key),
    model: recall(STORE.model, 'claude-opus-5'),
    effort: recall(STORE.effort, 'medium'),
    localBase: recall(STORE.localBase, 'http://localhost:11434'),
    localModel: recall(STORE.localModel),
    numCtx: Number(recall(STORE.numCtx, 16384)) || 16384,
  });
}

function save() {
  remember(STORE.provider, agent.settings.provider);
  remember(STORE.key, agent.settings.apiKey);
  remember(STORE.model, agent.settings.model);
  remember(STORE.effort, agent.settings.effort);
  remember(STORE.localBase, agent.settings.localBase);
  remember(STORE.localModel, agent.settings.localModel);
  remember(STORE.numCtx, agent.settings.numCtx);
  onChange();
}

// --------------------------------------------------------------- разметка

export function initDmSettings({ onChange: handler }) {
  onChange = handler || (() => {});
  render();
}

/** Переносит блок настроек в окно стола и обратно в лобби. */
export function moveDmSettings(intoSelector) {
  const block = qs('#dm-config');
  if (block) qs(intoSelector).append(block);
}

const local = () => agent.settings.provider === 'ollama' || agent.settings.provider === 'openai';
const offline = () => agent.settings.provider === 'offline';
const currentProvider = () => PROVIDERS.find((p) => p.id === agent.settings.provider) || PROVIDERS[0];

function render() {
  const host = qs('#dm-config') || el('div', { id: 'dm-config' });
  if (!host.parentNode) qs('#dm-home').append(host);
  clear(host);

  host.append(
    field('Мастер', select('dm-provider', PROVIDERS, agent.settings.provider, (value) => {
      const preset = PROVIDERS.find((p) => p.id === value);
      agent.configure({ provider: value, ...(preset?.base ? { localBase: preset.base } : {}) });
      modelsLoaded = null;
      save();
      render();
      if (local()) loadModels();
    })),
    el('span', { class: 'hint' }, currentProvider().hint),
  );

  if (offline()) {
    host.append(el('span', { class: 'hint good', id: 'dm-state' }, 'Мастер готов вести прямо сейчас — ничего настраивать не нужно.'));
    return;
  }

  if (local()) {
    host.append(
      field('Адрес сервера', input('local-base', agent.settings.localBase, 'text', (value) => {
        agent.configure({ localBase: value.trim() });
        modelsLoaded = null;
        save();
        loadModels();
      })),
      el('label', {}, [
        'Модель',
        el('div', { class: 'with-button' }, [
          select('local-model', modelOptions(), agent.settings.localModel, (value) => {
            agent.configure({ localModel: value });
            save();
          }),
          el(
            'button',
            { class: 'ghost icon-btn', id: 'local-refresh', title: 'Обновить список моделей', onclick: () => loadModels(true) },
            [icon('refresh', { size: 15 })],
          ),
        ]),
      ]),
      field(
        'Размер контекста',
        input('local-ctx', String(agent.settings.numCtx), 'number', (value) => {
          agent.configure({ numCtx: Math.max(4096, Number(value) || 16384) });
          save();
        }),
      ),
      el(
        'span',
        { class: 'hint' },
        'Правила и инструменты занимают около 4600 токенов ещё до первой реплики, ' +
          'так что меньше 8192 ставить бессмысленно. Больше — точнее память мастера, но и памяти компьютера надо больше.',
      ),
    );
    if (!modelsLoaded) loadModels();
  } else {
    host.append(
      field('Ключ', input('api-key', agent.settings.apiKey, 'password', (value) => {
        agent.configure({ apiKey: value.trim() });
        save();
      })),
      field('Модель', select('api-model', claudeModels(), agent.settings.model, (value) => {
        agent.configure({ model: value });
        save();
      })),
      field('Сколько мастер думает', select('api-effort', EFFORTS, agent.settings.effort, (value) => {
        agent.configure({ effort: value });
        save();
      })),
    );
  }

  host.append(el('span', { class: 'hint', id: 'dm-state' }, ''));
  refreshState();
}

const field = (label, control) => el('label', {}, [label, control]);

function input(id, value, type, handler) {
  return el('input', {
    id,
    type,
    value,
    autocomplete: 'off',
    ...(type === 'password' ? { placeholder: 'sk-ant-...' } : {}),
    onchange: (event) => handler(event.target.value),
  });
}

function select(id, items, selected, handler) {
  const node = el('select', { id, onchange: (event) => handler(event.target.value) });
  for (const item of items) {
    node.append(el('option', { value: item.id, selected: item.id === selected }, item.name));
  }
  if (!items.some((i) => i.id === selected) && items.length) node.value = items[0].id;
  return node;
}

const claudeModels = () => [
  { id: 'claude-opus-5', name: 'Opus 5 — лучший мастер' },
  { id: 'claude-sonnet-5', name: 'Sonnet 5 — быстрее и дешевле' },
  { id: 'claude-haiku-4-5-20251001', name: 'Haiku 4.5 — самый быстрый' },
];

let discovered = [];

function modelOptions() {
  if (discovered.length) return discovered;
  const current = agent.settings.localModel;
  return current ? [{ id: current, name: current }] : [{ id: '', name: '— сначала найдём модели —' }];
}

/** Спрашивает у локального сервера, что он умеет запускать. */
async function loadModels(force = false) {
  const base = agent.settings.localBase;
  if (!base || (modelsLoaded === base && !force)) return;
  modelsLoaded = base;

  setState('ищу модели…', null);
  try {
    const models = await agent.listModels();
    discovered = models;
    if (!models.length) {
      return setState('Сервер отвечает, но моделей в нём нет. Скачай хотя бы одну — например: ollama pull qwen3:8b', false);
    }
    // Раньше выбранная модель могла исчезнуть — тогда берём первую попавшуюся.
    if (!models.some((m) => m.id === agent.settings.localModel)) {
      agent.configure({ localModel: models[0].id });
      remember(STORE.localModel, agent.settings.localModel);
    }
    const node = qs('#local-model');
    if (node) {
      clear(node);
      for (const model of models) {
        node.append(el('option', { value: model.id, selected: model.id === agent.settings.localModel }, model.name));
      }
    }
    onChange();
    refreshState();
  } catch (e) {
    discovered = [];
    modelsLoaded = null;
    setState(e.message, false);
  }
}

function setState(text, good) {
  const node = qs('#dm-state');
  if (!node) return;
  node.textContent = text;
  node.classList.toggle('good', good === true);
  node.classList.toggle('bad', good === false);
}

export function refreshState() {
  if (offline()) {
    return setState('Мастер готов вести прямо сейчас — ничего настраивать не нужно.', true);
  }
  if (!agent.isReady()) {
    return setState(
      local()
        ? 'Мастер пока не настроен: нужен работающий сервер и выбранная модель. Играть можно и так — правила с кубиками работают без него.'
        : 'Мастер пока не настроен: без ключа он молчит. Правила и кубики работают в любом случае.',
      false,
    );
  }
  setState(
    local()
      ? `Мастера ведёт «${agent.settings.localModel}» на твоём компьютере. Ничего наружу не уходит.`
      : 'Ключ сохранён в этом браузере — мастер готов вести.',
    true,
  );
}
