# Ukrainian technical terms

How to name programming, testing, git, Godot and rendering concepts in Ukrainian comments, commits
and PRs. Register: **semi-formal** — established loanwords (коміт, тест, шейдер) are fine; English
stems with Ukrainian endings (пофіксити, емітить) are not.

**Decision:** **T** translate · **L** loanword in Cyrillic · **C** keep Latin, in `code`.

**Sources:** G = Godot `editor/uk.po`, GP = Godot `properties/uk.po`, B = Blender `uk.po`,
Git = git `po/uk.po`, WP = Ukrainian Wikipedia, Repo = counts in this repo (2026-10-17).
*[usage]* = no source, project decision. Godot's own uk files have known mistranslations — they are
listed at the end; do not copy them.

## How to choose

1. **The thing has a name in code** (`Callable`, `PackedScene`, `Viewport`, `null`, `assert`,
   `delta`, `seed`) → write the code name in backticks. A Ukrainian gloss may follow once.
2. **A standard Ukrainian term exists and developers use it** (функція, масив, подія, вузол) → use it.
3. **Official term exists but developers don't say it** (внесок for commit, сховище for repository,
   актив for asset) → use the developer loanword. Comments are read by developers.
4. **Two variants in the repo** → the table below decides; don't introduce a third.
5. **A word is two things in this project** — pick the one that doesn't collide: «меш», not «сітка»
   (сітка is the tile grid); «огляд» is vision, so review is «рев'ю».

## General programming

| EN | UA | | note |
| --- | --- | --- | --- |
| function / method | функція / метод | T | every `func` in a script is a method |
| argument / parameter | аргумент / параметр | T | value at call vs name in declaration |
| returns | повертає | T | |
| variable / constant | змінна / константа | T | |
| field / member / property | поле / член класу / властивість | T | not «учасник» (G error) |
| class / instance | клас / **екземпляр** | T | G 31×; not «інстанс» (Repo 19×) |
| enum | перелік, `enum` | T/C | |
| array / dictionary | масив / словник | T | |
| null | `null` | C | «порожнє» only for an empty collection |
| bool / int / float / string | `bool` / `int` / `float` / рядок | C/T | never «строка», «поплавок» |
| flag | прапорець | T | Repo 21×, «флаг» 0 |
| state | стан | T | |
| callback | зворотний виклик, `Callable` | T/C | not «колбек» |
| lambda / closure | лямбда / замикання | T | |
| scope | область видимості | T | |
| inheritance / override | успадкування / перевизначення | T | |
| side effect / pure function | побічний ефект / чиста функція | T | |
| invariant | інваріант | L | |
| edge case | граничний випадок | T | not «кейс» |
| assertion | `assert`, перевірка | C/T | |
| error / exception | помилка / виняток | T | GDScript has no exceptions — don't write «кидає» |
| fallback | резервний варіант | T | not «фолбек» |
| default | **типовий**, за замовчуванням | T | not «дефолтний» (Repo 15×) |
| payload | дані (події), корисне навантаження | T | |
| immutable / mutable | незмінний / змінюваний | T | |
| reference / copy | посилання / копія (глибока / поверхнева) | T | `duplicate(true)` |
| serialize | серіалізувати | L | |
| parse / parser | розбирати / парсер | T/L | |
| validate | перевіряти, валідувати | T/L | `Rules.validate()` |
| hash | хеш | L | |
| seed / RNG state | сід (`seed`) / стан ГВЧ (`rng.state`) | L/C | Repo «сід» 21×; GP «База» is wrong |
| random number generator | генератор випадкових чисел, `RandomNumberGenerator` | T/C | |
| deterministic | детермінований | T | |
| cache / lazy | кеш / лінивий (ліниве обчислення) | L/T | |
| buffer / queue / stack | буфер / черга / стек | T | |
| event / handler / listener | подія / обробник / слухач | T | `BattleEvent` is data, not a signal |
| signal / emit / connect | сигнал / **надсилає** сигнал, `emit()` / під'єднати | T | not «емітить» (Repo 16×), not «випромінює» |
| coroutine / await / async | співпрограма / `await` / асинхронний | T/C | |
| thread / race condition | потік / стан гонитви | T | |
| dependency / coupling | залежність / зв'язність | T | |
| layer / module / namespace | шар / модуль / простір імен | T | |
| wrapper / helper | обгортка / допоміжна функція | T | not «хелпер» |
| hook | хук | L | |
| pipeline | конвеєр | T | not «трубопровід» |
| round-trip | повний цикл туди й назад | T | |
| overhead / bottleneck | накладні витрати / вузьке місце | T | |
| threshold / budget | поріг / бюджет | T | |
| deprecated / legacy | застарілий | T | |
| workaround / hack | обхідне рішення / милиця | T | |
| tech debt / refactoring | технічний борг / рефакторинг | T/L | рефакторинг = behaviour unchanged |
| bug / regression / fix | помилка, вада (баг — розмовне) / регресія / виправлення | T | |
| feature | можливість | T | not «фіча» |
| build / export / import | збірка / експорт / імпорт | T/L | |
| deploy | розгортання | T | |
| debug / debugger | налагодження / налагоджувач | T | not «дебаг», «отладка» |
| log | журнал (лог — розмовне) | T | |
| profiler / benchmark | профайлер / вимірювання продуктивності | L/T | |
| headless | `--headless`, без вікна | C/T | |
| CLI | командний рядок | T | |
| config / settings | конфігурація / налаштування | T | not «настройки», «конфіг» |
| lookup | пошук (у таблиці) | T | not «лукап» (Repo 9×) |
| crash | збій, падіння | T | not «креш» |
| tool / dev tool | інструмент / інструмент розробника | T | not «тул», «девтул» |
| sibling (node) | сусідній вузол | T | not «сиблінг» |
| brief (task) | бриф, опис завдання | L/T | |

## Testing

| EN | UA | | note |
| --- | --- | --- | --- |
| test / suite / case | тест / набір тестів / тестовий випадок | T | |
| unit / integration test | модульний / інтеграційний тест | T | |
| end-to-end test | наскрізний тест, e2e | T/C | `tests/e2e/` — through the real UI |
| golden test | еталонний тест | T | the damage table (§3.3) |
| fixture / mock / stub | фікстура / мок / заглушка | L/T | GUT: `double()`, `stub()`, `spy` |
| flaky test | нестабільний тест | T | |
| coverage | покриття | T | |
| passes / fails | проходить / падає | T | |
| run the tests | запустити тести | T | «прогнати» — розмовне |

## Git and process

| EN | UA | | note |
| --- | --- | --- | --- |
| repository | репозиторій | L | Git uses «сховище», which also means storage |
| commit | коміт | L | not «внесок» (G) |
| branch / merge / rebase | гілка / злиття, злити / перебазування | T | not «змерджити» |
| conflict / diff | конфлікт / різниця, `diff` | T/C | |
| pull request / review | PR / рев'ю, рецензент | C/L | «огляд» means vision here |
| worktree / stash / tag | `worktree` / `stash` / тег | C/L | |
| main / upstream | `main` / `upstream` | C | |
| task in a plan | `Task 2.10` | C | matches the English plan docs |

## Godot, rendering, gamedev

| EN | UA | | note |
| --- | --- | --- | --- |
| scene / scene tree | сцена / дерево сцени (`SceneTree`) | T | |
| node | **вузол** | T | not «нода» (Repo 3×, wrong gender) |
| packed scene / instantiate | `PackedScene` / створити екземпляр | C/T | |
| resource | ресурс, `Resource` | T/C | a Godot class, not any asset |
| asset | асет | L | 2019 spelling drops the double «с»; not «актив» (B) |
| autoload | `autoload`, автозавантаження | C/T | not a «синглтон» |
| script | скрипт | L | «сценарій» = game scenario |
| tween / animation | твін (`Tween`) / анімація | L/T | |
| frame / frame time / FPS | кадр / час кадру / частота кадрів, FPS | T | |
| `_process` / `delta` | `_process` / `delta` | C | |
| viewport | `Viewport` | C | no Cyrillic spelling (Repo had three) |
| camera / orthographic | камера / ортографічна проєкція | T | not «фотоапарат» (GP) |
| overlay | оверлей | L | Repo 17× vs накладка 8× |
| HUD | HUD | C | |
| render / renderer | рендеринг, малювати / рендерер | L/T | |
| draw call | draw call | C | no Ukrainian term in use |
| batching / LOD | пакетування / LOD | T/C | |
| mesh / multimesh | меш / мультимеш | L | «сітка» is the tile grid |
| material / shader / texture | матеріал / шейдер / текстура | L | |
| vertex / polygon / triangle | вершина / полігон / трикутник | T | |
| UV / normal map | UV-розгортка / карта нормалей | C/T | |
| lightmap / bake | карта освітлення / запікання, запекти | T | not «випікати» |
| shadow / post-processing | тінь / постобробка | T | |
| particles / VFX | частинки / VFX | T/C | |
| collision / raycast | зіткнення / `RayCast3D` | T/C | |
| pathfinding | пошук шляху | T | |
| tile / grid | тайл (dev), клітинка (UI) / сітка | L/T | not «плитка» (G) |
| save / load | збереження / завантаження | T | |
| localisation / input | локалізація / введення | T | |
| touch / tap / gesture | дотик / дотик, торкнутися / жест | T | not «тап» |
| pan / zoom | панорамування / масштабування | T | not «зум» |
| safe area | безпечна зона | T | |
| low-processor mode | режим низького навантаження, `low_processor_mode` | T/C | |
| hot-seat / turn-based | гра на одному пристрої / покроковий | T | |

## Mistranslations in the source files — don't copy

| seen in | wrong | right |
| --- | --- | --- |
| G | поплавок (`float`) | `float`, число з рухомою комою |
| G | учасник (member) | член класу |
| G | внесок (commit) | коміт |
| GP | фотоапарат (Camera) | камера |
| GP | трубопровід, дозування | конвеєр, пакетування |
| GP | база (seed) | сід, `seed` |
| GP | процес зворотного виклику (`_process`) | `_process` |
| G/GP | випікати | запікати |
| Git | строка | рядок |
| B | стяги, стос, відтінювач, актив | прапорці, стек, шейдер, асет |

## Verbs from English stems — replace

юзати → використовувати · пофіксити → виправити · імплементувати → реалізувати ·
задеплоїти → розгорнути · дебажити → налагоджувати · залити (push) → надіслати, `push` ·
змерджити → злити · емітить → надсилає · гейтить → закриває гейтом, обмежує ·
пришпилює → фіксує · крешнутись → впасти.

## Серпанок на краю світу

| English | Українська | note |
| --- | --- | --- |
| fog lobes, billows, puffs | клуби (серпанку) | never «лоби»: calque, and «лоб» is front armour |
| wisps, strands | пасма | |
| world-edge haze | серпанок | «туман» is only the fog of war |
