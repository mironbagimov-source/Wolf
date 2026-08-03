// Подмена public/js/net.js в однофайловой сборке.
//
// Игровой экран не знает, где стоит стол: он просто зовёт net.send({t:'roll'}).
// В сетевой версии это уходит в веб-сокет, здесь — в соседний модуль в этой же
// вкладке. Благодаря этому game.js и battlemap.js остаются одни на две сборки.

let handler = () => {};

/** Стол подписывается сюда один раз при запуске. */
export function setHandler(fn) {
  handler = fn;
}

export function send(message) {
  handler(message);
}

// Дальше — заглушки ради совместимости формы модуля. Сетевой app.js в эту
// сборку не попадает, так что вызывать их некому.
export const identity = { playerId: null, playerName: '', lastTable: null };
export const on = () => () => {};
export const connect = () => {};
export const joinTable = () => {};
export const api = async () => {
  throw new Error('В однофайловой сборке нет сервера');
};
