// Экран создания персонажа. Общий для двух сборок: сетевой (стол на сервере)
// и однофайловой (всё в браузере) — они отличаются только тем, куда уходит
// готовый персонаж, поэтому это передаётся колбэками.

import { el, qs, qsa, clear, toast } from './dom.js';
import { classIcon } from './icons.js';

const CLASS_PRIORITY = {
  barbarian: ['str', 'con', 'dex', 'wis', 'cha', 'int'],
  bard: ['cha', 'dex', 'con', 'wis', 'int', 'str'],
  cleric: ['wis', 'con', 'str', 'cha', 'dex', 'int'],
  druid: ['wis', 'con', 'dex', 'int', 'cha', 'str'],
  fighter: ['str', 'con', 'dex', 'wis', 'cha', 'int'],
  monk: ['dex', 'wis', 'con', 'str', 'cha', 'int'],
  paladin: ['str', 'cha', 'con', 'wis', 'dex', 'int'],
  ranger: ['dex', 'wis', 'con', 'str', 'int', 'cha'],
  rogue: ['dex', 'int', 'con', 'wis', 'cha', 'str'],
  sorcerer: ['cha', 'con', 'dex', 'wis', 'int', 'str'],
  warlock: ['cha', 'con', 'dex', 'wis', 'int', 'str'],
  wizard: ['int', 'con', 'dex', 'wis', 'cha', 'str'],
};

const ABILITY_LABELS = {
  str: 'Сила',
  dex: 'Ловкость',
  con: 'Телосложение',
  int: 'Интеллект',
  wis: 'Мудрость',
  cha: 'Харизма',
};

const formatMod = (value) => (value < 0 ? `−${Math.abs(value)}` : `+${value}`);

const state = {
  options: null,
  pool: [],
  assignment: {},
  chosenSkills: new Set(),
  onRollAbilities: null,
};

export function initCreator({ options, onPick, onCreate, onRollAbilities }) {
  state.options = options;
  state.onRollAbilities = onRollAbilities;

  qsa('.tab').forEach((tab) =>
    tab.addEventListener('click', () => {
      qsa('.tab').forEach((t) => t.classList.toggle('active', t === tab));
      qsa('.tab-panel').forEach((p) => p.classList.toggle('active', p.id === `tab-${tab.dataset.tab}`));
    }),
  );

  const list = clear(qs('#pregen-list'));
  for (const pregen of options.pregens) {
    const sigil = el('div', { class: 'pregen-sigil', style: { color: pregen.portraitColor } });
    sigil.append(classIcon(pregen.class, { size: 20 }));
    list.append(
      el(
        'button',
        {
          class: 'pregen',
          style: { '--accent': pregen.portraitColor },
          onclick: () => onPick(pregen.id),
        },
        [
          el('div', { class: 'pregen-head' }, [
            sigil,
            el('div', {}, [
              el('h3', {}, pregen.name),
              el('div', { class: 'role' }, `${pregen.preview.raceName} · ${pregen.preview.className}`),
            ]),
          ]),
          el('p', {}, pregen.blurb),
          el('div', { class: 'hook' }, pregen.hook),
        ],
      ),
    );
  }

  const race = qs('#c-race');
  clear(race);
  for (const r of options.races) race.append(el('option', { value: r.index }, `${r.name} (${r.bonuses.join(', ')})`));
  const klass = qs('#c-class');
  clear(klass);
  for (const c of options.classes) klass.append(el('option', { value: c.index }, `${c.name} · к${c.hitDie}`));
  const background = qs('#c-background');
  clear(background);
  for (const b of options.backgrounds) {
    background.append(el('option', { value: b.index }, `${b.name} — ${b.skills.join(', ')}`));
  }

  race.addEventListener('change', refreshSubraces);
  klass.addEventListener('change', () => {
    refreshSkills();
    setPool(state.pool);
  });
  background.addEventListener('change', refreshSkills);

  qs('#use-array').addEventListener('click', () => {
    qs('#use-array').classList.add('active');
    qs('#use-roll').classList.remove('active');
    setPool([...options.standardArray]);
  });
  qs('#use-roll').addEventListener('click', () => {
    qs('#use-roll').classList.add('active');
    qs('#use-array').classList.remove('active');
    state.onRollAbilities?.();
  });

  qs('#create-character-btn').addEventListener('click', () => submit(onCreate));

  refreshSubraces();
  refreshSkills();
  setPool([...options.standardArray]);
}

function refreshSubraces() {
  const race = state.options.races.find((r) => r.index === qs('#c-race').value);
  const select = clear(qs('#c-subrace'));
  select.append(el('option', { value: '' }, '— без разновидности —'));
  for (const sub of race?.subraces || []) select.append(el('option', { value: sub.index }, sub.name));
  select.disabled = !(race?.subraces || []).length;
}

const currentClass = () =>
  state.options.classes.find((c) => c.index === qs('#c-class').value) || state.options.classes[0];

function refreshSkills() {
  const cls = currentClass();
  const allowed = new Set(cls.skillChoices.from);
  const limit = cls.skillChoices.choose;

  for (const skill of [...state.chosenSkills]) {
    if (!allowed.has(skill)) state.chosenSkills.delete(skill);
  }

  const list = clear(qs('#skill-list'));
  for (const skill of state.options.skills) {
    const selectable = allowed.has(skill.index);
    list.append(
      el('label', { class: `skill-item${selectable ? '' : ' disabled'}` }, [
        el('input', {
          type: 'checkbox',
          checked: state.chosenSkills.has(skill.index),
          disabled: !selectable,
          onchange: (event) => {
            if (event.target.checked) {
              if (state.chosenSkills.size >= limit) {
                event.target.checked = false;
                return toast(`${currentClass().name}: можно выбрать ${limit}`);
              }
              state.chosenSkills.add(skill.index);
            } else {
              state.chosenSkills.delete(skill.index);
            }
            updateSkillCounter();
          },
        }),
        el('span', {}, skill.name),
        el('span', { class: 'skill-ability' }, skill.ability.slice(0, 3)),
      ]),
    );
  }
  updateSkillCounter();
}

function updateSkillCounter() {
  const cls = currentClass();
  const bgSkills = state.options.backgrounds.find((b) => b.index === qs('#c-background').value)?.skills || [];
  qs('#skill-counter').textContent =
    `${state.chosenSkills.size}/${cls.skillChoices.choose}` +
    (bgSkills.length ? ` · от предыстории: ${bgSkills.join(', ')}` : '');
}

/** Раскладывает набор значений по характеристикам с учётом приоритета класса. */
export function setPool(scores) {
  state.pool = scores?.length ? scores : [...state.options.standardArray];
  const sorted = [...state.pool].sort((a, b) => b - a);
  const priority = CLASS_PRIORITY[qs('#c-class').value] || Object.keys(ABILITY_LABELS);
  state.assignment = {};
  priority.forEach((ability, i) => {
    state.assignment[ability] = sorted[i];
  });
  refreshAbilityRows();
}

function refreshAbilityRows() {
  const node = clear(qs('#ability-rows'));
  for (const [ability, label] of Object.entries(ABILITY_LABELS)) {
    const score = state.assignment[ability] ?? 10;
    const select = el('select', {
      onchange: (event) => {
        const wanted = Number(event.target.value);
        // Значения из набора уникальны: если оно занято — меняемся местами.
        const holder = Object.keys(state.assignment).find((k) => state.assignment[k] === wanted && k !== ability);
        if (holder) state.assignment[holder] = state.assignment[ability];
        state.assignment[ability] = wanted;
        refreshAbilityRows();
      },
    });
    for (const value of state.pool) select.append(el('option', { value: String(value) }, String(value)));
    select.value = String(score);

    node.append(
      el('div', { class: 'ability-row' }, [
        el('div', { class: 'name' }, label),
        el('div', { class: 'score' }, String(score)),
        el('div', { class: 'mod' }, formatMod(Math.floor((score - 10) / 2))),
        select,
      ]),
    );
  }
}

function submit(onCreate) {
  const name = qs('#c-name').value.trim();
  if (!name) return toast('У героя должно быть имя');
  const cls = currentClass();
  if (state.chosenSkills.size !== cls.skillChoices.choose) {
    return toast(`Выбери ровно ${cls.skillChoices.choose} навыка для класса «${cls.name}»`);
  }
  onCreate({
    name,
    race: qs('#c-race').value,
    subrace: qs('#c-subrace').value || null,
    class: qs('#c-class').value,
    background: qs('#c-background').value,
    alignment: qs('#c-alignment').value,
    skills: [...state.chosenSkills],
    abilities: state.assignment,
    portraitColor: qs('#c-color').value,
    blurb: qs('#c-blurb').value.trim(),
    hook: qs('#c-hook').value.trim(),
  });
  qs('#c-name').value = '';
}
