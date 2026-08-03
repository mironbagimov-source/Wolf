// Procedural battle maps: generation, tokens, movement and fog of war.
//
// Maps are generated rather than drawn so there are no art assets to license
// and the DM can conjure a room mid-scene. The grid is standard 5-foot squares,
// so distances line up with the rules in rules.js.

import { randomUUID, randomInt } from 'node:crypto';
import { gridDistance } from './rules.js';

export const TILE = {
  WALL: '#',
  FLOOR: '.',
  DOOR: '+',
  WATER: '~',
  RUBBLE: ':',
  CHASM: 'X',
  STAIRS: '>',
  GRASS: '"',
  TREE: 'T',
  PILLAR: 'O',
  TABLE: 'n',
  BED: 'b',
  CHEST: 'c',
  ALTAR: 'A',
  FIRE: '*',
};

const TILE_RU = {
  '#': 'стена',
  '.': 'пол',
  '+': 'дверь',
  '~': 'вода',
  ':': 'обломки (труднопроходимо)',
  X: 'провал',
  '>': 'лестница',
  '"': 'трава',
  T: 'дерево',
  O: 'колонна',
  n: 'стол',
  b: 'лежанка',
  c: 'сундук',
  A: 'алтарь',
  '*': 'огонь',
};

const BLOCKING = new Set([TILE.WALL, TILE.CHASM, TILE.TREE, TILE.PILLAR]);
const OPAQUE = new Set([TILE.WALL, TILE.TREE, TILE.PILLAR, TILE.DOOR]);
const DIFFICULT = new Set([TILE.RUBBLE, TILE.WATER, TILE.TABLE, TILE.BED]);

const rnd = (n) => randomInt(0, Math.max(1, n));
const pick = (arr) => arr[rnd(arr.length)];

const ROOM_NAMES = {
  dungeon: ['Караульная', 'Склад', 'Зал', 'Келья', 'Гробница', 'Колодец', 'Кузница', 'Библиотека', 'Тюрьма', 'Святилище'],
  cave: ['Грот', 'Расщелина', 'Полость', 'Зал сталактитов', 'Подземное озеро', 'Логово'],
  crypt: ['Склеп', 'Усыпальница', 'Ниша с урнами', 'Зал саркофагов', 'Часовня'],
  ruins: ['Обвалившийся зал', 'Двор', 'Галерея', 'Разрушенная башня', 'Терраса'],
  interior: ['Общий зал', 'Кухня', 'Кладовая', 'Спальня', 'Погреб', 'Кабинет'],
};

function blankGrid(width, height, fill) {
  return Array.from({ length: height }, () => Array.from({ length: width }, () => fill));
}

function carveRoom(grid, room, floor = TILE.FLOOR) {
  for (let y = room.y; y < room.y + room.h; y += 1) {
    for (let x = room.x; x < room.x + room.w; x += 1) {
      grid[y][x] = floor;
    }
  }
}

function overlaps(a, b, padding = 1) {
  return (
    a.x - padding < b.x + b.w &&
    a.x + a.w + padding > b.x &&
    a.y - padding < b.y + b.h &&
    a.y + a.h + padding > b.y
  );
}

function carveCorridor(grid, from, to) {
  let { x, y } = from;
  const horizontalFirst = rnd(2) === 0;
  const stepTo = (tx, ty) => {
    while (x !== tx) {
      x += Math.sign(tx - x);
      if (grid[y][x] === TILE.WALL) grid[y][x] = TILE.FLOOR;
    }
    while (y !== ty) {
      y += Math.sign(ty - y);
      if (grid[y][x] === TILE.WALL) grid[y][x] = TILE.FLOOR;
    }
  };
  if (horizontalFirst) stepTo(to.x, to.y);
  else {
    while (y !== to.y) {
      y += Math.sign(to.y - y);
      if (grid[y][x] === TILE.WALL) grid[y][x] = TILE.FLOOR;
    }
    stepTo(to.x, to.y);
  }
}

/** Rooms joined by corridors, with doors where a corridor pierces a wall. */
function generateDungeon(width, height, theme) {
  const grid = blankGrid(width, height, TILE.WALL);
  const rooms = [];
  const attempts = Math.floor((width * height) / 45);

  for (let i = 0; i < attempts && rooms.length < 9; i += 1) {
    const w = 4 + rnd(6);
    const h = 3 + rnd(5);
    const room = { x: 1 + rnd(width - w - 2), y: 1 + rnd(height - h - 2), w, h };
    if (rooms.some((r) => overlaps(room, r))) continue;
    room.name = ROOM_NAMES[theme]?.[rooms.length] || ROOM_NAMES.dungeon[rooms.length % ROOM_NAMES.dungeon.length];
    room.cx = room.x + Math.floor(room.w / 2);
    room.cy = room.y + Math.floor(room.h / 2);
    carveRoom(grid, room);
    rooms.push(room);
  }

  for (let i = 1; i < rooms.length; i += 1) {
    carveCorridor(grid, { x: rooms[i - 1].cx, y: rooms[i - 1].cy }, { x: rooms[i].cx, y: rooms[i].cy });
  }

  // A corridor square that touches a room edge becomes a door.
  for (const room of rooms) {
    for (let x = room.x - 1; x <= room.x + room.w; x += 1) {
      for (const y of [room.y - 1, room.y + room.h]) {
        if (grid[y]?.[x] === TILE.FLOOR && isDoorway(grid, x, y)) grid[y][x] = TILE.DOOR;
      }
    }
    for (let y = room.y - 1; y <= room.y + room.h; y += 1) {
      for (const x of [room.x - 1, room.x + room.w]) {
        if (grid[y]?.[x] === TILE.FLOOR && isDoorway(grid, x, y)) grid[y][x] = TILE.DOOR;
      }
    }
  }

  decorate(grid, rooms, theme);
  return { grid, rooms };
}

function isDoorway(grid, x, y) {
  const wall = (dx, dy) => grid[y + dy]?.[x + dx] === TILE.WALL;
  return (wall(-1, 0) && wall(1, 0)) || (wall(0, -1) && wall(0, 1));
}

/** Cellular-automata cave: organic blobs rather than boxes. */
function generateCave(width, height) {
  let grid = blankGrid(width, height, TILE.FLOOR).map((row, y) =>
    row.map((_, x) => (x === 0 || y === 0 || x === width - 1 || y === height - 1 || rnd(100) < 42 ? TILE.WALL : TILE.FLOOR)),
  );

  for (let pass = 0; pass < 4; pass += 1) {
    const next = grid.map((row) => [...row]);
    for (let y = 1; y < height - 1; y += 1) {
      for (let x = 1; x < width - 1; x += 1) {
        let walls = 0;
        for (let dy = -1; dy <= 1; dy += 1) {
          for (let dx = -1; dx <= 1; dx += 1) {
            if (dx === 0 && dy === 0) continue;
            if (grid[y + dy][x + dx] === TILE.WALL) walls += 1;
          }
        }
        next[y][x] = walls >= 5 ? TILE.WALL : TILE.FLOOR;
      }
    }
    grid = next;
  }

  // Scatter a few pools and rubble piles for cover.
  for (let i = 0; i < Math.floor((width * height) / 60); i += 1) {
    const x = 1 + rnd(width - 2);
    const y = 1 + rnd(height - 2);
    if (grid[y][x] === TILE.FLOOR) grid[y][x] = pick([TILE.WATER, TILE.RUBBLE, TILE.PILLAR]);
  }

  const rooms = [];
  // Treat large open pockets as named areas so the DM can talk about them.
  for (let i = 0; i < 4; i += 1) {
    const spot = findOpenSpot(grid, width, height);
    if (spot) rooms.push({ x: spot.x - 2, y: spot.y - 2, w: 5, h: 5, cx: spot.x, cy: spot.y, name: ROOM_NAMES.cave[i % ROOM_NAMES.cave.length] });
  }
  return { grid, rooms };
}

/** Open ground with scattered terrain — for ambushes on the road. */
function generateWilderness(width, height) {
  const grid = blankGrid(width, height, TILE.GRASS);
  const features = Math.floor((width * height) / 12);
  for (let i = 0; i < features; i += 1) {
    const x = rnd(width);
    const y = rnd(height);
    grid[y][x] = pick([TILE.TREE, TILE.TREE, TILE.RUBBLE, TILE.WATER, TILE.GRASS]);
  }
  // A path across the middle.
  const roadY = Math.floor(height / 2) + (rnd(3) - 1);
  for (let x = 0; x < width; x += 1) {
    grid[roadY][x] = TILE.FLOOR;
    if (grid[roadY + 1]) grid[roadY + 1][x] = TILE.FLOOR;
  }
  return {
    grid,
    rooms: [{ x: 0, y: roadY - 1, w: width, h: 3, cx: Math.floor(width / 2), cy: roadY, name: 'Дорога' }],
  };
}

/** A single furnished interior — tavern, chapel, throne room. */
function generateInterior(width, height, theme) {
  const grid = blankGrid(width, height, TILE.WALL);
  const room = { x: 1, y: 1, w: width - 2, h: height - 2 };
  carveRoom(grid, room);
  room.cx = Math.floor(width / 2);
  room.cy = Math.floor(height / 2);
  room.name = ROOM_NAMES.interior[0];

  const furniture = theme === 'temple' ? [TILE.ALTAR, TILE.PILLAR, TILE.FIRE] : [TILE.TABLE, TILE.TABLE, TILE.BED, TILE.CHEST, TILE.FIRE];
  for (let i = 0; i < Math.floor((width * height) / 14); i += 1) {
    const x = 2 + rnd(width - 4);
    const y = 2 + rnd(height - 4);
    if (grid[y][x] === TILE.FLOOR) grid[y][x] = pick(furniture);
  }
  // A door on a random wall.
  const side = rnd(4);
  if (side === 0) grid[0][room.cx] = TILE.DOOR;
  else if (side === 1) grid[height - 1][room.cx] = TILE.DOOR;
  else if (side === 2) grid[room.cy][0] = TILE.DOOR;
  else grid[room.cy][width - 1] = TILE.DOOR;

  return { grid, rooms: [room] };
}

function decorate(grid, rooms, theme) {
  for (const room of rooms) {
    const count = 1 + rnd(3);
    for (let i = 0; i < count; i += 1) {
      const x = room.x + rnd(room.w);
      const y = room.y + rnd(room.h);
      if (grid[y][x] !== TILE.FLOOR) continue;
      grid[y][x] = pick(
        theme === 'crypt'
          ? [TILE.PILLAR, TILE.RUBBLE, TILE.ALTAR]
          : theme === 'ruins'
            ? [TILE.RUBBLE, TILE.PILLAR, TILE.TREE]
            : [TILE.PILLAR, TILE.RUBBLE, TILE.TABLE, TILE.CHEST, TILE.FIRE],
      );
    }
  }
}

function findOpenSpot(grid, width, height) {
  for (let tries = 0; tries < 200; tries += 1) {
    const x = 2 + rnd(width - 4);
    const y = 2 + rnd(height - 4);
    if (grid[y][x] === TILE.FLOOR) return { x, y };
  }
  return null;
}

/**
 * Builds a map.
 * @param theme dungeon | cave | crypt | ruins | wilderness | interior | temple
 */
export function generateMap({ theme = 'dungeon', width = 30, height = 22, title = null } = {}) {
  const w = Math.max(10, Math.min(48, Math.round(width)));
  const h = Math.max(8, Math.min(36, Math.round(height)));

  let built;
  if (theme === 'cave') built = generateCave(w, h);
  else if (theme === 'wilderness') built = generateWilderness(w, h);
  else if (theme === 'interior' || theme === 'temple') built = generateInterior(w, h, theme);
  else built = generateDungeon(w, h, theme);

  const map = {
    id: randomUUID(),
    title: title || defaultTitle(theme),
    theme,
    width: w,
    height: h,
    grid: built.grid,
    rooms: built.rooms,
    revealed: blankGrid(w, h, false),
    tokens: [],
    createdAt: Date.now(),
  };

  const entry = built.rooms[0]
    ? { x: built.rooms[0].cx, y: built.rooms[0].cy }
    : findOpenSpot(built.grid, w, h) || { x: 1, y: 1 };
  map.entry = entry;
  revealCircle(map, entry.x, entry.y, 6);
  return map;
}

function defaultTitle(theme) {
  return (
    {
      dungeon: 'Подземелье',
      cave: 'Пещера',
      crypt: 'Склеп',
      ruins: 'Руины',
      wilderness: 'Открытая местность',
      interior: 'Помещение',
      temple: 'Храм',
    }[theme] || 'Карта'
  );
}

// ---------------------------------------------------------------- tokens

export function addToken(map, { id, name, kind = 'npc', x, y, color = '#ef4444', size = 1, label = null }) {
  // Two creatures never share a square: an explicit position that is taken (or
  // impassable) slides to the nearest free one instead of stacking.
  const wanted = x === undefined || y === undefined ? map.entry : { x: clamp(x, 0, map.width - 1), y: clamp(y, 0, map.height - 1) };
  const spot =
    isWalkable(map, wanted.x, wanted.y) && !isOccupied(map, wanted.x, wanted.y, id)
      ? wanted
      : freeSquareNear(map, wanted.x, wanted.y);
  const token = {
    id: id || randomUUID(),
    name,
    kind,
    x: clamp(spot.x, 0, map.width - 1),
    y: clamp(spot.y, 0, map.height - 1),
    color,
    size,
    label: label || name.slice(0, 2).toUpperCase(),
  };
  map.tokens = map.tokens.filter((t) => t.id !== token.id);
  map.tokens.push(token);
  if (kind === 'pc') revealCircle(map, token.x, token.y, 6);
  return token;
}

export function removeToken(map, id) {
  const before = map.tokens.length;
  map.tokens = map.tokens.filter((t) => t.id !== id);
  return map.tokens.length !== before;
}

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, Math.round(v)));

export function tileAt(map, x, y) {
  return map.grid[y]?.[x];
}

export function isWalkable(map, x, y) {
  const tile = tileAt(map, x, y);
  return tile !== undefined && !BLOCKING.has(tile);
}

export function isOccupied(map, x, y, exceptId = null) {
  return map.tokens.some((t) => t.id !== exceptId && t.x === x && t.y === y);
}

function freeSquareNear(map, x, y) {
  for (let radius = 0; radius < Math.max(map.width, map.height); radius += 1) {
    for (let dy = -radius; dy <= radius; dy += 1) {
      for (let dx = -radius; dx <= radius; dx += 1) {
        const nx = x + dx;
        const ny = y + dy;
        if (isWalkable(map, nx, ny) && !isOccupied(map, nx, ny)) return { x: nx, y: ny };
      }
    }
  }
  return { x, y };
}

/**
 * Moves a token. Returns the distance travelled in feet so the caller can check
 * it against the creature's speed; blocked squares are refused outright.
 */
export function moveToken(map, tokenId, x, y, { force = false } = {}) {
  const token = map.tokens.find((t) => t.id === tokenId);
  if (!token) return { ok: false, reason: 'токен не найден' };

  const tx = clamp(x, 0, map.width - 1);
  const ty = clamp(y, 0, map.height - 1);
  if (!force) {
    if (!isWalkable(map, tx, ty)) return { ok: false, reason: `клетка ${tx},${ty} непроходима (${TILE_RU[tileAt(map, tx, ty)] || '?'})` };
    if (isOccupied(map, tx, ty, tokenId)) return { ok: false, reason: `клетка ${tx},${ty} занята` };
  }

  const from = { x: token.x, y: token.y };
  const distance = gridDistance(from, { x: tx, y: ty });
  token.x = tx;
  token.y = ty;
  if (token.kind === 'pc') revealCircle(map, tx, ty, 6);
  return { ok: true, from, to: { x: tx, y: ty }, distance };
}

// ------------------------------------------------------------------- fog

/** Reveals squares within `radius`, stopping at walls (simple ray casting). */
export function revealCircle(map, cx, cy, radius = 5) {
  let revealedCount = 0;
  for (let y = Math.max(0, cy - radius); y <= Math.min(map.height - 1, cy + radius); y += 1) {
    for (let x = Math.max(0, cx - radius); x <= Math.min(map.width - 1, cx + radius); x += 1) {
      if ((x - cx) ** 2 + (y - cy) ** 2 > radius ** 2 + radius) continue;
      if (!hasLineOfSight(map, cx, cy, x, y)) continue;
      if (!map.revealed[y][x]) revealedCount += 1;
      map.revealed[y][x] = true;
    }
  }
  return revealedCount;
}

export function revealRoom(map, roomQuery) {
  const room =
    typeof roomQuery === 'number'
      ? map.rooms[roomQuery]
      : map.rooms.find((r) => String(r.name).toLowerCase().includes(String(roomQuery).toLowerCase()));
  if (!room) return 0;
  let count = 0;
  for (let y = room.y - 1; y <= room.y + room.h; y += 1) {
    for (let x = room.x - 1; x <= room.x + room.w; x += 1) {
      if (map.revealed[y]?.[x] === false) {
        map.revealed[y][x] = true;
        count += 1;
      }
    }
  }
  return count;
}

export function revealAll(map) {
  map.revealed = blankGrid(map.width, map.height, true);
}

/** Bresenham line stopped by opaque tiles. */
export function hasLineOfSight(map, x0, y0, x1, y1) {
  let x = x0;
  let y = y0;
  const dx = Math.abs(x1 - x0);
  const dy = Math.abs(y1 - y0);
  const sx = x0 < x1 ? 1 : -1;
  const sy = y0 < y1 ? 1 : -1;
  let err = dx - dy;

  while (x !== x1 || y !== y1) {
    const e2 = 2 * err;
    if (e2 > -dy) {
      err -= dy;
      x += sx;
    }
    if (e2 < dx) {
      err += dx;
      y += sy;
    }
    if (x === x1 && y === y1) break;
    if (OPAQUE.has(tileAt(map, x, y))) return false;
  }
  return true;
}

// ---------------------------------------------------------------- output

/**
 * Text rendering for the DM's context. Only the revealed part is drawn, and
 * only its bounding box, so a mostly-unexplored map costs almost nothing.
 */
export function asciiMap(map, { showAll = false } = {}) {
  let minX = map.width;
  let minY = map.height;
  let maxX = 0;
  let maxY = 0;
  for (let y = 0; y < map.height; y += 1) {
    for (let x = 0; x < map.width; x += 1) {
      if (showAll || map.revealed[y][x]) {
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x);
        minY = Math.min(minY, y);
        maxY = Math.max(maxY, y);
      }
    }
  }
  if (minX > maxX) return 'Карта ещё не разведана.';

  const tokenAt = new Map();
  map.tokens.forEach((t, i) => tokenAt.set(`${t.x},${t.y}`, String.fromCharCode(97 + (i % 26))));

  const lines = [`${map.title} (${map.width}×${map.height}, клетка = 5 фт.)`];
  const header = `    ${Array.from({ length: maxX - minX + 1 }, (_, i) => String((minX + i) % 10)).join('')}`;
  lines.push(header);
  for (let y = minY; y <= maxY; y += 1) {
    let row = '';
    for (let x = minX; x <= maxX; x += 1) {
      if (!showAll && !map.revealed[y][x]) row += ' ';
      else row += tokenAt.get(`${x},${y}`) || map.grid[y][x];
    }
    lines.push(`${String(y).padStart(3)} ${row}`);
  }

  if (map.tokens.length) {
    lines.push('Токены:');
    map.tokens.forEach((t, i) => {
      lines.push(`  ${String.fromCharCode(97 + (i % 26))} = ${t.name} (${t.x},${t.y})`);
    });
  }
  const legend = new Set();
  for (let y = minY; y <= maxY; y += 1) {
    for (let x = minX; x <= maxX; x += 1) {
      if (showAll || map.revealed[y][x]) legend.add(map.grid[y][x]);
    }
  }
  lines.push(
    `Легенда: ${[...legend]
      .filter((t) => TILE_RU[t])
      .map((t) => `${t} ${TILE_RU[t]}`)
      .join(', ')}`,
  );
  if (map.rooms?.length) {
    lines.push(`Области: ${map.rooms.map((r, i) => `${i}. ${r.name} (${r.cx},${r.cy})`).join('; ')}`);
  }
  return lines.join('\n');
}

/** Serialised form for the browser: rows as strings keep the payload small. */
export function toClient(map) {
  if (!map) return null;
  return {
    id: map.id,
    title: map.title,
    theme: map.theme,
    width: map.width,
    height: map.height,
    grid: map.grid.map((row) => row.join('')),
    revealed: map.revealed.map((row) => row.map((v) => (v ? '1' : '0')).join('')),
    tokens: map.tokens,
    rooms: map.rooms,
    legend: TILE_RU,
  };
}

export { TILE_RU, DIFFICULT };
