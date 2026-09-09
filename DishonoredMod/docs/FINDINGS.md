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

> **Отменено.** Второй проход не понадобился, и вывод «нужен ещё заход» был
> неверен по самой постановке. Словарь событий показывает только то, что
> успело вызваться, — искать в нём отсутствующее бессмысленно. В таблице имён
> разговоры нашлись сразу и целиком: 114 классов `DisConv_*`, см. «Разговоры:
> система найдена» ниже. Урок общий: об устройстве игры спрашивать надо
> таблицу имён, а поток событий — только о том, что происходит прямо сейчас.

Не видно и состояний `StateNPCMaster*` из конфигов: состояния в UE3 — не
функции, через `CallFunction` они не проходят. Их имена придётся ловить иначе.

## Что реально установлено в игре

Список пакетов снят с установки инструментом `tools/survey`.

### Дополнений нет

Ни одного пакета `DLC06` или `DLC07`. Установлена только базовая кампания:
Tower, Prison, Streets, Distillery, Brothel, Bridge, Boyle, Overseer, Flooded,
Island, Lighthouse. Ни «Knife of Dunwall», ни «Brigmore Witches», ни арены
Dunwall City Trials.

> **Неверно.** `DLC06_Slaughter_Int_Assassin.upk` нашёлся в установке: 7 МБ,
> 9655 экспортов, 7911 имён — полноценный пакет содержимого, а не заглушка.
> Значит «Knife of Dunwall» на месте, и обзор его не увидел. Скорее всего
> обзор смотрел не туда: пакеты дополнений лежат отдельно от кампании.
> Разбор пакета — в разделе «Что лежит в пакете дополнения» ниже.

### Но китобои в базовой игре есть

Это меняет вывод про Томаса, который иначе упирался бы в шесть недостающих
ассетов.

| Что нашлось | Где |
|---|---|
| Карта с китобоями Дауда | `L_Flooded_FAssassins_P.upk` и её Script/Nav/Stealth |
| Звуки ассасина | `Bank_AI_Assassin.pck` плюс три банка движения: приземление, скольжение, ветер |

Китобои — обычные враги затопленного района, поэтому риг, анимации и звуки
лежат в базовой игре. Из набора Томаса недостаёт только того, что было
собственным снаряжением Дауда: мини-арбалета и его личных способностей.

### Все фракции ролевого режима существуют

| Фракция | Звуковой банк |
|---|---|
| Аристократ | `Bank_AI_Aristo_Male` |
| Служанка, горожанка | `Bank_AI_Civ_Woman`, `Bank_AI_Broom`, `Bank_AI_Scrub_Floor` |
| Стража | `Bank_AI_Guard` |
| Смотритель | `Bank_AI_Overseer`, **`Bank_AI_Overseer_Music`** — шкатулка звучит отдельно |
| Плакальщик | `Bank_AI_Weeper` |
| Бандит | `bank_AI_Thug` |
| Палач | `Bank_AI_Executioner`, `Bank_AI_Executioner_Poker` |

Отдельный банк музыки смотрителя подтверждает, что «Гимн» — не выдумка
дизайна, а существующая в игре сущность со своим звуком.

### Точки отвлечения и приёма

`Bank_FixInt_Instr_Piano`, `Instr_Harp`, `Instr_Music_Box`,
`Bank_FixInt_Music_Player_Boyle` — те самые категории из `DefaultNPC.ini`
(Piano, Harp, Art, Dusting), уже расставленные по картам.

Карта приёма на месте целиком: `L_Boyle_Int_P` вместе с `_Basement`,
`_Stealth`, `_Script`. Любопытно, что «Soiree» используется не только там —
`L_Pub_Day_Soiree`, `_Dusk_`, `_Morning_`, `_Night_` показывают, что система
приёмов работает и в Песьей Яме.

## CallFunction видит не всё

Два словаря, снятых в разных сеансах, дали 271 и 270 имён — новых во втором
всего три. При этом во втором сеансе шёл бой: в словаре есть смерть NPC,
падение, кровь.

Значит `CallFunction` ловит вызовы скрипта из скрипта, а событий, которые
поднимает в скрипт нативный код игры, через неё не проходит. Отсюда и
отсутствие разговоров в обоих словарях.

Для подмены тела этого достаточно — `GetDefaultPlayerClass` в словаре есть. Для
ловли событий нужна `ProcessEvent`, и она пока не найдена.

### Что известно про её поиск

Раскладка `UFunction` вскрылась попутно:

| Поле | Смещение |
|---|---|
| `FunctionFlags` | `+0x80` |
| `iNative` | `+0x84` |
| `Func` | `+0x9C` |

Найдено по единственному месту в коде, где `Func` получает значение по
умолчанию: `movl $0x45ff10, 0x9c(%ebx)` по адресу `0x0046E818` — то есть туда
пишется `ProcessInternal`.

Проверенные и отброшенные ходы:

- прямых вызовов через `call [reg+0x9C]` в коде нет — вызов идёт через регистр;
- загрузок поля `+0x9C` пятьсот шестьдесят шесть, смещение слишком популярно у
  других структур;
- среди самых часто вызываемых функций (до семнадцати тысяч прямых вызовов) ни
  одна не читает полей `UFunction` — значит `ProcessEvent` вызывается
  виртуально.

Следующий заход стоит делать не статически, а тем же способом, который уже
сработал с `CallFunction`: поставить счётчики на кандидатов и дать ответить
самой игре.

## Таблица имён: 66 417 имён из живой игры

Снята режимом `namedump`, сжатая копия — [gnames-dump.txt.gz](gnames-dump.txt.gz).
Это то, ради чего иначе пришлось бы разбирать пакеты игры.

### Готовые роли: `Twk_Pawn_*`

Тридцать три настроенные пешки, и почти весь ролевой режим уже назван:

```
Twk_Pawn_Corvo            Twk_Pawn_Executioner      Twk_Pawn_Tallboy
Twk_Pawn_LadyEsmaBoyle    Twk_Pawn_GuardCaptain     Twk_Pawn_WolfHound
Twk_Pawn_LadyLydiaBoyle   Twk_Pawn_LordPendleton    Twk_Pawn_PossessionProxy
Twk_Pawn_LadyWaverlyBoyle Twk_Pawn_OverseerCampbell Twk_Pawn_DefaultNPC
Twk_Pawn_LadyEmily        Twk_Pawn_OverseerMartin   Twk_Pawn_DefaultPlayer
Twk_Pawn_Boyle            Twk_Pawn_Outsider         Twk_Pawn_Empress
Twk_Pawn_AdmiralHavelock  Twk_Pawn_AntonSokolov     Twk_Pawn_LordRegent
Twk_Pawn_PendletonBrother Twk_Pawn_Piero            Twk_Pawn_Calista
Twk_Pawn_Boatman          Twk_Pawn_BoatmanHub       Twk_Pawn_Martin
Twk_Pawn_Lighthouse       Twk_Pawn_Tower            Twk_Pawn_E3
```

**Все три сестры Бойл — отдельными настроенными объектами.** Роль хозяйки дома
не нужно собирать: она в игре уже есть, вместе с Палачом и капитаном стражи.

Список — поимённые персонажи сюжета. Массовку игра держит отдельно, под
префиксом `Pwn_`, и для приёма у Бойл она важнее: гостей на этой карте больше,
чем сестёр.

```
Pwn_Aristo        Pwn_TowerAristo   Pwn_MiddleClass   Pwn_Servant
Pwn_AristoFlooded Pwn_WeeperAristo  Pwn_Prostitute    Pwn_ServantLydia
Pwn_Civ           Pwn_BrothelMadam  Pwn_MusicOverseer Pwn_Cecelia
Pwn_Guard         Pwn_CityGuard     Pwn_EliteGuard    Pwn_LowerGuard
Pwn_Overseer      Pwn_OverseerHMaster Pwn_Thug        Pwn_ThugWhiskey
Pwn_Assassin      Pwn_AssassinIntro Pwn_Daud          Pwn_WolfHound
```

Аристократы трёх сортов, слуги, музыканты-смотрители и четыре ступени стражи —
это и есть гости приёма. Ролевому режиму не нужно придумывать, кем играть:
роли уже разложены по сословиям.

### Класс твика читается прямо из таблицы имён

Часть записей — не имена, а строки вида `пакет+++объект класс`:

```
Twk_Pawn_Corvo+++Twk_Pawn_Corvo DisTweaks_PlayerPawn
Twk_Pawn_LadyEsmaBoyle+++Twk_Pawn_LadyEsmaBoyle DisTweaks_NPCPawn
Pwn_Daud_MTall_1+++Pwn_Daud_MTall DisTweaks_NPCPawn
```

Это меняет цену вопроса. Раньше связка «объект → его класс» добывалась только
обходом памяти, ради которого писался режим `objdump`. Здесь она лежит
готовой строкой, и по ней сразу видно главное различие: **`DisTweaks_PlayerPawn`
против `DisTweaks_NPCPawn`**. Ровно на нём стоит решение играть за настоящего
NPC, а не за Корво в чужой одежде.

Разбор по классам даёт 83 объекта `DisTweaks_NPCPawn` и три
`DisTweaks_PlayerPawn` — `Twk_Pawn_Corvo`, `Twk_Pawn_Corvo_Release` и
`Twk_Pawn_DefaultPlayer`. Игровых тел в игре ровно три, всё остальное —
неигровые.

### Разговоры: система найдена

Открытый вопрос «как называется событие разговора» закрыт, и ответ оказался
шире вопроса. Разговоры в Dishonored — не событие, а движок из 114 классов с
префиксом `DisConv_`, и он управляется данными.

Условия — чем разговор начинается:

```
DisConv_Hook_KismetActivated      DisConv_Hook_WitnessedInteraction
DisConv_Hook_Notice               DisConv_Hook_WitnessedMagic
DisConv_Hook_NoticeBroken         DisConv_Hook_SuspicionLevel
DisConv_Hook_PlayerLookAt         DisConv_Hook_SuspicionDist
DisConv_Hook_PlayerLoiter         DisConv_Hook_DeathMode
```

Ветвления и проверки — чем разговор идёт дальше:

```
DisConv_PlayerChoice              DisConv_CheckSpeakerRelationship
DisConv_FactionBranch             DisConv_CheckSpeakerSuspicionLevel
DisConv_SpawnerBranch             DisConv_CheckStoryFlag
DisConv_SpeakerHasTweaks          DisConv_SetStoryFlag
DisConv_SpeakerInStoryGroup       DisConv_IsPossessed
DisConv_RandomBranch              DisConv_CompareDarknessLevel
```

Три из них снимают отдельные задачи мода целиком:

- **`DisConv_PlayerChoice`** — выбор игрока в разговоре. Меню выбора фракции не
  нужно рисовать: это узел разговора.
- **`DisConv_FactionBranch`** — ветка по фракции говорящего. Один и тот же
  разговор ведёт себя по-разному со стражником и с гостем, и это данные, а не
  код.
- **`DisConv_Hook_KismetActivated`** — разговор запускается из скрипта уровня.
  Отсюда мод входит в систему.

### Опасность «увидеть лишнее» уже реализована

Дизайн NPC-Корво держится на том, что смертельно не быть выслеженным, а
застать его за делом. Оказалось, что игра умеет это без нас:

| Что нужно | Чем сделано |
|---|---|
| Тебя заметили за незаконным | `DisConv_Hook_WitnessedInteraction` |
| Увидели, как ты колдуешь | `DisConv_Hook_WitnessedMagic` |
| Ты слишком долго смотришь | `DisConv_Hook_PlayerLookAt` |
| Ты околачиваешься где не надо | `DisConv_Hook_PlayerLoiter` |
| Нашли следы — сломанное, труп | `DisConv_Hook_NoticeBroken` |
| Накопленное подозрение | `DisConv_Hook_SuspicionLevel`, `DisConv_Hook_SuspicionDist` |

Свидетель, подозрение и реакция на увиденное — это готовая петля. Ролевому
режиму остаётся подключить к ней своего Корво, а не строить её заново.

### Приём у Бойл: своя фракция и сорок флагов

У карты собственный пакет фракций:

```
Boyle_Factions.Neutral_Civilian
Boyle_Factions.Neutral_Guard
```

**Нейтральные гость и стражник уже существуют** — именно те две стороны, за
которые задуман ролевой режим. Плюс общие умолчания:
`DisFaction_Defaults.Faction_Corvo_Default`, `Faction_Assassin_Default`,
`Faction_Guard_Default`, `Faction_Civilian_Default`, `Faction_Conspiracy_Default`.

Фракция переопределяется на ходу: `m_pFactionTweakOverride`,
`m_FactionOverrideMap`, `m_FriendlyFactionsOverride`. То есть стать гостем — это
подмена ссылки, а не переписывание отношений.

Состояние миссии — около сорока сюжетных флагов, и читаются они как сценарий:

```
Boyle_Has_Invitation        Boyle_SuspectEsma        Boyle_HasDrink
Boyle_against_rules         Boyle_SuspectLydia       Boyle_RequestDrinkOk
Boyle_Alarm_Rung            Boyle_SuspectWaverly     Boyle_TalkedwithOutsider
Boyle_RamseyTellsOnPlayer   Boyle_PlayerKnowsGuiltyGirl
Boyle_Player_Knows_All3_Girls  Boyle_Waverly_Red     Boyle_Waverly_White
```

**`Boyle_against_rules`** — флаг «ты нарушаешь правила приёма». Основной цикл
ролевого режима уже назван по имени и уже проверяется разговорами через
`DisConv_CheckStoryFlag`.

### Светский приём — отдельная подсистема

```
StatePlayerMasterSoiree           DisConv_Soiree
DisBehaviorSoiree                 DisConvoEndReason_SoireeRejection
DisTweaks_AIBehavior_Soiree       InterpTrackSoireeControl
AnimNotify_SoireeIn / Loop / Out / Accent / Apex / End
```

`StatePlayerMasterSoiree` — **состояние игрока на приёме**, не NPC. Игра уже
умеет ставить игрока в светский режим: с танцем (шесть анимационных отметок),
с поведением гостей вокруг и с возможностью получить отказ
(`SoireeRejection`). Социальный стелз ролевого режима опирается на готовую
подсистему.

Видимость игрока переопределяется на трёх уровнях —
`m_pGlobalPlayerVisSettings`, `m_pMapPlayerVisSettings`,
`m_pScriptedPlayerVisSettings` — и переключается из скрипта:
`DisSeqAct_SetPlayerVisSettings`, `DisSeqAct_ClearPlayerVisSettings`. Это ручка
«насколько ты сейчас свой».

### Смерть игрока умеет отменяться штатно

```
DisSeqAct_DLC05_PlayerBusted      DisSeqAct_DLC05_PlayerResurrect
DisSeqAct_OverridePossess         DisPossessionProxyPawn
```

Испытания используют пару «попался» + «воскрес» как обычные действия скрипта.
Утверждённое правило «удушение и вселение не заканчивают забег, а после смерти
продолжаешь другим гостем» ложится на них напрямую.

`DisPossessionProxyPawn` вместе с `Twk_Pawn_PossessionProxy` и его полным
набором подтвиков (`Actions`, `Animation`, `Attributes`, `Body`, `Combat`) —
готовое тело-посредник, через которое игрок управляет чужой пешкой.

### Кем можно стать: `Twk_Possessable_*`

```
Twk_Possessable_BaseNPC     Twk_Possessable_Daud      Twk_Possessable_Rat
Twk_Possessable_Servant     Twk_Possessable_Emily     Twk_Possessable_Fish
Twk_Possessable_BaseAnimal  Twk_Possessable_Outsider  Twk_Possessable_Wolfhound
```

Список важен вдвойне. Он подтверждает, что игрок может владеть NPC-телом — это
опора утверждённого дизайна. И в нём есть **`Twk_Possessable_Daud`**: вселение
в китобоя предусмотрено самой игрой.

### Смертей больше, чем считалось

```
StateNPCMasterBeingAssassinated   StateNPCMasterDead_Limp
StateNPCMasterBeingChoked         StateNPCMasterDead_Electrocuted
StateNPCMasterDead                StateNPCMasterDead_BeingCarried
StateNPCMasterActionImmolate      StateNPCMasterThrown
```

У каждого есть парный `_Template` — то есть это настраиваемые твик-объекты, а
не зашитые состояния.

**`StateNPCMasterDead_BeingCarried`** в дизайне не учитывалось, а зря: Корво
таскает тела, и играя за жертву, ты попадёшь именно в него. Ровно та сцена,
которую мы придумали для второй ступени смерти, — уже есть под своим именем.

### Код дополнений в игре есть, нет только ассетов

```
DisDLC06AssassinNPCPawn      DisDLC07AssassinNPCPawn
DisDLC06ButcherNPCPawn       DisDLC07GravehoundNPCPawn
DisDLC06SummonedAssassinNPCPawn  DisDLC07TentacleNPCPawn
```

Классы вкомпилированы в исполняемый файл, хотя пакетов нет. Значит недостача —
только в моделях и анимациях, а не в логике.

### На что опираются способности Томаса

| Способность | Что уже есть в игре |
|---|---|
| **Void Hunt** — ярость | `TwkAttackPattern_BerserkerElite`, `TwkAttackPattern_SwordBerserker` — паттерны атаки берсерка; `Attribute_AdrenalineBurnRate`, `Attribute_AdrenalineMultWhenTakingDamage` — система адреналина |
| **Вышибание дверей** | `DisDoorBreakSteps`, `DoorBreakable`, `doors_twk.BreakableDoorBase` — ломание дверей существует и настраивается по шагам |
| **Пробитие блока** | `Attribute_BlockBreakRate_Min` и `_Max` |
| **Похищение души** | `DisSoulRenderInterface`, `DisSoulMaterial`, `m_pSoul`, `m_aDisplayedSouls`, `m_bSoulRendering`, `DarkVision_Souls_INST` — душа как отображаемая сущность со своим материалом и шейдерами |

Ни одна из двух новых способностей не требует придумывать механику с нуля:
берсерк, ломаемые двери, пробитие блока и видимая душа — всё это игра уже
умеет, и настраивается твиками.

## Что искать дальше

- **Команды спавна и смены пешки** в отладочном меню отсутствуют. Меню — лишь
  выборка, поэтому команды могут существовать: у UE3 есть штатный `summon`,
  а семейство `dis_*` намекает на собственные.
- **`debugcreateplayer 1`** — не проверено, но это главный вопрос по
  сплит-скрину.
- **Файлы `Debug*.txt`** где-то в установке — по ним видно синтаксис
  exec-скриптов.
- **Содержимое дополнений** — риг и оружие китобоев лежат в пакетах DLC06 и
  DLC07, в базовой игре их нет. Но `Pwn_Assassin_MTBase` и `Pwn_Daud_MTall_1`
  идут с базовой игрой как `DisTweaks_NPCPawn`, поэтому Томас собирается и без
  дополнений.
- **Формат данных разговора.** Классы `DisConv_*` найдены, а вот в каком виде
  разговор лежит в пакете — нет. Без этого узел `DisConv_PlayerChoice` не
  добавить, а на нём стоит выбор фракции.
- **Чем задаётся фракция пешки.** `m_pFactionTweakOverride` и
  `m_FactionOverrideMap` найдены как имена свойств; какому классу они
  принадлежат и правятся ли из конфига — неизвестно.

## Что лежит в пакете дополнения

`DLC06_Slaughter_Int_Assassin.upk` — бойня из «Knife of Dunwall» вместе с
китобоями. Заголовок пакета сжат кусками по 128 КБ, кодек LZO1X; распаковав
их, таблицы читаются обычным разбором пакета UE3 (`tools/upk.py`).

Китобой как настроенная пешка — со всем набором подтвиков:

```
DLC06_Pwn_Assassin_1+++DLC06_Pwn_Assassin_Base DisDLC06Tweaks_NPCPawn
    :pActionTweaks      :pAnimationTweaks   :pAttributeTweaksNormal
    :pBodyTweaks        :pCombatTweaks      :pInteractableTweaks
    :pStateNPCMasterDead_BeingCarriedTweaks
DLC06_Pwn_Assassin_Lieut
AI_BrainTweaks_Assassin.BrainTweaks_Assassin
```

Способности китобоя названы отдельно: `AI_Assassin_Pwr_Teleport_Start` и
`_End` — перенос, `AI_Assassin_Pwr_Attract_Loop` — притягивание,
`AI_Assassin_Ranged_Attack_Fire` — стрельба.

Анимации на месте: полный набор `ADD_Sword_Aim*`, семейство `Crossbow_Fire`,
`Crossbow_Reload*`, `Crossbow_FastReload`, и добивания
`DisNPCAnim_AssassinationDramatic_Back`, `DisNPCAnim_AssassinationDrop`,
`DisNPCAnim_ShortFatality_Backhand` и `_Forehand`.

### Обе способности Томаса — настройки, а не код

| Что нужно | Чем задаётся |
|---|---|
| Удар не блокируется | `m_bUnblockable` — готовый флаг твика |
| Выводит из равновесия | `eDisVulnerabilityType_OffBalance`, окно уязвимости `m_fVulnerableTime_Knockdown` и `_Dizzy`, ограничение действий `m_bAllowWhenOffBalance` |
| Арбалет как скрытый клинок | `Crossbow_Fire`, `Crossbow_Reload_In` / `_Out` — анимации есть |
| Ярость Void Hunt | `TwkAttackPattern_SwordBerserker` — паттерн атаки берсерка; адреналин копится, в том числе `m_fAdrenalineAddedParryWin` |

Ни одна не требует новой механики. «Неблокируемый удар, выводящий из
равновесия» — это два готовых поля, а не задача программирования.

## Приём у Бойл снят с живой карты

Срез сделан прямо на `L_Boyle_Int_P`. Против прошлой сессии таблица имён
выросла на 3459 записей, и это целиком начинка приёма. Она отвечает на главный
вопрос ролевого режима — из чего собирать роль гостя — и ответ оказался
«ни из чего, она уже собрана».

### Дерево светских сцен

```
Soiree_Directory
    Soiree_JumpTo_BilliardRoom        Soiree_JumpTo_RegentBadMouthing
    Soiree_JumpTo_BusinessSucks       Soiree_JumpTo_SawTheft
    Soiree_JumpTo_ChatWithBuddy       Soiree_JumpTo_UpstairsWarning
    Soiree_JumpTo_IdleWithJack        Soiree_JumpTo_LordBrisbyQuestStart
```

`Soiree_Directory` — узел разговора с восемью переходами, то есть готовое
ветвление светских сцен. Выбор фракции — это ещё одна ветка в структуре,
которая уже существует, а не новое меню.

Две ветки стоят особняком. **`Soiree_JumpTo_SawTheft`** — сцена «гость увидел
кражу», **`Soiree_JumpTo_UpstairsWarning`** — «тебе не место наверху». Ровно та
механика, вокруг которой строился NPC-Корво: опасно не быть выслеженным, а
попасться на глаза за неположенным. Она написана и лежит на карте.

Рядом — управление сценами из скрипта: `entersimplesoiree`,
`BilliardRoomSoireeStart`, `RegentBadMouthingSoireeStart`,
`StartBusinessSuxSoiree`, `StartIdleWithJackSoiree`, `StopIdleWithJackSoiree`,
`EndBoatSoiree`, `stop stephen soiree`. И подбор собеседника: `randomguest`,
`guestused`, `two_guest_idle`.

### Роли гостей и стражи

```
Pwn_AristoParty_MTall_1 … _6      Pwn_EliteGuard_MTall_0 … _5
Pwn_Aristo_F_1 … _4               Pwn_EliteGuard_MTall_2_Doorman
Pwn_Aristo_MTall_1                Pwn_EliteGuard_MTall_*_Party
Pwn_MusicOverseer_MTall_1         Pwn_EliteGuard_MTall_2_ShawGuard2
```

Шесть мужских гостей, четыре женских, музыкант-смотритель. У стражи отдельные
праздничные варианты `_Party`, свой швейцар `_Doorman` и личный охранник Шоу.
Гости разложены по комнатам: `BallroomGuests`, `BilliardRoomGuests`,
`SmokingRoomGuests`, `PartyGuests`.

### Правила приёма уже сделаны предметами и задачами

| Правило | Чем реализовано |
|---|---|
| Вход по приглашению | `BoyleInvitation_twk`, `boyleinvitation_AbsItm`, `Brisby_Boyle_Invite` |
| Маска обязательна | `BoyleMaskBlack/Red/White`, `BlackMask`, `BlueMask`, `Female_BlackMask`, `Mask_Overseer_inst`, `Twk_Inv_OverseerMask`, `skm_Boylemask` |
| Гость с бокалом | `BoylePartyDrink_twk`, `DrinkingGlass_twk`, `Drink_Cider_01_twk`, жесты `Gesture_ReachForDrink`, `TakesDrink`, `FillDrinkIn` / `Out` |
| Светские поручения | `Get A Drink Task`, `Quest For the Drink`, `HasDrinkLogicCheck`, `MissWhitesDrink`, `Complete Talk to Guests Objective` |
| Список приглашённых | `Twk_Boyle_Guest_Book` |

Маски трёх цветов сестёр, бокал как предмет с анимациями, приглашение как
инвентарь, гостевая книга — всё то, из чего должен состоять социальный стелз,
уже лежит на карте отдельными объектами.

### Живые объекты разговоров

В срезе 26 объектов `DisDialogOneShot` — по одному на реплику, которую можно
услышать на приёме. Плюс мозги гостей под задачу:
`AI_BrainTwk_Civ_BoyleInBoat`, `AI_BrainTwk_Civ_WoLConfident`,
`Twk_Brain_OverSeerMusical_Default`.

## Фракции сняты с живой карты целиком

Полная выгрузка приёма у Бойл: 111 830 объектов, 3045 классов, значения у 9818.
Семнадцать фракций со всем содержимым массивов.

### Кто кому враг сейчас

| Фракция | Союзники | Враги |
|---|---|---|
| `Faction_Corvo_Default` | `Faction_Conspiracy_Default` (1 из 1) | `Faction_Guard_Default` (1 из 1) |
| `Faction_Assassin_Default` | нет (0 из 0) | Корво, Головорезы, Стража, Мясник, Плакальщики (6 из 6) |
| `Faction_Weepers_Default` | нет (0 из 0) | Гражданские, Корво, Стража, Головорезы, Убийцы, Заговор (9 из 9) |
| `Neutral_Civilian` | Стража, Гражданские, `Neutral_Guard` (3 из 3) | Плакальщики (1 из 1) |

**Половина задуманной расстановки уже стоит в игре.** Китобои враждебны Корво
без единой правки — это и есть Томас с Билли против Корво с Даудом.
Плакальщики уже нападают и на стражу, и на гостей, значит подвал с ними
работает сам, стоит их только выпустить.

Вместимость везде равна длине: свободных мест нет ни у кого. Дописать союзника
нельзя (см. ue3patch.h — рост массива требует чужого буфера), но замена
работает. У Корво единственное место союзника занято Заговором — свести его с
Даудом значит разорвать связь с заговорщиками. Для приёма это скорее верно, чем
нет: он там не по их поручению.

### Фракция задаётся одной ссылкой, а не массивом

```
Twk_Pawn_Corvo.m_pFactionTweak            -> Faction_Corvo_Default
Pwn_AristoParty_MTall.m_pFactionTweak     -> Faction_Civilian_Default
```

`m_pFactionTweak` — обычное `ObjectProperty`. Массивы отношений тут ни при чём:
принадлежность пешки к стороне меняется одной строкой, а патчер умеет это с
самого начала.

Отсюда ядро ролевого режима:

```ini
Patch1=Twk_Pawn_Corvo|m_pFactionTweak=@Neutral_Civilian
```

Игрок становится гостем приёма: стража его терпит, гости считают своим,
плакальщики нападают. Ровно те отношения, что нужны, и они уже описаны в
`Neutral_Civilian`.

### Чего на карте нет

`DLC06_Fctn_Daud_Default` и прочие фракции дополнения на приёме не загружены —
их пакеты подключаются только в кампании «Knife of Dunwall». Дауд как отдельная
сторона требует либо подгрузки чужого пакета, либо замены на базовую
`Faction_Assassin_Default`, которая на карте есть и уже враждебна Корво.

## Что изменилось в оценке работы

Пересчёт после разбора таблицы имён. Раньше предполагалось, что ролевой режим —
это в основном нативный код: перехватить события, подменить тело, свести
фракции, нарисовать выбор персонажа.

Оказалось наоборот. Фракции, разговоры с выбором игрока, светский приём,
видимость, свидетели и подозрение, отмена смерти — всё это подсистемы,
управляемые данными, и у каждой есть имя. Нативный слой нужен там, где данных
не хватает: подменить пешку игрока помимо конфига, связать чужие подсистемы
между собой, добавить поведение, которого в игре нет вовсе.

Это не отменяет нативный слой — он остаётся точкой входа и страховкой. Но
основной объём работы переезжает в данные, а значит правится без пересборки
DLL и без ещё одного захода в игру на каждую проверку.

## Ролевой режим

Собран в сборке 22. Задаётся одним ключом в `native/native.ini`:

```ini
[Roleplay]
Role=thomas
```

### Роль — это сторона, и больше ничего не нужно

`m_pFactionTweak` у твика пешки игрока — обычное `ObjectProperty`, одна ссылка.
Всё остальное игра выводит из неё сама: стража пропускает своего, гости
принимают гостя, плакальщики бросаются на того, кто им враг. Отношения сторон
уже расставлены в игре, и переписывать их не приходится.

Девять ролей, все девять фракций прочитаны с живой карты приёма:

| `Role=` | Фракция | Кто это |
|---|---|---|
| `corvo` | `Faction_Corvo_Default` | как в игре: стража враждебна |
| `daud` | `Faction_Corvo_Default` | Дауд, на стороне Корво |
| `thomas` | `Faction_Assassin_Default` | китобой, враг Корво с Даудом |
| `billie` | `Faction_Assassin_Default` | Билли Лерк, с Томасом |
| `guest` | `Neutral_Civilian` | гость приёма |
| `guard` | `Neutral_Guard` | стражник приёма |
| `civilian` | `Faction_Civilian_Default` | горожанин |
| `conspiracy` | `Faction_Conspiracy_Default` | заговорщик |
| `weeper` | `Faction_Weepers_Default` | плакальщик |

### Раскол китобоев оказался готовым

Корво с Даудом стоят на одной фракции, Томас с Билли — на другой. Одна фракция
на двоих делает их союзниками **по построению**, а вражда между сторонами в
игре уже прописана: у `Faction_Assassin_Default` Корво первым в списке врагов.

Значит задуманная расстановка четверых не требует ни одной правки таблиц
отношений — а это важно, потому что править их и нельзя: вместимость всюду
равна длине, дописать союзника некуда.

Держится всё на том, что у двух ролей совпадает имя фракции, — опечатка в одном
символе рвёт союз молча. Поэтому расстановка вынесена в `native/src/roles.h` и
проверяется тестом `test_roles` как утверждение, а не описывается комментарием.

### Правятся все три твика игрока

На карте приёма их ровно три: `Twk_Pawn_Corvo`, `Twk_Pawn_Corvo_Release`,
`Twk_Pawn_DefaultPlayer`. Какой из них игра читает на самом деле, из выгрузки не
видно, а промах выглядел бы хуже всего: лог отчитался бы об успешной правке, и
не изменилось бы ничего. Три записи вместо одной стоят ничего и снимают вопрос.

### Чего роль не делает: не меняет тело

Фракция меняет то, кем тебя считают, а не то, как ты выглядишь. Игрок остаётся
Корво внешне.

Тел Дауда, Томаса и Билли на приёме нет: их ассеты лежат в пакетах затопленного
района (`L_Flooded_FAssassins_P`) и дополнения (`DLC06_Slaughter_Int_Assassin`),
а карта приёма их не грузит. Чтобы это был факт из игры, а не предположение,
режим ищет их сам: у каждой из трёх ролей задана подстрока имени, и обход списка
объектов — который всё равно идёт — выписывает в лог всё найденное. Пусто в логе
означает пусто на карте.

Смена тела — отдельный шаг и требует подгрузки чужого пакета в рантайме. Для
`guest`, `guard` и `weeper` этой проблемы нет: их тела по карте и ходят.
