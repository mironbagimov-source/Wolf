# Что нашлось в игре

Снято с розничной Steam-сборки Dishonored 1.0 (приложение 205100), из
`DishonoredGame\Config`. Здесь записаны **факты о том, что игра умеет** —
имена команд и параметров, — а не содержимое файлов Arkane.

## Главное: у игры есть работающая консоль разработчика

`DefaultDebugMenu.ini` — не заглушка, а полноценное отладочное меню, которое
Arkane оставили в релизе. Из него виден список консольных команд, доживших до
розничной сборки. Часть из них закрывает задачи, под которые я планировал
реверс-инжиниринг.

### Загрузка карт

| Команда | Что делает |
|---|---|
| `start <карта>` | грузит карту напрямую |
| `ce <событие>` | запускает событие Kismet на уровне |
| `restartlevel` | перезапуск |

**Это решает нулевой пункт плана.** Я закладывал отдельный механизм «чистой
загрузки карты без миссионной логики» как обязательный для всех режимов —
оказалось, он в игре есть.

### Тестовые карты Arkane лежат в релизе

| Карта | Что это |
|---|---|
| `FT_combat` | полигон для боя |
| `DLC06_FT_combat` | то же для дополнения Дауда |
| `FT_Mechanics` | полигон механик |
| `Mit_hallway01` | карта персонажей |
| `FT_Routine` | полигон распорядков NPC |
| `DLC07_FT_Transition` | тест переходов |
| `Loc_Test` | локализация |

Чистые песочницы без сюжетных скриптов. Ровно то, что нужно и для проверки
сплит-скрина, и как основа для арены с кастомным режимом.

### Способности выдаются командой

```
addpower <имя> <уровень>
```

Активные: `bendtime`, `transversal`, `darkvision`, `summonassassin`,
`dauddarkvision`, `pull`.
Пассивные: `vitality`, `celerity`, `bloodthirsty`, `shadowkill`, `arcanebond`.

Существенно, что **`dauddarkvision` и `summonassassin` есть в базовой игре** —
силы Дауда зарегистрированы в общей системе, хотя контент лежит в дополнении.

Рядом: `MaxPowers`, `MinPowers`, `Manaadd`, `Manatoggle`, `GiveRunes`,
`givebonecharm`, `givecrackedbonecharm`.

### Предметы выдаются по пути к объекту

```
giveplayeritem DisTweaks_WepSword'Twk_Inv_PlayerSpecific.Twk_Inv_SwordCorvo'
addupgrade Twk_Upgrade_<название>
```

Пространство имён `Twk_Inv_PlayerSpecific` намекает, что оружие разложено по
персонажам — там же должны лежать клинок и арбалет китобоев.

### Управление ИИ

`AIDumb`, `AIBlind`, `AIDeaf`, `AINumb`, `AIDontAttack`, `AISetDebug`,
`NPCDestroy`, `NPCDestroyNonSelected`.

Готовые переключатели под правила режимов: слепые враги, глухие враги,
враги, которые не атакуют.

### Прочее

`ghost` / `walk` (полёт сквозь стены), `God`, `GodNPC`, `Buddha`,
`SetDifficulty 0-3`, `adddarkness` (хаос), `playerinfiniteammo`,
`GoreEnable`, `SwitchDLCLock 0-9`, `dis_save N` / `dis_load N`,
`SetPlaytestFlag`, `PlayerToggleAimAssist`, `Exit`.

Отладочные виды: `ShowDebug AnimState|Attributes|Blood|Inventory|PlayerState|PlayerCamera`,
`stat Player|NPC|AIBehavior|DisPawn`, `dmem`, `dstat`.

### Испытания Dunwall City Trials запускаются командой

```
DLC05StartChallenge DDCL_<название> <TRUE|FALSE>
```

Названия: `Countdown`, `Race`, `DropAttack`, `OilRain`, **`Arena`**, `Thief`,
`BendTimeMassacre`, `AssassinTraining`, `ChainKill`, `MysteryMan`.
Второй аргумент — экспертный режим.

`DDCL_Arena` — это «Back Alley Brawl», готовая арена. Мы её вычёркивали из
плана как слишком дорогую; выяснилось, что каркас уже есть.

### Консоль умеет выполнять файлы команд

```
exec <файл>.txt
```

В меню упоминаются `DebugVisibility.txt`, `DebugLOS.txt`, `DebugVisionCone.txt`,
`StealthBeep.txt`, `DebugStealth.txt` — значит, такие файлы лежат где-то в
установке.

**Это готовый слой скриптов.** Мод может поставляться как набор `.txt` с
командами, без единой правки бинарных файлов. Между слоем конфигов и нативным
слоем появляется третий, которого не было в плане.

## Персонаж игрока задаётся строкой в конфиге

`DefaultGame.ini`, секция `DishonoredGame.DishonoredGameInfo`:

```
m_CampaignPawnTweak=Twk_Pawn_Corvo.Twk_Pawn_Corvo_Release
m_CampaignPawnTweakPackage=Twk_Pawn_Corvo_SF
m_DefaultPawnTweak=Twk_Pawn_Corvo.Twk_Pawn_Corvo
m_DefaultPawnTweakPackage=Twk_Pawn_Corvo_SF
```

Гипотеза, высказанная по `DishonoredInput.ini`, подтвердилась полностью:
**пешка игрока — это ссылка на твик-объект, и ссылка лежит в текстовом
конфиге**. Отдельно для кампании и для остальных случаев, с явным указанием
пакета.

Если в дополнении есть `Twk_Pawn_Daud`, смена персонажа сводится к правке двух
строк. Проверяется командой `Obj List Package=Twk_Pawn_Daud_SF` или поиском по
пакетам DLC06.

Это опрокидывает прежнюю оценку: выбор персонажа переезжает из нативного слоя
в конфиги.

## У игрока есть номер фракции

`DefaultGame.ini`:

```
[DefaultPlayer]
Name=Corvo
Team=255
```

Плюс в списке отладочных категорий есть **`Factions`** — то есть система
фракций в игре существует и у неё даже своя отладочная визуализация
(`ShowDebug Factions`).

`Team=255` — тот самый крючок, через который игрок может принадлежать стороне.
Это ядро ролевого режима, и оно оказалось в конфиге.

## Меню испытаний — готовый выбор режимов

`DisDLC05GameInfo` описывает испытания Dunwall City Trials **данными**:

```
.m_Challenges=(m_ID="Arena",m_Type=DDCT_Action,m_Leaderboard=DDCL_Arena,
               m_LaunchCommand="start L_DLC05_Arena_P")
m_ChallengeMenuLaunchCommand="start L_DLC05_MainMenu_P"
```

У каждой записи произвольная **команда запуска**. Список задаётся в конфиге,
значит в него можно дописывать свои пункты.

То есть в игре уже есть **готовое меню выбора режима**, управляемое текстом.
Хаб в Бездне остаётся более красивым решением, но меню испытаний доступно
прямо сейчас и без единой новой карты.

## Интерфейс подменяется по фильтру карты

`DisGlobalUIManager`:

```
m_DefaultUI=(m_HUDMoviePath="UI_HUD.HUD",m_PowerWheelMoviePath=...,
             m_JournalMoviePath=...,m_PauseMenuMoviePath=...)
.m_DLCUI=(m_MapFilter="DLC06",m_HUDClassName="DisDLC06MoviePlayerHUD",...)
```

Интерфейс выбирается **по префиксу карты**. Для дополнений заданы свои HUD,
колесо, журнал и меню паузы. Значит, для своего набора карт можно объявить
свой интерфейс — включая пустой.

Рядом `m_bTutorialsEnabled=TRUE` в `DisGFxMoviePlayerHUD` — обучающие
подсказки выключаются одной строкой.

## Список способностей в интерфейсе — тоже данные

`DisGFxMoviePlayerJournal` перечисляет активные и пассивные силы записями
`.m_ActivePowerSlots` / `.m_PassivePowerSlots`. У дополнений свои наборы:
у DLC06 — `transversal`, `summonAssassin`, `daud_dark_vision`, `arcane_bond`;
у DLC07 добавляется `pull`.

Набор сил персонажа в интерфейсе задаётся конфигом, а не кодом.

## Имена карт кампании

`m_MissionsGame` перечисляет все карты по миссиям. Нужные нам:

| Что | Карты |
|---|---|
| Пролог, Корво до метки | `L_Tower_P` |
| Затопленный квартал | `L_Flooded_FIntro_P`, `L_Flooded_FStreets_P`, `L_Flooded_FAssassins_P`, `L_Flooded_FGate_P`, `L_Flooded_FRefinery_P` |
| Особняк Бойл | `L_Boyle_Ext_P`, `L_Boyle_Int_P` |
| Возвращение в Башню (палач) | `L_TowerRtrn_Yard_P`, `L_TowerRtrn_Int_P` |
| Бойня Ротвайлда | `DLC06_Slaughter_Ext_P`, `DLC06_Slaughter_Int_P` |
| Арена испытаний | `L_DLC05_Arena_P` |

Грузятся командой `start <карта>`.

## Отладочное меню открывается с клавиатуры

Команды навигации по меню живут в привязках клавиш (`DishonoredInput.ini`):

| Команда | Что делает |
|---|---|
| `ToggleDebugMenu` | **открывает и закрывает меню** |
| `DebugMenuEnter` | подтвердить пункт |
| `DebugMenuUp` / `Down` / `Left` / `Right` | навигация |

`ToggleDebugMenu` привязан к **Backspace** в секции `BaseBindings`, навигация —
на стрелках и Enter там же. К геймпаду меню привязано отдельно: открытие на A,
навигация на крестовине, во всех четырёх наборах `m_PadBindingSet1-4`.

Если базовые привязки перекрываются игровыми, команды добавляются в
`[Engine.PlayerInput]` в формате `m_PCBindings=(Name="F2",Command="ToggleDebugMenu")`
— без точки в начале, рядом с остальными такими же строками.

Важно не перепутать: меню открывает `ToggleDebugMenu`, а `DebugMenuEnter` лишь
подтверждает пункт в уже открытом.

### Структура файла привязок

- `[Engine.PlayerInput]` — здесь и `BaseBindings` (движковые), и `m_PCBindings`
  (клавиатура), и `m_PadBindingSet1-4` (геймпад)
- `[Engine.Console]` — `ConsoleKey=Tilde`, `TypeKey=Tab` уже заданы
- `[DishonoredGame.DishonoredPlayerInput]` — только ссылка на твик-объект
  `Twk_Pawn_DefaultPlayer.Twk_Pawn_PlayerInput`
- `[IniVersion]` — по этим номерам игра решает, что конфиг устарел, и
  перегенерирует его, стирая правки. Отсюда необходимость атрибута «только
  чтение»

## Отрезвляющее: настройки живут не только в ini

Приставка `Twk_` в командах (`Twk_Inv_SwordCorvo`, `Twk_Upgrade_Pistol`)
показывает, что у Arkane есть система «твик-объектов»: игровые величины
хранятся в объектах внутри пакетов `.upk`, а не в текстовых конфигах.

Значит, INI-слой тоньше, чем я рассчитывал, а слой UPK важнее. Часть правок
всё равно потребует работы с пакетами. Хорошая новость в том, что консоль и
`exec`-скрипты частично это компенсируют: многое настраивается в рантайме.

## Что подтвердилось в конфигах

### Система шума — в ini

`DefaultAI.ini`, секция `DisAINoiseManager`: массив `m_LoudnessDistanceArray`
из 17 значений, отображающий уровень громкости в расстояние слышимости
(от 200 до 6000). Прямо настраивается — для хоррор-режима это главный рычаг.

### Поиск игрока — в ini

Секция `DishonoredSearchCrumbsComponent`: время жизни следа, число точек
поиска, шаг блуждания. Отдельно радует `m_fChanceOfPsychicSearch` — у ИИ есть
шанс «телепатически» пойти в сторону игрока.

### Бой — в ini

`DisGlobalCombatManager`: времена сдерживания для каждого типа атаки и, главное,
`m_InnerSkirmishCaps` / `m_TotalSkirmishCaps` — сколько врагов одновременно
лезет в драку. Реакция ИИ: `m_ReactionDelay` 0.18–0.3 секунды,
`m_MagicReactionDelay` 0.2–0.3.

### Блинк — в ini

`DefaultPower.ini`, `DishonoredActivePowerComponent_Blink`: дальность по
горизонтали 1400, по вертикали 600, разогрев, откат, длина шага. Там же
`m_fBendTimeDownTime` и `m_fBendTimeUpTime` — **замедление времени при
прицеливании блинка уже параметризовано**, а это фирменная черта Дауда.

Рядом остались прототипные значения `m_fPROTOTYPE_MaxHorizDistance=2000`.

## Ошибка в прошлых предположениях

`DefaultContactSystem.ini` я записал в систему обнаружения — **это не так**.
Там типы поверхностей и поведение снарядов при попадании: куда липнут гранаты,
где срабатывают пружинные бритвы, что делает снаряд при контакте — блокируется,
уничтожается или пролетает насквозь.

Для стелса бесполезно, для ловушек кастомного режима — наоборот.

## Словарь скриптовых функций

Снят с живой игры режимом `dump`: 303 функции с объектами, на которых они
впервые вызвались. Полный список — [names-dump-1.txt](names-dump-1.txt).

Это первые данные, полученные из работающей игры, а не из конфигов. Всё ниже —
не догадки, а имена, которые движок произнёс сам.

### Классы, из которых собран мир

| Класс | Что это |
|---|---|
| `DishonoredGameInfo` | правила забега: спавн, смерть, пауза |
| `DishonoredPlayerController` | контроллер игрока |
| `DishonoredPlayerPawn` | тело игрока |
| `DishonoredNPCPawn` | тело NPC |
| `DishonoredNPCController` | мозг NPC |
| `DisPossessionProxyPawn` | **пешка-посредник при вселении** |
| `DishonoredViewportClient` | окно вывода, в том числе разделённое |
| `DishonoredPlayerCamera`, `DishonoredPlayerInput`, `DishonoredHUD` | камера, ввод, интерфейс |

### Играть за NPC: путь найден

Утверждённый дизайн требует, чтобы контроллер игрока владел `DishonoredNPCPawn`.
В словаре видна вся цепочка, по которой игра выдаёт игроку тело:

```
DishonoredGameInfo::RestartPlayer
  → SpawnDefaultPawnFor
      → GetDefaultPlayerClass     ← здесь решается, кем ты будешь
      → SpawnPlayer
  → DishonoredPlayerController::Possess
```

`GetDefaultPlayerClass` — единственная точка, где выбирается класс тела. Хук на
неё подменяет ответ, и дальше игра сама заспавнит NPC и сама привяжет к нему
контроллер: `Possess` вызывается тем же кодом и ничего не знает о том, какой
класс ему дали.

Существование `DisPossessionProxyPawn` подтверждает догадку из дизайна: игра
уже умеет отдавать игроку чужое тело, для этого у неё заведён отдельный класс.

### Смерть: игра сама разрешает её отменить

```
DishonoredGameInfo::PreventDeath  /  PreventDeath_Native
DishonoredNPCPawn::ChooseAndTriggerDeathEvent_Native
DishonoredNPCPawn::PlayDying_Native
DishonoredNPCController::NotifyKilled
DishonoredPlayerController::PawnDied
```

`PreventDeath` — готовая точка отмены. Трёхступенчатая смерть, которую мы
придумали (агония → тело → переход), не требует обхода движка: он сам
спрашивает разрешения, прежде чем убить.

`ChooseAndTriggerDeathEvent` и `PlayDying` есть **и у NPC, и у пешки игрока** —
то есть выбор конкретной анимации смерти проходит через одну и ту же функцию, и
играя NPC-телом, мы попадаем в неё автоматически.

### Сплит-скрин существует в этой сборке

```
DishonoredViewportClient::UpdateActiveSplitscreenType
DishonoredViewportClient::GetSplitscreenConfiguration
```

Обе вызываются при обычном одиночном запуске. Значит поддержка разделённого
экрана в коде есть и просто не включена — это не отсутствующая функция, а
неактивная.

### Прочее, что пригодится

| Функция | Зачем |
|---|---|
| `DishonoredPlayerController::SetCharacter` | выбор персонажа, вызывается при старте |
| `DishonoredGameInfo::AddDefaultInventory` | выдача снаряжения — набор китобоя для Томаса |
| `IgnoreMoveInput`, `IgnoreLookInput`, `SetCinematicMode` | отобрать управление, не трогая камеру: ровно то, что нужно, когда Корво вселяется в игрока |
| `DishonoredNPCController::NotifyTakeHit` | реакция NPC на попадание |
| `SeqEvent_Death`, `SeqEvent_Touch` | события Kismet — связь с логикой карты |

### Чего в словаре нет

Разговоров: ни `Convo`, ни `Dialog`, ни `Talk`. В этом заходе с гостями не
разговаривали, поэтому имя события выбора фракции по-прежнему неизвестно.
Нужен ещё один проход — с разговорами и боем.

Не видно и состояний `StateNPCMaster*` из конфигов: состояния в UE3 — не
функции, через `CallFunction` они не проходят. Их имена придётся ловить иначе.

## Что искать дальше

- **Команды спавна и смены пешки** в отладочном меню отсутствуют. Меню — лишь
  выборка, поэтому команды могут существовать: у UE3 есть штатный `summon`,
  а семейство `dis_*` намекает на собственные.
- **`debugcreateplayer 1`** — не проверено, но это главный вопрос по
  сплит-скрину.
- **Файлы `Debug*.txt`** где-то в установке — по ним видно синтаксис
  exec-скриптов.
- **Содержимое дополнений** — риг и оружие китобоев лежат в пакетах DLC06 и
  DLC07, в базовой игре их нет.
