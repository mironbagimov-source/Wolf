// Кто именно ведёт партию.
//
// Кубики, правила, карты и листы движок считает сам. Придумывать историю — дело
// ведущего, и вот его можно выбрать:
//
//   offline — встроенный мастер. Не нейросеть, а правила: поход по комнатам,
//             разбор написанного по смыслу. Работает сразу и без настроек.
//   ollama  — модель на своём компьютере через Ollama. Бесплатно и офлайн.
//   openai  — любой сервер с OpenAI-совместимым API: LM Studio, llama.cpp, Jan.
//   claude  — Claude по ключу Anthropic. Лучший мастер, но за токены надо платить.
//
// Внутри игры история хранится в формате Anthropic — он самый выразительный из
// трёх. Адаптеры переводят её туда и обратно, поэтому провайдера можно менять
// посреди кампании: летопись и память мастера переживут переезд.

import * as claude from './claude.js';
import * as ollama from './ollama.js';
import * as openai from './openai.js';

// Встроенный мастер живёт не здесь — он не разговаривает по сети, а работает
// с состоянием стола напрямую (см. standalone/offline/dm.js). Провайдером он
// числится только затем, чтобы выбираться из того же списка.
const offline = {
  isReady: () => true,
  listModels: async () => [],
  chat: () => {
    throw new Error('Встроенный мастер не ходит по сети');
  },
};

const PROVIDERS = { offline, claude, ollama, openai };

export const settings = {
  provider: 'offline',

  // Claude
  apiKey: '',
  model: 'claude-opus-5',
  effort: 'medium',
  maxTokens: 16000,
  apiBase: 'https://api.anthropic.com',

  // Локальная модель
  localBase: 'http://localhost:11434',
  localModel: '',
  // Контекст: системный промпт с описанием инструментов — это примерно 4600
  // токенов ещё до первой реплики, поэтому обычных для Ollama 4096 не хватит.
  numCtx: 16384,
};

export function configure(patch) {
  Object.assign(settings, patch);
}

const provider = () => PROVIDERS[settings.provider] || claude;

/** Готов ли мастер вести: у Claude это ключ, у локальной модели — адрес и имя. */
export function isReady() {
  return provider().isReady(settings);
}

export function readyHint() {
  if (settings.provider === 'offline') return '';
  if (settings.provider === 'claude') return 'Впиши ключ Anthropic API в настройках стола.';
  return 'Укажи в настройках стола адрес локальной модели и выбери саму модель.';
}

export const isOffline = () => settings.provider === 'offline';

/**
 * Один запрос к мастеру.
 *
 * `snapshot` передаётся отдельно от истории: Claude принимает его последним
 * сообщением, чтобы закэшированная часть запроса не менялась, а локальные
 * модели — в конце системного промпта, потому что не всякий шаблон чата
 * переживает системное сообщение в середине разговора.
 */
export function chat(request) {
  return provider().chat(settings, request);
}

/** Список моделей, которые сервер готов запустить прямо сейчас. */
export function listModels() {
  return provider().listModels(settings);
}
