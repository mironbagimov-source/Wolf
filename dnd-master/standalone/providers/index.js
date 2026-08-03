// Кто именно ведёт партию.
//
// Мастер — единственная часть игры, которую нельзя посчитать кодом: кубики,
// правила, карты и листы движок считает сам, а вот придумывать историю должна
// модель. Откуда её брать — выбор игроков:
//
//   claude — Claude по ключу Anthropic. Лучший мастер, но за токены надо платить.
//   ollama — модель на своём компьютере через Ollama. Бесплатно и офлайн.
//   openai — любой сервер с OpenAI-совместимым API: LM Studio, llama.cpp, Jan.
//
// Внутри игры история хранится в формате Anthropic — он самый выразительный из
// трёх. Адаптеры переводят её туда и обратно, поэтому провайдера можно менять
// посреди кампании: летопись и память мастера переживут переезд.

import * as claude from './claude.js';
import * as ollama from './ollama.js';
import * as openai from './openai.js';

const PROVIDERS = { claude, ollama, openai };

export const settings = {
  provider: 'claude',

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
  if (settings.provider === 'claude') return 'Впиши ключ Anthropic API в настройках стола.';
  return 'Укажи в настройках стола адрес локальной модели и выбери саму модель.';
}

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
