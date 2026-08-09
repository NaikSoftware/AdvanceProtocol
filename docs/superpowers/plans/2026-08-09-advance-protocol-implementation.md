# Advance Protocol — план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Довести Advance Protocol від порожнього репозиторію до мобільної гри v1 — хот-сит скірміш на 2–3 гравці, повний ростер із §3.6, меню й інтерфейс, атмосферний рендер, редактор карт і збірки під Android/iOS.

**Architecture:** `core/` — чисті правила без жодного Godot-нода: дані, детермінований RNG, команди на вході й впорядкований список подій на виході. `game/` — сцени Godot, які лише програють ці події. Потік дії гравця: `input → intent → Command → Rules.validate() → Rules.apply() → [BattleEvent] → view animates`. Вигляд ніколи не обчислює результат.

**Tech Stack:** Godot 4.7.1 stable, GDScript зі статичною типізацією, Mobile renderer (Vulkan) з фолбеком `gl_compatibility`, GUT 9.x для headless-тестів, GLB-ассети через скіл `asset-manager`, локалізація через CSV-переклади Godot.

**Спеціфікація:** `CLAUDE.md` у корені репозиторію. Кожне число, формула й інваріант беруться звідти дослівно. Якщо завдання плану суперечить `CLAUDE.md` — правий `CLAUDE.md`, і розбіжність фіксується в ньому окремим комітом.

---

## Global Constraints

- **Godot 4.7.1 stable.** Бінарник у `/home/naik/Downloads/Godot_v4.7.1-stable_linux.x86_64`, не на PATH. Перед роботою: `export GODOT=/home/naik/Downloads/Godot_v4.7.1-stable_linux.x86_64` і `export GODOT_PATH=$GODOT`.
- **`core/` не імпортує типи нодів Godot.** Ніяких `Node`, `Node3D`, `Sprite`, `get_node()`, сигналів, `_process`. Дозволені лише `RefCounted`, `Resource`, `Object` і вбудовані типи-значення (`Vector2i`, `Array`, `Dictionary`, `RandomNumberGenerator`).
- **Типізований GDScript усюди.** `var hp: int = 0`, `func fire(target: Unit) -> Array[BattleEvent]:`. Нетипізований член у `core/` — це дефект.
- **Детермінізм.** Один `RandomNumberGenerator`, засіяний на матч і збережений у `BattleState`. Кожен кидок іде через `Rules.roll()`. Глобальні `randi()`/`randf()` в `core/` заборонені.
- **Мінімальний дамаг 10.** Жодна атака ніколи не дає менше.
- **Інваріант броні:** `front >= side >= rear` для кожного запису в `core/unit_types.gd`. Порушення — падаючий білд, а не балансна дискусія.
- **`snake_case`** для файлів і членів, **`PascalCase`** для `class_name`.
- **Жодних хардкоджених рядків для показу.** Усі підписи — ключі перекладу, українська та англійська з першого дня.
- **Нейтральна термінологія.** Ніде — в коді, даних, UI — не називати реальну армію, країну чи машину. Сетинг не зафіксовано (див. Фазу 5, Task 5.0).
- **Тапабельні цілі ≥ 48 dp**, безпечні зони й виріз екрана враховані.
- **Тести обов'язкові для всього в `core/`.** Таблиця дамагу — золоті тести, ростер — структурний тест.
- **Комітити часто**, один комміт на завершене завдання (або на пару тест+реалізація всередині великого).

---

## Структура файлів

```
project.godot
export_presets.cfg
run_tests.sh                    # обгортка над GUT headless
addons/gut/                     # вендорений GUT 9.x

core/                           # чисті правила, без нодів
  unit_types.gd                 # таблиця статів — джерело істини
  unit.gd                       # екземпляр юніта в бою
  terrain.gd                    # види тайлів, штрафи, ground_state
  board.gd                      # сітка тайлів, зайнятість, доступ за координатою
  battle_state.gd               # весь стан матчу + RNG + черга ходів
  rules.gd                      # roll, entry_cost, armour_sector, damage
  pathing.gd                    # Dijkstra flood fill, дві зони, реконструкція шляху
  vision.gd                     # visible/seen на гравця
  veterancy.gd                  # пули XP, пороги, рівні
  objectives.gd                 # маркери цілей, захоплення, умова перемоги
  mines.gd                      # укладання, розкриття по гравцях, підрив
  events.gd                     # усі типи BattleEvent
  battle_serializer.gd          # стан ↔ Dictionary для збереження
  commands/
    command.gd                  # база: validate() -> String, apply() -> Array[BattleEvent]
    move_command.gd
    fire_command.gd
    drone_command.gd
    engineer_command.gd
    end_turn_command.gd

game/                           # сцени Godot
  autoload/
    scene_router.gd             # перемикання екранів, єдина точка навігації
    match_service.gd            # тримає BattleState, приймає команди, роздає події
    settings_service.gd         # мова, гучність, якість — збереження в user://
  battle/
    battle_screen.tscn/.gd      # корінь бойового екрана
    board_view.tscn/.gd         # інстансинг тайлів, туман
    unit_view.tscn/.gd          # один юніт: модель, поворот, HP-бар, значки
    zone_overlay.gd             # дві зони руху
    target_overlay.gd           # цілі, сектор броні, прогноз шкоди
    event_player.gd             # черга BattleEvent → анімації
    input_controller.gd         # тап, драг, вибір, підтвердження
  camera/
    iso_camera_rig.tscn/.gd     # фіксований кут, пан, обмежений зум
  ui/
    hud.tscn/.gd                # AP, ходи, ground_state, кнопки дій
    unit_inspector.tscn/.gd     # стати вибраного юніта
    handover_gate.tscn/.gd      # обов'язковий екран передачі пристрою
    main_menu.tscn/.gd
    match_setup.tscn/.gd        # кількість гравців, карта, ground_state, сід
    settings_screen.tscn/.gd
    pause_menu.tscn/.gd
    results_screen.tscn/.gd
    theme/ap_theme.tres
  fx/                           # погода, дим, уламки, влучання
  audio/

maps/                           # .tres описи карт
assets/models/ materials/ textures/ audio/ i18n/
tests/                          # GUT-специфікації проти core/
tools/map_editor/               # редактор карт
docs/superpowers/plans/
```

---

## Фази

| фаза | що дає | стан плану |
| --- | --- | --- |
| 1 | `core/` цілком + тести — правила працюють headless | покроково нижче |
| 2 | вертикальний зріз: одна карта, рух, постріл, камера, гейт передачі | покроково нижче |
| 3 | меню й оболонка UI, локалізація, збереження матчу | покроково нижче |
| 4 | повний ростер у вигляді: інженери, міни, дрони, цілі | перелік завдань + критерії |
| 5 | фіксація сетингу, ассети, атмосфера, звук | перелік завдань + критерії |
| 6 | редактор карт | перелік завдань + критерії |
| 7 | мобільні збірки, продуктивність, реліз | перелік завдань + критерії |

Фази 4–7 отримують покроковий план на початку самої фази — коли вже є реальний код фаз 1–3, від якого відштовхуватись. Планувати їх покроково зараз означало б вигадувати сигнатури до того, як існують їхні споживачі.

---

# Фаза 1 — `core/`

Мета фази: увесь матч можна відіграти в тесті без жодної сцени. Наприкінці фази існує тест, який створює стан на 2 гравці, робить рухи, постріли, підрив мосту й доводить матч до перемоги — усе через команди.

---

### Task 1.1: Каркас проєкту, GUT, тестовий раннер

**Files:**
- Create: `project.godot`
- Create: `run_tests.sh`
- Create: `.gitignore` (доповнити наявний)
- Create: `tests/test_smoke.gd`
- Create: `addons/gut/` (вендорений)

**Interfaces:**
- Consumes: нічого
- Produces: `./run_tests.sh` — команда запуску всіх тестів, якою користуються всі подальші завдання

- [ ] **Step 1: Створити `project.godot`**

```ini
config_version=5

[application]
config/name="Advance Protocol"
config/features=PackedStringArray("4.7", "Forward Plus")
run/main_scene="res://game/ui/main_menu.tscn"
config/icon="res://icon.svg"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/handheld/orientation="landscape"
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true

[application/config]
run/low_processor_mode=true
```

Тимчасово прибрати `run/main_scene` (сцени ще немає) — рядок додається у Task 3.1. Поки що залишити файл без нього.

- [ ] **Step 2: Вендорити GUT**

```bash
export GODOT=/home/naik/Downloads/Godot_v4.7.1-stable_linux.x86_64
git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut
mkdir -p addons
cp -r /tmp/gut/addons/gut addons/gut
grep '^version' addons/gut/plugin.cfg     # має починатись із 9.
rm -rf /tmp/gut
```

Якщо версія не 9.x — узяти тег `v9.4.0`: `git clone --depth 1 --branch v9.4.0 ...`. GUT 7.x/8.x не працює на Godot 4.

- [ ] **Step 3: Написати падаючий смоук-тест**

`tests/test_smoke.gd`:

```gdscript
extends GutTest

func test_gut_runs() -> void:
	assert_eq(1 + 1, 2, "арифметика жива")

func test_core_dir_exists() -> void:
	assert_true(DirAccess.dir_exists_absolute("res://core"), "каталог core/ має існувати")
```

- [ ] **Step 4: Створити раннер і запустити — другий тест має впасти**

`run_tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${GODOT:?export GODOT=/home/naik/Downloads/Godot_v4.7.1-stable_linux.x86_64}"
export GODOT_PATH="$GODOT"
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit "$@"
```

```bash
chmod +x run_tests.sh && ./run_tests.sh
```

Очікується: `test_gut_runs` PASS, `test_core_dir_exists` FAIL.

- [ ] **Step 5: Створити `core/` і повторити**

```bash
mkdir -p core/commands game/ui maps assets/i18n tools
touch core/.gdignore_placeholder && rm core/.gdignore_placeholder
```

Godot не зберігає порожні каталоги в git — створити `core/README.md` з одним рядком «Pure rules layer. No Godot node types here.» Аналогічно для `core/commands/`.

```bash
./run_tests.sh
```

Очікується: обидва тести PASS.

- [ ] **Step 6: Доповнити `.gitignore`**

Додати до наявного файлу:

```
.godot/
build/
*.translation
export_presets.cfg
```

- [ ] **Step 7: Коміт**

```bash
git add project.godot run_tests.sh .gitignore addons/gut core/README.md core/commands/README.md tests/test_smoke.gd
git commit -m "chore: Godot project scaffold with GUT headless test runner"
```

---

### Task 1.2: `core/unit_types.gd` — таблиця статів і структурний тест

**Files:**
- Create: `core/unit_types.gd`
- Test: `tests/core/test_unit_types.gd`

**Interfaces:**
- Consumes: нічого
- Produces:
  - `UnitTypes.UnitClass` — enum `{ INFANTRY, LIGHT_VEHICLE, TANK, ARTILLERY, ENGINEER }`
  - `UnitTypes.ArmourSector` — enum `{ FRONT, SIDE, REAR }`
  - `UnitTypes.TYPES: Array[Dictionary]` — ключі: `id: int`, `name_key: String`, `unit_class: int`, `attack: int`, `max_ap: int`, `max_hp: int`, `attack_range: int`, `fire_cost: int`, `armour: Array[int]` (F/S/R), `cross_country: int`, `vision: int`, `drones: int`
  - `UnitTypes.get_type(id: int) -> Dictionary`
  - `UnitTypes.count() -> int`

Ключ називається `attack_range`, а не `range`, бо `range` — вбудована функція GDScript і читається як помилка при кожному погляді на код.

- [ ] **Step 1: Написати падаючий структурний тест**

`tests/core/test_unit_types.gd`:

```gdscript
extends GutTest

func test_roster_has_thirteen_entries() -> void:
	assert_eq(UnitTypes.count(), 13, "ростер §3.6 має 13 записів, 0..12")

func test_ids_match_indices() -> void:
	for i in UnitTypes.count():
		assert_eq(UnitTypes.get_type(i)["id"], i, "id має дорівнювати індексу")

func test_armour_is_ordered_front_side_rear() -> void:
	for i in UnitTypes.count():
		var t: Dictionary = UnitTypes.get_type(i)
		var a: Array = t["armour"]
		assert_true(a[0] >= a[1], "%s: front(%d) >= side(%d)" % [t["name_key"], a[0], a[1]])
		assert_true(a[1] >= a[2], "%s: side(%d) >= rear(%d)" % [t["name_key"], a[1], a[2]])

func test_tank_mobility_is_strictly_ordered() -> void:
	# §3.6: light -> medium -> tank destroyer -> heavy, і по AP, і по прохідності
	var light: Dictionary = UnitTypes.get_type(7)
	var medium: Dictionary = UnitTypes.get_type(5)
	var destroyer: Dictionary = UnitTypes.get_type(6)
	var heavy: Dictionary = UnitTypes.get_type(8)
	for key in ["max_ap", "cross_country"]:
		assert_true(light[key] > medium[key], "light > medium за %s" % key)
		assert_true(medium[key] > destroyer[key], "medium > tank destroyer за %s" % key)
		assert_true(destroyer[key] > heavy[key], "tank destroyer > heavy за %s" % key)

func test_only_assault_squad_carries_drones() -> void:
	for i in UnitTypes.count():
		var expected: int = 2 if i == 1 else 0
		assert_eq(UnitTypes.get_type(i)["drones"], expected, "дрони лише в штурмового відділення (#1)")

func test_engineers_have_no_weapon() -> void:
	for i in UnitTypes.count():
		var t: Dictionary = UnitTypes.get_type(i)
		if t["unit_class"] == UnitTypes.UnitClass.ENGINEER:
			assert_eq(t["attack"], 0, "інженер не має зброї")

func test_every_name_key_is_unique_and_neutral() -> void:
	var seen: Dictionary = {}
	for i in UnitTypes.count():
		var key: String = UnitTypes.get_type(i)["name_key"]
		assert_false(seen.has(key), "ключ %s дублюється" % key)
		seen[key] = true
		assert_true(key.begins_with("UNIT_"), "ключ перекладу має починатися з UNIT_")
```

- [ ] **Step 2: Запустити — має впасти**

```bash
./run_tests.sh -gtest=res://tests/core/test_unit_types.gd
```

Очікується: FAIL, `Identifier "UnitTypes" not declared`.

- [ ] **Step 3: Реалізувати `core/unit_types.gd`**

```gdscript
class_name UnitTypes
extends RefCounted
## Таблиця статів — джерело істини для ростера (§3.6 CLAUDE.md).
## Таблиця в CLAUDE.md з моменту появи цього файлу є документацією, а не істиною.

enum UnitClass { INFANTRY, LIGHT_VEHICLE, TANK, ARTILLERY, ENGINEER }
enum ArmourSector { FRONT, SIDE, REAR }

const TYPES: Array[Dictionary] = [
	{"id": 0, "name_key": "UNIT_RIFLE_SQUAD", "unit_class": UnitClass.INFANTRY,
	 "attack": 15, "max_ap": 30, "max_hp": 100, "attack_range": 3, "fire_cost": 10,
	 "armour": [0, 0, 0], "cross_country": 80, "vision": 5, "drones": 0},
	{"id": 1, "name_key": "UNIT_ASSAULT_SQUAD", "unit_class": UnitClass.INFANTRY,
	 "attack": 15, "max_ap": 30, "max_hp": 100, "attack_range": 3, "fire_cost": 10,
	 "armour": [0, 0, 0], "cross_country": 80, "vision": 5, "drones": 2},
	{"id": 2, "name_key": "UNIT_ARMOURED_CAR", "unit_class": UnitClass.LIGHT_VEHICLE,
	 "attack": 60, "max_ap": 68, "max_hp": 250, "attack_range": 3, "fire_cost": 18,
	 "armour": [27, 18, 10], "cross_country": 5, "vision": 3, "drones": 0},
	{"id": 3, "name_key": "UNIT_TROOP_CARRIER", "unit_class": UnitClass.LIGHT_VEHICLE,
	 "attack": 70, "max_ap": 68, "max_hp": 250, "attack_range": 3, "fire_cost": 18,
	 "armour": [36, 31, 7], "cross_country": 7, "vision": 3, "drones": 0},
	{"id": 4, "name_key": "UNIT_SCOUT_CAR", "unit_class": UnitClass.LIGHT_VEHICLE,
	 "attack": 55, "max_ap": 48, "max_hp": 200, "attack_range": 3, "fire_cost": 18,
	 "armour": [35, 15, 7], "cross_country": 8, "vision": 3, "drones": 0},
	{"id": 5, "name_key": "UNIT_MEDIUM_TANK", "unit_class": UnitClass.TANK,
	 "attack": 95, "max_ap": 48, "max_hp": 400, "attack_range": 4, "fire_cost": 20,
	 "armour": [37, 27, 18], "cross_country": 12, "vision": 4, "drones": 0},
	{"id": 6, "name_key": "UNIT_TANK_DESTROYER", "unit_class": UnitClass.TANK,
	 "attack": 130, "max_ap": 44, "max_hp": 400, "attack_range": 4, "fire_cost": 20,
	 "armour": [45, 14, 8], "cross_country": 11, "vision": 4, "drones": 0},
	{"id": 7, "name_key": "UNIT_LIGHT_TANK", "unit_class": UnitClass.TANK,
	 "attack": 108, "max_ap": 56, "max_hp": 300, "attack_range": 4, "fire_cost": 25,
	 "armour": [37, 16, 10], "cross_country": 13, "vision": 4, "drones": 0},
	{"id": 8, "name_key": "UNIT_HEAVY_TANK", "unit_class": UnitClass.TANK,
	 "attack": 121, "max_ap": 40, "max_hp": 350, "attack_range": 4, "fire_cost": 20,
	 "armour": [56, 25, 20], "cross_country": 9, "vision": 4, "drones": 0},
	{"id": 9, "name_key": "UNIT_FIELD_GUN", "unit_class": UnitClass.ARTILLERY,
	 "attack": 200, "max_ap": 24, "max_hp": 200, "attack_range": 5, "fire_cost": 14,
	 "armour": [15, 0, 0], "cross_country": 6, "vision": 3, "drones": 0},
	{"id": 10, "name_key": "UNIT_HOWITZER", "unit_class": UnitClass.ARTILLERY,
	 "attack": 180, "max_ap": 24, "max_hp": 200, "attack_range": 5, "fire_cost": 14,
	 "armour": [15, 0, 0], "cross_country": 6, "vision": 3, "drones": 0},
	{"id": 11, "name_key": "UNIT_ENGINEER_SQUAD", "unit_class": UnitClass.ENGINEER,
	 "attack": 0, "max_ap": 68, "max_hp": 200, "attack_range": 1, "fire_cost": 20,
	 "armour": [10, 5, 5], "cross_country": -5, "vision": 3, "drones": 0},
	{"id": 12, "name_key": "UNIT_ENGINEER_VEHICLE", "unit_class": UnitClass.ENGINEER,
	 "attack": 0, "max_ap": 76, "max_hp": 200, "attack_range": 1, "fire_cost": 30,
	 "armour": [10, 5, 5], "cross_country": -5, "vision": 3, "drones": 0},
]

static func count() -> int:
	return TYPES.size()

static func get_type(id: int) -> Dictionary:
	assert(id >= 0 and id < TYPES.size(), "невідомий тип юніта: %d" % id)
	return TYPES[id]

static func is_vehicle(unit_class: int) -> bool:
	return unit_class != UnitClass.INFANTRY
```

- [ ] **Step 4: Запустити — усе має пройти**

```bash
./run_tests.sh -gtest=res://tests/core/test_unit_types.gd
```

Очікується: 7 тестів PASS.

- [ ] **Step 5: Коміт**

```bash
git add core/unit_types.gd tests/core/test_unit_types.gd
git commit -m "feat(core): unit stat table with roster invariant tests"
```

---

### Task 1.3: `core/terrain.gd` — види тайлів, штрафи, стан ґрунту

**Files:**
- Create: `core/terrain.gd`
- Test: `tests/core/test_terrain.gd`

**Interfaces:**
- Consumes: нічого
- Produces:
  - `Terrain.Kind` — enum `{ ROAD, FIELD, FOREST, HILL, MARSH, WATER, BUILDING, RUBBLE, BRIDGE, BRIDGE_DESTROYED }`
  - `Terrain.GroundState` — enum `{ DRY, MUD, FROZEN }`
  - `Terrain.IMPASSABLE: int` — «нескінченний» штраф
  - `Terrain.penalty(kind: int, ground_state: int) -> int`
  - `Terrain.is_road(kind: int) -> bool`
  - `Terrain.is_passable(kind: int, ground_state: int) -> bool`

Стан ґрунту зсуває штраф самого тайлу, а не вводить множник на юніта. Це достатньо: піхота має `cross_country` 80, тож формула `max(10, 10 + penalty - cross_country)` однаково впирається в підлогу 10 — «піхоти багнюка не стосується» випадає з математики безкоштовно, без спеціального випадку в мувері.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_terrain.gd`:

```gdscript
extends GutTest

func test_road_is_free_of_penalty() -> void:
	assert_eq(Terrain.penalty(Terrain.Kind.ROAD, Terrain.GroundState.DRY), 0)

func test_ground_state_never_touches_roads() -> void:
	for gs in [Terrain.GroundState.DRY, Terrain.GroundState.MUD, Terrain.GroundState.FROZEN]:
		assert_eq(Terrain.penalty(Terrain.Kind.ROAD, gs), 0, "дорога не залежить від ґрунту — у цьому її сенс")
		assert_eq(Terrain.penalty(Terrain.Kind.BRIDGE, gs), 0, "міст поводиться як дорога")

func test_mud_makes_offroad_worse() -> void:
	var dry: int = Terrain.penalty(Terrain.Kind.FIELD, Terrain.GroundState.DRY)
	var mud: int = Terrain.penalty(Terrain.Kind.FIELD, Terrain.GroundState.MUD)
	assert_true(mud > dry, "багнюка дорожча за суху землю")

func test_frozen_makes_offroad_cheaper() -> void:
	var dry: int = Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.DRY)
	var frozen: int = Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.FROZEN)
	assert_true(frozen < dry, "мерзла земля дешевша")

func test_marsh_is_impassable_until_frozen() -> void:
	assert_false(Terrain.is_passable(Terrain.Kind.MARSH, Terrain.GroundState.DRY))
	assert_false(Terrain.is_passable(Terrain.Kind.MARSH, Terrain.GroundState.MUD))
	assert_true(Terrain.is_passable(Terrain.Kind.MARSH, Terrain.GroundState.FROZEN),
		"§3.12: на морозі болото стає прохідним")

func test_water_is_never_passable() -> void:
	for gs in [Terrain.GroundState.DRY, Terrain.GroundState.MUD, Terrain.GroundState.FROZEN]:
		assert_false(Terrain.is_passable(Terrain.Kind.WATER, gs), "лід по воді — окрема фіча, не зараз")

func test_destroyed_bridge_is_impassable() -> void:
	assert_true(Terrain.is_passable(Terrain.Kind.BRIDGE, Terrain.GroundState.DRY))
	assert_false(Terrain.is_passable(Terrain.Kind.BRIDGE_DESTROYED, Terrain.GroundState.DRY))

func test_penalty_never_negative() -> void:
	for kind in Terrain.Kind.values():
		for gs in Terrain.GroundState.values():
			var p: int = Terrain.penalty(kind, gs)
			assert_true(p >= 0, "штраф не може бути відʼємним")
```

- [ ] **Step 2: Запустити — має впасти**

```bash
./run_tests.sh -gtest=res://tests/core/test_terrain.gd
```

- [ ] **Step 3: Реалізувати `core/terrain.gd`**

```gdscript
class_name Terrain
extends RefCounted
## Види тайлів і вартість входу (§3.2, §3.12).

enum Kind { ROAD, FIELD, FOREST, HILL, MARSH, WATER, BUILDING, RUBBLE, BRIDGE, BRIDGE_DESTROYED }
enum GroundState { DRY, MUD, FROZEN }

const IMPASSABLE: int = 1_000_000

## Шкала взята з референсу (§4), `GameCanvas.method_68`: там рівно шість кошиків —
## 0 (дорога), 5, 10 (базовий ґрунт), 20 (пересічена місцевість), 100 (забудова)
## і 1000 (непрохідно). Стискати їх не можна: при cross_country 5–13 будь-який
## штраф, менший за 13, повністю зникає під підлогою у max(10, 10 + p - cc), і
## техніка перестає відчувати місцевість узагалі.
const _BASE_PENALTY: Dictionary = {
	Kind.ROAD: 0,
	Kind.BRIDGE: 0,
	Kind.RUBBLE: 5,
	Kind.FIELD: 10,
	Kind.HILL: 20,
	Kind.FOREST: 20,
	Kind.BUILDING: 100,
	Kind.MARSH: IMPASSABLE,
	Kind.WATER: IMPASSABLE,
	Kind.BRIDGE_DESTROYED: IMPASSABLE,
}

const _MUD_OFFSET: int = 10
const _FROZEN_OFFSET: int = -5
const _FROZEN_MARSH_PENALTY: int = 20

static func is_road(kind: int) -> bool:
	return kind == Kind.ROAD or kind == Kind.BRIDGE

static func penalty(kind: int, ground_state: int) -> int:
	if kind == Kind.MARSH and ground_state == GroundState.FROZEN:
		return _FROZEN_MARSH_PENALTY
	var base: int = _BASE_PENALTY[kind]
	if base >= IMPASSABLE or is_road(kind):
		return base
	match ground_state:
		GroundState.MUD:
			return base + _MUD_OFFSET
		GroundState.FROZEN:
			return maxi(0, base + _FROZEN_OFFSET)
		_:
			return base

static func is_passable(kind: int, ground_state: int) -> bool:
	return penalty(kind, ground_state) < IMPASSABLE
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_terrain.gd
git add core/terrain.gd tests/core/test_terrain.gd
git commit -m "feat(core): terrain kinds, entry penalties and ground state"
```

---

### Task 1.4: `core/unit.gd` і `core/board.gd`

**Files:**
- Create: `core/unit.gd`
- Create: `core/board.gd`
- Test: `tests/core/test_unit.gd`
- Test: `tests/core/test_board.gd`

**Interfaces:**
- Consumes: `UnitTypes`, `Terrain`
- Produces:
  - `Unit` (RefCounted): `id: int`, `type_id: int`, `owner: int`, `pos: Vector2i`, `facing: int` (0..7), `hp: int`, `ap: int`, `drones_left: int`, `has_fired: bool`
    - `Unit.create(id: int, type_id: int, owner: int, pos: Vector2i, facing: int) -> Unit`
    - `unit.type() -> Dictionary`, `unit.unit_class() -> int`, `unit.attack() -> int`, `unit.max_ap() -> int`, `unit.max_hp() -> int`, `unit.attack_range() -> int`, `unit.fire_cost() -> int`, `unit.armour(sector: int) -> int`, `unit.cross_country() -> int`, `unit.vision() -> int`
    - `unit.is_alive() -> bool`, `unit.refill_ap() -> void`, `unit.spend_ap(n: int) -> void`, `unit.exhaust() -> void`
  - `Board` (RefCounted): `width: int`, `height: int`, `ground_state: int`, `tiles: PackedInt32Array`
    - `Board.create(width: int, height: int, ground_state: int) -> Board`
    - `board.in_bounds(p: Vector2i) -> bool`, `board.kind_at(p: Vector2i) -> int`, `board.set_kind(p: Vector2i, kind: int) -> void`
    - `board.penalty_at(p: Vector2i) -> int`, `board.is_passable(p: Vector2i) -> bool`
    - `Board.DIRS_4: Array[Vector2i]` — 4 ортогональні напрямки руху
    - `Board.DIRS_8: Array[Vector2i]` — 8 напрямків повороту, індекс = `facing`
    - `Board.neighbours4(p: Vector2i) -> Array[Vector2i]`
    - `Board.facing_towards(from: Vector2i, to: Vector2i) -> int`

`DIRS_8` фіксує порядок індексів фейсингу раз і назавжди; усе, що торкається броні, покладається на нього.

- [ ] **Step 1: Написати падаючі тести**

`tests/core/test_unit.gd`:

```gdscript
extends GutTest

func _make(type_id: int) -> Unit:
	return Unit.create(1, type_id, 0, Vector2i(3, 3), 0)

func test_unit_starts_full() -> void:
	var u: Unit = _make(5)
	assert_eq(u.hp, 400)
	assert_eq(u.ap, 48)
	assert_true(u.is_alive())
	assert_false(u.has_fired)

func test_assault_squad_starts_with_two_drones() -> void:
	assert_eq(_make(1).drones_left, 2)
	assert_eq(_make(0).drones_left, 0)

func test_armour_lookup_by_sector() -> void:
	var u: Unit = _make(6)   # винищувач танків 45/14/8
	assert_eq(u.armour(UnitTypes.ArmourSector.FRONT), 45)
	assert_eq(u.armour(UnitTypes.ArmourSector.SIDE), 14)
	assert_eq(u.armour(UnitTypes.ArmourSector.REAR), 8)

func test_exhaust_zeroes_ap_and_marks_fired() -> void:
	var u: Unit = _make(5)
	u.exhaust()
	assert_eq(u.ap, 0)
	assert_true(u.has_fired)

func test_refill_resets_ap_and_fired_flag() -> void:
	var u: Unit = _make(5)
	u.exhaust()
	u.refill_ap()
	assert_eq(u.ap, 48)
	assert_false(u.has_fired)

func test_dead_unit_is_not_alive() -> void:
	var u: Unit = _make(0)
	u.hp = 0
	assert_false(u.is_alive())
```

`tests/core/test_board.gd`:

```gdscript
extends GutTest

func _board() -> Board:
	return Board.create(8, 6, Terrain.GroundState.DRY)

func test_bounds() -> void:
	var b: Board = _board()
	assert_true(b.in_bounds(Vector2i(0, 0)))
	assert_true(b.in_bounds(Vector2i(7, 5)))
	assert_false(b.in_bounds(Vector2i(8, 0)))
	assert_false(b.in_bounds(Vector2i(-1, 2)))

func test_default_fill_is_field() -> void:
	assert_eq(_board().kind_at(Vector2i(4, 4)), Terrain.Kind.FIELD)

func test_set_and_read_kind() -> void:
	var b: Board = _board()
	b.set_kind(Vector2i(2, 2), Terrain.Kind.FOREST)
	assert_eq(b.kind_at(Vector2i(2, 2)), Terrain.Kind.FOREST)
	assert_eq(b.penalty_at(Vector2i(2, 2)), Terrain.penalty(Terrain.Kind.FOREST, Terrain.GroundState.DRY))

func test_out_of_bounds_is_impassable() -> void:
	assert_false(_board().is_passable(Vector2i(-1, 0)))

func test_movement_is_four_directional() -> void:
	assert_eq(Board.DIRS_4.size(), 4, "§3.1: рух лише ортогональний")
	for d in Board.DIRS_4:
		assert_eq(absi(d.x) + absi(d.y), 1, "жодних діагоналей у русі")

func test_facing_is_eight_directional() -> void:
	assert_eq(Board.DIRS_8.size(), 8, "§3.1: поворот — 8 напрямків")

func test_facing_towards_matches_dirs8() -> void:
	var origin := Vector2i(4, 4)
	for i in Board.DIRS_8.size():
		var target: Vector2i = origin + Board.DIRS_8[i] * 3
		assert_eq(Board.facing_towards(origin, target), i, "напрямок %d має бути стабільним" % i)

func test_neighbours_are_clipped_to_board() -> void:
	assert_eq(_board().neighbours4(Vector2i(0, 0)).size(), 2)
	assert_eq(_board().neighbours4(Vector2i(3, 3)).size(), 4)
```

- [ ] **Step 2: Запустити — мають упасти**

```bash
./run_tests.sh -gdir=res://tests/core
```

- [ ] **Step 3: Реалізувати `core/unit.gd`**

```gdscript
class_name Unit
extends RefCounted
## Екземпляр юніта в бою. Стати читаються з UnitTypes, тут лише змінний стан.

var id: int = 0
var type_id: int = 0
var owner: int = 0
var pos: Vector2i = Vector2i.ZERO
var facing: int = 0
var hp: int = 0
var ap: int = 0
var drones_left: int = 0
var has_fired: bool = false

static func create(p_id: int, p_type_id: int, p_owner: int, p_pos: Vector2i, p_facing: int) -> Unit:
	var u := Unit.new()
	u.id = p_id
	u.type_id = p_type_id
	u.owner = p_owner
	u.pos = p_pos
	u.facing = p_facing
	var t: Dictionary = UnitTypes.get_type(p_type_id)
	u.hp = t["max_hp"]
	u.ap = t["max_ap"]
	u.drones_left = t["drones"]
	return u

func type() -> Dictionary:
	return UnitTypes.get_type(type_id)

func unit_class() -> int:
	return type()["unit_class"]

func attack() -> int:
	return type()["attack"]

func max_ap() -> int:
	return type()["max_ap"]

func max_hp() -> int:
	return type()["max_hp"]

func attack_range() -> int:
	return type()["attack_range"]

func fire_cost() -> int:
	return type()["fire_cost"]

func armour(sector: int) -> int:
	return type()["armour"][sector]

func cross_country() -> int:
	return type()["cross_country"]

func vision() -> int:
	return type()["vision"]

func is_alive() -> bool:
	return hp > 0

func refill_ap() -> void:
	ap = max_ap()
	has_fired = false

func spend_ap(n: int) -> void:
	ap = maxi(0, ap - n)

func exhaust() -> void:
	## §3.2: постріл обнуляє AP і завершує активність юніта на цей хід.
	ap = 0
	has_fired = true
```

- [ ] **Step 4: Реалізувати `core/board.gd`**

```gdscript
class_name Board
extends RefCounted
## Сітка тайлів. Логічні координати цілі (x, y); ізометрію дає камера, не дані (§3.1).

const DIRS_4: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

## Індекс у цьому масиві — це значення facing. Порядок фіксований назавжди:
## 0 N, 1 NE, 2 E, 3 SE, 4 S, 5 SW, 6 W, 7 NW.
const DIRS_8: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]

var width: int = 0
var height: int = 0
var ground_state: int = Terrain.GroundState.DRY
var tiles: PackedInt32Array = PackedInt32Array()

static func create(p_width: int, p_height: int, p_ground_state: int) -> Board:
	var b := Board.new()
	b.width = p_width
	b.height = p_height
	b.ground_state = p_ground_state
	b.tiles.resize(p_width * p_height)
	b.tiles.fill(Terrain.Kind.FIELD)
	return b

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func _index(p: Vector2i) -> int:
	## Один запобіжник на обидва аксесори. `assert` вирізається в release-збірці,
	## тож у гарячому циклі Dijkstra він нічого не коштує. Контракт «за межами
	## дошки — непрохідно» тримають penalty_at()/is_passable(), а не ці два методи.
	assert(in_bounds(p), "board access out of bounds: %v" % p)
	return p.y * width + p.x

func kind_at(p: Vector2i) -> int:
	return tiles[_index(p)]

func set_kind(p: Vector2i, kind: int) -> void:
	tiles[_index(p)] = kind

func penalty_at(p: Vector2i) -> int:
	if not in_bounds(p):
		return Terrain.IMPASSABLE
	return Terrain.penalty(kind_at(p), ground_state)

func is_passable(p: Vector2i) -> bool:
	return penalty_at(p) < Terrain.IMPASSABLE

func neighbours4(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS_4:
		var n: Vector2i = p + d
		if in_bounds(n):
			out.append(n)
	return out

static func facing_towards(from: Vector2i, to: Vector2i) -> int:
	var v: Vector2i = to - from
	if v == Vector2i.ZERO:
		return 0
	var best: int = 0
	var best_dot: float = -INF
	var vf := Vector2(v).normalized()
	for i in DIRS_8.size():
		var d := Vector2(DIRS_8[i]).normalized()
		var dot: float = vf.dot(d)
		if dot > best_dot:
			best_dot = dot
			best = i
	return best
```

- [ ] **Step 5: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gdir=res://tests/core
git add core/unit.gd core/board.gd tests/core/test_unit.gd tests/core/test_board.gd
git commit -m "feat(core): unit instance and board grid with fixed facing order"
```

---

### Task 1.5: `core/rules.gd` — детермінований кидок і вартість входу

**Files:**
- Create: `core/rules.gd`
- Test: `tests/core/test_rules_movement.gd`

**Interfaces:**
- Consumes: `Unit`, `Board`, `Terrain`
- Produces:
  - `Rules.roll(rng: RandomNumberGenerator, n: int) -> int` — `rand(0, n)` включно з 0, **0 при `n <= 0`** (як `GameCanvas.method_2` у референсі §4)
  - `Rules.entry_cost(unit: Unit, penalty: int) -> int`
  - `Rules.entry_cost_at(unit: Unit, board: Board, p: Vector2i) -> int`

Кидок приймає `rng` явним параметром, а не лізе в `BattleState`. Так функція лишається чистою і тестується без стану.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_rules_movement.gd`:

```gdscript
extends GutTest

func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

func test_roll_is_zero_for_non_positive() -> void:
	assert_eq(Rules.roll(_rng(1), 0), 0)
	assert_eq(Rules.roll(_rng(1), -5), 0)

func test_roll_stays_within_inclusive_bounds() -> void:
	var r := _rng(12345)
	var saw_low: bool = false
	var saw_high: bool = false
	for i in 500:
		var v: int = Rules.roll(r, 10)
		assert_between(v, 0, 10)
		saw_low = saw_low or v == 0
		saw_high = saw_high or v == 10
	# Самої лише перевірки діапазону мало: вона однаково пройде і для [0,9], і для [1,10].
	# roll() — єдине джерело випадковості в грі, тож обидва кінці мають бути доведені.
	assert_true(saw_low, "0 має випадати — межа включна")
	assert_true(saw_high, "n має випадати — межа включна")

func test_roll_is_deterministic_for_same_seed() -> void:
	var a: Array[int] = []
	var b: Array[int] = []
	var ra := _rng(777)
	var rb := _rng(777)
	for i in 20:
		a.append(Rules.roll(ra, 100))
		b.append(Rules.roll(rb, 100))
	assert_eq(a, b, "один сід — одна послідовність, інакше реплеї неможливі")

func test_entry_cost_has_floor_of_ten() -> void:
	var infantry: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)   # cross_country 80
	assert_eq(Rules.entry_cost(infantry, 12), 10, "піхота платить підлогу всюди")
	assert_eq(Rules.entry_cost(infantry, 0), 10)

func test_entry_cost_formula() -> void:
	var medium: Unit = Unit.create(1, 5, 0, Vector2i.ZERO, 0)     # cross_country 12
	assert_eq(Rules.entry_cost(medium, 0), 10, "дорога: max(10, 10+0-12)")
	assert_eq(Rules.entry_cost(medium, 20), 18, "10 + 20 - 12")

func test_engineer_is_the_worst_offroad() -> void:
	var engineer: Unit = Unit.create(1, 11, 0, Vector2i.ZERO, 0)  # cross_country -5
	var medium: Unit = Unit.create(2, 5, 0, Vector2i.ZERO, 0)
	assert_true(Rules.entry_cost(engineer, 12) > Rules.entry_cost(medium, 12),
		"§3.6: інженер живе на дорогах")

func test_impassable_stays_impassable_for_everyone() -> void:
	var infantry: Unit = Unit.create(1, 0, 0, Vector2i.ZERO, 0)
	assert_true(Rules.entry_cost(infantry, Terrain.IMPASSABLE) >= Terrain.IMPASSABLE,
		"непрохідність — це нескінченний штраф, а не спецвипадок у мувері")
```

- [ ] **Step 2: Запустити — має впасти**

```bash
./run_tests.sh -gtest=res://tests/core/test_rules_movement.gd
```

- [ ] **Step 3: Реалізувати перший шматок `core/rules.gd`**

```gdscript
class_name Rules
extends RefCounted
## Уся математика бою (§3.2–3.4). Жодного глобального randi() тут ніколи не зʼявиться.

static func roll(rng: RandomNumberGenerator, n: int) -> int:
	## rand(0, n) включно. Повертає 0 для n <= 0 — так само, як референс §4.
	if n <= 0:
		return 0
	return rng.randi_range(0, n)

static func entry_cost(unit: Unit, penalty: int) -> int:
	## §3.2: cost = max(10, 10 + penalty - cross_country)
	if penalty >= Terrain.IMPASSABLE:
		return Terrain.IMPASSABLE
	return maxi(10, 10 + penalty - unit.cross_country())

static func entry_cost_at(unit: Unit, board: Board, p: Vector2i) -> int:
	return entry_cost(unit, board.penalty_at(p))
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_rules_movement.gd
git add core/rules.gd tests/core/test_rules_movement.gd
git commit -m "feat(core): deterministic roll and terrain entry cost"
```

---

### Task 1.6: Сектор броні

**Files:**
- Modify: `core/rules.gd`
- Test: `tests/core/test_rules_armour.gd`

**Interfaces:**
- Consumes: `Board.DIRS_8`, `UnitTypes.ArmourSector`
- Produces: `Rules.armour_sector(target_facing: int, target_pos: Vector2i, attacker_pos: Vector2i) -> int`

Цілочислова арифметика, без тригонометрії — точна формула з §3.4.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_rules_armour.gd`:

```gdscript
extends GutTest

const FRONT := UnitTypes.ArmourSector.FRONT
const SIDE := UnitTypes.ArmourSector.SIDE
const REAR := UnitTypes.ArmourSector.REAR

# Ціль стоїть у (5,5) і дивиться на північ (facing 0 = Vector2i(0,-1)).
const T := Vector2i(5, 5)

func test_attacker_straight_ahead_hits_front() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(5, 2)), FRONT)

func test_attacker_directly_behind_hits_rear() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(5, 9)), REAR)

func test_attacker_abeam_hits_side() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(9, 5)), SIDE)
	assert_eq(Rules.armour_sector(0, T, Vector2i(1, 5)), SIDE)

func test_forty_five_degrees_is_side() -> void:
	# рівно 45° від осі фейсингу: cos^2 = 0.5, а поріг у §3.4 — "<= 16" при масштабі 32
	assert_eq(Rules.armour_sector(0, T, Vector2i(8, 2)), SIDE)

func test_shallow_angle_is_still_front() -> void:
	assert_eq(Rules.armour_sector(0, T, Vector2i(6, 1)), FRONT)

func test_rotating_target_rotates_the_sectors() -> void:
	# та сама позиція атакера, ціль розвернулась на схід (facing 2)
	assert_eq(Rules.armour_sector(2, T, Vector2i(9, 5)), FRONT)
	assert_eq(Rules.armour_sector(2, T, Vector2i(1, 5)), REAR)
	assert_eq(Rules.armour_sector(2, T, Vector2i(5, 1)), SIDE)

func test_attacker_on_target_tile_is_front() -> void:
	assert_eq(Rules.armour_sector(0, T, T), FRONT, "виродженого випадку не має бути, але падати він не сміє")

func test_every_facing_has_a_front_a_side_and_a_rear() -> void:
	for facing in 8:
		var seen: Dictionary = {}
		for dx in range(-4, 5):
			for dy in range(-4, 5):
				if dx == 0 and dy == 0:
					continue
				seen[Rules.armour_sector(facing, T, T + Vector2i(dx, dy))] = true
		assert_eq(seen.size(), 3, "фейсинг %d має давати всі три сектори" % facing)
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Дописати в `core/rules.gd`**

```gdscript
static func armour_sector(target_facing: int, target_pos: Vector2i, attacker_pos: Vector2i) -> int:
	## §3.4. Цілі числа, без тригонометрії.
	var v: Vector2i = attacker_pos - target_pos
	if v == Vector2i.ZERO:
		return UnitTypes.ArmourSector.FRONT
	var f: Vector2i = Board.DIRS_8[target_facing]
	var dot: int = f.x * v.x + f.y * v.y
	var len_sq_f: int = f.x * f.x + f.y * f.y
	var len_sq_v: int = v.x * v.x + v.y * v.y
	# cos²θ <= 1/2, тобто 45° і ширше — межа сектора SIDE.
	# Порівняння перехресним множенням, а не діленням: варіант зі зсувом на 32 і
	# порогом 16 обрізався цілочисловим діленням і зсовував смугу cos² ∈ [0.5, 0.53125)
	# (кути 43.1°–45°) у SIDE. Розбіжність двох форм починається аж із 23.35 тайла,
	# тож жодного досяжного пострілу вона не міняла, але ця форма точна й без ділення.
	if 2 * dot * dot <= len_sq_f * len_sq_v:
		return UnitTypes.ArmourSector.SIDE
	return UnitTypes.ArmourSector.REAR if dot < 0 else UnitTypes.ArmourSector.FRONT
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_rules_armour.gd
git add core/rules.gd tests/core/test_rules_armour.gd
git commit -m "feat(core): integer armour sector resolution"
```

---

### Task 1.7: Формула шкоди — золоті тести

**Files:**
- Modify: `core/rules.gd`
- Test: `tests/core/test_rules_damage.gd`

**Interfaces:**
- Consumes: `Unit`, `UnitTypes`, `Rules.roll`, `Rules.armour_sector`
- Produces:
  - `Rules.MIN_DAMAGE: int = 10`
  - `Rules.compute_damage(rng, attacker: Unit, target: Unit, veterancy_level: int, sector: int, dist_sq: int) -> int`
  - `Rules.drone_damage(rng) -> int`

Це найважливіша функція в проєкті. Тести тут перевіряють **межі, а не одне число**: кидок робить результат діапазоном, тож золоті тести фіксують мінімум і максимум формули та кожен множник окремо.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_rules_damage.gd`:

```gdscript
extends GutTest

const INF_RIFLE := 0
const LIGHT_CAR := 2
const MEDIUM_TANK := 5
const HEAVY_TANK := 8
const FIELD_GUN := 9
const ENGINEER := 11

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _u(type_id: int) -> Unit:
	return Unit.create(1, type_id, 0, Vector2i.ZERO, 0)

func _samples(attacker_type: int, target_type: int, vet: int, sector: int, dist_sq: int) -> Array[int]:
	var out: Array[int] = []
	for s in 200:
		out.append(Rules.compute_damage(_rng(s), _u(attacker_type), _u(target_type), vet, sector, dist_sq))
	return out

func _min(a: Array[int]) -> int:
	var m: int = a[0]
	for v in a:
		m = mini(m, v)
	return m

func _max(a: Array[int]) -> int:
	var m: int = a[0]
	for v in a:
		m = maxi(m, v)
	return m

func test_damage_never_below_ten() -> void:
	# Сценарій має справді впиратися в підлогу: легка машина (60) у лоб важкому танку (56)
	# дає 45 + rand(0,15) − 42 − rand(0,14), тобто здебільшого відʼємне число.
	# Піхота тут не годиться: вона броню ігнорує, тож 0.75*15 = 11.25 → 11, і 10 недосяжне.
	var s: Array[int] = _samples(LIGHT_CAR, HEAVY_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_eq(_min(s), 10, "§3.3: мінімум 10, ніщо не є невразливим")

func test_infantry_ignores_armour_entirely() -> void:
	var vs_heavy: Array[int] = _samples(INF_RIFLE, HEAVY_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	var vs_infantry: Array[int] = _samples(INF_RIFLE, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_eq(_min(vs_heavy), _min(vs_infantry), "піхота не віднімає броню взагалі")
	assert_eq(_max(vs_heavy), _max(vs_infantry))

func test_infantry_base_range_band() -> void:
	# A = 15: 0.75*15 = 11.25, кидок 0..3 -> 11..14, але підлога 10 не втручається
	var s: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_between(_min(s), 11, 12)
	assert_between(_max(s), 13, 15)

func test_infantry_close_assault_is_quadruple() -> void:
	var far: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	var close: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 2)
	# ×4 множить float ДО єдиного int() наприкінці: int(11.25*4) = 45, а не int(11.25)*4 = 44.
	# Тому рівність тут хибна — правильне співвідношення має люфт на зрізання.
	assert_between(_min(close), _min(far) * 4, _min(far) * 4 + 3,
		"§3.3: dist_sq <= 2 множить на 4, з поправкою на зрізання int()")

func test_close_assault_boundary_is_dist_sq_two() -> void:
	var at_two: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 2)
	var at_three: Array[int] = _samples(INF_RIFLE, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 3)
	assert_true(_min(at_two) > _min(at_three), "діагональний сусід (dist_sq=2) ще штурм, dist_sq=3 вже ні")

func test_veterancy_adds_one_eighth_of_attack_per_level() -> void:
	var v0: Array[int] = _samples(MEDIUM_TANK, LIGHT_CAR, 0, UnitTypes.ArmourSector.REAR, 9)
	var v4: Array[int] = _samples(MEDIUM_TANK, LIGHT_CAR, 4, UnitTypes.ArmourSector.REAR, 9)
	# 95*4/8 у GDScript — це ціле 47, а у формулі член float: 47.5. Зрізання наприкінці
	# дає різницю 47 або 48 залежно від дробової частини бази, тож фіксуємо обидва.
	assert_between(_min(v4) - _min(v0), 47, 48, "+A*V/8 = 47.5")

func test_engineers_get_no_veterancy_bonus() -> void:
	var v0: Array[int] = _samples(ENGINEER, LIGHT_CAR, 0, UnitTypes.ArmourSector.FRONT, 9)
	var v5: Array[int] = _samples(ENGINEER, LIGHT_CAR, 5, UnitTypes.ArmourSector.FRONT, 9)
	assert_eq(_min(v0), _min(v5), "§3.3: інженер не отримує бонусу ветеранства")

func test_flanking_beats_frontal_fire() -> void:
	var front: Array[int] = _samples(MEDIUM_TANK, HEAVY_TANK, 0, UnitTypes.ArmourSector.FRONT, 9)
	var side: Array[int] = _samples(MEDIUM_TANK, HEAVY_TANK, 0, UnitTypes.ArmourSector.SIDE, 9)
	var rear: Array[int] = _samples(MEDIUM_TANK, HEAVY_TANK, 0, UnitTypes.ArmourSector.REAR, 9)
	assert_true(_min(side) > _min(front), "борт болючіший за лоб")
	assert_true(_min(rear) > _min(side), "корма болючіша за борт")

func test_artillery_bonus_against_tanks() -> void:
	var vs_tank: Array[int] = _samples(FIELD_GUN, MEDIUM_TANK, 0, UnitTypes.ArmourSector.FRONT, 25)
	assert_true(_max(vs_tank) > _min(vs_tank), "§3.3: проти танка додається rand(0, A/2)")

func test_artillery_minimum_range_penalty() -> void:
	var close: Array[int] = _samples(FIELD_GUN, LIGHT_CAR, 0, UnitTypes.ArmourSector.FRONT, 4)
	var far: Array[int] = _samples(FIELD_GUN, LIGHT_CAR, 0, UnitTypes.ArmourSector.FRONT, 25)
	assert_true(_min(close) < _min(far), "dist_sq <= 4 ділить шкоду навпіл")

func test_artillery_halved_against_light_vehicles() -> void:
	var vs_light: Array[int] = _samples(FIELD_GUN, LIGHT_CAR, 0, UnitTypes.ArmourSector.SIDE, 25)
	var vs_tank: Array[int] = _samples(FIELD_GUN, MEDIUM_TANK, 0, UnitTypes.ArmourSector.SIDE, 25)
	assert_true(_min(vs_light) < _min(vs_tank), "легка техніка отримує половину")

func test_armour_piercing_quartered_against_infantry() -> void:
	# Порівняння має ізолювати саме ділення на 4, тож обидві цілі мають нульову броню
	# в обраному секторі: у польової гармати корма 0, у піхоти броні немає взагалі.
	# (Порівняння з лобом легкої машини (27) змішувало б /4 з відніманням броні.)
	var vs_inf: Array[int] = _samples(MEDIUM_TANK, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	var vs_gun: Array[int] = _samples(MEDIUM_TANK, FIELD_GUN, 0, UnitTypes.ArmourSector.REAR, 9)
	assert_true(_min(vs_inf) * 3 < _min(vs_gun), "§3.3: танк/арта по піхоті — /4")

func test_light_vehicles_do_not_take_the_infantry_penalty() -> void:
	# §3.9: саме тому легка техніка — відповідь на дронарів
	var light_vs_inf: Array[int] = _samples(LIGHT_CAR, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	var tank_vs_inf: Array[int] = _samples(MEDIUM_TANK, INF_RIFLE, 0, UnitTypes.ArmourSector.FRONT, 9)
	assert_true(_min(light_vs_inf) > _min(tank_vs_inf))

func test_drone_strike_band() -> void:
	var out: Array[int] = []
	for s in 300:
		out.append(Rules.drone_damage(_rng(s)))
	assert_eq(_min(out), 120, "§3.9: 120 + rand(0, 60)")
	assert_between(_max(out), 170, 180)

func test_damage_is_deterministic_per_seed() -> void:
	var a: int = Rules.compute_damage(_rng(42), _u(MEDIUM_TANK), _u(HEAVY_TANK), 2, UnitTypes.ArmourSector.SIDE, 9)
	var b: int = Rules.compute_damage(_rng(42), _u(MEDIUM_TANK), _u(HEAVY_TANK), 2, UnitTypes.ArmourSector.SIDE, 9)
	assert_eq(a, b)
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Дописати в `core/rules.gd`**

Порядок операцій — рівно як у §3.3. Не переставляти: множники некомутативні через цілочислове ділення.

```gdscript
const MIN_DAMAGE: int = 10

static func compute_damage(rng: RandomNumberGenerator, attacker: Unit, target: Unit,
		veterancy_level: int, sector: int, dist_sq: int) -> int:
	## §3.3. Порядок множників критичний — не переставляти.
	var a: int = attacker.attack()
	var ac: int = attacker.unit_class()
	var tc: int = target.unit_class()

	var dmg: float = 0.75 * float(a) + float(roll(rng, a / 4))

	if ac != UnitTypes.UnitClass.ENGINEER:
		dmg += float(a * veterancy_level) / 8.0

	if ac == UnitTypes.UnitClass.INFANTRY:
		if dist_sq <= 2:
			dmg *= 4.0
		# броня не віднімається взагалі
	else:
		var r: int = target.armour(sector)
		dmg -= 0.75 * float(r) + float(roll(rng, r / 4))

	if ac == UnitTypes.UnitClass.ARTILLERY:
		if tc == UnitTypes.UnitClass.TANK:
			dmg += float(roll(rng, a / 2))
		if dist_sq <= 4:
			dmg /= 2.0
		if tc == UnitTypes.UnitClass.LIGHT_VEHICLE:
			dmg /= 2.0

	if tc == UnitTypes.UnitClass.INFANTRY and (ac == UnitTypes.UnitClass.TANK or ac == UnitTypes.UnitClass.ARTILLERY):
		dmg /= 4.0

	return maxi(MIN_DAMAGE, int(dmg))

static func drone_damage(rng: RandomNumberGenerator) -> int:
	## §3.9. Броня ігнорується повністю: дрон заходить згори, сектор не рахується.
	return 120 + roll(rng, 60)

static func distance_sq(a: Vector2i, b: Vector2i) -> int:
	var d: Vector2i = a - b
	return d.x * d.x + d.y * d.y

static func in_radius(a: Vector2i, b: Vector2i, r: int) -> bool:
	## §3.1: евклідів радіус, порівняння квадратів — без sqrt.
	return distance_sq(a, b) <= r * r
```

- [ ] **Step 4: Запустити — усе має пройти**

Якщо `test_infantry_base_range_band` не сходиться на одиницю — це округлення `int()` (обрізання до нуля), а не помилка формули. Підправити межі в тесті під фактичну поведінку `int()`, але **не міняти формулу**.

- [ ] **Step 5: Коміт**

```bash
git add core/rules.gd tests/core/test_rules_damage.gd
git commit -m "feat(core): damage model with golden tests"
```

---

### Task 1.8: `core/pathing.gd` — Dijkstra і дві зони руху

**Files:**
- Create: `core/pathing.gd`
- Test: `tests/core/test_pathing.gd`

**Interfaces:**
- Consumes: `Unit`, `Board`, `Rules.entry_cost_at`
- Produces:
  - `Pathing.Zones` (внутрішній клас): `cost: Dictionary` (`Vector2i -> int`), `came_from: Dictionary` (`Vector2i -> Vector2i`), `move_and_fire: Array[Vector2i]`, `move_only: Array[Vector2i]`
    - `zones.can_reach(p: Vector2i) -> bool`
    - `zones.cost_to(p: Vector2i) -> int`
  - `Pathing.compute_zones(board: Board, unit: Unit, occupied: Dictionary) -> Zones`
  - `Pathing.path_to(zones: Zones, target: Vector2i) -> Array[Vector2i]` — шлях без стартового тайла

`occupied` — це `Vector2i -> int` (id юніта). Зайняті тайли не можна кінцевими; проїзд крізь чужі юніти заборонено, крізь свої — теж (спрощення: жодного просочування, це читабельніше на телефоні).

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_pathing.gd`:

```gdscript
extends GutTest

func _open_board() -> Board:
	return Board.create(10, 10, Terrain.GroundState.DRY)

func _road_board() -> Board:
	var b: Board = _open_board()
	for x in 10:
		b.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	return b

func test_zones_split_at_fire_cost() -> void:
	var b: Board = _road_board()
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)   # ap 48, fire_cost 20
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, {})
	for p in z.move_and_fire:
		assert_true(tank.ap - z.cost_to(p) >= tank.fire_cost(),
			"золота зона: після руху лишається >= fire_cost")
	for p in z.move_only:
		assert_true(tank.ap - z.cost_to(p) < tank.fire_cost(),
			"червона зона: на постріл уже не вистачає")

func test_zones_do_not_overlap() -> void:
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(_road_board(), tank, {})
	for p in z.move_and_fire:
		assert_false(z.move_only.has(p), "тайл належить рівно одній зоні")

func test_start_tile_is_reachable_at_zero_cost() -> void:
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(4, 4), 0)
	var z: Pathing.Zones = Pathing.compute_zones(_open_board(), tank, {})
	assert_eq(z.cost_to(Vector2i(4, 4)), 0)
	assert_true(z.move_and_fire.has(Vector2i(4, 4)), "стояти на місці й стріляти завжди можна")

func test_road_reaches_further_than_rough_ground() -> void:
	# Порівнювати треба з пересіченою місцевістю, а не з чистим полем: у референсі
	# поле коштує 10, а середній танк має cross_country 12, тож max(10, 10+10-12)
	# упирається в підлогу — гусенична техніка відкритого поля не помічає, і це
	# автентична поведінка, а не баг. Дорогу видно там, де штраф справді кусає.
	var tank_road: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z_road: Pathing.Zones = Pathing.compute_zones(_road_board(), tank_road, {})
	var forest: Board = _open_board()
	for x in 10:
		forest.set_kind(Vector2i(x, 5), Terrain.Kind.FOREST)
	var tank_forest: Unit = Unit.create(2, 5, 0, Vector2i(0, 5), 2)
	var z_forest: Pathing.Zones = Pathing.compute_zones(forest, tank_forest, {})
	# Ціль має бути досяжною обома шляхами, інакше порівнюються не вартості:
	# лісом це 18 AP за тайл при бюджеті 48, тож (4,5) коштує 72 і недосяжна,
	# а cost_to() віддає сентинел −1, і будь-яке `<` мовчки стає істиною.
	var target := Vector2i(2, 5)
	assert_true(z_road.can_reach(target), "дорогою сюди дістатися можна")
	assert_true(z_forest.can_reach(target), "лісом теж можна, тільки дорожче")
	assert_true(z_road.cost_to(target) < z_forest.cost_to(target))

func test_infantry_ignores_terrain() -> void:
	var b: Board = _open_board()
	for y in 10:
		b.set_kind(Vector2i(3, y), Terrain.Kind.FOREST)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, inf, {})
	assert_eq(z.cost_to(Vector2i(3, 5)), 30, "піхота платить по 10 за тайл незалежно від лісу")

func test_impassable_tiles_are_unreachable() -> void:
	var b: Board = _open_board()
	for y in 10:
		b.set_kind(Vector2i(2, y), Terrain.Kind.WATER)
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, {})
	assert_false(z.can_reach(Vector2i(2, 5)))
	assert_false(z.can_reach(Vector2i(5, 5)), "за водою нічого не досяжно")

func test_occupied_tiles_block_movement() -> void:
	var b: Board = _road_board()
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var occupied: Dictionary = {Vector2i(2, 5): 99}
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, occupied)
	assert_false(z.can_reach(Vector2i(2, 5)), "на чужий тайл не стають")

func test_movement_never_uses_diagonals() -> void:
	var b: Board = _open_board()
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(0, 0), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, inf, {})
	assert_eq(z.cost_to(Vector2i(1, 1)), 20, "§3.1: діагональ — це два ортогональні кроки")

func test_path_reconstruction_is_contiguous() -> void:
	var b: Board = _road_board()
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(0, 5), 2)
	var z: Pathing.Zones = Pathing.compute_zones(b, tank, {})
	var path: Array[Vector2i] = Pathing.path_to(z, Vector2i(3, 5))
	assert_eq(path.size(), 3, "шлях не містить стартовий тайл")
	assert_eq(path[path.size() - 1], Vector2i(3, 5))
	var prev: Vector2i = tank.pos
	for step in path:
		assert_eq(absi(step.x - prev.x) + absi(step.y - prev.y), 1, "кожен крок — один ортогональний тайл")
		prev = step

func test_exhausted_unit_can_reach_only_itself() -> void:
	var tank: Unit = Unit.create(1, 5, 0, Vector2i(4, 4), 0)
	tank.exhaust()
	var z: Pathing.Zones = Pathing.compute_zones(_open_board(), tank, {})
	assert_eq(z.cost.size(), 1)
	assert_eq(z.move_and_fire.size(), 0, "з нулем AP стріляти вже нічим")
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/pathing.gd`**

```gdscript
class_name Pathing
extends RefCounted
## Дві зони руху (§3.2) — Dijkstra по вартості входу, 4-звʼязна сітка.

class Zones extends RefCounted:
	var origin: Vector2i = Vector2i.ZERO
	var cost: Dictionary = {}          # Vector2i -> int
	var came_from: Dictionary = {}     # Vector2i -> Vector2i
	var move_and_fire: Array[Vector2i] = []
	var move_only: Array[Vector2i] = []

	func can_reach(p: Vector2i) -> bool:
		return cost.has(p)

	func cost_to(p: Vector2i) -> int:
		## Викликати лише після can_reach(). Недосяжний тайл — це помилка виклику,
		## а не значення: −1 мовчки перевертає будь-яке порівняння `<`, і саме так
		## двічі падали тести цього завдання. Assert вирізається в release-збірці,
		## тож там лишається −1 як мʼяка деградація замість падіння на телефоні.
		assert(cost.has(p), "cost_to() для недосяжного тайла: %v" % p)
		return cost.get(p, -1)

static func compute_zones(board: Board, unit: Unit, occupied: Dictionary) -> Zones:
	var z := Zones.new()
	z.origin = unit.pos
	z.cost[unit.pos] = 0

	# Проста черга з пошуком мінімуму: карти маленькі (десятки на десятки),
	# купа тут не окупається і лише додає коду.
	var frontier: Array[Vector2i] = [unit.pos]
	while not frontier.is_empty():
		var best_i: int = 0
		for i in frontier.size():
			if z.cost[frontier[i]] < z.cost[frontier[best_i]]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)

		for n in board.neighbours4(current):
			if occupied.has(n):
				continue
			var step: int = Rules.entry_cost_at(unit, board, n)
			if step >= Terrain.IMPASSABLE:
				continue
			var total: int = z.cost[current] + step
			if total > unit.ap:
				continue
			if z.cost.has(n) and z.cost[n] <= total:
				continue
			z.cost[n] = total
			z.came_from[n] = current
			frontier.append(n)

	var fire_cost: int = unit.fire_cost()
	for p: Vector2i in z.cost:
		var left: int = unit.ap - z.cost[p]
		if left >= fire_cost:
			z.move_and_fire.append(p)
		else:
			z.move_only.append(p)
	return z

static func path_to(zones: Zones, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not zones.cost.has(target) or target == zones.origin:
		return out
	var current: Vector2i = target
	while current != zones.origin:
		out.push_front(current)
		current = zones.came_from[current]
	return out
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_pathing.gd
git add core/pathing.gd tests/core/test_pathing.gd
git commit -m "feat(core): Dijkstra flood fill for the two movement zones"
```

---

### Task 1.9: `core/vision.gd` — туман війни на гравця

**Files:**
- Create: `core/vision.gd`
- Test: `tests/core/test_vision.gd`

**Interfaces:**
- Consumes: `Board`, `Unit`, `Rules.in_radius`
- Produces:
  - `Vision` (RefCounted, по одному екземпляру на гравця): `visible: PackedByteArray`, `seen: PackedByteArray`
    - `Vision.create(width: int, height: int) -> Vision`
    - `vision.is_visible(p: Vector2i) -> bool`, `vision.is_seen(p: Vector2i) -> bool`
    - `vision.recompute(board: Board, units: Array[Unit], player: int) -> Array[Vector2i]` — перераховує `visible` з нуля, доливає в `seen`, повертає тайли, які щойно вперше побачили (для події `TileRevealed`)

`visible` завжди перебудовується з нуля — накопичувати його між ходами означає протікання чужої інформації, а це найдорожчий баг у хот-ситі.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_vision.gd`:

```gdscript
extends GutTest

func _board() -> Board:
	return Board.create(12, 12, Terrain.GroundState.DRY)

func test_unit_sees_its_own_radius() -> void:
	var v: Vision = Vision.create(12, 12)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)   # vision 5
	v.recompute(_board(), [inf], 0)
	assert_true(v.is_visible(Vector2i(6, 6)))
	assert_true(v.is_visible(Vector2i(6, 1)), "рівно 5 тайлів — усередині")
	assert_false(v.is_visible(Vector2i(6, 0)), "6 тайлів — уже ні")

func test_vision_is_euclidean_not_diamond() -> void:
	var v: Vision = Vision.create(12, 12)
	var inf: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	v.recompute(_board(), [inf], 0)
	assert_true(v.is_visible(Vector2i(9, 9)), "dist_sq 18 <= 25 — коло, не ромб")

func test_only_own_units_contribute() -> void:
	var v: Vision = Vision.create(12, 12)
	var mine: Unit = Unit.create(1, 0, 0, Vector2i(1, 1), 0)
	var theirs: Unit = Unit.create(2, 0, 1, Vector2i(10, 10), 0)
	v.recompute(_board(), [mine, theirs], 0)
	assert_false(v.is_visible(Vector2i(10, 10)), "чужий юніт не світить тобі карту")

func test_dead_units_see_nothing() -> void:
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	u.hp = 0
	v.recompute(_board(), [u], 0)
	assert_false(v.is_visible(Vector2i(6, 6)))

func test_seen_is_sticky_but_visible_is_not() -> void:
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(2, 2), 0)
	v.recompute(_board(), [u], 0)
	assert_true(v.is_visible(Vector2i(2, 2)))
	u.pos = Vector2i(10, 10)
	v.recompute(_board(), [u], 0)
	assert_false(v.is_visible(Vector2i(2, 2)), "visible перебудовується з нуля")
	assert_true(v.is_seen(Vector2i(2, 2)), "seen памʼятає назавжди")

func test_newly_revealed_tiles_are_reported_once() -> void:
	var v: Vision = Vision.create(12, 12)
	var u: Unit = Unit.create(1, 0, 0, Vector2i(6, 6), 0)
	var first: Array[Vector2i] = v.recompute(_board(), [u], 0)
	assert_true(first.size() > 0)
	var second: Array[Vector2i] = v.recompute(_board(), [u], 0)
	assert_eq(second.size(), 0, "той самий огляд другого разу нічого не відкриває")
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/vision.gd`**

```gdscript
class_name Vision
extends RefCounted
## Туман війни (§3.5). Один екземпляр на гравця; visible завжди з нуля.

var width: int = 0
var height: int = 0
var visible: PackedByteArray = PackedByteArray()
var seen: PackedByteArray = PackedByteArray()

static func create(p_width: int, p_height: int) -> Vision:
	var v := Vision.new()
	v.width = p_width
	v.height = p_height
	v.visible.resize(p_width * p_height)
	v.seen.resize(p_width * p_height)
	return v

func _index(p: Vector2i) -> int:
	return p.y * width + p.x

func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height

func is_visible(p: Vector2i) -> bool:
	return _in_bounds(p) and visible[_index(p)] == 1

func is_seen(p: Vector2i) -> bool:
	return _in_bounds(p) and seen[_index(p)] == 1

func recompute(board: Board, units: Array[Unit], player: int) -> Array[Vector2i]:
	visible.fill(0)
	var revealed: Array[Vector2i] = []
	for u in units:
		if u.owner != player or not u.is_alive():
			continue
		var r: int = u.vision()
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p: Vector2i = u.pos + Vector2i(dx, dy)
				if not board.in_bounds(p):
					continue
				if not Rules.in_radius(u.pos, p, r):
					continue
				var i: int = _index(p)
				visible[i] = 1
				if seen[i] == 0:
					seen[i] = 1
					revealed.append(p)
	return revealed
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_vision.gd
git add core/vision.gd tests/core/test_vision.gd
git commit -m "feat(core): per-player fog of war with sticky seen grid"
```

---

### Task 1.10: `core/events.gd` — словник подій

**Files:**
- Create: `core/events.gd`
- Test: `tests/core/test_events.gd`

**Interfaces:**
- Consumes: нічого
- Produces: `Events` із внутрішніми класами, кожен успадковує `Events.BattleEvent`:
  - `UnitMoved(unit_id: int, path: Array[Vector2i], facing: int)`
  - `UnitTurned(unit_id: int, facing: int)`
  - `ShotFired(attacker_id: int, target_id: int, sector: int)`
  - `DroneLaunched(attacker_id: int, target_id: int, drones_left: int)`
  - `DamageDealt(unit_id: int, amount: int, hp_left: int)`
  - `UnitDestroyed(unit_id: int, pos: Vector2i)`
  - `TileRevealed(player: int, tiles: Array[Vector2i])`
  - `MinePlaced(pos: Vector2i, owner: int)`
  - `MineCleared(pos: Vector2i)`
  - `MineTriggered(pos: Vector2i, unit_id: int)`
  - `MineRevealed(pos: Vector2i, player: int)`
  - `BridgeChanged(pos: Vector2i, destroyed: bool)`
  - `UnitRepaired(unit_id: int, amount: int, hp_left: int)`
  - `ObjectiveCaptured(index: int, owner: int)`
  - `ObjectiveDestroyed(index: int)`
  - `VeterancyGained(player: int, unit_class: int, level: int)`
  - `ApChanged(unit_id: int, ap: int)`
  - `TurnEnded(player: int)`
  - `TurnStarted(player: int, turn_number: int)`
  - `PlayerEliminated(player: int)`
  - `MatchEnded(winner: int)`

Кожен клас має `func describe() -> String` для читабельних падінь тестів і логів.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_events.gd`:

```gdscript
extends GutTest

func test_events_carry_their_payload() -> void:
	var e := Events.UnitMoved.new(7, [Vector2i(1, 1), Vector2i(1, 2)], 4)
	assert_eq(e.unit_id, 7)
	assert_eq(e.path.size(), 2)
	assert_eq(e.facing, 4)

func test_every_event_describes_itself() -> void:
	var samples: Array = [
		Events.UnitMoved.new(1, [Vector2i.ZERO], 0),
		Events.ShotFired.new(1, 2, UnitTypes.ArmourSector.SIDE),
		Events.DamageDealt.new(2, 40, 60),
		Events.UnitDestroyed.new(2, Vector2i(3, 3)),
		Events.MatchEnded.new(0),
	]
	for e in samples:
		assert_true(e is Events.BattleEvent, "усе успадковує спільну базу")
		assert_false(e.describe().is_empty())
```

Плюс третій тест, який конструює **всі 21 тип** зі списку в **Interfaces** явними викликами
конструкторів і для кожного перевіряє `is Events.BattleEvent` та непорожній `describe()`.
Двох тестів вище недостатньо: вони чіпають 5 типів із 21, а цей файл існує саме як контракт
для всіх подальших завдань — перейменоване поле чи переставлений аргумент у решті 16 класів
проїхали б мовчки. Виклики конструкторів виписуються дослівно, не генеруються рефлексією:
сам виклик і є перевіркою.

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/events.gd`**

Шаблон — далі так само для кожного типу зі списку вище:

```gdscript
class_name Events
extends RefCounted
## Усе, що core/ повідомляє вигляду. Жодних сигналів Godot — лише значення.

class BattleEvent extends RefCounted:
	func describe() -> String:
		return "BattleEvent"

class UnitMoved extends BattleEvent:
	var unit_id: int
	var path: Array[Vector2i]
	var facing: int
	func _init(p_unit_id: int, p_path: Array[Vector2i], p_facing: int) -> void:
		unit_id = p_unit_id
		path = p_path
		facing = p_facing
	func describe() -> String:
		return "UnitMoved(unit=%d, steps=%d, facing=%d)" % [unit_id, path.size(), facing]

class ShotFired extends BattleEvent:
	var attacker_id: int
	var target_id: int
	var sector: int
	func _init(p_attacker_id: int, p_target_id: int, p_sector: int) -> void:
		attacker_id = p_attacker_id
		target_id = p_target_id
		sector = p_sector
	func describe() -> String:
		return "ShotFired(%d -> %d, sector=%d)" % [attacker_id, target_id, sector]

class DamageDealt extends BattleEvent:
	var unit_id: int
	var amount: int
	var hp_left: int
	func _init(p_unit_id: int, p_amount: int, p_hp_left: int) -> void:
		unit_id = p_unit_id
		amount = p_amount
		hp_left = p_hp_left
	func describe() -> String:
		return "DamageDealt(unit=%d, -%d, hp=%d)" % [unit_id, amount, hp_left]

class UnitDestroyed extends BattleEvent:
	var unit_id: int
	var pos: Vector2i
	func _init(p_unit_id: int, p_pos: Vector2i) -> void:
		unit_id = p_unit_id
		pos = p_pos
	func describe() -> String:
		return "UnitDestroyed(unit=%d at %s)" % [unit_id, pos]

class MatchEnded extends BattleEvent:
	var winner: int
	func _init(p_winner: int) -> void:
		winner = p_winner
	func describe() -> String:
		return "MatchEnded(winner=%d)" % winner
```

Решта класів зі списку в **Interfaces** пишуться за цим самим шаблоном: типізовані поля, `_init` з усіма полями, `describe()`.

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_events.gd
git add core/events.gd tests/core/test_events.gd
git commit -m "feat(core): battle event vocabulary"
```

---

### Task 1.11: `core/veterancy.gd`

**Files:**
- Create: `core/veterancy.gd`
- Test: `tests/core/test_veterancy.gd`

**Interfaces:**
- Consumes: `UnitTypes.UnitClass`
- Produces:
  - `Veterancy` (RefCounted, по одному на гравця): `xp: Array[int]` (5 пулів за індексом класу), `level: Array[int]`
    - `Veterancy.create() -> Veterancy`
    - `veterancy.add_damage(unit_class: int, amount: int) -> int` — повертає новий рівень; підвищення можливе кілька разів за виклик
    - `veterancy.level_of(unit_class: int) -> int`
    - `Veterancy.THRESHOLDS: Dictionary` — пороги з §3.7
  - Максимальний рівень — 5.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_veterancy.gd`:

```gdscript
extends GutTest

const INF := UnitTypes.UnitClass.INFANTRY
const TANK := UnitTypes.UnitClass.TANK
const ENG := UnitTypes.UnitClass.ENGINEER

func test_starts_at_zero() -> void:
	assert_eq(Veterancy.create().level_of(INF), 0)

func test_first_infantry_threshold_is_150() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(INF, 149), 0)
	assert_eq(v.add_damage(INF, 1), 1, "150 сумарно — рівень 1")

func test_threshold_is_subtracted_not_reset() -> void:
	var v: Veterancy = Veterancy.create()
	v.add_damage(INF, 200)
	assert_eq(v.xp[INF], 50, "§3.7: пул зменшується на поріг, залишок переноситься")

func test_multiple_levels_in_one_hit() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(INF, 600), 2, "150 + 375 = 525 <= 600")

func test_caps_at_five() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(INF, 1_000_000), 5)
	assert_eq(v.add_damage(INF, 1_000_000), 5, "вище пʼятого не росте")

func test_classes_are_independent() -> void:
	var v: Veterancy = Veterancy.create()
	v.add_damage(INF, 1500)
	# Самої лише перевірки рівня мало: перший поріг танка — 1000, тож 500 XP, що
	# протекли б із піхоти, однаково лишили б рівень 0. Тому 1500 (вистачило б на
	# рівень танка) і пряма перевірка пулу.
	assert_eq(v.level_of(TANK), 0, "пули не течуть між класами")
	assert_eq(v.xp[TANK], 0, "у чужому пулі не має бути жодного XP")

func test_tank_progresses_slower_than_infantry() -> void:
	var a: Veterancy = Veterancy.create()
	var b: Veterancy = Veterancy.create()
	a.add_damage(INF, 1000)
	b.add_damage(TANK, 1000)
	assert_true(a.level_of(INF) > b.level_of(TANK))

func test_engineers_never_level() -> void:
	var v: Veterancy = Veterancy.create()
	assert_eq(v.add_damage(ENG, 1_000_000), 0, "§3.7: інженери шкоди не завдають і рівнів не мають")
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/veterancy.gd`**

```gdscript
class_name Veterancy
extends RefCounted
## §3.7. Прогрес — на клас і на гравця, за завдану шкоду. У скірміші — на матч.

const MAX_LEVEL: int = 5

const THRESHOLDS: Dictionary = {
	UnitTypes.UnitClass.INFANTRY:      [150, 375, 938, 2344, 5859],
	UnitTypes.UnitClass.LIGHT_VEHICLE: [700, 1750, 4375, 10938, 27344],
	UnitTypes.UnitClass.TANK:          [1000, 2500, 6250, 15625, 39063],
	UnitTypes.UnitClass.ARTILLERY:     [2000, 5000, 12500, 31250, 78125],
	UnitTypes.UnitClass.ENGINEER:      [],
}

var xp: Array[int] = [0, 0, 0, 0, 0]
var level: Array[int] = [0, 0, 0, 0, 0]

static func create() -> Veterancy:
	return Veterancy.new()

func level_of(unit_class: int) -> int:
	return level[unit_class]

func add_damage(unit_class: int, amount: int) -> int:
	var thresholds: Array = THRESHOLDS[unit_class]
	if thresholds.is_empty() or amount <= 0:
		return level[unit_class]
	xp[unit_class] += amount
	while level[unit_class] < MAX_LEVEL:
		var next: int = thresholds[level[unit_class]]
		if xp[unit_class] < next:
			break
		xp[unit_class] -= next
		level[unit_class] += 1
	return level[unit_class]
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_veterancy.gd
git add core/veterancy.gd tests/core/test_veterancy.gd
git commit -m "feat(core): per-class veterancy pools and thresholds"
```

---

### Task 1.12: `core/battle_state.gd` — стан матчу і черга ходів

**Files:**
- Create: `core/battle_state.gd`
- Test: `tests/core/test_battle_state.gd`

**Interfaces:**
- Consumes: `Board`, `Unit`, `Vision`, `Veterancy`, `Events`
- Produces:
  - `BattleState` (RefCounted): `board: Board`, `units: Dictionary` (`int -> Unit`), `player_count: int`, `active_player: int`, `turn_number: int`, `rng: RandomNumberGenerator`, `seed_value: int`, `vision: Array[Vision]`, `veterancy: Array[Veterancy]`, `eliminated: Array[bool]`, `winner: int` (−1 доки триває), `_next_unit_id: int`
    - `BattleState.create(board: Board, player_count: int, seed_value: int) -> BattleState`
    - `state.add_unit(type_id: int, owner: int, pos: Vector2i, facing: int) -> Unit`
    - `state.unit_at(p: Vector2i) -> Unit` (або `null`)
    - `state.units_of(player: int) -> Array[Unit]`
    - `state.alive_units() -> Array[Unit]`
    - `state.occupied_map() -> Dictionary` — `Vector2i -> unit_id`, лише живі
    - `state.is_over() -> bool`
    - `state.begin_turn() -> Array[Events.BattleEvent]` — поповнює AP усім юнітам активного гравця, перераховує його туман, повертає `TurnStarted` + `TileRevealed`
    - `state.advance_player() -> int` — наступний неусунутий гравець
    - `state.check_elimination() -> Array[Events.BattleEvent]`

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_battle_state.gd`:

```gdscript
extends GutTest

func _state(players: int = 2) -> BattleState:
	return BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), players, 4242)

func test_ids_are_unique_and_increasing() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(0, 0, Vector2i(1, 1), 0)
	var b: Unit = s.add_unit(0, 1, Vector2i(8, 8), 0)
	assert_true(b.id > a.id)
	assert_eq(s.units.size(), 2)

func test_unit_at_finds_living_units_only() -> void:
	var s: BattleState = _state()
	var u: Unit = s.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_eq(s.unit_at(Vector2i(4, 4)), u)
	u.hp = 0
	assert_null(s.unit_at(Vector2i(4, 4)), "труп не займає тайл")

func test_occupied_map_covers_all_living_units() -> void:
	var s: BattleState = _state()
	s.add_unit(0, 0, Vector2i(1, 1), 0)
	s.add_unit(0, 1, Vector2i(2, 2), 0)
	assert_eq(s.occupied_map().size(), 2)

func test_begin_turn_refills_only_active_players_units() -> void:
	var s: BattleState = _state()
	var mine: Unit = s.add_unit(5, 0, Vector2i(1, 1), 0)
	var theirs: Unit = s.add_unit(5, 1, Vector2i(8, 8), 0)
	mine.exhaust()
	theirs.exhaust()
	s.active_player = 0
	s.begin_turn()
	assert_eq(mine.ap, mine.max_ap())
	assert_eq(theirs.ap, 0, "чужі юніти чекають свого ходу")

## Порядок подій у begin_turn перевіряється теж: TurnStarted мусить іти перед
## TileRevealed, інакше вигляд відкриє тайли ще до того, як оголосить чий хід.
func test_begin_turn_emits_turn_started() -> void:
	var s: BattleState = _state()
	s.add_unit(0, 0, Vector2i(5, 5), 0)
	var events: Array = s.begin_turn()
	assert_true(events[0] is Events.TurnStarted)

func test_rng_is_seeded_and_reproducible() -> void:
	var a: BattleState = BattleState.create(Board.create(4, 4, 0), 2, 99)
	var b: BattleState = BattleState.create(Board.create(4, 4, 0), 2, 99)
	assert_eq(Rules.roll(a.rng, 1000), Rules.roll(b.rng, 1000))

func test_advance_player_skips_eliminated_in_three_player_game() -> void:
	var s: BattleState = _state(3)
	s.active_player = 0
	s.eliminated[1] = true
	assert_eq(s.advance_player(), 2, "§3.10: усунутий гравець просто пропускається")

func test_elimination_is_detected_and_reported() -> void:
	var s: BattleState = _state()
	var a: Unit = s.add_unit(0, 0, Vector2i(1, 1), 0)
	var b: Unit = s.add_unit(0, 1, Vector2i(8, 8), 0)
	b.hp = 0
	var events: Array = s.check_elimination()
	assert_true(s.eliminated[1])
	assert_true(s.is_over())
	assert_eq(s.winner, 0)
	# Порядок подій — теж контракт: вигляд програє їх послідовно, і повідомити
	# про кінець матчу раніше за вибуття гравця означало б зіпсувати подачу.
	var eliminated_at: int = -1
	var ended_at: int = -1
	for i in events.size():
		if events[i] is Events.PlayerEliminated:
			eliminated_at = i
		elif events[i] is Events.MatchEnded:
			ended_at = i
	assert_true(eliminated_at >= 0 and ended_at > eliminated_at,
		"PlayerEliminated має передувати MatchEnded")

func test_match_ends_in_a_draw_when_nobody_survives() -> void:
	# Досяжно не лише взаємним знищенням: карта, де жоден гравець не має юнітів,
	# дає цей стан на першій же перевірці. Без DRAW матч зависав би назавжди —
	# winner лишався б NO_WINNER, is_over() ніколи не істина, а advance_player()
	# повертав би вибулого гравця.
	var s: BattleState = _state()
	var events: Array = s.check_elimination()
	assert_true(s.is_over(), "матч мусить завершитися, а не зависнути")
	assert_eq(s.winner, BattleState.DRAW, "нічия — не те саме, що незавершена гра")

func test_each_player_gets_its_own_vision() -> void:
	var s: BattleState = _state(3)
	assert_eq(s.vision.size(), 3)
	assert_ne(s.vision[0], s.vision[1], "жодного спільного об'єкта туману")
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/battle_state.gd`**

```gdscript
class_name BattleState
extends RefCounted
## Весь стан матчу. Серіалізовний, детермінований, без жодного нода.

var board: Board = null
var units: Dictionary = {}                # int -> Unit
var player_count: int = 2
var active_player: int = 0
var turn_number: int = 1
var seed_value: int = 0
var rng: RandomNumberGenerator = null
var vision: Array[Vision] = []
var veterancy: Array[Veterancy] = []
var eliminated: Array[bool] = []
## Матч триває, доки winner == NO_WINNER. DRAW потрібен окремим значенням, бо −1
## уже зайняте «ще триває»: без нього нічия була б невідрізненна від незавершеної гри.
const NO_WINNER: int = -1
const DRAW: int = -2

var winner: int = NO_WINNER
var mines: Array = []                     # заповнюється в Task 1.16
var objectives: Array = []                # заповнюється в Task 1.17
var _next_unit_id: int = 1

static func create(p_board: Board, p_player_count: int, p_seed: int) -> BattleState:
	var s := BattleState.new()
	s.board = p_board
	s.player_count = p_player_count
	s.seed_value = p_seed
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = p_seed
	for i in p_player_count:
		s.vision.append(Vision.create(p_board.width, p_board.height))
		s.veterancy.append(Veterancy.create())
		s.eliminated.append(false)
	return s

func add_unit(type_id: int, owner: int, pos: Vector2i, facing: int) -> Unit:
	var u: Unit = Unit.create(_next_unit_id, type_id, owner, pos, facing)
	_next_unit_id += 1
	units[u.id] = u
	return u

func get_unit(id: int) -> Unit:
	return units.get(id, null)

func alive_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for id in units:
		var u: Unit = units[id]
		if u.is_alive():
			out.append(u)
	return out

func units_of(player: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in alive_units():
		if u.owner == player:
			out.append(u)
	return out

func unit_at(p: Vector2i) -> Unit:
	for u in alive_units():
		if u.pos == p:
			return u
	return null

func occupied_map() -> Dictionary:
	var out: Dictionary = {}
	for u in alive_units():
		out[u.pos] = u.id
	return out

func is_over() -> bool:
	return winner != NO_WINNER

func begin_turn() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	out.append(Events.TurnStarted.new(active_player, turn_number))
	for u in units_of(active_player):
		u.refill_ap()
	out.append_array(refresh_vision(active_player))
	return out

func refresh_vision(player: int) -> Array[Events.BattleEvent]:
	## §3.5: перерахунок з нуля, ніколи не переносити чужу видимість у рендерер.
	var revealed: Array[Vector2i] = vision[player].recompute(board, alive_units(), player)
	if revealed.is_empty():
		return []
	return [Events.TileRevealed.new(player, revealed)] as Array[Events.BattleEvent]

func advance_player() -> int:
	## Якщо живих не лишилось, цикл нічого не знайде і поверне вибулого гравця.
	## Викликати лише коли матч ще триває — це стверджується, а не мовчиться.
	assert(not is_over(), "advance_player() після завершення матчу")
	var next: int = active_player
	for i in player_count:
		next = (next + 1) % player_count
		if not eliminated[next]:
			break
	return next

func check_elimination() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for p in player_count:
		if eliminated[p]:
			continue
		if units_of(p).is_empty():
			eliminated[p] = true
			out.append(Events.PlayerEliminated.new(p))
	var alive: Array[int] = []
	for p in player_count:
		if not eliminated[p]:
			alive.append(p)
	# `<= 1`, а не `== 1`: якщо живих не лишилось жодного, матч мусить усе одно
	# завершитися. Інакше winner навіки лишається NO_WINNER, is_over() ніколи не
	# стає істиною, а advance_player() повертає вибулого гравця — матч зависає
	# без жодного легального активного гравця. Досяжно не лише взаємним
	# знищенням, а й картою, де двоє гравців стартують без юнітів.
	if alive.size() <= 1 and winner == NO_WINNER:
		winner = alive[0] if alive.size() == 1 else DRAW
		out.append(Events.MatchEnded.new(winner))
	return out
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_battle_state.gd
git add core/battle_state.gd tests/core/test_battle_state.gd
git commit -m "feat(core): battle state, turn order and elimination"
```

---

### Task 1.13: Команди руху, повороту й завершення ходу

**Files:**
- Create: `core/commands/command.gd`
- Create: `core/commands/move_command.gd`
- Create: `core/commands/end_turn_command.gd`
- Test: `tests/core/test_move_command.gd`

**Interfaces:**
- Consumes: `BattleState`, `Pathing`, `Events`
- Produces:
  - `Command` (база): `func validate(state: BattleState) -> String` (порожній рядок = дозволено, інакше ключ помилки), `func apply(state: BattleState) -> Array[Events.BattleEvent]`
  - `MoveCommand.create(unit_id: int, target: Vector2i, facing: int) -> MoveCommand`
  - `EndTurnCommand.create() -> EndTurnCommand`

`facing` у `MoveCommand` — це напрямок, у якому юніт лишається стояти після руху; гравець задає його явно, бо це прямо годує модель броні. Якщо передано `-1`, береться напрямок останнього кроку.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_move_command.gd`:

```gdscript
extends GutTest

var state: BattleState

func before_each() -> void:
	var b: Board = Board.create(10, 10, Terrain.GroundState.DRY)
	for x in 10:
		b.set_kind(Vector2i(x, 5), Terrain.Kind.ROAD)
	state = BattleState.create(b, 2, 11)

func test_move_costs_ap_and_moves_the_unit() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	var before: int = u.ap
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(3, 5), -1)
	assert_eq(cmd.validate(state), "")
	var events: Array = cmd.apply(state)
	assert_eq(u.pos, Vector2i(3, 5))
	assert_true(u.ap < before)
	assert_true(events[0] is Events.UnitMoved)

func test_move_sets_explicit_facing() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	MoveCommand.create(u.id, Vector2i(3, 5), 6).apply(state)
	assert_eq(u.facing, 6, "гравець сам вирішує, куди дивитись — це вхід у модель броні")

func test_move_without_facing_uses_last_step_direction() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 0)
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_eq(u.facing, 2, "останній крок був на схід")

func test_cannot_move_beyond_ap() -> void:
	var u: Unit = state.add_unit(9, 0, Vector2i(0, 5), 2)   # арта, ap 24
	var cmd: MoveCommand = MoveCommand.create(u.id, Vector2i(9, 5), -1)
	assert_ne(cmd.validate(state), "", "недосяжна ціль має бути відхилена")

func test_cannot_move_onto_another_unit() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	state.add_unit(5, 1, Vector2i(2, 5), 2)
	assert_ne(MoveCommand.create(a.id, Vector2i(2, 5), -1).validate(state), "")

func test_cannot_move_someone_elses_unit() -> void:
	var theirs: Unit = state.add_unit(5, 1, Vector2i(0, 5), 2)
	state.active_player = 0
	assert_ne(MoveCommand.create(theirs.id, Vector2i(1, 5), -1).validate(state), "")

func test_unit_that_fired_cannot_move() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	u.exhaust()
	assert_ne(MoveCommand.create(u.id, Vector2i(1, 5), -1).validate(state), "")

func test_move_refreshes_vision() -> void:
	var u: Unit = state.add_unit(0, 0, Vector2i(0, 5), 2)
	state.begin_turn()
	var events: Array = MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	var has_reveal: bool = false
	for e in events:
		if e is Events.TileRevealed:
			has_reveal = true
	assert_true(has_reveal, "§3.5: видимість перераховується після кожного руху")

func test_end_turn_switches_player_and_bumps_turn_number() -> void:
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.add_unit(0, 1, Vector2i(8, 8), 0)
	state.active_player = 0
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 1)
	EndTurnCommand.create().apply(state)
	assert_eq(state.active_player, 0)
	assert_eq(state.turn_number, 2, "номер ходу росте, коли черга повертається до першого гравця")
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати базу і `MoveCommand`**

```gdscript
# core/commands/command.gd
class_name Command
extends RefCounted
## База для всіх дій. validate() повертає порожній рядок, якщо дія дозволена,
## або ключ перекладу помилки — щоб UI показав причину без власної логіки правил.
##
## Конвенція для КОЖНОЇ команди, без винятків:
##   1. `apply()` починається з `assert(validate(state) == "", ...)`. Диспетчера,
##      який гарантував би порядок, поки немає, тож інваріант тримає assert.
##   2. `apply()` не перераховує правила, які вже вирішив `validate()`, але й не
##      довіряє їм наосліп у release-збірці, де assert вирізано: кожне звернення
##      до значення, що існує лише для валідної дії, має безпечний запасний шлях,
##      і цей шлях ніколи не буває вигіднішим за легальну дію.
##   3. Перевірка `state.is_over()` — у validate() кожної команди. Матч, що
##      завершився, не приймає жодних дій.

func validate(_state: BattleState) -> String:
	return "ERR_NOT_IMPLEMENTED"

func apply(_state: BattleState) -> Array[Events.BattleEvent]:
	return []
```

```gdscript
# core/commands/move_command.gd
class_name MoveCommand
extends Command

var unit_id: int = 0
var target: Vector2i = Vector2i.ZERO
var facing: int = -1

static func create(p_unit_id: int, p_target: Vector2i, p_facing: int) -> MoveCommand:
	var c := MoveCommand.new()
	c.unit_id = p_unit_id
	c.target = p_target
	c.facing = p_facing
	return c

func validate(state: BattleState) -> String:
	if state.is_over():
		return "ERR_MATCH_OVER"
	var u: Unit = state.get_unit(unit_id)
	if u == null or not u.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if u.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if u.has_fired:
		return "ERR_ALREADY_FIRED"
	if not state.board.in_bounds(target):
		return "ERR_OFF_BOARD"
	var occupied: Dictionary = state.occupied_map()
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	if not zones.can_reach(target):
		return "ERR_OUT_OF_RANGE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	assert(validate(state) == "", "apply() без успішного validate()")
	var out: Array[Events.BattleEvent] = []
	var u: Unit = state.get_unit(unit_id)
	var occupied: Dictionary = state.occupied_map()
	occupied.erase(u.pos)
	var zones: Pathing.Zones = Pathing.compute_zones(state.board, u, occupied)
	var path: Array[Vector2i] = Pathing.path_to(zones, target)
	# cost_to() кличеться лише під can_reach(). У release-збірці assert вирізано,
	# тож недосяжна ціль повернула б −1, а spend_ap(−1) ДОДАВ би юнітові очко дії:
	# нелегальний хід ставав би вигіднішим за легальний. Запасний шлях — списати
	# все, що є: помилка не має винагороджуватись.
	var spent: int = zones.cost_to(target) if zones.can_reach(target) else u.ap

	var final_facing: int = facing
	if final_facing < 0:
		final_facing = Board.facing_towards(
			path[path.size() - 2] if path.size() >= 2 else u.pos,
			target) if not path.is_empty() else u.facing

	u.pos = target
	u.facing = final_facing
	u.spend_ap(spent)

	# Поворот на місці — це UnitTurned, а не UnitMoved з порожнім шляхом:
	# інакше вигляд мусив би сам розрізняти ці випадки за довжиною масиву.
	if path.is_empty():
		out.append(Events.UnitTurned.new(unit_id, final_facing))
	else:
		out.append(Events.UnitMoved.new(unit_id, path, final_facing))
	out.append(Events.ApChanged.new(unit_id, u.ap))
	out.append_array(state.refresh_vision(u.owner))
	# міни під ногами обробляються в Task 1.16 — там сюди додається виклик Mines.step_on()
	return out
```

```gdscript
# core/commands/end_turn_command.gd
class_name EndTurnCommand
extends Command

static func create() -> EndTurnCommand:
	return EndTurnCommand.new()

func validate(state: BattleState) -> String:
	return "ERR_MATCH_OVER" if state.is_over() else ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	out.append(Events.TurnEnded.new(state.active_player))
	out.append_array(state.check_elimination())
	if state.is_over():
		return out
	var previous: int = state.active_player
	state.active_player = state.advance_player()
	if state.active_player <= previous:
		state.turn_number += 1
	out.append_array(state.begin_turn())
	return out
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_move_command.gd
git add core/commands tests/core/test_move_command.gd
git commit -m "feat(core): move and end-turn commands"
```

---

### Task 1.14: `FireCommand` — постріл, ветеранство, знищення

**Files:**
- Create: `core/commands/fire_command.gd`
- Test: `tests/core/test_fire_command.gd`

**Interfaces:**
- Consumes: `BattleState`, `Rules`, `Veterancy`, `Events`
- Produces:
  - `FireCommand.create(unit_id: int, target_id: int) -> FireCommand`
  - `FireCommand.preview(state: BattleState, unit_id: int, target_id: int) -> Dictionary` — `{"sector": int, "min": int, "max": int}`, для показу прогнозу **до** підтвердження (§3.4: сектор має бути видно завжди)

Прев'ю не використовує `state.rng` — воно рахує межі формули аналітично, підставляючи 0 і максимум замість кидків. Інакше показ прогнозу зсував би послідовність RNG і ламав детермінізм.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_fire_command.gd`:

```gdscript
extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 7)
	state.active_player = 0

## Юніти додаються ПІСЛЯ before_each, а туман рахується лише в begin_turn(),
## тож кожен тест, який очікує легальний постріл, мусить викликати state.begin_turn()
## після розстановки. Без цього vision[0] лишається порожнім — і тести відхилення
## проходять із НЕПРАВИЛЬНОЇ причини (ціль невидима), нічого насправді не перевіряючи.
## Саме тому кожен тест відхилення звіряє конкретний ключ помилки, а не просто «не порожньо».

func test_fire_deals_damage_and_zeroes_ap() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	var before: int = t.hp
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "")
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(t.hp < before)
	assert_eq(a.ap, 0, "§3.2: постріл обнуляє AP")
	assert_true(a.has_fired)

func test_fire_emits_shot_then_damage() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	assert_true(events[0] is Events.ShotFired)
	assert_true(events[1] is Events.DamageDealt)

func test_out_of_range_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(0, 0), 2)   # range 4
	var t: Unit = state.add_unit(2, 1, Vector2i(11, 11), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_OUT_OF_RANGE")

func test_invisible_target_cannot_be_shot() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(0, 0), 2)   # арта, vision 3, range 5
	var t: Unit = state.add_unit(2, 1, Vector2i(4, 0), 2)
	state.begin_turn()
	assert_ne(FireCommand.create(a.id, t.id).validate(state), "",
		"§3.5: стріляти можна лише по тому, що бачиш")

func test_friendly_fire_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var f: Unit = state.add_unit(5, 0, Vector2i(5, 4), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(a.id, f.id).validate(state), "ERR_FRIENDLY_FIRE")

func test_engineer_cannot_fire() -> void:
	var e: Unit = state.add_unit(11, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(5, 4), 2)
	state.begin_turn()
	assert_eq(FireCommand.create(e.id, t.id).validate(state), "ERR_NO_WEAPON",
		"§3.6: інженер не має зброї")

func test_second_shot_in_a_turn_is_rejected() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	FireCommand.create(a.id, t.id).apply(state)
	assert_eq(FireCommand.create(a.id, t.id).validate(state), "ERR_NOT_ENOUGH_AP")

func test_kill_emits_destruction_and_checks_victory() -> void:
	var a: Unit = state.add_unit(9, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 6)
	state.begin_turn()
	t.hp = 1
	var events: Array = FireCommand.create(a.id, t.id).apply(state)
	var destroyed: bool = false
	var ended: bool = false
	for e in events:
		if e is Events.UnitDestroyed:
			destroyed = true
		if e is Events.MatchEnded:
			ended = true
	assert_true(destroyed)
	assert_true(ended, "останній юніт супротивника — кінець матчу")

func test_damage_feeds_the_attackers_class_pool() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	state.begin_turn()
	FireCommand.create(a.id, t.id).apply(state)
	assert_true(state.veterancy[0].xp[UnitTypes.UnitClass.TANK] > 0)

func test_preview_reports_sector_and_bounds() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)   # дивиться на схід, атака зі заходу
	var p: Dictionary = FireCommand.preview(state, a.id, t.id)
	assert_eq(p["sector"], UnitTypes.ArmourSector.REAR)
	# Конкретні числа, а не `min <= max`: остання перевірка не може впасти за
	# побудовою, бо обидва значення походять з одного джерела. Середній танк (95)
	# по кормі легкої машини (броня 10), ветеранство 0:
	#   мін = 0.75*95 + 0 − (0.75*10 + rand_max(2)) = 61.75 → 61
	#   макс = 0.75*95 + rand_max(23) − (0.75*10 + 0)  = 86.75 → 86
	assert_eq(p["min"], 61, "нижня межа — нульовий кидок атаки і максимальний кидок броні")
	assert_eq(p["max"], 86, "верхня межа — максимальний кидок атаки і нульовий кидок броні")

func test_preview_brackets_every_real_roll_and_is_tight() -> void:
	# Прев'ю бреше в обидва боки однаково погано: завузько — гравець ризикує
	# наосліп, зашироко — прогноз марний. Тому перевіряємо і охоплення, і щільність.
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	var p: Dictionary = FireCommand.preview(state, a.id, t.id)
	var seen_min: bool = false
	var seen_max: bool = false
	for s in 400:
		var r := RandomNumberGenerator.new()
		r.seed = s
		var v: int = Rules.compute_damage(r, a, t, 0, p["sector"], Rules.distance_sq(a.pos, t.pos))
		assert_between(v, p["min"], p["max"], "жоден реальний кидок не виходить за межі прев\'ю")
		seen_min = seen_min or v == p["min"]
		seen_max = seen_max or v == p["max"]
	assert_true(seen_min, "нижня межа досяжна, а не вигадана із запасом")
	assert_true(seen_max, "верхня межа досяжна — інакше прев\'ю занижує ризик")

func test_preview_does_not_disturb_the_rng() -> void:
	var a: Unit = state.add_unit(5, 0, Vector2i(4, 4), 2)
	var t: Unit = state.add_unit(2, 1, Vector2i(6, 4), 2)
	var before: int = Rules.roll(state.rng, 1000)
	state.rng.seed = state.seed_value
	Rules.roll(state.rng, 1000)
	FireCommand.preview(state, a.id, t.id)
	var after: int = Rules.roll(state.rng, 1000)
	state.rng.seed = state.seed_value
	Rules.roll(state.rng, 1000)
	assert_eq(after, Rules.roll(state.rng, 1000), "прев'ю не має споживати кидки")
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/commands/fire_command.gd`**

```gdscript
class_name FireCommand
extends Command

var unit_id: int = 0
var target_id: int = 0

static func create(p_unit_id: int, p_target_id: int) -> FireCommand:
	var c := FireCommand.new()
	c.unit_id = p_unit_id
	c.target_id = p_target_id
	return c

func validate(state: BattleState) -> String:
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	if a == null or not a.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if t == null or not t.is_alive():
		return "ERR_NO_SUCH_TARGET"
	if a.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if t.owner == a.owner:
		return "ERR_FRIENDLY_FIRE"
	if a.unit_class() == UnitTypes.UnitClass.ENGINEER:
		return "ERR_NO_WEAPON"
	if a.has_fired or a.ap < a.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if not Rules.in_radius(a.pos, t.pos, a.attack_range()):
		return "ERR_OUT_OF_RANGE"
	if not state.vision[a.owner].is_visible(t.pos):
		return "ERR_TARGET_NOT_VISIBLE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.veterancy[a.owner].level_of(a.unit_class())
	var dmg: int = Rules.compute_damage(state.rng, a, t, level, sector, dist_sq)

	a.exhaust()
	out.append(Events.ShotFired.new(unit_id, target_id, sector))
	out.append_array(_resolve_damage(state, a, t, dmg))
	out.append(Events.ApChanged.new(unit_id, 0))
	return out

static func _resolve_damage(state: BattleState, attacker: Unit, target: Unit, dmg: int) -> Array[Events.BattleEvent]:
	## Спільний хвіст для пострілу і для дронового удару.
	var out: Array[Events.BattleEvent] = []
	var applied: int = mini(dmg, target.hp)
	target.hp -= applied
	out.append(Events.DamageDealt.new(target.id, applied, target.hp))

	var before: int = state.veterancy[attacker.owner].level_of(attacker.unit_class())
	var after: int = state.veterancy[attacker.owner].add_damage(attacker.unit_class(), applied)
	if after != before:
		out.append(Events.VeterancyGained.new(attacker.owner, attacker.unit_class(), after))

	if not target.is_alive():
		out.append(Events.UnitDestroyed.new(target.id, target.pos))
		out.append_array(state.check_elimination())
	for p in state.player_count:
		out.append_array(state.refresh_vision(p))
	return out

static func preview(state: BattleState, unit_id: int, target_id: int) -> Dictionary:
	## Точні межі формули, без жодного кидка — RNG матчу тут не чіпається.
	## Межі бере Rules.damage_bounds(), а не перебір сідів: 64 проби давали
	## заниженy стелю (для арти по танку простір результатів — тисячі комбінацій,
	## і справжній максимум у вибірку майже ніколи не потрапляв). Гравцеві не
	## можна показувати хибно вузький діапазон у мить, коли він приймає рішення.
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	var sector: int = Rules.armour_sector(t.facing, t.pos, a.pos)
	var dist_sq: int = Rules.distance_sq(a.pos, t.pos)
	var level: int = state.veterancy[a.owner].level_of(a.unit_class())
	var bounds: Vector2i = Rules.damage_bounds(a, t, level, sector, dist_sq)
	return {"sector": sector, "min": bounds.x, "max": bounds.y}
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_fire_command.gd
git add core/commands/fire_command.gd tests/core/test_fire_command.gd
git commit -m "feat(core): fire command with armour sector preview"
```

---

### Task 1.15: `DroneCommand` — удар дроном штурмового відділення

**Files:**
- Create: `core/commands/drone_command.gd`
- Test: `tests/core/test_drone_command.gd`

**Interfaces:**
- Consumes: `FireCommand._resolve_damage`, `Rules.drone_damage`
- Produces: `DroneCommand.create(unit_id: int, target_id: int) -> DroneCommand`, `DroneCommand.RANGE: int = 5`

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_drone_command.gd`:

```gdscript
extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(14, 14, Terrain.GroundState.DRY), 2, 3)
	state.active_player = 0

func _assault(pos: Vector2i) -> Unit:
	return state.add_unit(1, 0, pos, 2)

func test_drone_ignores_armour_and_hits_hard() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(8, 1, Vector2i(6, 2), 2)   # важкий танк, лоб 56
	state.begin_turn()
	var before: int = t.hp
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "")
	DroneCommand.create(a.id, t.id).apply(state)
	assert_true(before - t.hp >= 120, "§3.9: 120 + rand(0,60), броня не віднімається")

func test_drone_reaches_five_tiles() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(7, 2), 2)
	state.begin_turn()
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "", "рівно 5 — у межах")

func test_drone_cannot_reach_six_tiles() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(8, 2), 2)
	state.begin_turn()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "")

func test_drone_cannot_target_infantry() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(0, 1, Vector2i(4, 2), 2)
	state.begin_turn()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "",
		"§3.9: піхота — не ціль для дрона, це і є контргра")

func test_drone_can_target_every_vehicle_class() -> void:
	for type_id in [2, 5, 9, 11]:
		before_each()
		var a: Unit = _assault(Vector2i(2, 2))
		var t: Unit = state.add_unit(type_id, 1, Vector2i(5, 2), 2)
		state.begin_turn()
		assert_eq(DroneCommand.create(a.id, t.id).validate(state), "", "тип %d має бути цілю" % type_id)

func test_rifle_squad_has_no_drones() -> void:
	var a: Unit = state.add_unit(0, 0, Vector2i(2, 2), 2)
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 2), 2)
	state.begin_turn()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "")

func test_ammo_is_two_and_not_replenishable() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 2)
	t.hp = 10_000
	state.begin_turn()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_eq(a.drones_left, 1)
	a.refill_ap()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_eq(a.drones_left, 0)
	a.refill_ap()
	assert_ne(DroneCommand.create(a.id, t.id).validate(state), "", "третього дрона немає ніколи")

func test_drone_costs_all_remaining_ap() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(5, 2), 2)
	state.begin_turn()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_eq(a.ap, 0)
	assert_true(a.has_fired)

func test_invisible_target_is_rejected() -> void:
	# Цей стан сьогодні недосяжний чесною грою, і тест про це чесно каже.
	# Зір штурмового відділення — 5, дальність дрона — 5, а туман ведеться ПО ТАЙЛАХ
	# і без перекриття перешкодами. Тому будь-яка ціль у межах дальності стоїть на
	# видимому тайлі, і гілка ERR_TARGET_NOT_VISIBLE недосяжна доти, доки ці два
	# числа рівні. Попередня версія тесту ставила ціль на 6 тайлів і насправді
	# перевіряла ERR_OUT_OF_RANGE, тобто не перевіряла нічого.
	# Гасимо туман вручну: гілка має працювати на той день, коли числа розійдуться.
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(5, 1, Vector2i(2, 6), 2)   # 4 тайли — усередині дальності
	state.begin_turn()
	state.vision[0].visible.fill(0)
	assert_eq(DroneCommand.create(a.id, t.id).validate(state), "ERR_TARGET_NOT_VISIBLE",
		"§3.9: ціль має бути видима гравцеві просто зараз")

func test_drone_damage_feeds_infantry_pool() -> void:
	var a: Unit = _assault(Vector2i(2, 2))
	var t: Unit = state.add_unit(8, 1, Vector2i(5, 2), 2)
	t.hp = 10_000
	state.begin_turn()
	DroneCommand.create(a.id, t.id).apply(state)
	assert_true(state.veterancy[0].xp[UnitTypes.UnitClass.INFANTRY] > 0)
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/commands/drone_command.gd`**

```gdscript
class_name DroneCommand
extends Command
## §3.9. Окрема дія, а не модифікатор звичайної атаки.

const RANGE: int = 5

var unit_id: int = 0
var target_id: int = 0

static func create(p_unit_id: int, p_target_id: int) -> DroneCommand:
	var c := DroneCommand.new()
	c.unit_id = p_unit_id
	c.target_id = p_target_id
	return c

func validate(state: BattleState) -> String:
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	if a == null or not a.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if t == null or not t.is_alive():
		return "ERR_NO_SUCH_TARGET"
	if a.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if t.owner == a.owner:
		return "ERR_FRIENDLY_FIRE"
	if a.drones_left <= 0:
		return "ERR_NO_DRONES_LEFT"
	if a.has_fired or a.ap < a.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if t.unit_class() == UnitTypes.UnitClass.INFANTRY:
		return "ERR_DRONE_CANNOT_TARGET_INFANTRY"
	if not Rules.in_radius(a.pos, t.pos, RANGE):
		return "ERR_OUT_OF_RANGE"
	if not state.vision[a.owner].is_visible(t.pos):
		return "ERR_TARGET_NOT_VISIBLE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	var a: Unit = state.get_unit(unit_id)
	var t: Unit = state.get_unit(target_id)
	a.drones_left -= 1
	a.exhaust()
	out.append(Events.DroneLaunched.new(unit_id, target_id, a.drones_left))
	out.append_array(FireCommand._resolve_damage(state, a, t, Rules.drone_damage(state.rng)))
	out.append(Events.ApChanged.new(unit_id, 0))
	return out
```

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_drone_command.gd
git add core/commands/drone_command.gd tests/core/test_drone_command.gd
git commit -m "feat(core): drone strike with ammo and infantry immunity"
```

---

### Task 1.16: `core/mines.gd` — укладання, розкриття по гравцях, підрив

**Files:**
- Create: `core/mines.gd`
- Modify: `core/commands/move_command.gd` (виклик `Mines.step_on` після руху)
- Test: `tests/core/test_mines.gd`

**Interfaces:**
- Consumes: `BattleState`, `Events`
- Produces:
  - `Mines.Mine` (внутрішній клас): `pos: Vector2i`, `owner: int`, `known_to: Array[bool]`
  - `Mines.place(state, pos: Vector2i, owner: int) -> Array[Events.BattleEvent]`
  - `Mines.clear(state, pos: Vector2i) -> Array[Events.BattleEvent]`
  - `Mines.mine_at(state, pos: Vector2i) -> Mines.Mine`
  - `Mines.reveal_near(state, player: int) -> Array[Events.BattleEvent]` — розкриває міни в радіусі 1 від юнітів гравця
  - `Mines.step_on(state, unit: Unit) -> Array[Events.BattleEvent]`
  - `Mines.DAMAGE_BASE: int = 90` і `Mines.DAMAGE_ROLL: int = 90` — шкода `90 + rand(0, 90)`
  - `Mines.is_known(state, pos: Vector2i, player: int) -> bool`

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_mines.gd`:

```gdscript
extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 5)

func test_mine_is_visible_only_to_owner() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 0), "власник свої міни бачить")
	assert_false(Mines.is_known(state, Vector2i(5, 5), 1), "§3.11: для решти вона невидима")

func test_passing_near_reveals_the_mine_for_that_player_only() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 3, 5)
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(0, 1, Vector2i(5, 6), 0)
	Mines.reveal_near(state, 1)
	assert_true(Mines.is_known(state, Vector2i(5, 5), 1))
	assert_false(Mines.is_known(state, Vector2i(5, 5), 2), "розкриття — на гравця, як і туман")

func test_driving_onto_an_unknown_mine_detonates_it() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	var u: Unit = state.add_unit(5, 1, Vector2i(5, 5), 0)
	var before: int = u.hp
	var events: Array = Mines.step_on(state, u)
	assert_true(u.hp < before)
	assert_null(Mines.mine_at(state, Vector2i(5, 5)), "міна одноразова")
	var triggered: bool = false
	for e in events:
		if e is Events.MineTriggered:
			triggered = true
	assert_true(triggered)

func test_own_mines_do_not_detonate_under_the_owner() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	var u: Unit = state.add_unit(5, 0, Vector2i(5, 5), 0)
	var before: int = u.hp
	Mines.step_on(state, u)
	assert_eq(u.hp, before, "своя міна свого не рве")

func test_clearing_removes_the_mine() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	Mines.clear(state, Vector2i(5, 5))
	assert_null(Mines.mine_at(state, Vector2i(5, 5)))

func test_mine_can_kill_and_end_the_match() -> void:
	Mines.place(state, Vector2i(5, 5), 0)
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	var u: Unit = state.add_unit(2, 1, Vector2i(5, 5), 0)
	u.hp = 10
	var events: Array = Mines.step_on(state, u)
	assert_false(u.is_alive())
	var ended: bool = false
	for e in events:
		if e is Events.MatchEnded:
			ended = true
	assert_true(ended)
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/mines.gd`**

```gdscript
class_name Mines
extends RefCounted
## §3.11. Видимість міни ведеться на гравця — так само, як туман тайлів.

## §4: у референсі (`class_1.method_105`) міна завдає `90 + rand(0, 90)`, а не фіксовану
## величину. Пласке число зробило б міну єдиним джерелом шкоди в грі, яке не кидається.
const DAMAGE_BASE: int = 90
const DAMAGE_ROLL: int = 90
const REVEAL_RADIUS: int = 1

class Mine extends RefCounted:
	var pos: Vector2i
	var owner: int
	var known_to: Array[bool] = []
	func _init(p_pos: Vector2i, p_owner: int, p_player_count: int) -> void:
		pos = p_pos
		owner = p_owner
		for i in p_player_count:
			known_to.append(i == p_owner)

static func mine_at(state: BattleState, pos: Vector2i) -> Mine:
	for m in state.mines:
		if m.pos == pos:
			return m
	return null

static func is_known(state: BattleState, pos: Vector2i, player: int) -> bool:
	var m: Mine = mine_at(state, pos)
	return m != null and m.known_to[player]

static func place(state: BattleState, pos: Vector2i, owner: int) -> Array[Events.BattleEvent]:
	if mine_at(state, pos) != null:
		return []
	state.mines.append(Mine.new(pos, owner, state.player_count))
	return [Events.MinePlaced.new(pos, owner)] as Array[Events.BattleEvent]

static func clear(state: BattleState, pos: Vector2i) -> Array[Events.BattleEvent]:
	var m: Mine = mine_at(state, pos)
	if m == null:
		return []
	state.mines.erase(m)
	return [Events.MineCleared.new(pos)] as Array[Events.BattleEvent]

static func reveal_near(state: BattleState, player: int) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for u in state.units_of(player):
		for m in state.mines:
			if m.known_to[player]:
				continue
			if Rules.in_radius(u.pos, m.pos, REVEAL_RADIUS):
				m.known_to[player] = true
				out.append(Events.MineRevealed.new(m.pos, player))
	return out

static func step_on(state: BattleState, unit: Unit) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	var m: Mine = mine_at(state, unit.pos)
	if m == null or m.owner == unit.owner:
		return out
	state.mines.erase(m)
	out.append(Events.MineTriggered.new(m.pos, unit.id))
	var applied: int = mini(DAMAGE_BASE + Rules.roll(state.rng, DAMAGE_ROLL), unit.hp)
	unit.hp -= applied
	out.append(Events.DamageDealt.new(unit.id, applied, unit.hp))
	if not unit.is_alive():
		out.append(Events.UnitDestroyed.new(unit.id, unit.pos))
		out.append_array(state.check_elimination())
	return out
```

- [ ] **Step 4: Підключити до `MoveCommand.apply`**

**Міна спрацьовує одразу, на першому ж пройденому тайлі, а не лише в кінцевій клітинці.**
Інакше мінне поле можна було б безкарно перетинати, зупиняючись одразу за ним, і міни
перестали б бути засобом заборони руху — вони стали б лотереєю для того, хто випадково
зупинився саме там. Юніт зупиняється на тайлі підриву: під ним щойно вибухнуло.

Тому `apply()` не просто телепортує юніт у `target`, а проходить шлях і шукає перший
замінований тайл. Предикат обрізання мусить бути **точно тією самою умовою**, за якою
детонує `Mines.step_on()` (`міна існує` і `її власник — не той, хто йде`), інакше шлях
обірветься там, де вибуху не буде, або навпаки.

```gdscript
	# Перший замінований тайл на шляху зупиняє рух.
	var stop_index: int = -1
	for i in path.size():
		var m: Mines.Mine = Mines.mine_at(state, path[i])
		if m != null and m.owner != u.owner:
			stop_index = i
			break
	var walked: Array[Vector2i] = path if stop_index < 0 else path.slice(0, stop_index + 1)
	var final_pos: Vector2i = target if walked.is_empty() else walked[walked.size() - 1]
	var spent: int = zones.cost_to(final_pos) if zones.can_reach(final_pos) else u.ap
```

`walked` іде в `UnitMoved` замість повного `path`, `final_pos` — у `u.pos`, і лише після
цього викликається `step_on`, який дивиться на `u.pos`. Порядок подій: рух → AP → підрив
→ розкриття сусідніх мін → перерахунок туману.

```gdscript
	out.append_array(Mines.step_on(state, u))
	out.append_array(Mines.reveal_near(state, u.owner))
	out.append_array(state.refresh_vision(u.owner))
	return out
```

Додати в `tests/core/test_move_command.gd`:

```gdscript
func test_moving_onto_an_enemy_mine_detonates_it() -> void:
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	Mines.place(state, Vector2i(2, 5), 1)
	var before: int = u.hp
	MoveCommand.create(u.id, Vector2i(3, 5), -1).apply(state)
	assert_true(u.hp < before, "§3.11: наїзд на нерозкриту міну — підрив")
	assert_eq(u.pos, Vector2i(2, 5),
		"міна спрацьовує одразу — юніт лишається на тайлі підриву, а не доходить до (3,5)")

func test_a_minefield_cannot_be_crossed_by_stopping_past_it() -> void:
	# Найважливіший тест цього завдання: якби детонував лише кінцевий тайл,
	# міну можна було б просто переїхати, і вся механіка заборони руху зникла б.
	var u: Unit = state.add_unit(5, 0, Vector2i(0, 5), 2)
	Mines.place(state, Vector2i(1, 5), 1)
	MoveCommand.create(u.id, Vector2i(4, 5), -1).apply(state)
	assert_eq(u.pos, Vector2i(1, 5), "рух обривається на міні, а не проходить крізь неї")
	assert_true(state.mines.is_empty(), "міна витрачена")
```

- [ ] **Step 5: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gdir=res://tests/core
git add core/mines.gd core/commands/move_command.gd tests/core/test_mines.gd tests/core/test_move_command.gd
git commit -m "feat(core): mines with per-player reveal and detonation on entry"
```

---

### Task 1.17: `core/objectives.gd` і `EngineerCommand`

**Files:**
- Create: `core/objectives.gd`
- Create: `core/commands/engineer_command.gd`
- Test: `tests/core/test_objectives.gd`
- Test: `tests/core/test_engineer_command.gd`

**Interfaces:**
- Consumes: `BattleState`, `Mines`, `Terrain`, `Events`
- Produces:
  - `Objectives.Objective`: `pos: Vector2i`, `owner: int` (−1 нейтральний), `intact: bool`, `seen_by: Array[bool]`
  - `Objectives.MAX_PER_MAP: int = 15`
  - `Objectives.add(state, pos: Vector2i, owner: int) -> int`
  - `Objectives.at(state, pos: Vector2i) -> Objectives.Objective`
  - `Objectives.refresh_seen(state, player: int) -> Array[Events.BattleEvent]` — ціль стає відомою, щойно гравець її побачив (§3.10)
  - `Objectives.held_by(state, player: int) -> int`
  - `Objectives.check_victory(state, hold_target: int) -> Array[Events.BattleEvent]`
  - `EngineerCommand.Action` — enum `{ LAY_MINE, CLEAR_MINE, REPAIR_BRIDGE, DEMOLISH_BRIDGE, REPAIR_UNIT, CAPTURE_OBJECTIVE, DEMOLISH_OBJECTIVE }`
  - `EngineerCommand.create(unit_id: int, action: int, target_pos: Vector2i) -> EngineerCommand`
  - `EngineerCommand.repair_amount(rng, engineer: Unit) -> int` — `(40 + rand(0, ap_left - fire_cost)) / 2`

Усі дії інженера — на **ортогонально сусідньому** тайлі й коштують `fire_cost` AP. Ремонт — єдине місце в грі, де невитрачені AP щось означають; тому він рахується **до** списання вартості.

- [ ] **Step 1: Написати падаючі тести**

`tests/core/test_engineer_command.gd`:

```gdscript
extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(10, 10, Terrain.GroundState.DRY), 2, 21)
	state.active_player = 0

func _engineer(pos: Vector2i) -> Unit:
	return state.add_unit(11, 0, pos, 0)

func test_lay_mine_on_adjacent_tile() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var cmd: EngineerCommand = EngineerCommand.create(e.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3))
	assert_eq(cmd.validate(state), "")
	cmd.apply(state)
	assert_not_null(Mines.mine_at(state, Vector2i(4, 3)))
	assert_true(e.ap < e.max_ap(), "дія коштує fire_cost")

func test_diagonal_target_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var cmd: EngineerCommand = EngineerCommand.create(e.id, EngineerCommand.Action.LAY_MINE, Vector2i(5, 5))
	assert_ne(cmd.validate(state), "", "§3.8: лише ортогонально сусідній тайл")

func test_clear_mine_removes_it() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	Mines.place(state, Vector2i(4, 3), 1)
	EngineerCommand.create(e.id, EngineerCommand.Action.CLEAR_MINE, Vector2i(4, 3)).apply(state)
	assert_null(Mines.mine_at(state, Vector2i(4, 3)))

func test_demolish_bridge_reshapes_the_map() -> void:
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE)
	var e: Unit = _engineer(Vector2i(4, 4))
	EngineerCommand.create(e.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(4, 3)).apply(state)
	assert_eq(state.board.kind_at(Vector2i(4, 3)), Terrain.Kind.BRIDGE_DESTROYED)
	assert_false(state.board.is_passable(Vector2i(4, 3)))

func test_repair_bridge_restores_it() -> void:
	state.board.set_kind(Vector2i(4, 3), Terrain.Kind.BRIDGE_DESTROYED)
	var e: Unit = _engineer(Vector2i(4, 4))
	EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_BRIDGE, Vector2i(4, 3)).apply(state)
	assert_eq(state.board.kind_at(Vector2i(4, 3)), Terrain.Kind.BRIDGE)

func test_repair_heals_a_damaged_friendly_unit() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	var friend: Unit = state.add_unit(5, 0, Vector2i(4, 3), 0)
	friend.hp = 100
	EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).apply(state)
	assert_true(friend.hp > 100)
	assert_true(friend.hp <= friend.max_hp(), "лікування не перевищує максимум")

func test_repair_is_worse_when_the_engineer_drove_all_turn() -> void:
	var fresh: Unit = _engineer(Vector2i(1, 1))
	var tired: Unit = _engineer(Vector2i(8, 8))
	tired.ap = tired.fire_cost()
	var a: int = EngineerCommand.repair_amount(state.rng, fresh)
	var b: int = EngineerCommand.repair_amount(state.rng, tired)
	assert_true(a >= b, "§3.8: єдине місце, де невитрачені AP щось означають")

func test_repair_of_enemy_unit_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	state.add_unit(5, 1, Vector2i(4, 3), 0)
	assert_ne(EngineerCommand.create(e.id, EngineerCommand.Action.REPAIR_UNIT, Vector2i(4, 3)).validate(state), "")

func test_non_engineer_cannot_use_engineer_actions() -> void:
	var tank: Unit = state.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_ne(EngineerCommand.create(tank.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3)).validate(state), "")

func test_action_without_enough_ap_is_rejected() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	e.ap = 1
	assert_ne(EngineerCommand.create(e.id, EngineerCommand.Action.LAY_MINE, Vector2i(4, 3)).validate(state), "")

func test_capture_objective_flips_ownership() -> void:
	var e: Unit = _engineer(Vector2i(4, 4))
	Objectives.add(state, Vector2i(4, 3), -1)
	EngineerCommand.create(e.id, EngineerCommand.Action.CAPTURE_OBJECTIVE, Vector2i(4, 3)).apply(state)
	assert_eq(Objectives.at(state, Vector2i(4, 3)).owner, 0)
```

`tests/core/test_objectives.gd`:

```gdscript
extends GutTest

var state: BattleState

func before_each() -> void:
	state = BattleState.create(Board.create(12, 12, Terrain.GroundState.DRY), 2, 8)

func test_objective_is_hidden_until_seen() -> void:
	Objectives.add(state, Vector2i(10, 10), 1)
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.refresh_vision(0)
	Objectives.refresh_seen(state, 0)
	assert_false(Objectives.at(state, Vector2i(10, 10)).seen_by[0], "§3.10: цілі підкоряються туману")

func test_objective_becomes_known_once_observed() -> void:
	Objectives.add(state, Vector2i(3, 3), 1)
	state.add_unit(0, 0, Vector2i(3, 5), 0)
	state.refresh_vision(0)
	Objectives.refresh_seen(state, 0)
	assert_true(Objectives.at(state, Vector2i(3, 3)).seen_by[0])

func test_map_cannot_exceed_fifteen_objectives() -> void:
	for i in 15:
		assert_true(Objectives.add(state, Vector2i(i, 0), -1) >= 0)
	assert_eq(Objectives.add(state, Vector2i(0, 5), -1), -1, "§3.10: до 15 маркерів на карту")

func test_holding_enough_objectives_wins_the_match() -> void:
	state.add_unit(0, 0, Vector2i(1, 1), 0)
	state.add_unit(0, 1, Vector2i(10, 10), 0)
	for i in 3:
		Objectives.add(state, Vector2i(i, 0), 0)
	var events: Array = Objectives.check_victory(state, 3)
	assert_eq(state.winner, 0)
	assert_true(events.size() > 0)

func test_destroyed_objective_counts_for_nobody() -> void:
	Objectives.add(state, Vector2i(1, 0), 0)
	Objectives.at(state, Vector2i(1, 0)).intact = false
	assert_eq(Objectives.held_by(state, 0), 0)
```

- [ ] **Step 2: Запустити — мають упасти**

- [ ] **Step 3: Реалізувати `core/objectives.gd`**

```gdscript
class_name Objectives
extends RefCounted
## §3.10. Цілі підкоряються туману так само, як тайли.

const MAX_PER_MAP: int = 15

class Objective extends RefCounted:
	var pos: Vector2i
	var owner: int = -1
	var intact: bool = true
	var seen_by: Array[bool] = []
	func _init(p_pos: Vector2i, p_owner: int, p_player_count: int) -> void:
		pos = p_pos
		owner = p_owner
		for i in p_player_count:
			seen_by.append(false)

static func add(state: BattleState, pos: Vector2i, owner: int) -> int:
	if state.objectives.size() >= MAX_PER_MAP:
		return -1
	state.objectives.append(Objective.new(pos, owner, state.player_count))
	return state.objectives.size() - 1

static func at(state: BattleState, pos: Vector2i) -> Objective:
	for o in state.objectives:
		if o.pos == pos:
			return o
	return null

static func refresh_seen(state: BattleState, player: int) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	for o in state.objectives:
		if o.seen_by[player]:
			continue
		if state.vision[player].is_visible(o.pos):
			o.seen_by[player] = true
			out.append(Events.TileRevealed.new(player, [o.pos] as Array[Vector2i]))
	return out

static func held_by(state: BattleState, player: int) -> int:
	var n: int = 0
	for o in state.objectives:
		if o.intact and o.owner == player:
			n += 1
	return n

static func check_victory(state: BattleState, hold_target: int) -> Array[Events.BattleEvent]:
	if state.is_over() or hold_target <= 0:
		return []
	for p in state.player_count:
		if state.eliminated[p]:
			continue
		if held_by(state, p) >= hold_target:
			state.winner = p
			return [Events.MatchEnded.new(p)] as Array[Events.BattleEvent]
	return []
```

- [ ] **Step 4: Реалізувати `core/commands/engineer_command.gd`**

```gdscript
class_name EngineerCommand
extends Command
## §3.8. Верби замість гармати. Усе — на ортогонально сусідньому тайлі за fire_cost AP.

enum Action { LAY_MINE, CLEAR_MINE, REPAIR_BRIDGE, DEMOLISH_BRIDGE, REPAIR_UNIT, CAPTURE_OBJECTIVE, DEMOLISH_OBJECTIVE }

var unit_id: int = 0
var action: int = Action.LAY_MINE
var target_pos: Vector2i = Vector2i.ZERO

static func create(p_unit_id: int, p_action: int, p_target_pos: Vector2i) -> EngineerCommand:
	var c := EngineerCommand.new()
	c.unit_id = p_unit_id
	c.action = p_action
	c.target_pos = p_target_pos
	return c

static func repair_amount(rng: RandomNumberGenerator, engineer: Unit) -> int:
	## §3.8: (40 + rand(0, ap_left - fire_cost)) / 2 — інженер, що весь хід їхав, ремонтує погано.
	return (40 + Rules.roll(rng, engineer.ap - engineer.fire_cost())) / 2

func validate(state: BattleState) -> String:
	var e: Unit = state.get_unit(unit_id)
	if e == null or not e.is_alive():
		return "ERR_NO_SUCH_UNIT"
	if e.owner != state.active_player:
		return "ERR_NOT_YOUR_UNIT"
	if e.unit_class() != UnitTypes.UnitClass.ENGINEER:
		return "ERR_NOT_AN_ENGINEER"
	if e.has_fired or e.ap < e.fire_cost():
		return "ERR_NOT_ENOUGH_AP"
	if not state.board.in_bounds(target_pos):
		return "ERR_OFF_BOARD"
	var delta: Vector2i = target_pos - e.pos
	if absi(delta.x) + absi(delta.y) != 1:
		return "ERR_NOT_ADJACENT"

	match action:
		Action.LAY_MINE:
			if Mines.mine_at(state, target_pos) != null:
				return "ERR_MINE_ALREADY_THERE"
			if state.unit_at(target_pos) != null:
				return "ERR_TILE_OCCUPIED"
		Action.CLEAR_MINE:
			if Mines.mine_at(state, target_pos) == null:
				return "ERR_NO_MINE_THERE"
		Action.DEMOLISH_BRIDGE:
			if state.board.kind_at(target_pos) != Terrain.Kind.BRIDGE:
				return "ERR_NO_BRIDGE_THERE"
		Action.REPAIR_BRIDGE:
			if state.board.kind_at(target_pos) != Terrain.Kind.BRIDGE_DESTROYED:
				return "ERR_NOTHING_TO_REPAIR"
		Action.REPAIR_UNIT:
			var t: Unit = state.unit_at(target_pos)
			if t == null or t.owner != e.owner:
				return "ERR_NO_FRIENDLY_UNIT_THERE"
			if t.hp >= t.max_hp():
				return "ERR_UNIT_UNDAMAGED"
		Action.CAPTURE_OBJECTIVE, Action.DEMOLISH_OBJECTIVE:
			var o: Objectives.Objective = Objectives.at(state, target_pos)
			if o == null:
				return "ERR_NO_OBJECTIVE_THERE"
			if action == Action.CAPTURE_OBJECTIVE and (o.owner == e.owner or not o.intact):
				return "ERR_NOTHING_TO_CAPTURE"
	return ""

func apply(state: BattleState) -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = []
	var e: Unit = state.get_unit(unit_id)

	match action:
		Action.LAY_MINE:
			out.append_array(Mines.place(state, target_pos, e.owner))
		Action.CLEAR_MINE:
			out.append_array(Mines.clear(state, target_pos))
		Action.DEMOLISH_BRIDGE:
			state.board.set_kind(target_pos, Terrain.Kind.BRIDGE_DESTROYED)
			out.append(Events.BridgeChanged.new(target_pos, true))
		Action.REPAIR_BRIDGE:
			state.board.set_kind(target_pos, Terrain.Kind.BRIDGE)
			out.append(Events.BridgeChanged.new(target_pos, false))
		Action.REPAIR_UNIT:
			var t: Unit = state.unit_at(target_pos)
			# рахуємо ДО списання AP: у формулі бере участь саме залишок ходу
			var healed: int = mini(repair_amount(state.rng, e), t.max_hp() - t.hp)
			t.hp += healed
			out.append(Events.UnitRepaired.new(t.id, healed, t.hp))
		Action.CAPTURE_OBJECTIVE:
			var o: Objectives.Objective = Objectives.at(state, target_pos)
			o.owner = e.owner
			out.append(Events.ObjectiveCaptured.new(state.objectives.find(o), e.owner))
		Action.DEMOLISH_OBJECTIVE:
			var od: Objectives.Objective = Objectives.at(state, target_pos)
			od.intact = false
			out.append(Events.ObjectiveDestroyed.new(state.objectives.find(od)))

	e.exhaust()
	out.append(Events.ApChanged.new(unit_id, 0))
	for p in state.player_count:
		out.append_array(state.refresh_vision(p))
	return out
```

- [ ] **Step 5: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gdir=res://tests/core
git add core/objectives.gd core/commands/engineer_command.gd tests/core/test_objectives.gd tests/core/test_engineer_command.gd
git commit -m "feat(core): objectives, victory condition and engineer verbs"
```

---

### Task 1.18: Серіалізація стану

**Files:**
- Create: `core/battle_serializer.gd`
- Test: `tests/core/test_battle_serializer.gd`

**Interfaces:**
- Consumes: увесь `core/`
- Produces:
  - `BattleSerializer.VERSION: int = 1`
  - `BattleSerializer.to_dict(state: BattleState) -> Dictionary`
  - `BattleSerializer.from_dict(data: Dictionary) -> BattleState`
  - `BattleSerializer.save_to(state: BattleState, path: String) -> Error`
  - `BattleSerializer.load_from(path: String) -> BattleState`

Стан RNG зберігається як `rng.state`, не як сід: інакше після завантаження гра «перекидає» ті самі числа заново.

- [ ] **Step 1: Написати падаючий тест**

`tests/core/test_battle_serializer.gd`:

```gdscript
extends GutTest

func _populated_state() -> BattleState:
	var b: Board = Board.create(8, 8, Terrain.GroundState.MUD)
	b.set_kind(Vector2i(3, 3), Terrain.Kind.FOREST)
	b.set_kind(Vector2i(4, 4), Terrain.Kind.BRIDGE)
	var s: BattleState = BattleState.create(b, 3, 1234)
	s.add_unit(5, 0, Vector2i(1, 1), 3)
	s.add_unit(1, 1, Vector2i(6, 6), 5)
	s.add_unit(11, 2, Vector2i(2, 6), 0)
	Mines.place(s, Vector2i(5, 5), 0)
	Objectives.add(s, Vector2i(4, 0), 1)
	s.veterancy[0].add_damage(UnitTypes.UnitClass.TANK, 1200)
	s.turn_number = 4
	s.active_player = 2
	return s

func test_round_trip_preserves_everything() -> void:
	var a: BattleState = _populated_state()
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	assert_eq(b.board.width, a.board.width)
	assert_eq(b.board.ground_state, a.board.ground_state)
	assert_eq(b.board.kind_at(Vector2i(3, 3)), Terrain.Kind.FOREST)
	assert_eq(b.units.size(), a.units.size())
	assert_eq(b.turn_number, 4)
	assert_eq(b.active_player, 2)
	assert_eq(b.mines.size(), 1)
	assert_eq(b.objectives.size(), 1)
	assert_eq(b.veterancy[0].level_of(UnitTypes.UnitClass.TANK), a.veterancy[0].level_of(UnitTypes.UnitClass.TANK))

func test_unit_fields_survive() -> void:
	var a: BattleState = _populated_state()
	var assault: Unit = a.get_unit(2)
	assault.hp = 55
	assault.ap = 7
	assault.drones_left = 1
	assault.has_fired = true
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	var restored: Unit = b.get_unit(2)
	assert_eq(restored.hp, 55)
	assert_eq(restored.ap, 7)
	assert_eq(restored.drones_left, 1)
	assert_true(restored.has_fired)
	assert_eq(restored.facing, assault.facing)

func test_fog_is_restored_per_player() -> void:
	var a: BattleState = _populated_state()
	for p in a.player_count:
		a.refresh_vision(p)
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a))
	for p in a.player_count:
		assert_eq(b.vision[p].seen, a.vision[p].seen, "памʼять карти гравця %d" % p)

func test_rng_continues_where_it_stopped() -> void:
	var a: BattleState = _populated_state()
	for i in 17:
		Rules.roll(a.rng, 100)
	var expected: int = Rules.roll(a.rng, 100)
	for i in 17:
		pass
	var a2: BattleState = _populated_state()
	for i in 17:
		Rules.roll(a2.rng, 100)
	var b: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(a2))
	assert_eq(Rules.roll(b.rng, 100), expected, "зберігається стан RNG, а не сід")

func test_save_and_load_a_file() -> void:
	var path := "user://test_save.json"
	var a: BattleState = _populated_state()
	assert_eq(BattleSerializer.save_to(a, path), OK)
	var b: BattleState = BattleSerializer.load_from(path)
	assert_not_null(b)
	assert_eq(b.units.size(), a.units.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
```

- [ ] **Step 2: Запустити — має впасти**

- [ ] **Step 3: Реалізувати `core/battle_serializer.gd`**

Структура словника (кожне поле — явно, жодного `inst_to_dict`):

```gdscript
class_name BattleSerializer
extends RefCounted
## Стан ↔ Dictionary. Використовується і для збереження матчу, і для реплеїв.

const VERSION: int = 1

static func to_dict(state: BattleState) -> Dictionary:
	var units: Array = []
	for id in state.units:
		var u: Unit = state.units[id]
		units.append({
			"id": u.id, "type_id": u.type_id, "owner": u.owner,
			"x": u.pos.x, "y": u.pos.y, "facing": u.facing,
			"hp": u.hp, "ap": u.ap, "drones_left": u.drones_left, "has_fired": u.has_fired,
		})
	var mines: Array = []
	for m in state.mines:
		mines.append({"x": m.pos.x, "y": m.pos.y, "owner": m.owner, "known_to": m.known_to})
	var objectives: Array = []
	for o in state.objectives:
		objectives.append({"x": o.pos.x, "y": o.pos.y, "owner": o.owner, "intact": o.intact, "seen_by": o.seen_by})
	var vision: Array = []
	for v in state.vision:
		vision.append({"visible": Array(v.visible), "seen": Array(v.seen)})
	var veterancy: Array = []
	for vet in state.veterancy:
		veterancy.append({"xp": vet.xp, "level": vet.level})
	return {
		"version": VERSION,
		"board": {
			"width": state.board.width, "height": state.board.height,
			"ground_state": state.board.ground_state, "tiles": Array(state.board.tiles),
		},
		"player_count": state.player_count,
		"active_player": state.active_player,
		"turn_number": state.turn_number,
		"seed_value": state.seed_value,
		"rng_state": str(state.rng.state),
		"winner": state.winner,
		"eliminated": state.eliminated,
		"next_unit_id": state._next_unit_id,
		"units": units, "mines": mines, "objectives": objectives,
		"vision": vision, "veterancy": veterancy,
	}
```

`from_dict` дзеркально відновлює кожне поле; `rng.state` присвоюється через `int(data["rng_state"])`. `save_to`/`load_from` — `FileAccess` + `JSON.stringify`/`JSON.parse_string`, з поверненням `null` на невідомій `version`.

- [ ] **Step 4: Запустити — усе має пройти, коміт**

```bash
./run_tests.sh -gtest=res://tests/core/test_battle_serializer.gd
git add core/battle_serializer.gd tests/core/test_battle_serializer.gd
git commit -m "feat(core): battle state serialization with RNG continuity"
```

---

### Task 1.19: Наскрізний тест матчу

**Files:**
- Test: `tests/core/test_full_match.gd`

**Interfaces:**
- Consumes: увесь `core/`
- Produces: нічого — це страховка, яка ловить регресії на стиках

- [ ] **Step 1: Написати тест**

```gdscript
extends GutTest

func _map() -> Board:
	var b: Board = Board.create(16, 12, Terrain.GroundState.DRY)
	for x in 16:
		b.set_kind(Vector2i(x, 6), Terrain.Kind.ROAD)
	b.set_kind(Vector2i(8, 6), Terrain.Kind.BRIDGE)
	for y in 12:
		if y != 6:
			b.set_kind(Vector2i(8, y), Terrain.Kind.WATER)
	return b

func test_a_whole_match_runs_through_commands_only() -> void:
	var s: BattleState = BattleState.create(_map(), 2, 2024)
	var tank: Unit = s.add_unit(5, 0, Vector2i(2, 6), 2)
	var engineer: Unit = s.add_unit(11, 0, Vector2i(1, 6), 2)
	var enemy: Unit = s.add_unit(2, 1, Vector2i(12, 6), 6)
	Objectives.add(s, Vector2i(8, 6), -1)

	var log: Array[Events.BattleEvent] = []
	log.append_array(s.begin_turn())

	# гравець 0 їде до мосту й лишається зі стрільбою
	log.append_array(MoveCommand.create(tank.id, Vector2i(6, 6), 2).apply(s))
	assert_true(tank.ap >= tank.fire_cost(), "золота зона: рух і постріл ще можливі")
	log.append_array(EndTurnCommand.create().apply(s))
	assert_eq(s.active_player, 1)

	# гравець 1 підʼїжджає
	log.append_array(MoveCommand.create(enemy.id, Vector2i(10, 6), 6).apply(s))
	log.append_array(EndTurnCommand.create().apply(s))

	# гравець 0 стріляє, доки ворог живий
	var guard: int = 0
	while enemy.is_alive() and guard < 40:
		guard += 1
		if s.active_player != 0:
			log.append_array(EndTurnCommand.create().apply(s))
			continue
		var cmd: FireCommand = FireCommand.create(tank.id, enemy.id)
		if cmd.validate(s) == "":
			log.append_array(cmd.apply(s))
		log.append_array(EndTurnCommand.create().apply(s))

	assert_false(enemy.is_alive(), "танк мав дотиснути легку машину")
	assert_true(s.is_over())
	assert_eq(s.winner, 0)
	var ended: int = 0
	for e in log:
		if e is Events.MatchEnded:
			ended += 1
	assert_eq(ended, 1, "матч завершується рівно один раз")

func test_demolished_bridge_cuts_the_map_in_two() -> void:
	var s: BattleState = BattleState.create(_map(), 2, 5)
	var engineer: Unit = s.add_unit(11, 0, Vector2i(7, 6), 2)
	s.add_unit(5, 1, Vector2i(12, 6), 6)
	s.begin_turn()
	EngineerCommand.create(engineer.id, EngineerCommand.Action.DEMOLISH_BRIDGE, Vector2i(8, 6)).apply(s)
	var tank: Unit = s.add_unit(5, 0, Vector2i(6, 6), 2)
	tank.ap = 10_000
	var zones: Pathing.Zones = Pathing.compute_zones(s.board, tank, s.occupied_map())
	assert_false(zones.can_reach(Vector2i(12, 6)),
		"§3.8: підрив переправи перекроює карту — це найважча дія в грі")

func test_state_survives_a_save_load_mid_match() -> void:
	var s: BattleState = BattleState.create(_map(), 2, 99)
	var tank: Unit = s.add_unit(5, 0, Vector2i(2, 6), 2)
	s.add_unit(2, 1, Vector2i(12, 6), 6)
	s.begin_turn()
	MoveCommand.create(tank.id, Vector2i(5, 6), 2).apply(s)
	var restored: BattleState = BattleSerializer.from_dict(BattleSerializer.to_dict(s))
	assert_eq(restored.get_unit(tank.id).pos, Vector2i(5, 6))
	assert_eq(restored.get_unit(tank.id).ap, tank.ap)
	assert_eq(EndTurnCommand.create().validate(restored), "")
```

- [ ] **Step 2: Запустити повний набір**

```bash
./run_tests.sh
```

Очікується: усі тести PASS. Якщо `test_a_whole_match_runs_through_commands_only` впирається в `guard` — розібратися **чому** танк не добиває легку машину, а не піднімати ліміт.

- [ ] **Step 3: Коміт**

```bash
git add tests/core/test_full_match.gd
git commit -m "test(core): end-to-end match through commands only"
```

**Критерій завершення Фази 1:** `./run_tests.sh` зелений, `core/` не містить жодного згадування `Node`, і повний матч відіграється headless.

```bash
grep -rnE "\b(Node|Node3D|Node2D|Control|Sprite|get_node|_process|_ready|signal)\b" core/ && echo "ПОРУШЕННЯ ГРАНИЦІ core/" || echo "core/ чистий"
```

---

# Фаза 2 — вертикальний зріз

Мета фази: одна карта, кілька юнітів, повний цикл ходу на екрані, обовʼязковий гейт передачі пристрою. Геометрія — примітиви (`BoxMesh`, `CylinderMesh`); справжні моделі приходять у Фазі 5 і не мають вимагати змін у логіці вигляду.

Правило фази, яке не порушується: **вигляд ніколи нічого не обчислює.** Якщо в `game/` зʼявився виклик `Rules.compute_damage` не через прев'ю або будь-яка зміна `Unit` напряму — це дефект.

---

### Task 2.1: Автолоади `match_service` і `scene_router`

**Files:**
- Create: `game/autoload/match_service.gd`
- Create: `game/autoload/scene_router.gd`
- Modify: `project.godot` (секція `[autoload]`)
- Test: `tests/game/test_match_service.gd`

**Interfaces:**
- Consumes: `BattleState`, `Command`, `BattleSerializer`
- Produces:
  - `MatchService` (Node, автолоад): `state: BattleState`
    - `start_match(board: Board, player_count: int, seed_value: int) -> void`
    - `submit(command: Command) -> String` — валідує, застосовує, кладе події в чергу, повертає ключ помилки або `""`
    - `take_events() -> Array[Events.BattleEvent]` — забирає й очищає чергу
    - `signal events_ready` — єдиний сигнал назовні; напрямок строго view-ward
    - `save_current(path: String) -> Error`, `load_saved(path: String) -> bool`
  - `SceneRouter` (Node, автолоад): `goto(scene_path: String) -> void`, `goto_battle() -> void`, `goto_main_menu() -> void`

`MatchService` — єдине місце, де вигляд торкається `core/`. Жоден вузол не тримає власного посилання на `BattleState`, окрім читання через сервіс.

- [ ] **Step 1: Написати падаючий тест**

```gdscript
extends GutTest

var service: Node

func before_each() -> void:
	service = load("res://game/autoload/match_service.gd").new()
	add_child_autofree(service)
	service.start_match(Board.create(8, 8, Terrain.GroundState.DRY), 2, 1)

func test_rejected_command_produces_no_events() -> void:
	var enemy_unit: Unit = service.state.add_unit(5, 1, Vector2i(4, 4), 0)
	var err: String = service.submit(MoveCommand.create(enemy_unit.id, Vector2i(4, 5), -1))
	assert_ne(err, "", "чужий юніт не рухається")
	assert_eq(service.take_events().size(), 0, "відхилена команда не змінює нічого")

func test_accepted_command_queues_events() -> void:
	var u: Unit = service.state.add_unit(5, 0, Vector2i(4, 4), 0)
	assert_eq(service.submit(MoveCommand.create(u.id, Vector2i(4, 5), -1)), "")
	assert_true(service.take_events().size() > 0)
	assert_eq(service.take_events().size(), 0, "черга спорожняється після забору")
```

- [ ] **Step 2: Запустити, реалізувати, запустити знову**

```gdscript
# game/autoload/match_service.gd
extends Node
## Єдиний міст між сценами і core/. Сигнали йдуть лише назовні.

signal events_ready

var state: BattleState = null
var _queue: Array[Events.BattleEvent] = []

func start_match(board: Board, player_count: int, seed_value: int) -> void:
	state = BattleState.create(board, player_count, seed_value)
	_queue.clear()

func submit(command: Command) -> String:
	var err: String = command.validate(state)
	if err != "":
		return err
	_queue.append_array(command.apply(state))
	events_ready.emit()
	return ""

func take_events() -> Array[Events.BattleEvent]:
	var out: Array[Events.BattleEvent] = _queue.duplicate()
	_queue.clear()
	return out
```

- [ ] **Step 3: Зареєструвати автолоади в `project.godot`**

```ini
[autoload]
SettingsService="*res://game/autoload/settings_service.gd"
MatchService="*res://game/autoload/match_service.gd"
SceneRouter="*res://game/autoload/scene_router.gd"
```

`settings_service.gd` поки що — порожній `Node`; наповнюється в Task 3.4.

- [ ] **Step 4: Коміт**

```bash
git add game/autoload project.godot tests/game/test_match_service.gd
git commit -m "feat(game): match service and scene router autoloads"
```

---

### Task 2.2: Ізометричний ріг камери

**Files:**
- Create: `game/camera/iso_camera_rig.tscn`
- Create: `game/camera/iso_camera_rig.gd`
- Test: `tests/game/test_iso_camera_rig.gd`

**Interfaces:**
- Produces:
  - `IsoCameraRig` (Node3D): `pan(delta: Vector2) -> void`, `zoom_by(factor: float) -> void`, `center_on(cell: Vector2i) -> void`, `set_bounds(board_size: Vector2i) -> void`
  - `IsoCameraRig.cell_to_world(cell: Vector2i) -> Vector3` — `(x, 0, y)`, 45° **не** запікається в дані
  - `IsoCameraRig.world_to_cell(point: Vector3) -> Vector2i`

Камера — `Camera3D` у режимі `PROJECTION_ORTHOGONAL`, батьківський `Node3D` повернутий на 45° по Y, камера нахилена на 52° по X. Зум міняє `size` камери в межах `[6, 20]`. Панорама обмежена межами дошки з полем в 2 тайли.

- [ ] **Step 1: Тест на чисті функції рига**

```gdscript
extends GutTest

var rig: Node3D

func before_each() -> void:
	rig = load("res://game/camera/iso_camera_rig.tscn").instantiate()
	add_child_autofree(rig)
	rig.set_bounds(Vector2i(20, 20))

func test_cell_to_world_does_not_bake_the_isometric_angle() -> void:
	assert_eq(rig.cell_to_world(Vector2i(3, 4)), Vector3(3, 0, 4), "§3.1: 45° дає камера, не дані")

func test_world_to_cell_round_trips() -> void:
	for c in [Vector2i(0, 0), Vector2i(7, 2), Vector2i(19, 19)]:
		assert_eq(rig.world_to_cell(rig.cell_to_world(c)), c)

func test_zoom_is_clamped() -> void:
	for i in 50:
		rig.zoom_by(0.5)
	assert_true(rig.zoom_level >= rig.MIN_ZOOM)
	for i in 50:
		rig.zoom_by(2.0)
	assert_true(rig.zoom_level <= rig.MAX_ZOOM)

func test_pan_is_clamped_to_board() -> void:
	rig.pan(Vector2(1000, 1000))
	var focus: Vector3 = rig.global_position
	assert_true(focus.x <= 22.0 and focus.z <= 22.0, "камера не тікає з карти")

func test_center_on_moves_focus() -> void:
	rig.center_on(Vector2i(10, 10))
	assert_almost_eq(rig.global_position.x, 10.0, 0.01)
	assert_almost_eq(rig.global_position.z, 10.0, 0.01)
```

- [ ] **Step 2: Реалізувати сцену і скрипт, прогнати тест, закомітити**

```bash
./run_tests.sh -gtest=res://tests/game/test_iso_camera_rig.gd
git add game/camera tests/game/test_iso_camera_rig.gd
git commit -m "feat(game): fixed isometric camera rig with clamped pan and zoom"
```

---

### Task 2.3: `board_view` — рендер тайлів і туману

**Files:**
- Create: `game/battle/board_view.tscn`
- Create: `game/battle/board_view.gd`

**Interfaces:**
- Consumes: `Board`, `Vision`, `IsoCameraRig.cell_to_world`
- Produces:
  - `BoardView.build(board: Board) -> void` — інстансує `MultiMeshInstance3D` на кожен вид тайлу (один draw call на вид, а не на тайл)
  - `BoardView.apply_fog(vision: Vision) -> void` — три стани тайлу: невидимий (не рендериться), памʼятний (приглушений колір, без юнітів), видимий (повний)
  - `BoardView.highlight_tiles(tiles: Array[Vector2i], color: Color, layer: int) -> void`
  - `BoardView.clear_highlights(layer: int) -> void`

Три шари підсвітки: `LAYER_ZONES`, `LAYER_TARGETS`, `LAYER_SELECTION` — щоб зони не гасили підсвітку цілі.

- [ ] **Step 1: Побудувати сцену з `MultiMeshInstance3D` на вид тайлу**
- [ ] **Step 2: Реалізувати `apply_fog` через колір інстансу мультимешу (`INSTANCE_CUSTOM`)**
- [ ] **Step 3: Ручна перевірка**

```bash
$GODOT --path . game/battle/battle_screen.tscn
```

Очікується: дошка 16×12, дорога читається, за межами огляду тайли не малюються.

- [ ] **Step 4: Коміт**

---

### Task 2.4: `unit_view` — юніт на дошці

**Files:**
- Create: `game/battle/unit_view.tscn`
- Create: `game/battle/unit_view.gd`

**Interfaces:**
- Consumes: `Unit`, `UnitTypes`
- Produces:
  - `UnitView.bind(unit: Unit) -> void`
  - `UnitView.move_along(path: Array[Vector2i], duration_per_step: float) -> Signal` — твін по шляху, повертає `tween.finished`
  - `UnitView.face(direction: int) -> void`
  - `UnitView.set_hp(hp: int, max_hp: int) -> void`
  - `UnitView.set_drones(count: int) -> void` — §3.9 вимагає, щоб залишок дронів було видно **завжди**
  - `UnitView.play_destroyed() -> Signal`
  - `UnitView.set_dimmed(dimmed: bool) -> void` — для юнітів, які вже відстрілялись

Силует розпізнається з висоти на ~100 px (§1.5): піхота — низький вузький блок, легка техніка — плаский подовжений, танк — масивний із виступом ствола, арта — довгий тонкий ствол, інженер — коробка з жовтою смугою. Кольори гравців — на матеріалі корпусу, не на всьому меші.

- [ ] **Step 1: Сцена з примітивами на кожен клас**
- [ ] **Step 2: Твіни руху й повороту**
- [ ] **Step 3: HP-бар і значок дронів як `Sprite3D` з `billboard = enabled`**
- [ ] **Step 4: Коміт**

---

### Task 2.5: `zone_overlay` — дві зони руху

**Files:**
- Create: `game/battle/zone_overlay.gd`

**Interfaces:**
- Consumes: `Pathing.Zones`, `BoardView.highlight_tiles`
- Produces: `ZoneOverlay.show_for(unit: Unit, zones: Pathing.Zones) -> void`, `ZoneOverlay.clear() -> void`

Золотий — `move_and_fire`, червоний — `move_only` (§3.2). Це головний UI гри; він перемальовується після **кожної** дії, що змінює AP або зайнятість.

- [ ] **Step 1: Реалізувати**
- [ ] **Step 2: Перевірити вручну, що після пострілу обидві зони зникають**
- [ ] **Step 3: Коміт**

---

### Task 2.6: `event_player` — програвання подій

**Files:**
- Create: `game/battle/event_player.gd`
- Test: `tests/game/test_event_player.gd`

**Interfaces:**
- Consumes: `Events.*`, `BoardView`, `UnitView`
- Produces:
  - `EventPlayer.play(events: Array[Events.BattleEvent]) -> void` — послідовно, з `await` на кожній анімації
  - `EventPlayer.is_playing() -> bool`
  - `signal playback_finished`

Правило: у момент програвання ввід заблокований. Порядок подій зберігається строго. Снаряд летить 400 мс, але шкода вже вирішена — вигляд лише показує число.

- [ ] **Step 1: Тест на те, що кожен тип події має обробник**

```gdscript
func test_every_event_type_has_a_handler() -> void:
	var player = load("res://game/battle/event_player.gd").new()
	for name in EventPlayer.HANDLERS.keys():
		assert_true(player.has_method(EventPlayer.HANDLERS[name]),
			"подія %s не має обробника — вона мовчки зникне з екрана" % name)
```

- [ ] **Step 2: Реалізувати таблицю `HANDLERS: Dictionary` (назва класу події → назва методу)**
- [ ] **Step 3: Прогнати тест, коміт**

---

### Task 2.7: `input_controller` — вибір, рух, ціль

**Files:**
- Create: `game/battle/input_controller.gd`

**Interfaces:**
- Consumes: `MatchService`, `Pathing`, `FireCommand.preview`
- Produces:
  - `InputController.select_unit(unit: Unit) -> void`
  - `InputController.tap_cell(cell: Vector2i) -> void`
  - `signal selection_changed(unit)`
  - `signal action_preview(preview: Dictionary)`

Модель взаємодії, два тапи на будь-яку дію — жодного випадкового ходу від дотику:
1. тап по своєму юніту → вибір, показ двох зон;
2. тап по тайлу зони → показ шляху й залишку AP, кнопка підтвердження;
3. тап по ворогові в межах пострілу → показ сектора броні й прогнозу шкоди, кнопка підтвердження.

Тап поза дошкою або по вже вибраному юніту знімає вибір.

- [ ] **Step 1: Реалізувати вибір і рейкаст тапу в клітинку**
- [ ] **Step 2: Підключити прев'ю пострілу до HUD**
- [ ] **Step 3: Ручна перевірка циклу «вибрав → пішов → вистрілив»**
- [ ] **Step 4: Коміт**

---

### Task 2.8: HUD та інспектор юніта

**Files:**
- Create: `game/ui/hud.tscn`, `game/ui/hud.gd`
- Create: `game/ui/unit_inspector.tscn`, `game/ui/unit_inspector.gd`

**Interfaces:**
- Produces: `Hud.bind(state: BattleState) -> void`, `Hud.show_preview(preview: Dictionary) -> void`, `Hud.set_active_player(player: int) -> void`

HUD показує постійно: номер ходу, активного гравця, `ground_state` підписаною іконкою (§3.12), AP вибраного юніта числом, залишок дронів, кнопку «Завершити хід». Інспектор — стати з `UnitTypes` і три числа броні з підсвіченим сектором, у який піде постріл.

Кожне правило, що впливає на кидок, має бути видиме як число або іконка (§1.5). Прев'ю пострілу показує сектор і діапазон шкоди **до** підтвердження (§3.4).

- [ ] **Step 1: Розмітка з `SafeArea`-полями, тапабельні цілі ≥ 48 dp**
- [ ] **Step 2: Привʼязка до подій `MatchService`**
- [ ] **Step 3: Коміт**

---

### Task 2.9: Гейт передачі пристрою

**Files:**
- Create: `game/ui/handover_gate.tscn`, `game/ui/handover_gate.gd`
- Test: `tests/game/test_handover_gate.gd`

**Interfaces:**
- Produces: `HandoverGate.show_for(player: int) -> void`, `signal confirmed`

Це **функція коректності, а не декор** (§3.5). Вимоги, кожна перевіряється тестом або ручним чеклістом:

- дошка повністю затулена непрозорою панеллю до підтвердження;
- жодної анімації «проїзду» повз екран — нічого не видно ані до, ані під час;
- камера рецентрується на першому юніті гравця, що заходить, **до** зняття панелі, щоб позиція камери попереднього гравця не видала його розташування;
- кнопки «пропустити» не існує.

- [ ] **Step 1: Тест: після `show_for` панель непрозора і `visible`, події вводу дошки заблоковані**
- [ ] **Step 2: Тест: `confirmed` не емітується без явного натискання**
- [ ] **Step 3: Реалізувати, підключити до `Events.TurnStarted`**
- [ ] **Step 4: Коміт**

---

### Task 2.10: `battle_screen` — збірка зрізу

**Files:**
- Create: `game/battle/battle_screen.tscn`, `game/battle/battle_screen.gd`
- Create: `maps/skirmish_bridge.tres` + `core/map_data.gd` (Resource з тайлами, стартовими юнітами, цілями, `ground_state`)

**Interfaces:**
- Produces: `MapData` (Resource): `width`, `height`, `ground_state`, `tiles: PackedInt32Array`, `spawns: Array[Dictionary]`, `objectives: Array[Vector2i]`, `hold_target: int`, `name_key: String`
  - `MapData.to_board() -> Board`
  - `MapData.populate(state: BattleState) -> void`

- [ ] **Step 1: Створити `core/map_data.gd` і тест на `to_board()`**
- [ ] **Step 2: Зібрати `battle_screen.tscn`: ріг камери, `BoardView`, контейнер юнітів, HUD, гейт**
- [ ] **Step 3: Прописати ручну карту `skirmish_bridge` — 16×12, річка з мостом, по 3 юніти на гравця**
- [ ] **Step 4: Зіграти повний матч на пристрої або в вікні**

```bash
$GODOT --path .
```

Чекліст приймання Фази 2:
- вибір юніта показує дві зони різними кольорами;
- рух списує саме стільки AP, скільки показував шлях;
- постріл показує сектор броні до підтвердження й обнуляє AP після;
- між ходами зʼявляється гейт, і після нього на екрані немає нічого з попереднього гравця;
- знищення юніта прибирає його з дошки, а матч завершується екраном результату.

- [ ] **Step 5: Коміт**

```bash
git add game maps core/map_data.gd tests/game
git commit -m "feat(game): playable vertical slice with fog, zones and handover gate"
```

---

# Фаза 3 — меню й оболонка інтерфейсу

Мета фази: гра запускається з меню, матч налаштовується, мова перемикається, матч зберігається й відновлюється, а завершення матчу веде на екран результату, а не в порожнечу.

---

### Task 3.1: Локалізація з першого дня

**Files:**
- Create: `assets/i18n/strings.csv`
- Modify: `project.godot` (`internationalization/locale/translations`)
- Test: `tests/game/test_localisation.gd`

**Interfaces:**
- Produces: CSV із колонками `keys,uk,en`; усі ключі юнітів (`UNIT_*`), помилок (`ERR_*`), UI (`UI_*`), класів (`CLASS_*`), станів ґрунту (`GROUND_*`)

- [ ] **Step 1: Тест, що кожен ключ із core має переклад в обох мовах**

```gdscript
func test_every_unit_name_key_is_translated() -> void:
	for i in UnitTypes.count():
		var key: String = UnitTypes.get_type(i)["name_key"]
		for locale in ["uk", "en"]:
			TranslationServer.set_locale(locale)
			assert_ne(tr(key), key, "немає перекладу %s для %s" % [key, locale])

func test_every_error_key_is_translated() -> void:
	var keys: Array[String] = [
		"ERR_NO_SUCH_UNIT", "ERR_NOT_YOUR_UNIT", "ERR_ALREADY_FIRED", "ERR_OFF_BOARD",
		"ERR_OUT_OF_RANGE", "ERR_NO_SUCH_TARGET", "ERR_FRIENDLY_FIRE", "ERR_NO_WEAPON",
		"ERR_NOT_ENOUGH_AP", "ERR_TARGET_NOT_VISIBLE", "ERR_NO_DRONES_LEFT",
		"ERR_DRONE_CANNOT_TARGET_INFANTRY", "ERR_NOT_AN_ENGINEER", "ERR_NOT_ADJACENT",
		"ERR_MINE_ALREADY_THERE", "ERR_TILE_OCCUPIED", "ERR_NO_MINE_THERE",
		"ERR_NO_BRIDGE_THERE", "ERR_NOTHING_TO_REPAIR", "ERR_NO_FRIENDLY_UNIT_THERE",
		"ERR_UNIT_UNDAMAGED", "ERR_NO_OBJECTIVE_THERE", "ERR_NOTHING_TO_CAPTURE",
		"ERR_MATCH_OVER",
	]
	for locale in ["uk", "en"]:
		TranslationServer.set_locale(locale)
		for key in keys:
			assert_ne(tr(key), key, "немає перекладу %s для %s" % [key, locale])
```

- [ ] **Step 2: Заповнити CSV, прогнати тест, коміт**

Цей тест — механізм, що не дає новому ключу помилки просочитися на екран у вигляді `ERR_SOMETHING`.

---

### Task 3.2: Головне меню

**Files:**
- Create: `game/ui/main_menu.tscn`, `game/ui/main_menu.gd`
- Create: `game/ui/theme/ap_theme.tres`
- Modify: `project.godot` (`run/main_scene`)

Пункти: **Продовжити** (активний лише за наявності збереження), **Новий матч**, **Налаштування**, **Про гру**, **Вийти** (тільки на Android/десктопі). Тло — статичний рендер бойової сцени, без анімації: батарея коштує дорожче, ніж вигляд.

- [ ] **Step 1: Тема `ap_theme.tres`: шрифти, кольори, мінімальний розмір кнопки 48 dp**
- [ ] **Step 2: Сцена й навігація через `SceneRouter`**
- [ ] **Step 3: `run/main_scene="res://game/ui/main_menu.tscn"`**
- [ ] **Step 4: Коміт**

---

### Task 3.3: Налаштування матчу

**Files:**
- Create: `game/ui/match_setup.tscn`, `game/ui/match_setup.gd`

Що обирається: кількість гравців (2 або 3), карта зі списку `maps/`, `ground_state`, кольори гравців, сід (за замовчуванням випадковий, з полем для ручного вводу — це те, що робить реплей відтворюваним).

Кнопка «Почати» викликає `MatchService.start_match(map.to_board(), players, seed)` і `SceneRouter.goto_battle()`.

- [ ] **Step 1: Сцена й привʼязка до `MapData`**
- [ ] **Step 2: Тест: обраний сід потрапляє в `state.seed_value`**
- [ ] **Step 3: Коміт**

---

### Task 3.4: `settings_service` і екран налаштувань

**Files:**
- Modify: `game/autoload/settings_service.gd`
- Create: `game/ui/settings_screen.tscn`, `game/ui/settings_screen.gd`

**Interfaces:**
- Produces: `SettingsService.locale: String`, `.music_volume: float`, `.sfx_volume: float`, `.quality: int`, `.save() -> void`, `.load() -> void` (файл `user://settings.cfg` через `ConfigFile`)

Мова застосовується миттєво через `TranslationServer.set_locale`. Якість — три пресети (низька/середня/висока), які керують тінями, частинками й роздільністю рендера; використовуються у Фазі 5.

- [ ] **Step 1: Реалізувати сервіс + тест на круговий обіг збереження**
- [ ] **Step 2: Екран, коміт**

---

### Task 3.5: Пауза, збереження й екран результату

**Files:**
- Create: `game/ui/pause_menu.tscn`, `game/ui/pause_menu.gd`
- Create: `game/ui/results_screen.tscn`, `game/ui/results_screen.gd`

Пауза: продовжити, зберегти й вийти, налаштування, здатися. Збереження — через `BattleSerializer.save_to("user://save.json")`; «Продовжити» в головному меню читає цей файл.

Екран результату: переможець, підсумок по гравцях (втрати, завдана шкода, утримані цілі, досягнуті рівні ветеранства), кнопки «Реванш» (той самий матч, новий сід) і «В меню».

Важливо: пауза не має показувати нічого, що належить неактивному гравцеві. Це той самий інваріант, що й гейт передачі.

- [ ] **Step 1: Пауза й збереження, тест на круговий обіг «зберегти → в меню → продовжити»**
- [ ] **Step 2: Екран результату, привʼязка до `Events.MatchEnded`**
- [ ] **Step 3: Коміт**

**Критерій завершення Фази 3:** гру можна запустити з нуля, налаштувати матч, зіграти, вийти в меню, повернутись і продовжити з того самого місця — жодного разу не торкнувшись коду.

---

# Фаза 4 — повний ростер на екрані

Фаза 1 вже містить усі правила. Ця фаза дає їм інтерфейс. Покроковий план пишеться на початку фази — коли існують `input_controller` і `hud`, від яких усе тут залежить.

| # | завдання | файли | критерій приймання |
| --- | --- | --- | --- |
| 4.1 | Усі 13 типів у `unit_view` | `game/battle/unit_view.gd`, `game/battle/unit_silhouettes.gd` | кожен клас розпізнається з висоти на 100 px; жоден силует не плутається з іншим на скріншоті в масштабі 1:1 |
| 4.2 | Панель дій інженера | `game/ui/engineer_panel.tscn` | сім верб із §3.8, кожна показує вартість AP і підсвічує допустимі сусідні тайли; недоступна дія сіра з підказкою-причиною з `validate()` |
| 4.3 | Ремонт із показом залишку AP | `game/ui/engineer_panel.gd` | перед підтвердженням видно діапазон лікування — це єдине місце, де невитрачені AP щось значать, і гравець має це бачити |
| 4.4 | Дронова дія | `game/ui/drone_button.gd` | окрема кнопка, а не режим стрільби; показує залишок дронів і радіус 5; ціль-піхота підсвічена як заборонена з причиною |
| 4.5 | Міни в інтерфейсі | `game/battle/mine_layer.gd` | свої міни видно завжди, розкриті чужі — окремою іконкою, нерозкриті не рендеряться взагалі й не мають жодного натяку в жодному шарі |
| 4.6 | Цілі та їхній стан | `game/battle/objective_view.gd` | значок власника, стан «зруйновано»; ціль зʼявляється лише коли `seen_by[active_player]` |
| 4.7 | Індикатор ветеранства | `game/ui/hud.gd` | рівень класу активного гравця видно в інспекторі, підвищення показується подією |
| 4.8 | Три гравці | `game/battle/battle_screen.gd` | усунутий гравець пропускається; гейт передачі називає правильного наступного; матч триває між двома, що лишились |
| 4.9 | Умова перемоги по цілях | `game/battle/battle_screen.gd` | «утримай N з M» перевіряється в кінці ходу, HUD показує лічильник для активного гравця |
| 4.10 | Комплект карт | `maps/*.tres` | не менше 5 карт: мостова, міська, відкрита, лісова, гірська; кожна грається на 2 і на 3 гравці |

---

# Фаза 5 — сетинг, ассети, атмосфера

### Task 5.0 — ворота фази: зафіксувати сетинг

**Це блокує всю решту фази і не обходиться.** §2 `CLAUDE.md` прямо каже: сетинг має бути зафіксований **до** початку генерації ассетів, бо він визначає кожен промпт моделі, кожен матеріал, світловий і звуковий бріф. Поки він відкритий, будь-яка згенерована модель — це ставка.

Результат завдання: розділ у `CLAUDE.md` з описом світу, епохи, палітри, матеріальної мови й звукової естетики, і перейменування ключів `UNIT_*` під цей світ одним комітом. Ролі юнітів при цьому не міняються — міняються лише назви.

| # | завдання | критерій приймання |
| --- | --- | --- |
| 5.1 | Пайплайн ассетів через скіл `asset-manager` | прочитано скіл, зафіксовано полібюджети, один тестовий GLB проходить від промпта до сцени |
| 5.2 | 13 моделей юнітів | силует читається з фіксованого кута; низи не моделюються (їх ніколи не видно); бюджет тримається |
| 5.3 | Набір тайлів терену | 10 видів із §Terrain.Kind, тайлінг без видимого шва |
| 5.4 | Матеріали й вологість | `roughness`+`normal` як параметр, керований контролером погоди |
| 5.5 | Запікання світла карт | статичне освітлення запечене, одне спрямоване джерело з тінями лише для юнітів |
| 5.6 | Час доби як пресет карти | 4 пресети, жоден **не торкається жодного числа** — це тільки світло |
| 5.7 | Погода | дощ, туман, сніг, хмарність: частинки + екранний оверлей + вітер у шейдері листя + звуковий шар |
| 5.8 | Сліди бою | уламки лишаються; стовп диму стоїть кілька ходів; вирви й колії накопичуються |
| 5.9 | Пост-обробка | LUT, легка віньєтка, мінімальне зерно. **Без SSAO і SSR** |
| 5.10 | Звук | шар оточення на карту, звуки пострілів на клас, UI, музика меню |
| 5.11 | Бюджет кадру | < 100 draw calls і < 150k трикутників на екрані на середньому телефоні; перевірено профайлером, число записано в `docs/` |

Погода й час доби **не змінюють жодного правила** (§3.12). Якщо в цій фазі зʼявився патч, що зменшує радіус огляду в тумані, — він відхиляється; таке правило в хот-ситі читається як шахрайство, бо гравець його не бачить.

---

# Фаза 6 — редактор карт

| # | завдання | файли | критерій приймання |
| --- | --- | --- | --- |
| 6.1 | Оболонка редактора | `tools/map_editor/editor_screen.tscn` | запускається з головного меню; та сама камера, що й у бою |
| 6.2 | Палітра тайлів і малювання | `tools/map_editor/tile_brush.gd` | малювання пензлем, заливка, гумка; скасування останніх 50 дій |
| 6.3 | Розстановка юнітів | `tools/map_editor/spawn_tool.gd` | вибір типу, гравця й фейсингу; заборона двох юнітів на тайлі |
| 6.4 | Цілі й умова перемоги | `tools/map_editor/objective_tool.gd` | до 15 маркерів (§3.10), поле «утримати N» |
| 6.5 | Стан ґрунту й пресет часу доби | `tools/map_editor/map_props.gd` | вибір із трьох станів, попередній перегляд освітлення |
| 6.6 | Збереження й завантаження | `tools/map_editor/map_io.gd` | запис `MapData` у `user://maps/`, читання назад без втрат — тест на круговий обіг |
| 6.7 | Валідація карти | `tools/map_editor/map_validator.gd` | не дає зберегти карту, де в гравця немає юнітів, старт заблоковано непрохідним тереном, або цілей більше за 15 |
| 6.8 | Тест-запуск із редактора | `tools/map_editor/editor_screen.gd` | кнопка «Зіграти» стартує матч на поточній карті без збереження |

---

# Фаза 7 — мобільні збірки й реліз

| # | завдання | критерій приймання |
| --- | --- | --- |
| 7.1 | Android-експорт | `export_presets.cfg`, keystore поза репозиторієм; APK збирається однією командою |
| 7.2 | iOS-експорт | пресет і підпис; збірка проходить на macOS-машині |
| 7.3 | Безпечні зони й вирізи | UI не заходить під виріз на пристрої 19.5:9; перевірено на реальному телефоні |
| 7.4 | Керування дотиком | пан двома пальцями, зум щипком, тап-цілі ≥ 48 dp; жодної дії від випадкового дотику |
| 7.5 | Енергоспоживання | `low_processor_mode` увімкнено; кадр падає, коли нічого не анімується; заміряно споживання за 30 хв гри |
| 7.6 | Фолбек `gl_compatibility` | гра запускається на пристрої без Vulkan із деградованими ефектами |
| 7.7 | Профіль продуктивності | 60 fps на середньому пристрої; результат записано в `docs/performance.md` |
| 7.8 | Відновлення після згортання | згортання під час ходу не втрачає стан; автозбереження при `NOTIFICATION_APPLICATION_PAUSED` |
| 7.9 | Прогін збірки | повний матч на 3 гравці на реальному пристрої, від меню до екрана результату |

---

## Порядок роботи

`CLAUDE.md` §7 задає режим Agent Team: підзадачі віддаються дочірнім агентам, головний контекст аналізує результати, інтегрує й ухвалює рішення. Для цього плану це означає:

- одне завдання = один дочірній агент, із власним тестовим циклом і критерієм приймання з блоку **Interfaces**;
- завдання Фази 1 йдуть **послідовно** — кожне наступне споживає типи попереднього;
- завдання Фази 4 і Фази 6 здебільшого незалежні й можуть іти паралельно в окремих гілках або worktree;
- продуктові й дизайнерські рішення (сетинг, баланс, назви) головний контекст не делегує.

Після кожного завдання: `./run_tests.sh` зелений, потім коміт. Після кожної фази — прогін гри на пристрої, а не лише тестів.

---

## Самоперевірка плану

Пройдено проти `CLAUDE.md` розділ за розділом.

**Покриття специфікації:**

| розділ CLAUDE.md | де реалізовано |
| --- | --- |
| §3.1 сітка, 4-напрямний рух, 8-напрямний фейсинг, евклідів радіус | 1.4 (`Board.DIRS_4/DIRS_8`), 1.7 (`Rules.in_radius`), 1.8 (тест на діагоналі) |
| §3.2 AP, вартість входу, дві зони | 1.5, 1.8 |
| §3.3 формула шкоди | 1.7, золоті тести |
| §3.4 напрямна броня | 1.6; показ сектора до підтвердження — 2.7, 2.8 |
| §3.5 огляд і туман, гейт передачі | 1.9, 2.9 |
| §3.6 класи й ростер, інваріант броні, порядок мобільності танків | 1.2 |
| §3.7 ветеранство | 1.11 |
| §3.8 верби інженера | 1.17; інтерфейс — 4.2, 4.3 |
| §3.9 дрон | 1.15; інтерфейс і показ боєзапасу — 4.4, 2.4 |
| §3.10 цілі й перемога | 1.17; інтерфейс — 4.6, 4.9 |
| §3.11 міни | 1.16; інтерфейс — 4.5 |
| §3.12 погода косметична, ґрунт — правило | 1.3 (ґрунт у вартості), 5.6–5.7 (косметика), 2.8 (іконка стану в HUD) |
| §5 стек | 1.1 |
| §6 архітектура, детермінізм, потік команд і подій | 1.5, 1.10, 1.12–1.17, 2.1, 2.6 |
| §7 режим Agent Team | «Порядок роботи» вище |
| §8 рендер і бюджет | 2.2–2.5, 5.5, 5.9, 5.11, 7.5–7.7 |
| §9 конвенції, локалізація, тести | Global Constraints, 3.1, тести в кожному завданні Фази 1 |

**Прогалини, свідомо залишені поза планом:** ШІ-опонент, кампанія, онлайн — §2 виносить їх за межі v1. Персистентні профілі ветеранства — §3.7 привʼязує їх до кампанії.

**Узгодженість типів:** `attack_range` (не `range`) скрізь; `unit_class` (не `class`); `Pathing.Zones.cost_to` повертає `-1` для недосяжного, і всі споживачі спершу питають `can_reach`; `validate()` всюди повертає `String` (порожній = дозволено); `apply()` всюди повертає `Array[Events.BattleEvent]`; `FireCommand._resolve_damage` — єдиний шлях нанесення шкоди, спільний для пострілу й дрона.

**Відкриті питання з §4, які план не закриває і не має закривати:** шкода танка по артилерії залишена ×1.0; форма зони огляду — евклідова. Обидва чекають плейтесту, а не рішення в коді.
