// Заглушка node:path: ровно те две функции, которыми пользуется движок, и
// только для того, чтобы выражения с путями не падали при разборе.

export const join = (...parts) => parts.filter(Boolean).join('/');
export const dirname = (target) => String(target).replace(/\/[^/]*$/, '');
export const basename = (target) => String(target).split('/').pop();

export default { join, dirname, basename };
