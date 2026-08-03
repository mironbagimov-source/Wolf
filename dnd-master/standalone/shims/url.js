// Заглушка node:url.

export const fileURLToPath = (url) => String(url).replace(/^file:\/\//, '');

export default { fileURLToPath };
