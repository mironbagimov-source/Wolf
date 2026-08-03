// Dice roller. Every random number in the game comes from here, and every roll
// is returned with its individual die values so the client can show the full
// breakdown — the AI narrates the outcome but it never decides it, and players
// can audit any result in the log.

import { randomInt } from 'node:crypto';

/** One die. Uses crypto.randomInt so results are uniform, not Math.random-biased. */
export function rollDie(faces) {
  if (!Number.isInteger(faces) || faces < 2 || faces > 1000) {
    throw new Error(`Некорректная грань кости: d${faces}`);
  }
  return randomInt(1, faces + 1);
}

const TERM_RE = /^(\d*)d(\d+)(?:(kh|kl|dh|dl)(\d*))?$/i;

/**
 * Parses "2d6 + 3 - 1d4" into signed terms. Supports keep/drop suffixes:
 * 4d6kh3 (keep highest 3), 2d20kl1 (keep lowest 1 = disadvantage),
 * 4d6dl1 (drop lowest 1).
 */
export function parse(expression) {
  const cleaned = String(expression).replace(/\s+/g, '').toLowerCase();
  if (!cleaned) throw new Error('Пустое выражение броска');
  if (!/^[+-]?[\dd+\-khl]+$/.test(cleaned)) {
    throw new Error(`Не понимаю выражение: ${expression}`);
  }

  const terms = [];
  // Split while keeping the sign attached to the term that follows it.
  const chunks = cleaned.match(/[+-]?[^+-]+/g) || [];
  for (const chunk of chunks) {
    const sign = chunk.startsWith('-') ? -1 : 1;
    const body = chunk.replace(/^[+-]/, '');
    if (!body) continue;

    const dice = body.match(TERM_RE);
    if (dice) {
      const count = dice[1] === '' ? 1 : Number(dice[1]);
      const faces = Number(dice[2]);
      const mode = dice[3] || null;
      const amount = dice[4] === '' || dice[4] === undefined ? 1 : Number(dice[4]);
      if (count < 1 || count > 100) throw new Error(`Слишком много костей: ${body}`);
      if (mode && amount > count) throw new Error(`Нельзя оставить ${amount} из ${count} костей`);
      terms.push({ kind: 'dice', sign, count, faces, mode, amount });
      continue;
    }

    if (/^\d+$/.test(body)) {
      terms.push({ kind: 'const', sign, value: Number(body) });
      continue;
    }

    throw new Error(`Не понимаю часть выражения: ${chunk}`);
  }

  if (terms.length === 0) throw new Error(`Не понимаю выражение: ${expression}`);
  return terms;
}

function applyKeep(values, mode, amount) {
  if (!mode) return { kept: values.map((_, i) => i), dropped: [] };
  const order = values
    .map((value, index) => ({ value, index }))
    .sort((a, b) => (mode === 'kh' || mode === 'dl' ? b.value - a.value : a.value - b.value));
  // kh/kl keep `amount`; dh/dl drop `amount`.
  const keepCount = mode === 'kh' || mode === 'kl' ? amount : values.length - amount;
  const kept = order.slice(0, keepCount).map((e) => e.index).sort((a, b) => a - b);
  const dropped = order.slice(keepCount).map((e) => e.index).sort((a, b) => a - b);
  return { kept, dropped };
}

/**
 * Rolls an expression.
 * @returns {{expression:string, total:number, parts:Array, dice:number[]}}
 *   `dice` is the flat list of every die face rolled, in order — used to spot
 *   natural 20s and 1s on d20 checks.
 */
export function roll(expression) {
  const terms = parse(expression);
  const parts = [];
  const dice = [];
  let total = 0;

  for (const term of terms) {
    if (term.kind === 'const') {
      total += term.sign * term.value;
      parts.push({ kind: 'const', sign: term.sign, value: term.value });
      continue;
    }

    const values = Array.from({ length: term.count }, () => rollDie(term.faces));
    const { kept, dropped } = applyKeep(values, term.mode, term.amount);
    const subtotal = kept.reduce((sum, i) => sum + values[i], 0);
    total += term.sign * subtotal;
    dice.push(...kept.map((i) => values[i]));
    parts.push({
      kind: 'dice',
      sign: term.sign,
      faces: term.faces,
      values,
      kept,
      dropped,
      subtotal,
    });
  }

  return { expression: String(expression), total, parts, dice };
}

/**
 * A d20 test: roll + modifier, with advantage/disadvantage handled properly
 * (both cancel out, per the rules).
 */
export function d20Test({ modifier = 0, advantage = false, disadvantage = false } = {}) {
  const net = advantage && !disadvantage ? 'adv' : disadvantage && !advantage ? 'dis' : null;
  const expr = net === 'adv' ? '2d20kh1' : net === 'dis' ? '2d20kl1' : '1d20';
  const base = roll(expr);
  const natural = base.dice[0];
  const total = base.total + modifier;
  return {
    ...base,
    natural,
    modifier,
    total,
    mode: net,
    crit: natural === 20,
    fumble: natural === 1,
  };
}

/** Compact human-readable breakdown, e.g. "2d6[4,6] +3 = 13". */
export function describe(result) {
  const pieces = [];
  for (const part of result.parts) {
    const sign = part.sign < 0 ? '−' : pieces.length ? '+' : '';
    if (part.kind === 'const') {
      pieces.push(`${sign}${part.value}`);
    } else {
      const shown = part.values
        .map((v, i) => (part.dropped.includes(i) ? `~~${v}~~` : String(v)))
        .join(',');
      pieces.push(`${sign}${part.values.length}d${part.faces}[${shown}]`);
    }
  }
  if (result.modifier) {
    pieces.push(`${result.modifier < 0 ? '−' : '+'}${Math.abs(result.modifier)}`);
  }
  return `${pieces.join(' ')} = ${result.total}`;
}

/** Average of an expression, used for monster HP when we don't want to roll. */
export function average(expression) {
  const terms = parse(expression);
  let total = 0;
  for (const term of terms) {
    if (term.kind === 'const') total += term.sign * term.value;
    else {
      const per = (term.faces + 1) / 2;
      const count = term.mode ? (term.mode === 'kh' || term.mode === 'kl' ? term.amount : term.count - term.amount) : term.count;
      total += term.sign * per * count;
    }
  }
  return Math.floor(total);
}
