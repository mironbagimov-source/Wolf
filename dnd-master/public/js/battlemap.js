// Боевая карта на canvas: тайлы, туман войны, фишки и перемещение своей фишки.

import { qs } from './dom.js';

const TILE_COLORS = {
  '#': '#262932',
  '.': '#3a352d',
  '+': '#8b5a2b',
  '~': '#1c3a5c',
  ':': '#4a4238',
  X: '#08090c',
  '>': '#6b7280',
  '"': '#22321e',
  T: '#15381a',
  O: '#53565e',
  n: '#5c4326',
  b: '#4a3a52',
  c: '#7c5a1e',
  A: '#5b5148',
  '*': '#7c2d12',
};

const GLYPHS = {
  '+': '▯',
  '~': '≈',
  ':': '▪',
  X: '',
  '>': '≡',
  T: '♣',
  O: '●',
  n: '▬',
  b: '▭',
  c: '▣',
  A: '⌂',
  '*': '✶',
};

const state = {
  map: null,
  myCharacterId: null,
  selected: false,
  hover: null,
  cell: 20,
  onMove: null,
};

let canvas = null;
let ctx = null;

export function initMap({ onMove }) {
  canvas = qs('#map-canvas');
  ctx = canvas.getContext('2d');
  state.onMove = onMove;

  canvas.addEventListener('mousemove', (event) => {
    const cell = cellAt(event);
    if (!cell) return;
    if (!state.hover || state.hover.x !== cell.x || state.hover.y !== cell.y) {
      state.hover = cell;
      draw();
      updateHint();
    }
  });

  canvas.addEventListener('mouseleave', () => {
    state.hover = null;
    draw();
  });

  canvas.addEventListener('click', (event) => {
    const cell = cellAt(event);
    if (!cell || !state.map) return;
    const mine = state.map.tokens.find((t) => t.id === state.myCharacterId);
    if (!mine) return;

    if (!state.selected) {
      // Первый клик по своей фишке — взять её.
      if (mine.x === cell.x && mine.y === cell.y) {
        state.selected = true;
        draw();
        updateHint();
      }
      return;
    }
    state.selected = false;
    state.onMove?.(cell.x, cell.y);
    draw();
    updateHint();
  });

  window.addEventListener('resize', () => {
    if (state.map) render(state.map, state.myCharacterId);
  });
}

function cellAt(event) {
  if (!state.map) return null;
  const rect = canvas.getBoundingClientRect();
  const scale = canvas.width / rect.width;
  const x = Math.floor(((event.clientX - rect.left) * scale) / state.cell);
  const y = Math.floor(((event.clientY - rect.top) * scale) / state.cell);
  if (x < 0 || y < 0 || x >= state.map.width || y >= state.map.height) return null;
  return { x, y };
}

export function render(map, myCharacterId) {
  state.map = map;
  state.myCharacterId = myCharacterId;

  const title = qs('#map-title');
  if (!map) {
    title.textContent = 'Карты пока нет';
    if (ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
    canvas.height = 0;
    updateHint();
    return;
  }

  title.textContent = map.title;
  const available = canvas.parentElement.clientWidth || 380;
  // Целые пиксели на клетку — иначе сетка «плывёт».
  state.cell = Math.max(10, Math.floor(available / map.width));
  canvas.width = state.cell * map.width;
  canvas.height = state.cell * map.height;
  canvas.style.width = `${canvas.width}px`;
  draw();
  updateHint();
}

function draw() {
  const map = state.map;
  if (!map || !ctx) return;
  const cell = state.cell;

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.font = `${Math.floor(cell * 0.62)}px sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  for (let y = 0; y < map.height; y += 1) {
    for (let x = 0; x < map.width; x += 1) {
      const revealed = map.revealed[y][x] === '1';
      const tile = map.grid[y][x];
      const px = x * cell;
      const py = y * cell;

      if (!revealed) {
        // Неразведанное всё равно рисуем сеткой: видно размер карты и то,
        // сколько ещё осталось, но не видно, что там.
        ctx.fillStyle = '#0a0b0e';
        ctx.fillRect(px, py, cell, cell);
        ctx.strokeStyle = 'rgba(255,255,255,0.03)';
        ctx.strokeRect(px + 0.5, py + 0.5, cell - 1, cell - 1);
        continue;
      }

      ctx.fillStyle = TILE_COLORS[tile] || '#3a352d';
      ctx.fillRect(px, py, cell, cell);

      const glyph = GLYPHS[tile];
      if (glyph) {
        ctx.fillStyle = 'rgba(255,255,255,0.28)';
        ctx.fillText(glyph, px + cell / 2, py + cell / 2 + 1);
      }

      // Сетка только по проходимым клеткам — стены читаются как масса.
      if (tile !== '#') {
        ctx.strokeStyle = 'rgba(255,255,255,0.055)';
        ctx.strokeRect(px + 0.5, py + 0.5, cell - 1, cell - 1);
      }
    }
  }

  const mine = map.tokens.find((t) => t.id === state.myCharacterId);

  // Подсветка пути и дистанции от своей фишки.
  if (state.selected && mine && state.hover) {
    const distance = Math.max(Math.abs(mine.x - state.hover.x), Math.abs(mine.y - state.hover.y)) * 5;
    ctx.fillStyle = distance <= 30 ? 'rgba(134,239,172,0.22)' : 'rgba(248,113,113,0.18)';
    ctx.fillRect(state.hover.x * cell, state.hover.y * cell, cell, cell);
  }

  for (const token of map.tokens) {
    if (map.revealed[token.y]?.[token.x] !== '1') continue;
    const cx = token.x * cell + cell / 2;
    const cy = token.y * cell + cell / 2;
    const radius = cell * 0.4;

    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fillStyle = token.color || '#dc2626';
    ctx.fill();

    if (token.id === state.myCharacterId) {
      ctx.strokeStyle = state.selected ? '#fde68a' : '#e5e7eb';
      ctx.lineWidth = state.selected ? 3 : 2;
    } else {
      ctx.strokeStyle = 'rgba(0,0,0,0.55)';
      ctx.lineWidth = 1.5;
    }
    ctx.stroke();

    ctx.fillStyle = '#0b0c10';
    ctx.font = `600 ${Math.floor(cell * 0.42)}px sans-serif`;
    ctx.fillText(String(token.label || token.name).slice(0, 2), cx, cy + 1);
    ctx.font = `${Math.floor(cell * 0.62)}px sans-serif`;
  }
}

function updateHint() {
  const hint = qs('#map-hint');
  if (!state.map) {
    hint.textContent = 'Мастер создаст карту, когда дойдёт до боя или подземелья.';
    return;
  }
  const mine = state.map.tokens.find((t) => t.id === state.myCharacterId);
  if (!mine) {
    hint.textContent = 'Твоей фишки на этой карте нет.';
    return;
  }
  if (state.selected) {
    const target = state.hover
      ? ` → (${state.hover.x},${state.hover.y}), ${Math.max(Math.abs(mine.x - state.hover.x), Math.abs(mine.y - state.hover.y)) * 5} фт.`
      : '';
    hint.textContent = `Фишка взята${target}. Клик — переместить.`;
    return;
  }
  hint.textContent = 'Клик по своей фишке — взять её, второй клик — переместиться. Клетка = 5 футов.';
}
