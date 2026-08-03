// Starting kits and default spell lists per class.
//
// The SRD ships starting equipment as a tree of "choose one of A / B / (C and
// D)" options. Walking that tree in the UI would be a character-builder project
// of its own, so each class instead gets one sensible, playable loadout here.
// Players can buy and swap gear in play through the DM.

export const CLASS_KITS = {
  barbarian: {
    equipment: [
      ['greataxe', 1],
      ['handaxe', 2],
      ['javelin', 4],
      ['explorers-pack', 1],
    ],
    gold: 10,
  },
  bard: {
    equipment: [
      ['rapier', 1],
      ['leather-armor', 1],
      ['dagger', 1],
      ['lute', 1],
      ['entertainers-pack', 1],
    ],
    gold: 15,
  },
  cleric: {
    equipment: [
      ['mace', 1],
      ['scale-mail', 1],
      ['shield', 1],
      ['crossbow-light', 1],
      ['crossbow-bolt', 20],
      ['priests-pack', 1],
      ['amulet', 1],
    ],
    gold: 15,
  },
  druid: {
    equipment: [
      ['scimitar', 1],
      ['leather-armor', 1],
      ['shield', 1],
      ['explorers-pack', 1],
      ['sprig-of-mistletoe', 1],
    ],
    gold: 10,
  },
  fighter: {
    equipment: [
      ['chain-mail', 1],
      ['longsword', 1],
      ['shield', 1],
      ['crossbow-light', 1],
      ['crossbow-bolt', 20],
      ['dungeoneers-pack', 1],
    ],
    gold: 10,
  },
  monk: {
    equipment: [
      ['shortsword', 1],
      ['dart', 10],
      ['explorers-pack', 1],
    ],
    gold: 5,
  },
  paladin: {
    equipment: [
      ['chain-mail', 1],
      ['longsword', 1],
      ['shield', 1],
      ['javelin', 5],
      ['priests-pack', 1],
      ['amulet', 1],
    ],
    gold: 10,
  },
  ranger: {
    equipment: [
      ['scale-mail', 1],
      ['shortsword', 2],
      ['longbow', 1],
      ['arrow', 20],
      ['explorers-pack', 1],
    ],
    gold: 10,
  },
  rogue: {
    equipment: [
      ['shortsword', 1],
      ['shortbow', 1],
      ['arrow', 20],
      ['leather-armor', 1],
      ['dagger', 2],
      ['thieves-tools', 1],
      ['burglars-pack', 1],
    ],
    gold: 15,
  },
  sorcerer: {
    equipment: [
      ['crossbow-light', 1],
      ['crossbow-bolt', 20],
      ['dagger', 2],
      ['component-pouch', 1],
      ['dungeoneers-pack', 1],
    ],
    gold: 15,
  },
  warlock: {
    equipment: [
      ['crossbow-light', 1],
      ['crossbow-bolt', 20],
      ['leather-armor', 1],
      ['dagger', 2],
      ['component-pouch', 1],
      ['scholars-pack', 1],
    ],
    gold: 15,
  },
  wizard: {
    equipment: [
      ['quarterstaff', 1],
      ['dagger', 1],
      ['component-pouch', 1],
      ['scholars-pack', 1],
    ],
    gold: 20,
  },
};

/**
 * Backgrounds. The SRD only publishes Acolyte, so the rest are written here in
 * the same shape: two skill proficiencies, a little gear, some coin, and a
 * feature the DM can hang a scene on.
 */
export const BACKGROUNDS = [
  {
    index: 'acolyte',
    name: 'Прислужник',
    skills: ['insight', 'religion'],
    equipment: [['clothes-common', 1], ['pouch', 1]],
    gold: 15,
    feature: 'Приют при храме: тебя и твоих спутников бесплатно накормят и укроют в святилище твоей веры.',
  },
  {
    index: 'soldier',
    name: 'Солдат',
    skills: ['athletics', 'intimidation'],
    equipment: [['clothes-common', 1], ['rope-hempen-50-feet', 1]],
    gold: 10,
    feature: 'Воинское звание: солдаты твоего прежнего полка узнают тебя и подчиняются простым приказам.',
  },
  {
    index: 'criminal',
    name: 'Преступник',
    skills: ['deception', 'stealth'],
    equipment: [['crowbar', 1], ['clothes-common', 1]],
    gold: 15,
    feature: 'Связной: у тебя есть надёжный человек, через которого ты передаёшь весточки в преступный мир.',
  },
  {
    index: 'sage',
    name: 'Мудрец',
    skills: ['arcana', 'history'],
    equipment: [['ink-1-ounce-bottle', 1], ['parchment-one-sheet', 1], ['clothes-common', 1]],
    gold: 10,
    feature: 'Исследователь: если ты не знаешь ответа, ты знаешь, где его искать.',
  },
  {
    index: 'folk-hero',
    name: 'Народный герой',
    skills: ['animal-handling', 'survival'],
    equipment: [['shovel', 1], ['clothes-common', 1]],
    gold: 10,
    feature: 'Деревенское гостеприимство: простой люд укроет тебя, если только это не грозит им бедой.',
  },
  {
    index: 'charlatan',
    name: 'Шарлатан',
    skills: ['deception', 'sleight-of-hand'],
    equipment: [['clothes-fine', 1], ['pouch', 1]],
    gold: 15,
    feature: 'Ложная личность: у тебя есть вторая биография с документами и знакомыми, которые её подтвердят.',
  },
  {
    index: 'outlander',
    name: 'Чужеземец',
    skills: ['athletics', 'survival'],
    equipment: [['rope-hempen-50-feet', 1], ['clothes-travelers', 1]],
    gold: 10,
    feature: 'Странник: ты всегда помнишь пройденный путь и находишь еду и воду на двоих в дикой местности.',
  },
  {
    index: 'noble',
    name: 'Дворянин',
    skills: ['history', 'persuasion'],
    equipment: [['clothes-fine', 1], ['pouch', 1]],
    gold: 25,
    feature: 'Привилегия: тебя принимают там, куда простолюдина не пустят, и с тобой говорят как с равным.',
  },
  {
    index: 'guild-artisan',
    name: 'Ремесленник',
    skills: ['insight', 'persuasion'],
    equipment: [['smiths-tools', 1], ['clothes-travelers', 1]],
    gold: 15,
    feature: 'Членство в гильдии: собратья по цеху дадут кров и работу, пока ты платишь взносы.',
  },
  {
    index: 'entertainer',
    name: 'Артист',
    skills: ['acrobatics', 'performance'],
    equipment: [['lute', 1], ['clothes-fine', 1]],
    gold: 15,
    feature: 'Популярность: в тавернах тебя узнают, и публика примет твою сторону в споре.',
  },
];

export const BACKGROUND_BY_INDEX = new Map(BACKGROUNDS.map((b) => [b.index, b]));

/** Which armour/shield from the kit the character actually wears by default. */
export const AUTO_EQUIP = new Set([
  'chain-mail',
  'scale-mail',
  'leather-armor',
  'studded-leather-armor',
  'hide-armor',
  'chain-shirt',
  'breastplate',
  'half-plate-armor',
  'ring-mail',
  'splint',
  'plate-armor',
  'padded-armor',
  'shield',
]);

/**
 * Default cantrips and level-1 spells so a caster is playable straight out of
 * character creation. Players can ask the DM to swap any of them.
 */
export const CLASS_SPELLS = {
  bard: {
    cantrips: ['vicious-mockery', 'minor-illusion'],
    known: ['healing-word', 'charm-person', 'faerie-fire', 'thunderwave'],
  },
  cleric: {
    cantrips: ['sacred-flame', 'guidance', 'thaumaturgy'],
    known: ['cure-wounds', 'bless', 'guiding-bolt', 'shield-of-faith', 'healing-word'],
  },
  druid: {
    cantrips: ['produce-flame', 'druidcraft'],
    known: ['entangle', 'cure-wounds', 'faerie-fire', 'thunderwave'],
  },
  paladin: { cantrips: [], known: [] },
  ranger: { cantrips: [], known: [] },
  sorcerer: {
    cantrips: ['fire-bolt', 'prestidigitation', 'mage-hand', 'ray-of-frost'],
    known: ['magic-missile', 'shield'],
  },
  warlock: {
    cantrips: ['eldritch-blast', 'minor-illusion'],
    known: ['hellish-rebuke', 'charm-person', 'expeditious-retreat'],
  },
  wizard: {
    cantrips: ['fire-bolt', 'mage-hand', 'light'],
    known: ['magic-missile', 'shield', 'sleep', 'detect-magic', 'burning-hands', 'mage-armor'],
  },
};

/** Ability priority per class — used to assign the standard array sensibly. */
export const ABILITY_PRIORITY = {
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

/**
 * Pre-made characters, so a group can start playing in under a minute. Level 1,
 * standard array, one clear hook each for the DM to pull on.
 */
export const PREGENS = [
  {
    id: 'pregen-fighter',
    name: 'Бранд Железный Шаг',
    race: 'human',
    class: 'fighter',
    background: 'soldier',
    alignment: 'законно-нейтральный',
    skills: ['athletics', 'perception'],
    portraitColor: '#b45309',
    blurb: 'Бывший городской стражник. Ушёл со службы после того, как приказ велел ему смотреть в другую сторону.',
    hook: 'Ищет капитана, который отдал тот приказ.',
  },
  {
    id: 'pregen-rogue',
    name: 'Лисса Тихая Монета',
    race: 'halfling',
    class: 'rogue',
    background: 'criminal',
    alignment: 'хаотично-нейтральный',
    skills: ['stealth', 'sleight-of-hand', 'perception', 'deception'],
    portraitColor: '#6d28d9',
    blurb: 'Взломщица, которая берёт заказы только у тех, кому не может отказать.',
    hook: 'Должна крупную сумму гильдии, которая не принимает отсрочек.',
  },
  {
    id: 'pregen-wizard',
    name: 'Ирвен Пепельный Лист',
    race: 'elf',
    class: 'wizard',
    background: 'sage',
    alignment: 'нейтрально-добрый',
    skills: ['arcana', 'history'],
    portraitColor: '#0e7490',
    blurb: 'Переписчик из библиотеки, который прочитал книгу, которую читать не следовало.',
    hook: 'С тех пор ему снится дверь, которой нет ни на одной карте.',
  },
  {
    id: 'pregen-cleric',
    name: 'Мать Гелла',
    race: 'dwarf',
    class: 'cleric',
    background: 'acolyte',
    alignment: 'законно-добрый',
    skills: ['medicine', 'religion'],
    portraitColor: '#b91c1c',
    blurb: 'Полевой лекарь трёх войн. Верит, что боги слышат тех, кто работает руками.',
    hook: 'Ведёт список тех, кого не сумела спасти, и он длиннее, чем ей хотелось бы.',
  },
  {
    id: 'pregen-barbarian',
    name: 'Ская Волчья Тень',
    race: 'half-orc',
    class: 'barbarian',
    background: 'outlander',
    alignment: 'хаотично-добрый',
    skills: ['survival', 'intimidation'],
    portraitColor: '#166534',
    blurb: 'Охотница с северных пустошей. Пришла в город впервые в жизни и не в восторге.',
    hook: 'Идёт по следу твари, которая вырезала её стойбище.',
  },
  {
    id: 'pregen-ranger',
    name: 'Кайл Долгий Путь',
    race: 'half-elf',
    class: 'ranger',
    background: 'folk-hero',
    alignment: 'нейтральный',
    skills: ['survival', 'nature', 'stealth'],
    portraitColor: '#4d7c0f',
    blurb: 'Проводник, который знает дороги лучше, чем те, кто их строил.',
    hook: 'Последний караван, который он вёл, не дошёл. Он единственный вернулся.',
  },
  {
    id: 'pregen-bard',
    name: 'Верис Сладкий Язык',
    race: 'tiefling',
    class: 'bard',
    background: 'entertainer',
    alignment: 'хаотично-нейтральный',
    skills: ['persuasion', 'performance', 'deception'],
    portraitColor: '#be185d',
    blurb: 'Играет в тавернах, где за правильную песню платят больше, чем за хорошую.',
    hook: 'Знает секрет, за который его хотят убить как минимум двое.',
  },
  {
    id: 'pregen-paladin',
    name: 'Сир Одрик Немой Обет',
    race: 'human',
    class: 'paladin',
    background: 'noble',
    alignment: 'законно-добрый',
    skills: ['athletics', 'religion'],
    portraitColor: '#a16207',
    blurb: 'Дал обет не говорить о своём прошлом, пока не искупит его.',
    hook: 'Кто-то в этих краях знает, что он сделал.',
  },
];
