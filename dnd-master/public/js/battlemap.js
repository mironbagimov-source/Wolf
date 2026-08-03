// Боевая карта: тайлы, свет факелов, туман войны, фишки и перемещение.
//
// Разведанное рисуется целиком, но освещается по расстоянию до ближайшего
// героя: рядом — тёплый свет, дальше — «по памяти», за пределом разведки —
// темнота. Фишки едут в новую клетку плавно, а не телепортируются.

import { el, qs, clear } from './dom.js';
import { icon } from './icons.js';

const TILE_COLORS = {
  '#': '#2b241c',
  '.': '#43392c',
  '+': '#8a5a26',
  '~': '#1d3a55',
  ':': '#4d4335',
  X: '#0a0908',
  '>': '#6a6152',
  '"': '#28361f',
  T: '#1b3a1c',
  O: '#5b5346',
  n: '#5f4526',
  b: '#4a3a4e',
  c: '#7d5a1c',
  A: '#5d5449',
  '*': '#7a3213',
};

const GLYPHS = {
  '+': '▯',
  '~': '≈',
  ':': '·',
  '>': '≡',
  T: '♣',
  O: '●',
  n: '▬',
  b: '▭',
  c: '▣',
  A: '⌂',
  '*': '✶',
};

const LIT_RADIUS = 5; // клеток вокруг героя, где светло
const FADE_RANGE = 6; // на сколько клеток свет угасает до «памяти»

const state = {
  map: null,
  myId: null,
  selected: false,
  hover: null,
  cell: 20,
  onMove: null,
  positions: new Map(), // id -> {x, y} — экранные позиции для анимации
  raf: null,
};

let canvas = null;
let ctx = null;

export function initMap({ onMove }) {
  state.onMove = onMove;
  window.addEventListener('resize', () => {
    if (state.map) render(state.map, state.myId);
  });
}

function ensureCanvas() {
  if (canvas && canvas.isConnected) return;
  const container = clear(qs('#map-container'));
  const frame = el('div', { class: 'map-frame' });
  canvas = el('canvas', { id: 'map-canvas' });
  frame.append(canvas);
  container.append(el('div', { class: 'map-head' }, [el('span', { class: 'map-title', id: 'map-title' }, '')]), frame);
  ctx = canvas.getContext('2d');
  bindPointer();
}

function bindPointer() {
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
    const mine = state.map.tokens.find((t) => t.id === state.myId);
    if (!mine) return;

    if (!state.selected) {
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

export function render(map, myId) {
  const previous = state.map;
  state.map = map;
  state.myId = myId;

  if (!map) {
    state.positions.clear();
    const container = clear(qs('#map-container'));
    container.append(
      el('div', { class: 'map-frame' }, [
        el('div', { class: 'map-empty' }, [
          icon('map', { size: 34 }),
          el('div', {}, 'Карты пока нет'),
          el('div', { class: 'hint', style: { margin: '6px 0 0' } }, 'Мастер выложит её, когда дойдёт до боя или подземелья.'),
        ]),
      ]),
    );
    canvas = null;
    updateHint();
    return;
  }

  ensureCanvas();
  qs('#map-title').textContent = map.title;

  // Новая карта — фишки появляются на месте, без «полёта» через весь экран.
  if (!previous || previous.id !== map.id) state.positions.clear();
  for (const token of map.tokens) {
    if (!state.positions.has(token.id)) state.positions.set(token.id, { x: token.x, y: token.y });
  }
  for (const id of [...state.positions.keys()]) {
    if (!map.tokens.some((t) => t.id === id)) state.positions.delete(id);
  }

  const available = canvas.parentElement.clientWidth || 360;
  state.cell = Math.max(9, Math.floor((available - 2) / map.width));
  canvas.width = state.cell * map.width;
  canvas.height = state.cell * map.height;
  canvas.style.width = `${canvas.width}px`;

  animate();
  updateHint();
}

/** Плавное движение фишек: тянемся к целевым клеткам, пока не доедем. */
function animate() {
  if (state.raf) cancelAnimationFrame(state.raf);
  const step = () => {
    let moving = false;
    for (const token of state.map?.tokens || []) {
      const position = state.positions.get(token.id);
      if (!position) continue;
      const dx = token.x - position.x;
      const dy = token.y - position.y;
      if (Math.abs(dx) < 0.02 && Math.abs(dy) < 0.02) {
        position.x = token.x;
        position.y = token.y;
        continue;
      }
      position.x += dx * 0.22;
      position.y += dy * 0.22;
      moving = true;
    }
    draw();
    state.raf = moving ? requestAnimationFrame(step) : null;
  };
  step();
}

/** Детерминированный шум по клетке: камень не выглядит залитым одним цветом. */
function cellNoise(x, y) {
  const value = Math.sin(x * 127.1 + y * 311.7) * 43758.5453;
  return value - Math.floor(value);
}

/** Освещённость клетки: 1 — под факелом, 0.32 — разведано, но темно. */
function lightAt(x, y, heroes) {
  if (heroes.length === 0) return 0.55;
  let best = Infinity;
  for (const hero of heroes) {
    const distance = Math.max(Math.abs(hero.x - x), Math.abs(hero.y - y));
    if (distance < best) best = distance;
  }
  if (best <= LIT_RADIUS) return 1;
  return Math.max(0.46, 1 - (best - LIT_RADIUS) / FADE_RANGE);
}

function draw() {
  const map = state.map;
  if (!map || !ctx) return;
  const cell = state.cell;
  const heroes = map.tokens.filter((t) => t.kind === 'pc').map((t) => state.positions.get(t.id) || t);

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  for (let y = 0; y < map.height; y += 1) {
    for (let x = 0; x < map.width; x += 1) {
      const px = x * cell;
      const py = y * cell;

      if (map.revealed[y][x] !== '1') {
        ctx.fillStyle = '#070605';
        ctx.fillRect(px, py, cell, cell);
        ctx.strokeStyle = 'rgba(217,180,81,0.028)';
        ctx.strokeRect(px + 0.5, py + 0.5, cell - 1, cell - 1);
        continue;
      }

      const tile = map.grid[y][x];
      ctx.fillStyle = TILE_COLORS[tile] || '#43392c';
      ctx.fillRect(px, py, cell, cell);

      // Лёгкая крапина, чтобы плоскость не читалась заливкой
      const noise = cellNoise(x, y);
      ctx.fillStyle = noise > 0.5 ? 'rgba(255,255,255,0.022)' : 'rgba(0,0,0,0.045)';
      ctx.fillRect(px, py, cell, cell);

      // У стен подсвеченная верхняя грань — появляется объём
      if (tile === '#') {
        ctx.fillStyle = 'rgba(255,225,170,0.05)';
        ctx.fillRect(px, py, cell, Math.max(1, cell * 0.12));
      } else {
        ctx.strokeStyle = 'rgba(255,255,255,0.035)';
        ctx.strokeRect(px + 0.5, py + 0.5, cell - 1, cell - 1);
      }

      const glyph = GLYPHS[tile];
      if (glyph && cell >= 12) {
        ctx.font = `${Math.floor(cell * 0.6)}px serif`;
        ctx.fillStyle = 'rgba(255,240,215,0.3)';
        ctx.fillText(glyph, px + cell / 2, py + cell / 2 + 1);
      }

      // Темнота поверх: чем дальше от героев, тем глуше
      const shade = 1 - lightAt(x, y, heroes);
      if (shade > 0.001) {
        ctx.fillStyle = `rgba(4,3,2,${shade * 0.72})`;
        ctx.fillRect(px, py, cell, cell);
      }
    }
  }

  // Тёплое пятно света вокруг каждого героя
  ctx.globalCompositeOperation = 'lighter';
  for (const hero of heroes) {
    const cx = (hero.x + 0.5) * cell;
    const cy = (hero.y + 0.5) * cell;
    const radius = cell * (LIT_RADIUS + 1);
    const glow = ctx.createRadialGradient(cx, cy, cell * 0.5, cx, cy, radius);
    glow.addColorStop(0, 'rgba(230,170,70,0.16)');
    glow.addColorStop(0.5, 'rgba(210,140,50,0.06)');
    glow.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = glow;
    ctx.fillRect(cx - radius, cy - radius, radius * 2, radius * 2);
  }
  ctx.globalCompositeOperation = 'source-over';

  const mine = map.tokens.find((t) => t.id === state.myId);

  if (state.selected && mine && state.hover) {
    const distance = Math.max(Math.abs(mine.x - state.hover.x), Math.abs(mine.y - state.hover.y)) * 5;
    const reachable = distance <= 30;
    ctx.fillStyle = reachable ? 'rgba(95,212,138,0.2)' : 'rgba(239,68,68,0.16)';
    ctx.fillRect(state.hover.x * cell, state.hover.y * cell, cell, cell);
    ctx.strokeStyle = reachable ? 'rgba(95,212,138,0.6)' : 'rgba(239,68,68,0.5)';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(state.hover.x * cell + 0.75, state.hover.y * cell + 0.75, cell - 1.5, cell - 1.5);
  } else if (state.hover && map.revealed[state.hover.y]?.[state.hover.x] === '1') {
    ctx.strokeStyle = 'rgba(217,180,81,0.35)';
    ctx.lineWidth = 1;
    ctx.strokeRect(state.hover.x * cell + 0.5, state.hover.y * cell + 0.5, cell - 1, cell - 1);
  }

  for (const token of map.tokens) {
    const position = state.positions.get(token.id) || token;
    const gridX = Math.round(position.x);
    const gridY = Math.round(position.y);
    if (map.revealed[gridY]?.[gridX] !== '1') continue;

    const cx = (position.x + 0.5) * cell;
    const cy = (position.y + 0.5) * cell;
    const radius = cell * 0.38;
    const isMine = token.id === state.myId;

    // Тень под фишкой — она «стоит» на полу, а не наклеена
    ctx.beginPath();
    ctx.ellipse(cx, cy + radius * 0.55, radius * 0.85, radius * 0.35, 0, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.fill();

    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.fillStyle = token.color || '#c2410c';
    ctx.fill();

    ctx.beginPath();
    ctx.arc(cx, cy, radius, 0, Math.PI * 2);
    ctx.strokeStyle = isMine ? (state.selected ? '#f6e3a8' : 'rgba(255,240,210,0.85)') : 'rgba(0,0,0,0.6)';
    ctx.lineWidth = isMine ? (state.selected ? 2.5 : 1.8) : 1.4;
    ctx.stroke();

    if (cell >= 14) {
      ctx.font = `600 ${Math.floor(cell * 0.4)}px system-ui, sans-serif`;
      ctx.fillStyle = 'rgba(10,8,6,0.85)';
      ctx.fillText(String(token.label || token.name).slice(0, 2), cx, cy + 1);
    }
  }
}

function updateHint() {
  const hint = qs('#map-hint');
  if (!hint) return;
  if (!state.map) {
    hint.textContent = '';
    return;
  }
  const mine = state.map.tokens.find((t) => t.id === state.myId);
  if (!mine) {
    hint.textContent = 'Твоей фишки на этой карте нет.';
    return;
  }
  if (state.selected) {
    const target = state.hover
      ? ` → (${state.hover.x},${state.hover.y}), ${Math.max(Math.abs(mine.x - state.hover.x), Math.abs(mine.y - state.hover.y)) * 5} фт.`
      : '';
    hint.textContent = `Фишка взята${target}. Клик — переместиться.`;
    return;
  }
  hint.textContent = 'Клик по своей фишке — взять её, второй клик — переместиться. Клетка = 5 футов.';
}
