// Дорога до локального сервера модели — и разбор того, почему по ней не проехать.
//
// Браузер прячет причину сетевой ошибки: и «сервер не запущен», и «сервер
// запретил обращаться со страницы, открытой с диска» приходят одинаковым
// TypeError без подробностей. А чинятся они по-разному, поэтому диагноз тут
// ставится отдельно — иначе игрок остаётся один на один с «Failed to fetch».

/**
 * На многих системах localhost сначала резолвится в ::1, а Ollama и LM Studio
 * слушают 127.0.0.1 — получается отказ на ровном месте. Пробуем оба адреса.
 */
const alternate = (base) => base.replace('//localhost', '//127.0.0.1');

/** @returns {{response: Response, base: string}} base — адрес, который сработал. */
export async function localFetch(base, path, init) {
  try {
    return { response: await fetch(base + path, init), base };
  } catch (cause) {
    const other = alternate(base);
    if (other !== base) {
      try {
        return { response: await fetch(other + path, init), base: other };
      } catch {
        // И по второму адресу тишина — значит, дело не в имени хоста.
      }
    }
    throw await diagnose(base, cause);
  }
}

/**
 * Жив ли сервер вообще. Запрос в режиме no-cors уходит без проверки заголовков
 * и доходит до сервера, даже если тот запрещает читать ответ, — поэтому он
 * отличает «не запущен» от «запущен, но не пускает».
 */
export async function probe(base) {
  for (const candidate of [base, alternate(base)]) {
    try {
      await fetch(candidate, { mode: 'no-cors', cache: 'no-store' });
      return { alive: true, base: candidate };
    } catch {
      // Пробуем следующий адрес.
    }
  }
  return { alive: false, base };
}

async function diagnose(base, cause) {
  const { alive, base: reachable } = await probe(base);
  if (alive) {
    return new Error(
      `Сервер по адресу ${reachable} отвечает, но не пускает страницу, открытую с диска: ` +
        'у файла с диска нет привычного адреса, и по умолчанию такие запросы отклоняются. ' +
        'Ollama надо перезапустить командой OLLAMA_ORIGINS="*" ollama serve, ' +
        'в LM Studio — включить CORS в настройках сервера.',
    );
  }
  return new Error(
    `По адресу ${base} никто не отвечает. Модели внутри этого файла нет — он умеет только позвать ту, ` +
      'что уже запущена на компьютере. Поставь Ollama с ollama.com, скачай модель командой ' +
      '"ollama pull qwen3:8b" и запусти сервер: OLLAMA_ORIGINS="*" ollama serve. ' +
      `Если сервер уже работает, проверь адрес и порт. (${cause.message})`,
  );
}
