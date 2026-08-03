// Заглушка node:fs. В однофайловой сборке до диска дело не доходит: справочник
// SRD вшит в страницу, а сохранения кампаний живут в localStorage.
//
// Функции не убраны насовсем, а честно падают: если движок вдруг полезет на
// диск, лучше увидеть внятную ошибку, чем тихо получить пустоту.

const unavailable = () => {
  throw new Error('Файловая система недоступна в браузерной сборке');
};

export const existsSync = () => false;
export const readFileSync = unavailable;
export const writeFileSync = unavailable;
export const renameSync = unavailable;
export const unlinkSync = unavailable;
export const mkdirSync = unavailable;
export const readdirSync = () => [];

export default { existsSync, readFileSync, writeFileSync, renameSync, unlinkSync, mkdirSync, readdirSync };
