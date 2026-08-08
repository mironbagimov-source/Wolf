'use strict';
// =====================================================================
// Волчий Лог — survival horror in the browser.
// Tuning tables live here so balance can be changed without hunting
// through systems code. Everything below is data; behaviour is elsewhere.
// =====================================================================

const TUNE = {
  eyeHeight: 1.62,
  crouchEye: 1.05,
  playerRadius: 0.34,
  walkSpeed: 2.9,
  sprintSpeed: 5.1,
  aimSpeed: 1.45,
  backMul: 0.68,
  accel: 22,          // ground acceleration, m/s^2 — heavy enough to feel weighty
  friction: 14,
  staminaMax: 100,
  staminaDrain: 22,   // per second while sprinting
  staminaRegen: 16,
  staminaRegenDelay: 0.9,
  hpMax: 100,
  lookSens: 0.0021,   // radians per pixel of raw mouse movement
  aimSensMul: 0.55,
  pitchLimit: Math.PI / 2 - 0.06,
  guardReduction: 0.72,   // fraction of damage absorbed while guarding
  guardStamina: 26,       // stamina spent per blocked hit
  iframes: 0.55,          // seconds of invulnerability after taking a hit
  interactRange: 2.6,
  bloodDecals: 40,
};

// ------------------------------------------------------------ weapons
// dmg is per bullet at the body; head multiplies it. Guns fire hitscan
// rays; the shotgun fires `pellets` rays inside `spread`.
const WEAPONS = {
  knife: {
    id: 'knife', name: 'Нож', kind: 'melee', icon: '🗡️',
    dmg: 26, headMul: 1.6, rate: 0.42, range: 2.1, arc: 0.5,
    stagger: 0.25,
  },
  revolver: {
    id: 'revolver', name: 'Наган', kind: 'gun', icon: '🔫',
    dmg: 34, headMul: 2.8, rate: 0.44, mag: 7, reload: 2.0,
    ammo: 'ammo38', pellets: 1, spread: 0.010, adsSpread: 0.0022,
    recoil: 0.055, kick: 0.09, stagger: 0.55, shake: 0.5, sfx: 'pistol',
  },
  shotgun: {
    id: 'shotgun', name: 'Обрез', kind: 'gun', icon: '🔫',
    dmg: 17, headMul: 1.9, rate: 0.85, mag: 2, reload: 2.7,
    ammo: 'shells', pellets: 8, spread: 0.075, adsSpread: 0.048,
    recoil: 0.16, kick: 0.26, stagger: 1.5, shake: 1.5, sfx: 'shotgun',
  },
};

// Upgrade ladders bought from the merchant. Each level multiplies or adds.
const UPGRADES = {
  revolver: [
    { stat: 'dmg', name: 'Ствол: расточка', desc: 'Урон +30%', mul: 1.3, prices: [1400, 3200, 6400] },
    { stat: 'mag', name: 'Барабан на 9', desc: 'Ёмкость +2', add: 2, prices: [1100, 2600] },
    { stat: 'reload', name: 'Скобa быстрого сброса', desc: 'Перезарядка -25%', mul: 0.75, prices: [1200, 2800] },
  ],
  shotgun: [
    { stat: 'dmg', name: 'Кучность и навеска', desc: 'Урон +35%', mul: 1.35, prices: [2200, 4600, 8200] },
    { stat: 'mag', name: 'Третий ствол', desc: 'Ёмкость +1', add: 1, prices: [2600, 5400] },
    { stat: 'reload', name: 'Патронташ на запястье', desc: 'Перезарядка -25%', mul: 0.75, prices: [1800, 3800] },
  ],
};

// ------------------------------------------------------------- items
// w/h are cells in the case; stack is how many fit in one slot.
const ITEMS = {
  ammo38:    { name: 'Патроны .38',      icon: '🟨', w: 1, h: 1, stack: 30, kind: 'ammo',  price: 14,  sell: 5,
               desc: 'Тупоносые, для нагана. В деревне такие не купишь — только собрать из пороха и гильз.' },
  shells:    { name: 'Заряды к обрезу',  icon: '🟥', w: 1, h: 1, stack: 12, kind: 'ammo',  price: 30,  sell: 11,
               desc: 'Картонные гильзы, набитые крупной дробью. Одного хватает, чтобы сложить упыря пополам.' },
  herb:      { name: 'Трава',            icon: '🌿', w: 1, h: 1, stack: 6,  kind: 'mat',   price: 20,  sell: 7,
               desc: 'Горькая, растёт у погоста. Сама по себе почти бесполезна — две вместе дают отвар.' },
  brew:      { name: 'Отвар',            icon: '🧪', w: 1, h: 1, stack: 3,  kind: 'heal',  price: 90,  sell: 32, heal: 62,
               desc: 'Пахнет плесенью и спиртом. Затягивает раны на глазах.' },
  powder:    { name: 'Порох',            icon: '⬛', w: 1, h: 1, stack: 10, kind: 'mat',   price: 45,  sell: 16,
               desc: 'Дымный, крупного помола. Основа любого заряда.' },
  casing:    { name: 'Гильзы',           icon: '⬜', w: 1, h: 1, stack: 10, kind: 'mat',   price: 25,  sell: 9,
               desc: 'Стреляные, но целые. С порохом дают патроны к нагану.' },
  lead:      { name: 'Свинец',           icon: '🔘', w: 1, h: 1, stack: 10, kind: 'mat',   price: 35,  sell: 12,
               desc: 'Ломаная дробь и кусок оплавленной пули. С порохом — заряд к обрезу.' },
  holywater: { name: 'Святая вода',      icon: '💧', w: 1, h: 1, stack: 3,  kind: 'throw', price: 160, sell: 55, dmg: 130,
               desc: 'Склянка из церкви. Нечисть от неё горит, а стрыга — особенно.' },
  revolver:  { name: 'Наган',            icon: '🔫', w: 2, h: 1, stack: 1,  kind: 'weapon', weapon: 'revolver', price: 0, sell: 0,
               desc: 'Табельный, с царапиной на скобе. Единственное, что осталось от прежней службы.' },
  shotgun:   { name: 'Обрез',            icon: '🔫', w: 3, h: 1, stack: 1,  kind: 'weapon', weapon: 'shotgun', price: 3800, sell: 0,
               desc: 'Двустволка с отпиленными стволами. Бьёт как лошадь, бьёт близко.' },
  // treasure — no use but selling
  icon_silver: { name: 'Серебряный оклад', icon: '🖼️', w: 2, h: 2, stack: 1, kind: 'treasure', price: 0, sell: 1450,
               desc: 'Оклад с церковной иконы. Сама икона сгорела, серебро — нет.' },
  ring:      { name: 'Перстень с гранатом', icon: '💍', w: 1, h: 1, stack: 1, kind: 'treasure', price: 0, sell: 900,
               desc: 'Тяжёлый, не по крестьянской руке. Камень мутный, как запёкшаяся кровь.' },
  chalice:   { name: 'Потир',            icon: '🏆', w: 2, h: 2, stack: 1,  kind: 'treasure', price: 0, sell: 2100,
               desc: 'Из усадебной часовни. Внутри бурый налёт, и это не вино.' },
  teeth:     { name: 'Клык вурдалака',   icon: '🦷', w: 1, h: 1, stack: 4,  kind: 'treasure', price: 0, sell: 180,
               desc: 'Ворон платит за них не торгуясь и не объясняет зачем.' },
};

// item + item -> result. Symmetric; checked both ways.
const RECIPES = [
  { a: 'herb',   b: 'herb',   out: 'brew',   count: 1, name: 'Отвар' },
  { a: 'powder', b: 'casing', out: 'ammo38', count: 10, name: 'Патроны .38' },
  { a: 'powder', b: 'lead',   out: 'shells', count: 5,  name: 'Заряды к обрезу' },
];

// -------------------------------------------------------- key items
const KEY_ITEMS = {
  crestLeft:  { name: 'Половина волчьего герба (левая)', icon: '🐺',
                desc: 'Литой чугун, скол по краю. Вторая половина где-то в деревне.' },
  crestRight: { name: 'Половина волчьего герба (правая)', icon: '🐺',
                desc: 'Такой же скол. Вместе они откроют ворота усадьбы.' },
  cryptKey:   { name: 'Ключ от крипты', icon: '🗝️', desc: 'Церковный, с бородкой в виде креста.' },
  millKey:    { name: 'Ключ от мельницы', icon: '🗝️', desc: 'Ржавый, на верёвочной петле.' },
  manorKey:   { name: 'Ключ от парадной', icon: '🗝️', desc: 'Латунный, с гербом Мораны на головке.' },
};

// ------------------------------------------------------------ enemies
const ENEMIES = {
  ghoul: {
    id: 'ghoul', name: 'Упырь',
    hp: 115, speed: 2.45, chaseSpeed: 2.9, dmg: 15, attackRange: 1.75, attackWindup: 0.48,
    attackRecover: 0.85, sight: 20, hearing: 13, tint: 0x3f463c, scale: 1.0, hunch: 0.16,
    staggerHp: 42,      // damage inside one window that knocks it down
    loot: [['ammo38', 0.28, 4], ['herb', 0.22, 1], ['powder', 0.16, 1], ['casing', 0.16, 2], ['teeth', 0.05, 1]],
    money: [30, 90],
    growl: 'ghoul',
  },
  vurdalak: {
    id: 'vurdalak', name: 'Вурдалак',
    hp: 88, speed: 3.3, chaseSpeed: 5.0, dmg: 21, attackRange: 2.0, attackWindup: 0.3,
    attackRecover: 0.7, sight: 24, hearing: 17, tint: 0x53322c, scale: 0.95, hunch: 0.3,
    staggerHp: 30, lunge: 7.5,
    loot: [['shells', 0.24, 2], ['lead', 0.22, 1], ['powder', 0.2, 1], ['teeth', 0.3, 1]],
    money: [60, 150],
    growl: 'vurdalak',
  },
  stryga: {
    id: 'stryga', name: 'Стрыга',
    hp: 190, speed: 2.0, chaseSpeed: 3.4, dmg: 24, attackRange: 2.2, attackWindup: 0.6,
    attackRecover: 1.0, sight: 26, hearing: 20, tint: 0x322a44, scale: 1.12, hunch: 0.1,
    staggerHp: 70, ranged: true, rangedCooldown: 3.4, rangedDmg: 14, holyMul: 2.6,
    loot: [['holywater', 0.2, 1], ['shells', 0.4, 3], ['ring', 0.12, 1]],
    money: [140, 280],
    growl: 'stryga',
  },
};

// ------------------------------------------------------------ merchant
const SHOP_STOCK = [
  { item: 'ammo38', count: 10, price: 130, repeat: true },
  { item: 'shells', count: 5,  price: 145, repeat: true },
  { item: 'powder', count: 3,  price: 120, repeat: true },
  { item: 'casing', count: 5,  price: 110, repeat: true },
  { item: 'lead',   count: 5,  price: 150, repeat: true },
  { item: 'brew',   count: 1,  price: 260, repeat: true },
  { item: 'holywater', count: 1, price: 420, repeat: true },
  { item: 'shotgun', count: 1, price: 3800, once: 'boughtShotgun' },
];

const CASE_UPGRADES = [
  { rows: 6, price: 1600, name: 'Кейс: нижний ярус', desc: 'Ещё один ряд ячеек' },
  { rows: 7, price: 4200, name: 'Кейс: двойное дно', desc: 'И ещё один' },
];

const SHOP_LINES = [
  'Ночь долгая, а товар — конечный.',
  'Мёртвые не покупают. Ты пока покупаешь.',
  'Бери порох. Порохом в этой деревне решают всё.',
  'Клыки? Клыки беру. Не спрашивай зачем.',
  'В усадьбу пойдёшь — возьми вдвое больше, чем считаешь нужным.',
];

// ------------------------------------------------------------- notes
const NOTES = {
  churchNote: {
    title: 'Запись отца Никодима',
    body: [
      'Третью неделю не хороним — земля не берёт. Клали Матвея в мёрзлую яму, а к утру яма пуста и следы ведут к усадьбе.',
      'Замок на сундуке в крипте я перевесил. Число прежнее, отцовское: год, когда сгорела старая колокольня — восемьсот сорок седьмой. Три последние цифры, больше подсказок не оставлю.',
      'Если читаешь это и ты ещё жив — не ходи к воротам без герба. Волк на створках не украшение. Он замок.',
    ],
    sign: 'о. Никодим',
  },
  millNote: {
    title: 'Клочок бумаги на жернове',
    body: [
      'Барыга говорит, серебро их жжёт. Врёт, наверное, — но у него и правда никто ночью в лавке не сидит.',
      'Графиня забрала девчонку кузнеца. Потом мою. Ходит слух, что она их не ест, а держит. Не знаю, что хуже.',
      'Вторую половину герба дед прятал в мучном ларе. Я не трогал. Трону — придут.',
    ],
    sign: 'мельник Гринь',
  },
  manorNote: {
    title: 'Письмо без адреса',
    body: [
      'Морана не вампир в том смысле, как пишут в книжках. Она старше слова «вампир». Кровь ей нужна не для жизни, а чтобы помнить, как это — быть живой.',
      'Сердце у неё снаружи. Видел сам: когда она вскидывается для удара, под рёбрами открывается свет. Бей туда. Больше никуда не бей — бесполезно.',
      'Я это пишу, зная, что не выйду. Кто выйдет — сожгите усадьбу дотла.',
    ],
    sign: 'егерь Тарас',
  },
  cryptNote: {
    title: 'Мел на стене крипты',
    body: [
      'Считал гробы. Их двадцать два, а имён на плитах девятнадцать.',
      'Три лишних не пустые.',
    ],
    sign: '',
  },
};

const LOCK_CODE = [8, 4, 7];  // «восемьсот сорок седьмой» из записки отца Никодима
