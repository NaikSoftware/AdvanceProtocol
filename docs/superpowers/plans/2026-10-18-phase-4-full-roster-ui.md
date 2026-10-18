# Фаза 4 — повний ростер на екрані: план реалізації

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** дати інтерфейс усім правилам, які `core/` уже вміє (інженер, дрон, міни, три гравці), на екрані, що коректно масштабується від малого телефона до ПК (без прив'язки до конкретного пристрою), і покрити кожну фічу e2e-сценарієм.

**Architecture:** кожен новий запит «що можна зробити / що показати» — статична функція в `core/` з юніт-тестом; вигляд (`game/`) лише малює її результат і подає `Command` крізь `InputController` → `MatchService.submit()`. Шар мін перебудовується **зі стану** для активного гравця, а не з потоку подій — потік не фільтрований по спостерігачу (§6, відомий борг). UI — контейнери + якорі, масштаб через `content_scale_factor`, порахований чистою функцією від розміру екрана й DPI.

**Tech Stack:** Godot 4.7.2, статично типізований GDScript, GUT headless.

**Spec:** розділ «Фаза 4 — повний ростер на екрані» і наскрізний розділ «Стиль, респонсивність і воркфлоу арту» в `docs/superpowers/plans/2026-08-09-advance-protocol-implementation.md`; `CLAUDE.md` §3 (особливо §3.8, §3.9, §3.11, §3.13), §6, §9; `docs/ui/overlays.md`; `docs/rules/{units,vision-and-fog}.md`.

## Global Constraints

- Ростер — **12** типів (id 0–11), єдиний `ENGINEER` — інженерна машина (id 11, `fire_cost` 30, `max_ap` 76). Інженерного відділення немає (рішення власника 2026-10-17).
- `core/` не імпортує вузли Godot; коментарі в `core/` — українською; типізований GDScript скрізь.
- Вигляд нічого не рахує: дозволені цілі, тайли, межі ремонту, позначки дрона — лише з функцій `core/` (§3.13).
- Прихована інформація: нерозкрита ворожа міна не має **жодного** вузла, контура чи відмінності в зонах; нічого неактивного гравця не переживає гейт.
- Кожен новий рядок для показу — ключ у `assets/i18n/strings.csv` (`keys,uk,en`) і в списку `tests/game/test_localisation.gd`.
- Жодної нової механіки. Неврегульоване — у розділ «Відкриті питання», не в код.
- **Нічого не хардкодиться під конкретний пристрій.** Масштаб — загальна формула від розміру екрана й DPI; розкладка — контейнери, що тягнуться під будь-яке співвідношення сторін. Google Pixel 10 Pro XL (2992×1344 @ 486 ppi → ≈ 985×442 логічних, 1 логічний px ≈ 1 dp) — лише **орієнтир** і один із тестових прикладів, не ціль, під яку підганяються числа.
- Розміри приймання для кожного UI-завдання (логічні px ≈ dp): **PHONE_SMALL 800×360** (найменший поширений Android-лендскейп — найжорсткіша перевірка), **PHONE_LARGE 985×442** (орієнтир Pixel 10 Pro XL), **PC 1280×720**, **TABLET 1280×800** (2560×1600 @ 276 ppi). Додатково **WIDE 1600×720** (вікно 2400×1080 @ 96 dpi) — лише для перевірки `max_width`. Тести ітерують по `LayoutProbe.SIZES`, а не по окремих константах.
- Тап-цілі ≥ 48 логічних px (після Task 1 це ≥ 48 dp на телефоні й не менше на ПК/планшеті).
- Розкладка: якорі + `MarginContainer`/`VBox`/`HBox`/`GridContainer`/`CenterContainer`; жодних абсолютних координат, крім уже наявного `Hud._reposition_inspector()`; поля `SafeArea` як у `game/ui/hud.tscn`.
- Кожна фіча гравця — e2e у `tests/e2e/`: headless GUT, справжні події вводу (`click_at`) і кнопки HUD, перевірки на `MatchService.state` з golden-числами. Жодних віконних драйверів у `tools/`.
- Тести: `GODOT=$HOME/.local/bin/godot ./run_tests.sh` (сам робить `--import`; у свіжому worktree перед першим запуском окремо `$GODOT --headless --path . --import`). Один файл: `./run_tests.sh -gselect=<file>.gd`.
- **Перевірка кількості скриптів обов'язкова** (GUT мовчки пропускає файл, що не парситься): число в рядку `Scripts` звіту дорівнює `find tests -name 'test_*.gd' | wc -l`.

## Review Focus

1. **Малий телефон 800×360 (і 985×442) з усім HUD одночасно** (вибраний інженер: панель верб + інспектор + нижній рядок) — нічого не виходить за `Viewport`, панелі не перекриваються, дошці лишається смуга ≥ 50 % висоти. Тест — Task 13 `test_full_hud_fits_every_size`.
2. **Нерозкрита ворожа міна в маршруті** — зони й контур шляху побудовані так, ніби міни немає, і `MineLayer` не має для неї вузла. Тест — Task 5 `test_unrevealed_enemy_mine_leaves_no_trace_in_any_layer`.
3. **Міна, відкрита гравцем A, після гейта гравця B** — шар перебудовується під B до зняття гейта. Тест — Task 5 `test_own_mine_hidden_after_handover`.
4. **Зміна мови посеред ходу** з відкритою панеллю інженера / кнопкою дрона — підписи й текст причини перекладаються (той самий `NOTIFICATION_TRANSLATION_CHANGED`, що в `hud.gd:107`). Тест — Task 8 `test_engineer_panel_relabels_on_locale_change`.
5. **Карта на 3 гравці, обрана для 2** — спавни гравця 2 не ламають матч. Тест — Task 12 `test_three_player_map_runs_with_two_players`.

---

## Аналіз прогалин (стан коду на 2026-10-18)

| # | що вже є | чого немає |
| --- | --- | --- |
| 4.1 | силует на **клас**: `_HULL_SIZES` + ствол/смуга, `game/battle/unit_view.gd:65,334-360` | розрізнення 12 **типів**: 4 танки, 3 легкі машини, 2 загони, 2 гармати виглядають однаково |
| 4.2 | `EngineerCommand` з усіма вербами й причинами відмови, `core/commands/engineer_command.gd:5,28-78` | запит «допустимі тайли / причина» в `core/`; режим інженера в `InputController` (`ActionType` лише `MOVE, SHOT`, `input_controller.gd:36`); панель; оновлення дошки на `BridgeChanged` (no-op, `event_player.gd:265`) |
| 4.3 | формула `repair_amount()`, `engineer_command.gd:20-22` | аналітичні межі ремонту без кидка; показ у прев'ю |
| 4.4 | `DroneCommand` + `check_strike()` (`drone_command.gd:19`), `Targeting.drone_targets()` (`targeting.gd:64`), значок на юніті `unit_view.gd:320`, рядок `DronesRow` у HUD `hud.gd:242` | кнопка дії, режим дрона в контролері, кільце радіуса 5, позначки «заборонено» з причиною; ворожі тайли кільця з `seen` (немає жодної функції, що повертає тайли обвідної) |
| 4.5 | `Mines` з `known_to[]`, `core/mines.gd`; події `Mine*` | будь-який візуал: усі обробники — no-op, `event_player.gd:245-260` |
| 4.8 | пропуск вибулого `battle_state.gd:211`, повернення AP відповідачам `:220`, гейт `handover_gate.gd:81`, вибір 3 гравців `match_setup.gd:62` | лише e2e на 3 гравців (`_boot` у `test_battle_e2e.gd:72` жорстко передає 2) |
| 4.10 | одна карта `maps/skirmish_bridge.tres` (16×12, 2 гравці) | 4 карти; `MapData.populate()` додає спавн власника ≥ `player_count` і ламає матч на 2 — латентний баг (`core/map_data.gd:45-53`) |
| масштаб | `canvas_items` + `expand`, база 1280×720 (`project.godot:26-29`) | на Pixel 10 Pro XL масштаб 1344/720 = 1.867, логічний екран ≈ 1603×720, 48 логічних px ≈ 4.7 мм проти 48 dp = 7.6 мм — **у 1.63 раза замало**. Потрібна Task 1 |

**Арифметика масштабу (фіксується тестом Task 1).** `stretch = min(w/1280, h/720)`, `dp = dpi/160`. Шуканий `content_scale_factor = max(1.0, dp / stretch)`.

| екран | stretch | dp | factor | логічний Viewport |
| --- | --- | --- | --- | --- |
| Pixel 10 Pro XL 2992×1344 @ 486 | 1.8667 | 3.0375 | **1.627** | **985×442** |
| ПК 1920×1080 @ 96 | 1.5 | 0.6 | 1.0 | 1280×720 |
| планшет 2560×1600 @ 276 | 2.0 | 1.725 | 1.0 | 1280×800 |
| вікно 2400×1080 @ 96 | 1.5 | 0.6 | 1.0 | 1600×720 |
| емуляція Pixel на ПК: вікно 1496×672 з `--ui-dpi=243` | 0.9333 | 1.519 | 1.627 | 985×442 |

## Порядок і паралельність

```
T1 масштаб+розкладка ─┐
T2 e2e-каркас ────────┼─► T5 міни
T3 силуети (4.1)      │
T4a core: інженер ────┼─► T8 панель інженера (4.2) ─► T9 ремонт (4.3)
T4b core: дрон/обвідна┼─► T10 дрон (4.4) ─► T14 кільце й загрози (§3.13)
                      └─► T12 три гравці + карти (4.8, 4.10)
                              T8,T9,T10,T14 ─► T13 повний HUD на всіх розмірах
```

- **Паралельно з нуля, окремими worktree:** T1, T2, T3 (core-завдання не чіпають `game/`).
- Після T1+T2: T5, T12 — паралельно. T8 чекає T4a і T5 (верби міни перевіряються на шарі). T10 чекає T4b і T8. T14 чекає T10. T15 іде після T8. T13 — останнім.
- `hud.tscn`/`hud.gd` змінюють T1, T8, T10, T14 — у паралельних гілках очікувати конфлікту злиття саме там; зливати по одній.

---

### Task 1: Масштаб UI під dp і перевірка розкладки на трьох розмірах

**Files:**
- Create: `game/ui/ui_scale.gd` (`class_name UiScale`)
- Modify: `game/autoload/scene_router.gd` (застосування в `_ready()`)
- Create: `tests/game/layout_probe.gd` (без префікса `test_` — помічник)
- Test: `tests/game/test_ui_scale.gd`, `tests/game/test_layout_screens.gd`
- Modify за результатом перевірки: `game/ui/hud.tscn`, інші `game/ui/*.tscn`, що не влізуть у 985×442

**Interfaces:**
- Produces:
  - `UiScale.BASE := Vector2i(1280, 720)`
  - `static func factor(screen_px: Vector2i, dpi: float) -> float` — `max(1.0, (dpi/160) / min(w/1280, h/720))`
  - `static func dpi_override(args: PackedStringArray) -> float` — значення `--ui-dpi=N` з `OS.get_cmdline_user_args()`, інакше `-1.0`
  - `static func apply(window: Window) -> void` — DPI = override або `DisplayServer.screen_get_dpi()`; ставить `window.content_scale_factor`; перераховує на `window.size_changed`
  - `LayoutProbe.PHONE_SMALL := Vector2i(800, 360)`, `PHONE_LARGE := Vector2i(985, 442)`, `PC := Vector2i(1280, 720)`, `TABLET := Vector2i(1280, 800)`, `WIDE := Vector2i(1600, 720)`; `SIZES := [PHONE_SMALL, PHONE_LARGE, PC, TABLET]`
  - `static func mount(test: GutTest, scene: PackedScene, size: Vector2i) -> Control` — інстанціює сцену всередині `SubViewport` заданого розміру, чекає два кадри розкладки, повертає корінь
  - `static func overflowing(root: Control, size: Vector2i) -> Array[String]` — імена видимих `Control`, чий `get_global_rect()` виходить за `Rect2(Vector2.ZERO, size)`
  - `static func small_targets(root: Control, min_px: float = 48.0) -> Array[String]` — видимі `BaseButton` з `size.x` або `size.y` < `min_px`
  - `static func overlapping(controls: Array[Control]) -> Array[String]` — пари видимих, чиї прямокутники перетинаються

- [ ] **Step 1: Тест чистої функції**

```gdscript
func test_large_phone_gets_dp_factor() -> void:   # приклад: Pixel 10 Pro XL
	assert_almost_eq(UiScale.factor(Vector2i(2992, 1344), 486.0), 1.627, 0.005)
func test_desktop_1080p_keeps_current_look() -> void:
	assert_eq(UiScale.factor(Vector2i(1920, 1080), 96.0), 1.0)
func test_tablet_2560x1600_is_not_shrunk() -> void:
	assert_eq(UiScale.factor(Vector2i(2560, 1600), 276.0), 1.0)
func test_logical_height_is_dp_on_any_phone() -> void:   # 2400×1080 @ 480 → 360 dp; Pixel → 442 dp; 1600×720 @ 320 → 360 dp
	for c in [[Vector2i(2400, 1080), 480.0], [Vector2i(2992, 1344), 486.0], [Vector2i(1600, 720), 320.0]]:
		var f := UiScale.factor(c[0], c[1])
		var logical_h := 720.0 / f
		assert_almost_eq(logical_h, c[0].y / (c[1] / 160.0), 1.0)
func test_half_size_pixel_emulation_matches_pixel() -> void:
	assert_almost_eq(UiScale.factor(Vector2i(1496, 672), 243.0), UiScale.factor(Vector2i(2992, 1344), 486.0), 0.001)
func test_zero_dpi_falls_back_to_one() -> void:   # headless повертає 96 або 0 — не ділити на нуль
	assert_eq(UiScale.factor(Vector2i(1280, 720), 0.0), 1.0)
func test_dpi_override_parsed_from_user_args() -> void:
	assert_eq(UiScale.dpi_override(PackedStringArray(["--ui-dpi=486"])), 486.0)
	assert_eq(UiScale.dpi_override(PackedStringArray()), -1.0)
```

- [ ] **Step 2:** `./run_tests.sh -gselect=test_ui_scale.gd` — FAIL (`UiScale` не існує).
- [ ] **Step 3:** Реалізувати `UiScale`; викликати `UiScale.apply(get_tree().root)` у `SceneRouter._ready()`. DPI — `DisplayServer.screen_get_dpi()`; `screen_get_scale()` на Android не використовувати (у Godot 4 він підтримується лише на macOS/iOS/Wayland/Web). Факт DPI на пристрої звіряється у Фазі 7.3. Там само `_drag_threshold_px()` (`battle_screen.gd:634`) повертає 10 логічних px без ділення на `content_scale_factor` (відкрите питання 4).
- [ ] **Step 4:** Тест PASS. Ручна перевірка емуляції на ПК: `$GODOT --path . --resolution 1496x672 -- --ui-dpi=243` — у консолі `get_viewport().get_visible_rect().size` (тимчасовий `print` в `UiScale.apply`, прибрати перед комітом) ≈ `(985, 442)`. Якщо Godot дає інший логічний розмір — зупинитись і повідомити: уся решта плану спирається на те, що логічний px ≈ dp.
- [ ] **Step 5: Тест розкладки наявних екранів**

```gdscript
# test_layout_screens.gd — один параметризований тест на сцену × розмір
const SCREENS := ["res://game/ui/hud.tscn", "res://game/ui/main_menu.tscn", "res://game/ui/match_setup.tscn",
	"res://game/ui/settings_screen.tscn", "res://game/ui/pause_menu.tscn", "res://game/ui/results_screen.tscn",
	"res://game/ui/handover_gate.tscn"]
func test_screens_fit_phone_pc_tablet(p = use_parameters(_cases())) -> void:
	var root := await LayoutProbe.mount(self, load(p[0]), p[1])
	assert_eq(LayoutProbe.overflowing(root, p[1]), [] as Array[String])
	assert_eq(LayoutProbe.small_targets(root), [] as Array[String])
func test_hud_bars_do_not_overlap_on_phone() -> void:
	# TopBar, BottomBar з hud.tscn
	assert_eq(LayoutProbe.overlapping([top_bar, bottom_bar]), [] as Array[String])
func test_menu_content_capped_on_wide() -> void:
	# головний контейнер меню на WIDE не ширший за свій max_width
```

`pause_menu`/`results_screen`/`hud` для показу вмісту потребують прив'язки до стану — у тесті дати їм мінімальний `BattleState` (той самий прийом, що в `tests/game/test_hud.gd:41`).
- [ ] **Step 6:** Запустити — очікувано FAIL на PHONE_SMALL/PHONE_LARGE щонайменше для `hud.tscn` (три кнопки по 160 + прев'ю в один `HBox` не влазять у 985 − 2·56). Виправити розкладку контейнерами: прев'ю пострілу/руху — окремим рядком над кнопками або `HFlowContainer`; кнопки — `size_flags`, мінімум 48×48, без фіксованої ширини 160. Жодних абсолютних координат.
- [ ] **Step 7:** Повний прогін `./run_tests.sh` зелений, `Scripts` = кількість `test_*.gd`.
- [ ] **Step 8: Коміт** `feat(ui): масштаб під dp від DPI екрана й перевірка розкладки на телефонах, ПК і планшеті`

---

### Task 2: Спільний бойовий e2e-каркас

**Files:**
- Modify: `tests/e2e/e2e_helpers.gd`
- Modify: `tests/e2e/test_battle_e2e.gd` (перейти на каркас; поведінка тестів не змінюється)

**Interfaces:**
- Consumes: наявні `_boot/_settle/_tap/_confirm/_end_turn/_confirm_gate/_act/_events_of` з `test_battle_e2e.gd:58-160`, `RecService` (`:35`)
- Produces (у `e2e_helpers.gd`):
  - `class RecService` (перенесений)
  - `func boot(width: int, height: int, spawns: Array, opts: Dictionary = {}) -> BattleScreen` — ключі `opts`: `tiles: Dictionary`, `ground: int`, `seed: int` (типово 7), `players: int` (типово 2), `prepare: Callable(state: BattleState)` — викликається після `setup()` до першого показу (покласти міну, зменшити HP), після нього — `_screen._rebuild_units_for_active_player()` і перебудова шарів
  - `func tap(cell: Vector2i)`, `func press(button: BaseButton)`, `func confirm()`, `func end_turn()`, `func confirm_gate()`, `func act(from, to)`, `func hud() -> Hud`, `func gate() -> HandoverGate`, `func events_of(cls) -> Array[Events.BattleEvent]`, властивості `service`, `screen`
  - `click_at(p: Vector2, vp: Viewport = null)` — необов'язковий viewport для сцен у `SubViewport` (Task 13)

- [ ] **Step 1:** Перенести каркас; `test_battle_e2e.gd` викликає його. Виправити коментар у шапці (`:10`) — «дронів і мін немає, бо UI немає» стає неправдою після T5/T10, тепер він посилається на `test_engineer_e2e.gd`/`test_drone_e2e.gd`.
- [ ] **Step 2:** `./run_tests.sh -gselect=test_battle_e2e.gd` — та сама кількість тестів, усі PASS (рефакторинг тесту без зміни очікувань).
- [ ] **Step 3: Коміт** `test(e2e): спільний каркас бою з гравцями й підготовкою стану`

---

### Task 3: Силует на кожен із 12 типів (4.1)

**Files:**
- Create: `game/battle/unit_silhouettes.gd` (`class_name UnitSilhouettes`, дані + побудова)
- Modify: `game/battle/unit_view.gd:65-71,334-360` (`_HULL_SIZES` і гілки `match` переїжджають сюди)
- Test: `tests/game/test_unit_view.gd`

**Interfaces:**
- Produces: `static func spec(type_id: int) -> Dictionary` — `{hull: Vector3, barrel: float (0 — без ствола), extras: Array[StringName]}`; `extras` із набору `&"stripe"` (інженер), `&"drone_rack"` (штурмовий загін), `&"wheels"` (колісна легка техніка), `&"turret"` (танки), `&"spade"` (польова гармата), `&"tall_barrel"` (гаубиця); `static func build(type_id: int, owner_color: Color) -> Node3D`

Тимчасові примітиви до асетів Фази 5.2 — мінімум, що відрізняє типи з висоти; ціна — кількість мешів (§8: ≤ 4 меші на юніт).

- [ ] **Step 1: Тест**

```gdscript
func test_every_type_has_a_distinct_silhouette() -> void:
	var seen := {}
	for id in UnitTypes.count():   # 12
		var key := var_to_str(UnitSilhouettes.spec(id))
		assert_false(seen.has(key), "тип %d повторює силует типу %s" % [id, seen.get(key)])
		seen[key] = id
func test_heavier_tank_has_larger_hull_footprint() -> void:   # light 7 < medium 5 < heavy 8 за x*z
func test_silhouette_stays_within_four_meshes() -> void:      # для кожного типу
func test_silhouette_fits_one_tile() -> void:                 # AABB x,z <= 1.0, низ y >= 0
```

- [ ] **Step 2:** FAIL → реалізувати → PASS.
- [ ] **Step 3:** Візуальна перевірка: `tools/ui_shot` зі сценою на 12 юнітів у ряд, скріншот у фіксованому ракурсі; жодні два не однакові на 100 px. Скріншот — у PR, не в репозиторій.
- [ ] **Step 4: Коміт** `feat(battle): силует-заступник на кожен із 12 типів`

---

### Task 4a: Запити інженера в `core/`

**Files:**
- Modify: `core/commands/engineer_command.gd`
- Test: `tests/core/test_engineer_command.gd`

**Interfaces:**
- Produces:
  - `static func action_status(state: BattleState, unit_id: int, action: int) -> Dictionary` — `{"tiles": Array[Vector2i], "reason": String}`. Перебирає `Board.DIRS_4` у їхньому порядку, для кожного сусіда в межах дошки — `create(unit_id, action, p).validate(state)`. `tiles` — де `""`; `reason` — `""`, якщо `tiles` не порожні, інакше причина **першого** сусіда в порядку `DIRS_4` (причини рівня юніта — AP, `has_fired`, чужий хід — однакові для всіх сусідів, тож випадають природно)
  - `static func repair_bounds(engineer: Unit, target: Unit) -> Vector2i` — `x = mini(20, missing)`, `y = mini((40 + maxi(0, engineer.ap - engineer.fire_cost())) / 2, missing)`, де `missing = target.max_hp() - target.hp`; без RNG

- [ ] **Step 1: Тести**

```gdscript
func test_lay_mine_status_lists_free_adjacent_tiles_only() -> void   # 4 сусіди, один зайнятий → 3 тайли
func test_status_reason_when_no_ap() -> void                        # ap 20 < 30 → reason "ERR_NOT_ENOUGH_AP", tiles []
func test_clear_mine_reason_without_mine() -> void                  # "ERR_NO_MINE_THERE"
func test_demolish_bridge_forbidden_with_own_unit_on_it() -> void   # "ERR_TILE_OCCUPIED"
func test_status_never_changes_state_or_rng() -> void               # серіалізований стан і rng.state до/після рівні
func test_status_matches_validate_for_every_action_and_tile() -> void  # 5 дій × 4 сусіди: has(p) == (validate == "")
func test_repair_bounds_full_ap() -> void:
	# інженер ap 76, ціль 400/200 → (20, 43)
	assert_eq(EngineerCommand.repair_bounds(e, t), Vector2i(20, 43))
func test_repair_bounds_after_one_field_step() -> void   # ap 51 → (20, 30)
func test_repair_bounds_capped_by_missing_hp() -> void   # бракує 12 HP → (12, 12)
func test_repair_bounds_bracket_actual_roll() -> void    # 200 сідів: repair_amount ∈ [x, y] до кепу
```

- [ ] **Step 2:** FAIL → реалізувати → PASS (повний прогін, `Scripts` звірено).
- [ ] **Step 3: Коміт** `feat(core): допустимі тайли й межі ремонту для панелі інженера`

---

### Task 4b: Запити дрона й обвідної в `core/`

**Files:**
- Modify: `core/targeting.gd`, `core/rules.gd`
- Test: `tests/core/test_targeting.gd`, `tests/core/test_rules_damage.gd`

**Interfaces:**
- Produces:
  - `Rules.drone_damage_bounds() -> Vector2i` — `(120, 180)`; `drone_damage()` використовує ті самі константи
  - `Targeting.reach_tiles(state: BattleState, unit_id: int, radius: int) -> Array[Vector2i]` — тайли кола `in_radius(u.pos, p, radius)` у межах дошки, перетнуті з `state.vision[state.active_player].is_seen(p)`; порожньо, якщо юніт не видимий активному гравцеві (`seen` під ним). Це обвідна з `docs/ui/overlays.md` («коло ∩ seen спостерігача»), спільна для своїх і чужих
  - `Targeting.drone_marks(state: BattleState, unit_id: int) -> Dictionary` — `{target_id: String}` для кожного живого ворожого юніта на `seen`-тайлі активного гравця всередині `DroneCommand.RANGE`; значення — `DroneCommand.check_strike()` (`""` = можна бити). Лише для свого загону; для чужого — `{}`

- [ ] **Step 1: Тести**

```gdscript
func test_drone_bounds_match_roll_range() -> void          # 500 кидків ∈ [120, 180], обидві межі досягнуті
func test_reach_tiles_radius_5_on_open_board() -> void     # усе розвідано: 81 тайл (dx²+dy² <= 25)
func test_reach_tiles_clipped_by_seen() -> void            # нерозвідана смуга не входить
func test_reach_tiles_empty_for_unseen_enemy() -> void
func test_reach_tiles_ignores_owner_network_of_enemy() -> void  # для ворога — seen АКТИВНОГО, не його
func test_drone_marks_flag_infantry_with_reason() -> void  # піхота → "ERR_DRONE_CANNOT_TARGET_INFANTRY", танк → ""
func test_drone_marks_agree_with_drone_targets() -> void   # ключі з "" == Targeting.drone_targets()
func test_drone_marks_empty_without_drones() -> void       # усі значення "ERR_NO_DRONES_LEFT"
func test_queries_do_not_touch_state() -> void
```

- [ ] **Step 2:** FAIL → реалізувати → PASS.
- [ ] **Step 3: Коміт** `feat(core): тайли обвідної й позначки дрона для оверлея`

---

### Task 5: Міни на дошці (4.5)

**Files:**
- Create: `game/battle/mine_layer.gd` (`class_name MineLayer extends Node3D`)
- Modify: `game/battle/battle_screen.tscn` (вузол `%MineLayer` під дошкою), `game/battle/battle_screen.gd` (перебудова поряд із `_rebuild_units_for_active_player()` — на `_on_gate_confirmed`, після пакета подій, у `setup`/`resume`)
- Test: `tests/game/test_mine_layer.gd`, `tests/e2e/test_mines_e2e.gd`

**Interfaces:**
- Consumes: `Mines.Mine.known_to`, `state.mines`; каркас T2
- Produces: `func rebuild(state: BattleState, observer: int) -> void` — один маркер на міну з `m.owner == observer` (стиль `OWN`) або `m.known_to[observer]` (стиль `ENEMY_REVEALED`); `func marker_count() -> int`; `func marker_at(p: Vector2i) -> Node3D` (null — немає). Нічого не читає з потоку подій.

- [ ] **Step 1: Модульні тести шару**

```gdscript
func test_own_mines_always_drawn() -> void
func test_revealed_enemy_mine_has_enemy_style() -> void
func test_unrevealed_enemy_mine_has_no_node() -> void     # marker_count() == 0, get_child_count() == 0
func test_rebuild_replaces_not_accumulates() -> void
```

- [ ] **Step 2: e2e (`test_mines_e2e.gd`)**

```gdscript
func test_engineer_lays_mine_and_it_shows_for_owner() -> void
	# інженер (11) P0 на (2,1); тап по ньому, кнопка «Покласти міну» (T8), тап (3,1), Confirm
	# state.mines.size() == 1, AP інженера 0, MineLayer.marker_at((3,1)) != null
	# (до T8 — подати EngineerCommand через prepare; після T8 замінити на кнопки)
func test_own_mine_hidden_after_handover() -> void       # end_turn, confirm_gate → marker_count() == 0
func test_unrevealed_enemy_mine_leaves_no_trace_in_any_layer() -> void
	# P1 бачить свій броньовик; знімок contour_segments(LAYER_ZONES) з міною == без міни
	# (той самий бут без prepare); MineLayer.marker_count() == 0
func test_driving_onto_mine_detonates_on_entry() -> void
	# P1 броньовик іде крізь (3,1) далі; зупинка НА (3,1), events_of(MineTriggered).size() == 1,
	# hp ∈ [250-180, 250-90], міна зникла з state.mines; точне HP — golden для сіда 7
func test_engineer_reveals_enemy_mine_in_its_diamond() -> void
	# інженер P1 у межах ромба 3 → після confirm_gate marker_at((3,1)) зі стилем ENEMY_REVEALED
```

- [ ] **Step 3:** FAIL → реалізувати → PASS; повний прогін, `Scripts` звірено.
- [ ] **Step 4: Коміт** `feat(battle): шар мін для активного гравця`

---

### Task 7: Систему досвіду видалено (замість 4.7)

Рішення власника 2026-10-18; виконано, деталі — в історії git.

---

### Task 8: Панель дій інженера (4.2)

**Files:**
- Create: `game/ui/engineer_panel.tscn`, `game/ui/engineer_panel.gd` (`class_name EngineerPanel extends PanelContainer`)
- Create: `game/battle/target_overlay.gd` (`class_name TargetOverlay` — контур довільного набору тайлів; спільний з T10)
- Modify: `game/battle/input_controller.gd`, `game/battle/board_view.gd` (шар `LAYER_TARGETS`), `game/battle/event_player.gd:265` (`BridgeChanged` → перебудова дошки), `game/battle/battle_screen.gd`, `game/ui/hud.tscn`, `game/ui/hud.gd`
- Modify: `assets/i18n/strings.csv` — `eng_lay_mine`, `eng_clear_mine`, `eng_repair_bridge`, `eng_demolish_bridge`, `eng_repair_unit`, `eng_ap_cost` («%d AP»)
- Test: `tests/game/test_input_controller.gd`, `tests/game/test_engineer_panel.gd`, `tests/e2e/test_engineer_e2e.gd`

**Interfaces:**
- Consumes: `EngineerCommand.action_status()` (T4a), `MineLayer.rebuild`, каркас T2, `LayoutProbe` (T1)
- Produces:
  - `InputController.ActionType` += `ENGINEER`, `DRONE` (останній — для T10)
  - `InputController.arm_engineer(action: int) -> void` — для вибраного свого інженера: якщо `action_status.tiles` порожні — сигнал `action_refused(reason: String)` і нічого не озброєно; інакше сигнал `targets_changed(tiles: Array[Vector2i])`
  - `InputController.disarm() -> void` (і неявно на `select_unit`, `_deselect`, після підтвердження) → `targets_changed([])`
  - у режимі ENGINEER `tap_cell(c)` для `c` з `tiles` → прев'ю `{type: ENGINEER, unit_id, action, target}`; інший тап по своєму юніту — вибір (знімає режим); решта — no-op
  - `_build_command` → `EngineerCommand.create(unit_id, action, target)`
  - `EngineerPanel.show_for(state: BattleState, unit: Unit) -> void`, сигнал `action_chosen(action: int)`; `func button_for(action: int) -> Button`
  - `TargetOverlay.show_tiles(tiles: Array[Vector2i]) -> void`, `clear() -> void` (ребра — та сама логіка, що `ZoneOverlay._edges`, викликати її, не копіювати)

Поведінка панелі: п'ять кнопок завжди (порядок `EngineerCommand.Action`), на кожній назва і `fire_cost` («30 AP»). Недоступна — сірий стиль теми (`theme_type_variation`), але **не `disabled`**: тап по ній показує `tr(reason)` у рядку причини панелі (на телефоні немає наведення для підказки). Розкладка — `GridContainer` на 2 колонки праворуч у `Middle` HUD; на жодному з `SIZES` не перекриває `TopBar`/`BottomBar`; на PHONE_SMALL сітка може згортатися (`HFlowContainer`/прокрутка), але кнопки лишаються ≥ 48.

- [ ] **Step 1: Тести контролера**

```gdscript
func test_arm_engineer_emits_valid_tiles() -> void
func test_arm_engineer_without_tiles_refuses_with_reason() -> void   # "ERR_NOT_ENOUGH_AP"
func test_tap_on_valid_tile_sets_engineer_preview() -> void
func test_tap_outside_tiles_is_noop_in_engineer_mode() -> void
func test_selecting_another_unit_disarms() -> void
func test_targets_cleared_after_confirm() -> void
```

- [ ] **Step 2: Тести панелі** — `test_five_buttons_with_ap_cost`, `test_unavailable_button_shows_reason_on_press`, `test_engineer_panel_relabels_on_locale_change`, `test_panel_fits_phone_without_overlapping_bars` (`LayoutProbe.mount(hud.tscn, size)` для кожного з `SIZES`, вибраний інженер; `overflowing == []`, `small_targets == []`, `overlapping([TopBar, BottomBar, EngineerPanel]) == []`).
- [ ] **Step 3: e2e (`test_engineer_e2e.gd`) — кожна з п'яти верб через кнопки**

```gdscript
func test_lay_and_clear_mine() -> void          # state.mines.size() 1 → (наступний хід) 0; AP 0 після кожної
func test_demolish_bridge_with_enemy_on_it() -> void
	# міст (Terrain.BRIDGE) з ворожим загоном: kind_at == BRIDGE_DESTROYED, ворог мертвий,
	# damage_dealt[0] == 100, BoardView показує зруйнований міст (вид інстансу тайла)
func test_demolish_refused_with_own_unit_on_bridge() -> void   # рядок причини == tr("ERR_TILE_OCCUPIED"), state не змінився
func test_repair_bridge() -> void               # BRIDGE_DESTROYED → BRIDGE
func test_repair_unit_heals_within_bounds() -> void  # див. T9 — тут лише факт UnitRepaired і hp зросло
func test_engineer_buttons_hidden_for_non_engineer() -> void
```

- [ ] **Step 4:** FAIL → реалізувати → PASS; повний прогін, `Scripts` звірено.
- [ ] **Step 5: Коміт** `feat(ui): панель верб інженера з допустимими тайлами й причинами`

---

### Task 9: Прев'ю ремонту з межами (4.3)

**Files:**
- Modify: `game/battle/input_controller.gd` (прев'ю `REPAIR_UNIT` несе `heal_min`, `heal_max`), `game/ui/hud.gd`, `game/ui/hud.tscn` (`PreviewRepairBox`)
- Modify: `assets/i18n/strings.csv` — `hud_heal`
- Test: `tests/game/test_hud.gd`, `tests/e2e/test_engineer_e2e.gd`

**Interfaces:**
- Consumes: `EngineerCommand.repair_bounds()` (T4a), режим ENGINEER (T8)
- Produces: прев'ю `{type: ENGINEER, unit_id, action: REPAIR_UNIT, target, heal_min: int, heal_max: int}`; HUD показує «20–43» без перерахунку

- [ ] **Step 1: e2e**

```gdscript
func test_repair_preview_full_ap_shows_20_to_43() -> void
	# prepare: свій танк hp 300/400 поряд з інженером; кнопка «Ремонт», тап по танку
	# PreviewRepairBox видимий, текст "20–43"; Confirm → hp ∈ [320, 343]; точне — golden для сіда 7
func test_repair_preview_after_one_field_step_shows_20_to_30() -> void
func test_repair_preview_capped_by_missing_hp() -> void    # hp 388/400 → "12–12"
```

- [ ] **Step 2:** FAIL → реалізувати → PASS; `LayoutProbe` по `SIZES` з видимим `PreviewRepairBox` — без виходу за межі.
- [ ] **Step 3: Коміт** `feat(ui): межі ремонту видно до підтвердження`

---

### Task 10: Дія дрона (4.4)

**Files:**
- Create: `game/ui/drone_button.gd` (`class_name DroneButton extends Button`), вузол у `game/ui/hud.tscn`
- Modify: `game/battle/input_controller.gd` (режим DRONE), `game/battle/unit_view.gd` (`set_forbidden(on: bool)`), `game/battle/battle_screen.gd` (кільце через `TargetOverlay` з T8, позначки на `UnitView`)
- Modify: `assets/i18n/strings.csv` — `hud_drone_strike` («Дрон (%d)» / «Drone (%d)»), `hud_drone_range`
- Test: `tests/game/test_input_controller.gd`, `tests/game/test_unit_view.gd`, `tests/e2e/test_drone_e2e.gd`

**Interfaces:**
- Consumes: `Targeting.reach_tiles(state, id, DroneCommand.RANGE)`, `Targeting.drone_marks()`, `Rules.drone_damage_bounds()` (T4b); `TargetOverlay` (T8)
- Produces:
  - `InputController.arm_drone() -> void` — для вибраного свого юніта з `type().drones > 0`: сигнал `drone_armed(ring: Array[Vector2i], marks: Dictionary)`; без дронів/AP — `action_refused(reason)`
  - у режимі DRONE тап по ворогу з `marks[id] == ""` → прев'ю `{type: DRONE, unit_id, target_id, min: 120, max: 180}`; з непорожньою причиною → `action_refused(reason)`, прев'ю немає
  - `_build_command` → `DroneCommand.create(unit_id, target_id)`
  - `DroneButton.show_for(unit: Unit) -> void` — видима лише для типів з дронами, текст із залишком; натиск → `arm_drone()`

Кнопка — окрема дія поруч із «Підтвердити», не перемикач режиму стрільби. Звичайний тап по ворогу без натиснутої кнопки лишається пострілом.

- [ ] **Step 1: Тести контролера** — `test_arm_drone_emits_ring_and_marks`, `test_drone_tap_on_infantry_refused_with_reason`, `test_drone_tap_on_vehicle_sets_preview_120_180`, `test_plain_tap_on_enemy_still_previews_shot`, `test_arm_drone_without_drones_refused`.
- [ ] **Step 2: e2e (`test_drone_e2e.gd`)**

```gdscript
# 10×3, усе розвідано; штурмовий загін (1) P0 на (0,1), середній танк (5) P1 на (5,1), стрілецький (0) P1 на (3,1)
func test_drone_strike_through_button() -> void
	# тап загону, кнопка «Дрон (2)», кільце: contour_segments(LAYER_TARGETS) не порожній
	# танк — приціл; загін P1 — set_forbidden(true)
	# тап танка, Confirm: drones_left 1, текст кнопки «Дрон (1)», значок на юніті 1,
	# hp танка ∈ [220, 280], ShotRetaliated відсутній (танк: дальність 4 < 5); точне HP — golden
func test_drone_on_infantry_shows_reason_and_does_nothing() -> void
	# рядок причини == tr("ERR_DRONE_CANNOT_TARGET_INFANTRY"); drones_left 2; AP загону 30
func test_drone_button_hidden_for_rifle_squad() -> void
func test_third_strike_refused() -> void   # prepare: drones_left 0 → натиск кнопки дає ERR_NO_DRONES_LEFT
```

- [ ] **Step 3:** FAIL → реалізувати → PASS; `LayoutProbe` по `SIZES`: кнопка ≥ 48, `BottomBar` не виходить за межі з нею.
- [ ] **Step 4: Коміт** `feat(ui): кнопка дронового удару з кільцем і забороненими цілями`

---

### Task 12: Три гравці й комплект карт (4.8, 4.10)

**Files:**
- Modify: `core/map_data.gd` (`populate()` пропускає спавн з `owner >= state.player_count`; див. відкрите питання 1)
- Create: `maps/urban.tres`, `maps/open.tres`, `maps/forest.tres`, `maps/mountain.tres`; Modify: `maps/skirmish_bridge.tres` (третій гравець)
- Modify: `assets/i18n/strings.csv` — `map_bridge`, `map_urban`, `map_open`, `map_forest`, `map_mountain`
- Test: `tests/core/test_map_data.gd`, `tests/game/test_maps.gd`, `tests/e2e/test_three_players_e2e.gd`

**Interfaces:**
- Consumes: каркас T2 (`players: 3`), `MatchSetup.map_supports()` (`game/ui/match_setup.gd:69`)

- [ ] **Step 1: Тест core** — `test_populate_skips_spawns_beyond_player_count` (спавни 0,1,2 при `player_count` 2 → 2 власники, `populate` повертає `true`, жодного юніта з `owner` 2).
- [ ] **Step 2: Структурний тест карт (`test_maps.gd`) — для кожного `maps/*.tres`**

```gdscript
func test_map_is_well_formed(p = use_parameters(_map_paths())) -> void:
	# tiles.size() == width*height; name_key перекладений
	# кожен спавн у межах, на прохідному для свого юніта тайлі (Rules.entry_cost_at < IMPASSABLE), facing 0..7
	# жодних двох спавнів на одному тайлі
	# MatchSetup.map_supports(map, 2) і map_supports(map, 3)
	# BFS по прохідних тайлах: від першого спавну кожного гравця досяжний тайл поряд зі спавном кожного іншого
	# для 2 і 3: start_match + populate + begin без помилок, state.units_of(p) не порожні
func test_five_maps_with_required_kinds() -> void
	# рівно 5 файлів; bridge містить BRIDGE, urban — BUILDING, forest — FOREST >= 25 %,
	# mountain — HILL >= 25 %, open — FIELD/ROAD >= 80 %
```

Розміри й склад — контент-рішення: орієнтир 16×12…20×14, по 5–7 юнітів на гравця з різних класів, щонайменше один інженер і одна артилерія на гравця.
- [ ] **Step 3: e2e (`test_three_players_e2e.gd`)**

```gdscript
func test_eliminated_player_is_skipped_and_gate_names_next() -> void
	# 3 гравці; P1 має один напівмертвий загін поряд із P0 (prepare: hp 10)
	# P0 стріляє → PlayerEliminated(1); end_turn → gate PlayerValue == "3" (не "2")
	# confirm_gate, end_turn → gate "1"; state.is_over() == false
func test_match_continues_between_remaining_two() -> void   # state.eliminated == [false, true, false], winner == -1
func test_three_player_map_runs_with_two_players() -> void   # maps/urban.tres, players 2 → матч стартує, 2 власники
```

- [ ] **Step 4:** FAIL → реалізувати → PASS; ручний прогін кожної карти на 3 гравці на ПК (кілька ходів) і скріншот у PR.
- [ ] **Step 5: Коміт** `feat(maps): п'ять карт на 2 і 3 гравці; спавн поза кількістю гравців пропускається`

---

### Task 14: Кільце дальності й позначки загроз будь-якого видимого юніта (§3.13)

Додано власником 2026-10-18. Правило вже записане в `CLAUDE.md` §3.13 і `docs/ui/overlays.md` (таблиця «inspecting / ring / marked units»); у вигляді його немає: тап по ворогу без вибраного юніта — no-op (`input_controller.gd:140`), `Targeting.threatened_units()` / `drone_threatened_units()` (`core/targeting.gd:75,137`) ніхто не викликає. Нової механіки немає.

**Files:**
- Modify: `game/battle/input_controller.gd` (інспекція), `game/battle/battle_screen.gd`, `game/battle/unit_view.gd` (`set_threatened(on: bool)`), `game/ui/hud.gd`/`hud.tscn` (рядок «прогноз — нижня межа»)
- Modify: `assets/i18n/strings.csv` — `hud_threat_floor` («Щонайменше: мережа розвідки ворога прихована» / «At least: the enemy's spotter network is hidden»)
- Test: `tests/core/test_targeting.gd`, `tests/game/test_input_controller.gd`, `tests/e2e/test_threat_e2e.gd`

**Interfaces:**
- Consumes: `Targeting.reach_tiles()` (T4b), `TargetOverlay` (T8), `Targeting.threatened_units(state, id, observer)`, `Targeting.drone_threatened_units(...)`, `Targeting.firing_targets()`; позначки дрона з T10
- Produces:
  - `InputController.inspect_unit(unit: Unit) -> void` → сигнал `inspected(ring: Array[Vector2i], drone_ring: Array[Vector2i], marked: Array[int], is_floor: bool)`; `inspect_clear()` → той самий сигнал з порожніми масивами
  - Свій юніт (за таблицею overlays.md): кільце завжди, навіть при 0 AP; позначені — `firing_targets()` (дальність, видимість, AP). Ворог: кільце завжди; позначені — `threatened_units(state, id, state.active_player)` (лише сам юніт, **AP не перевіряється**), `is_floor = true`. Штурмовий загін з `drones_left > 0` (свій чи ворожий) — окреме `drone_ring` радіуса `DroneCommand.RANGE` і позначки з `drone_threatened_units`; без дронів — `drone_ring` порожнє
  - Тап по ворогу, коли нічого не вибрано, → `inspect_unit`; тап по ворогу з вибраним своїм юнітом лишається прев'ю пострілу (поведінка не змінюється); тап по порожньому → `inspect_clear`

- [ ] **Step 1: Тести core** (якщо T4b їх ще не покрив) — `test_enemy_threat_ignores_ap` (ворог з AP 0 позначає мій юніт у дальності), `test_enemy_threat_uses_that_unit_vision_only` (мій юніт, видимий лише іншому ворогу, не позначений), `test_enemy_drone_threat_reaches_5_when_drones_left`, `test_no_drone_threat_when_drones_spent`.
- [ ] **Step 2: Тести контролера** — `test_tap_enemy_with_nothing_selected_inspects`, `test_tap_enemy_with_unit_selected_still_previews_shot`, `test_own_unit_ring_shown_at_zero_ap`, `test_inspect_cleared_on_empty_tap`, `test_inspect_cleared_after_handover` (нічого з інспекції не переживає гейт).
- [ ] **Step 3: e2e (`test_threat_e2e.gd`)** — 10×3, усе розвідано: P1 середній танк (5) на (6,1) з AP 0, P0 броньовик (2) на (3,1) і загін (0) на (0,1). Тап по танку без вибору: `contour_segments(LAYER_TARGETS)` не порожній; броньовик `is_threatened()`, загін — ні (поза дальністю); рядок `hud_threat_floor` видимий. Ворожий штурмовий загін з 2 дронами — `drone_ring` непорожній, мій броньовик на відстані 5 позначений; той самий бут з `drones_left = 0` — не позначений.
- [ ] **Step 4:** FAIL → реалізувати → PASS; `LayoutProbe` по `SIZES`: рядок «нижня межа» не виходить за межі; повний прогін, `Scripts` звірено.
- [ ] **Step 5: Коміт** `feat(battle): кільце дальності й позначки загроз для будь-якого видимого юніта`

---

### Task 13: Повний бойовий HUD на всіх розмірах

**Files:**
- Test: `tests/e2e/test_layout_e2e.gd`
- Modify за результатом: `game/ui/hud.tscn`, `game/ui/engineer_panel.tscn`

**Interfaces:**
- Consumes: `LayoutProbe.mount` (T1), каркас T2 з `click_at(p, vp)`, усі панелі T8–T10 і T14

- [ ] **Step 1: e2e**

```gdscript
func test_full_hud_fits_every_size(p = use_parameters(LayoutProbe.SIZES)) -> void:
	# battle_screen.tscn у SubViewport розміру p
	# справжній тап (click_at у цей viewport) по інженеру → панель інженера + інспектор видимі;
	# тап «Ремонт» по пошкодженому сусіду → PreviewRepairBox видимий
	# overflowing(hud, p) == []; small_targets(hud) == []
	# overlapping([TopBar, BottomBar, EngineerPanel, Inspector]) == []
	# смуга дошки між низом TopBar і верхом BottomBar >= 0.5 * p.y
	# те саме для вибраного штурмового загону з DroneButton
func test_board_still_tappable_on_phone() -> void
	# на PHONE_SMALL тап у центр смуги дошки вибирає юніт, що там стоїть (не з'їдено панеллю)
```

- [ ] **Step 2:** Запуск; якщо FAIL — виправити розкладку контейнерами (не числами позицій), повторити до PASS.
- [ ] **Step 3:** Ручна перевірка на ПК: `$GODOT --path . --resolution 1496x672 -- --ui-dpi=243` (емуляція Pixel) і `--resolution 1280x720`; скріншоти обох у PR.
- [ ] **Step 4:** Повний прогін `./run_tests.sh` зелений, `Scripts` = `find tests -name 'test_*.gd' | wc -l`.
- [ ] **Step 5: Коміт** `test(e2e): увесь HUD бою влазить у телефони, ПК і планшет`

---

### Task 15: Видалити механіку цілей (рішення власника 2026-10-18)

Перемога — лише знищенням. Повний бриф — `task-15-brief.md` у робочій теці SDD; іде після T8.

## Відкриті питання до власника

1. ~~Карта на 3 гравці, зіграна вдвох.~~ **Рішення головного контексту:** `populate` пропускає спавни гравця 2; окремих варіантів карт немає.
2. ~~Кільце дальності й позначки загроз (§3.13).~~ **Власник 2026-10-18: додати** — Task 14.
3. ~~Поріг драга після масштабування.~~ **Рішення головного контексту (у T1):** поріг — 10 логічних px без ділення на `content_scale_factor`; після T1 логічний px ≈ dp, тож на Pixel це ≈ 10 dp, як і задумано.
4. ~~Усі кнопки інженера завжди чи лише доступні?~~ **Відповідь у таблиці Фази 4:** усі, недоступні сірі з причиною на тап.
5. ~~Силуети на 12 типів примітивами (4.1).~~ **Рішення головного контексту:** робимо мінімум за T3 — таблиця Фази 4 цього вимагає, а 12 однакових силуетів роблять e2e і ручні прогони нечитабельними до Фази 5.

## Самоперевірка

- **Покриття:** 4.1 → T3; 4.2 → T4a+T8; 4.3 → T4a+T9; 4.4 → T4b+T10; 4.5 → T5; 4.6, 4.7, 4.9 → скасовано (T7, T15); 4.8 → T12; 4.10 → T12; респонсивність (без прив'язки до пристрою) → T1+T13 і крок `LayoutProbe` у кожному UI-завданні; e2e — у кожному завданні з фічею гравця.
- **Узгодженість імен:** `action_status`, `repair_bounds`, `reach_tiles`, `drone_marks`, `drone_damage_bounds`, `TargetOverlay.show_tiles`, `InputController.arm_engineer/arm_drone/disarm`, сигнали `targets_changed`, `drone_armed`, `action_refused`; `ActionType.ENGINEER/DRONE` вводить T8, споживає T10.
- **Що застаріло в старій таблиці:** «13 типів» → 12; значок дронів (4.4) і ядро трьох гравців (4.8) уже є; шар мін мусить читати стан, а не події; 720×360 із розділу «Стиль» замінено набором `LayoutProbe.SIZES` (800×360 … 1280×800); Pixel 10 Pro XL — лише орієнтир.
