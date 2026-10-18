# Phase 5a — New Maps and Battlefield Look Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five old maps with three balanced 26×22 two-player maps, and replace the
coloured-box board with a rainy, textured, dressed battlefield seen through a perspective camera,
tuned for the River map.

**Architecture:** Maps are authored as ASCII text and converted to the existing `MapData` `.tres`
by a tool; tests pin symmetry and pace. On the view side `BoardView` keeps its public API (every
overlay caller stays untouched) but its box tiles are replaced by three children it owns:
`GroundSurface` (one shaded mesh, kind map texture), `WaterSurface`, and `PropLayer`
(one MultiMesh per prop model, deterministic placement, occlusion fade). A `WeatherRig` applies a
cosmetic `BattleLook` preset chosen by map path. Nothing in `core/` changes except tests.

**Tech Stack:** Godot 4.7.2, typed GDScript, GUT (headless), Godot shaders, Python 3.12 + Pillow
for texture tooling, `agy` for 2D generation, `tripo` via the `asset-manager` skill for 3D.

**Spec:** `docs/superpowers/specs/2026-10-18-phase-5a-maps-and-battlefield-look-design.md`

## Global Constraints

- Weather and look change no number; `MapData.ground_state` is the only ground rule (CLAUDE.md §3.12).
- Nothing may render a unit the active player cannot see — including reflections (spec anti-goals).
- Prop placement is a pure function of the board: same board → identical transforms; never `Rules.roll`, never `randi()`/`randf()`.
- Budget: < ~100 draw calls, < ~150k triangles on screen (CLAUDE.md §8). No SSR, no SSAO, no volumetric fog.
- Logic stays flat: units and overlays at `y = 0`; one tile = 1.0 world unit; front is `−Z`.
- `BoardView`'s public API is frozen: `build`, `rebuild_tiles`, `draw_contour`, `clear_contour`, `contour_segments`, `draw_circles`, `circles`, `kind_at`, `LAYER_*`.
- Render layers: layer 1 = world (ground, water, props); **layer 2 = units** (`UnitView` and its children). The reflection probe's cull mask is layer 1 only.
- Two-player maps only; three-player code keeps its tests via a fixture under `tests/fixtures/`.
- Six units per side on every map: type ids `[0, 1, 2, 5, 9, 11]` (rifle squad, assault squad, armoured car, medium tank, field gun, engineer vehicle).
- Display strings via `assets/i18n/strings.csv` (uk + en). Code comments in `core/` and `game/` in Ukrainian; docs in English (`write` skill).
- After any shader change run `$GODOT --headless --path . --import` and grep its output for `SHADER ERROR` — GUT never compiles shaders.
- Every generated texture, reference or accepted asset render is published to the owner's browser page as it is made (show-and-continue, not a gate). Tripo: at most 3 re-rolls per asset.
- Phone-size screenshots via `tests/game/layout_probe.gd` / `tools/ui_shot` (`--write-movie` ignores `--resolution`).

## Review Focus

1. **A tap lands on the cell under the finger at every zoom.** Perspective changes the ray; a tap at the screen edge at MAX zoom must select the cell drawn there — Task 3 tests taps at MIN and MAX zoom near the screen corners.
2. **A demolished or repaired bridge changes the scene.** `rebuild_tiles` after a demolish must swap the bridge prop and the water under it — Task 8 test.
3. **A unit inside a forest or a building stays readable.** Props on the unit's cell and on the camera-side neighbours fade — Task 8 test on `PropLayer.set_reveal_cells`.
4. **A hidden enemy never shows in a puddle or the river.** Probe culls layer 2 and captures once — Task 6 test.
5. **Loading an old save whose map was deleted.** `MatchService.map_path` points to `res://maps/urban.tres`; `BattleScreen` must fall back to River, not crash — Task 2 test.

---

### Task 1: ASCII map format and converter

**Files:**
- Create: `tools/map_ascii.gd` (`class_name MapAscii`, `extends RefCounted`)
- Create: `tools/build_maps.gd` (`extends SceneTree`, headless entry point)
- Test: `tests/game/test_map_ascii.gd`

**Interfaces:**
- Produces: `static func parse(text: String) -> MapData` — returns `null` on any format error (and `push_error`s why).
- Produces: `tools/build_maps.gd` converts every `tools/maps/*.txt` to `maps/<same basename>.tres` via `ResourceSaver.save`. Run: `$GODOT --headless --path . -s res://tools/build_maps.gd`.

Format (one file per map):
```
name_key=map_river
ground=MUD            # DRY | MUD | FROZEN
tiles:
<H lines of exactly W chars>   # = . T ^ ~ w B r H x  → ROAD FIELD FOREST HILL MARSH WATER BUILDING RUBBLE BRIDGE BRIDGE_DESTROYED
spawns:
<type_id> <x> <y> <facing>      # player 0 only; one per line
```
Player 1's spawns are generated: position `(W-1-x, H-1-y)`, facing `(f + 4) % 8` (`Board.DIRS_8` index 0 is north).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_parse_reads_size_tiles_ground_and_name() -> void
	# 3×2 map "=.T" / "w~B", ground=MUD → width 3, height 2, ground_state Terrain.GroundState.MUD,
	# tiles == [ROAD, FIELD, FOREST, WATER, MARSH, BUILDING] as ints, name_key "map_x"
func test_parse_mirrors_player0_spawns_for_player1() -> void
	# 4×3 map, spawn "2 0 2 0" → spawns == [{type_id 2, owner 0, pos (0,2), facing 0},
	#                                        {type_id 2, owner 1, pos (3,0), facing 4}]
func test_parse_rejects_ragged_rows_and_unknown_chars() -> void
	# a row one char short → null; a 'Q' in the grid → null
```

- [ ] **Step 2: Run, expect FAIL** — `./run_tests.sh -gtest=res://tests/game/test_map_ascii.gd` → fails, `MapAscii` not found.
- [ ] **Step 3: Implement `MapAscii.parse` and `tools/build_maps.gd`.**
- [ ] **Step 4: Run, expect PASS**, and check the GUT "Scripts" count went up by one.
- [ ] **Step 5: Commit** — `git commit -m "feat(tools): ASCII-формат карт і конвертер у MapData"`

---

### Task 2: Three new maps replace the old five

**Files:**
- Create: `tools/maps/river.txt`, `tools/maps/crossroads.txt`, `tools/maps/ridge.txt`; generated `maps/river.tres`, `maps/crossroads.tres`, `maps/ridge.tres`
- Delete: `maps/forest.tres`, `maps/mountain.tres`, `maps/open.tres`, `maps/skirmish_bridge.tres`; move `maps/urban.tres` → `tests/fixtures/three_player_map.tres` (`git mv`, set its `name_key = ""`)
- Modify: `assets/i18n/strings.csv:113-117` — remove `map_bridge`, `map_urban`, `map_open`, `map_forest`, `map_mountain`; add `map_river,Річка,River`, `map_crossroads,Перехрестя,Crossroads`, `map_ridge,Хребет,Ridge`
- Modify: `game/battle/battle_screen.gd:46` — `_FallbackMap` → `res://maps/river.tres`; `:186-188` — a `map_path` that no longer exists falls back to `_FallbackMap`
- Modify: `tests/game/test_maps.gd` — drop `map_supports(m, 3)` and the `[2, 3]` loop's 3; replace `test_five_maps_with_required_kinds`
- Modify: `tests/core/test_map_data.gd:100-101`, `tests/game/test_match_flow.gd:11,429,435`, `tests/e2e/test_three_players_e2e.gd:75` — two-player cases use `res://maps/river.tres`; three-player cases use `res://tests/fixtures/three_player_map.tres`

**Interfaces:**
- Consumes: `MapAscii.parse`, `tools/build_maps.gd` (Task 1).
- Produces: `res://maps/river.tres` (26×22, `MUD`), `res://maps/crossroads.tres` (26×22, `DRY`), `res://maps/ridge.tres` (26×22, `DRY`). Player 0 starts in the bottom half.

Layouts start from `docs/art/map_sketches.py` (run it; concepts A/B/C = river/crossroads/ridge). The sketch measured pace under `DRY`; River is `MUD`, so retune it.

- [ ] **Step 1: Write the failing tests in `tests/game/test_maps.gd`**

```gdscript
func test_exactly_the_three_new_maps() -> void
	# _map_paths() == ["res://maps/crossroads.tres", "res://maps/ridge.tres", "res://maps/river.tres"]
func test_map_is_180_degree_symmetric(p = use_parameters(_map_paths())) -> void
	# for every (x,y): tiles[y*W+x] == tiles[(H-1-y)*W + (W-1-x)];
	# every owner-0 spawn has an owner-1 twin at (W-1-x, H-1-y) with facing (f+4)%8 and same type_id
func test_map_has_the_six_unit_set_per_side(p = use_parameters(_map_paths())) -> void
	# sorted type_ids of each owner == [0, 1, 2, 5, 9, 11]; owners == {0, 1}
func test_map_pace(p = use_parameters(_map_paths())) -> void
	# Dijkstra (4-dir) with Rules.entry_cost_at(unit, board, cell) on m.to_board() (its own ground state)
	# from owner 0's spawn of type T to owner 1's spawn of type T, turns = cost / UnitTypes AP:
	#   type 2 (armoured car): 4.0 <= turns <= 6.0
	#   type 5 (medium tank):  6.0 <= turns <= 8.0
	# a finite cost is also the vehicle-reachability check
func test_river_has_three_crossings_and_a_town() -> void
	# river.tres: count(BRIDGE) >= 6 (3 crossings × 2 rows), count(BUILDING) >= 8
func test_crossroads_town_block_and_ridge_forest() -> void
	# crossroads: count(BUILDING) >= 20; ridge: count(FOREST) + count(HILL) >= 60
```

In `tests/game/test_battle_screen.gd` add:
```gdscript
func test_a_save_pointing_at_a_deleted_map_falls_back_to_river() -> void
	# match_service.map_path = "res://maps/urban.tres" → battle starts; board is 26×22
```

- [ ] **Step 2: Run, expect FAIL** (old maps still present).
- [ ] **Step 3: Author the three `.txt` files, run `tools/build_maps.gd`, delete/move the old maps, update strings and references.** Iterate the layouts until `test_map_pace` passes; keep "no straight base-to-base road".
- [ ] **Step 4: Run the full suite** — `./run_tests.sh` → all green; Scripts count unchanged from Task 1 (no new test file here). Publish the three map sketches (re-run `docs/art/map_sketches.py`-style render from the real `.tres`) to the owner's browser page.
- [ ] **Step 5: Commit** — `git commit -m "feat(maps): Річка, Перехрестя, Хребет замість п'яти старих карт"`

---

### Task 3: Mobile renderer and perspective camera

**Files:**
- Modify: `project.godot:43` — `renderer/rendering_method.mobile="mobile"`
- Modify: `game/camera/iso_camera_rig.gd` (`_ready`, `_apply_zoom_keep_anchor`, constants), `game/camera/iso_camera_rig.tscn`
- Modify: `game/battle/unit_view.gd` — every `VisualInstance3D` under a `UnitView` uses render layer 2 only
- Test: `tests/game/test_iso_camera_rig.gd`, `tests/game/test_project_settings.gd` (create), `tests/e2e/test_river_e2e.gd` (create)

**Interfaces:**
- Produces: `zoom_level` now means the camera's distance from its focus point (rig origin on `y = 0`) along the view axis. `MIN_ZOOM` / `MAX_ZOOM` keep their names; values retuned by the builder.
- Produces: `const PITCH_NEAR_DEG: float = 40.0`, `const PITCH_FAR_DEG: float = 55.0`, `const FOV_DEG: float` (builder's value); `func pitch_for(zoom: float) -> float` — linear from `PITCH_NEAR_DEG` at `MIN_ZOOM` to `PITCH_FAR_DEG` at `MAX_ZOOM`.
- Produces: `const UNIT_LAYER: int = 2` on `UnitView`.
- Unchanged: every other public method of `IsoCameraRig`.

- [ ] **Step 1: Write the failing tests**

```gdscript
# test_project_settings.gd
func test_phones_use_the_mobile_renderer() -> void
	# ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "mobile"
# test_iso_camera_rig.gd
func test_camera_is_perspective() -> void          # _camera.projection == PROJECTION_PERSPECTIVE
func test_pitch_eases_with_zoom() -> void          # pitch_for(MIN_ZOOM) == 40.0, pitch_for(MAX_ZOOM) == 55.0
func test_screen_centre_looks_at_the_rig_origin() -> void
	# at MIN and MAX zoom: _ray_ground_point(viewport centre) ≈ rig.global_position (within 0.01)
func test_corner_taps_hit_the_drawn_cell_at_min_and_max_zoom() -> void
	# for zoom in [MIN, MAX], for each of 4 points 40 px inside the viewport corners:
	# screen_point_to_cell(p) == world_to_cell of the ground point unproject() maps back to p
# test_river_e2e.gd
func test_a_unit_moves_on_river_through_real_taps_at_both_zoom_ends() -> void
	# boot River (extend E2eHelpers.boot with opts["map_path"] if it has no such option);
	# at MAX zoom tap own armoured car, tap a gold tile, confirm → unit.pos == that tile, AP dropped;
	# zoom to MIN, recentre, repeat with the rifle squad
```
Existing camera tests (anchor fixed under zoom, pan clamp, pan keeps point under finger, centre_on, fly_to) must pass unchanged — they are the acceptance for the projection switch.

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Camera local transform on the `Yaw` node: `position = Vector3(0, d·sin(p), d·cos(p))`, `rotation_degrees.x = -p`, with `d = zoom_level`, `p = pitch_for(d)`; `_apply_zoom_keep_anchor` sets this instead of `_camera.size`.
- [ ] **Step 4: Run the full suite → green.** Take screenshots of River (current box tiles) at MIN and MAX zoom and publish them to the owner's page.
- [ ] **Step 5: Commit** — `git commit -m "feat(camera): перспективна камера з нахилом від зуму; рендерер Mobile"`

---

### Task 4: Terrain textures (agy)

**Files:**
- Create: `tools/terrain_tex.py` — subcommands `seamless <in> <out>` (cross-fade the image with its half-offset copy so opposite edges match), `normal <albedo> <out> [--strength S]` (Sobel on luminance), `check <png>...` (exit 1 if any image's left/right or top/bottom edge mean abs diff > 6/255)
- Create: `assets/terrain/{road,field,forest,hill,marsh,mud,rubble,bank}_albedo.png` and matching `_normal.png`, 1024×1024
- Test: `tools/terrain_tex.py check assets/terrain/*.png`

**Interfaces:**
- Produces: the 16 PNGs above; a `Texture2DArray` is built from the albedos in Task 5 in this layer order: `road, field, forest, hill, marsh, mud, rubble, bank`.

Prompts (agy, one image each, flags before `-p`, see memory `agy image generation`): seamless top-down photo texture, overcast diffuse light, no shadows, no perspective, no objects; road = *wet dark asphalt with fine cracks*, field = *short autumn meadow grass, wet*, forest = *forest floor, pine needles, birch leaves, moss*, hill = *rocky scrub, grey stones in brown soil*, marsh = *bog, dark water between sedge tufts*, mud = *churned wet mud with tyre ruts and standing water*, rubble = *broken brick and concrete debris*, bank = *wet river bank, silt and pebbles*. Palette per `docs/art-direction.md` and `docs/art/mood/river_target.jpg`.

- [ ] **Step 1:** Write `terrain_tex.py`; self-check: `python3 -I tools/terrain_tex.py check` on a random-noise PNG fails, on its `seamless` output passes.
- [ ] **Step 2:** Generate the 8 albedos with agy; run `seamless` then `normal` on each.
- [ ] **Step 3:** `python3 -I tools/terrain_tex.py check assets/terrain/*.png` → exit 0.
- [ ] **Step 4:** Publish a page showing each texture tiled 2×2 beside the target frame; regenerate any that look wrong against the target (owner may interject).
- [ ] **Step 5: Commit** — `git commit -m "feat(art): текстури місцевості для ґрунтового шейдера"`

---

### Task 5: Continuous ground surface

**Files:**
- Create: `game/battle/ground_surface.gd` (`class_name GroundSurface`, `extends MeshInstance3D`), `game/battle/shaders/ground.gdshader`
- Modify: `game/battle/board_view.gd` — `build()` creates one `GroundSurface` instead of the per-kind MultiMeshes; remove `_build_kind_instance`, `_tile_mesh`, `_tile_material`, `_TILE_GAP`, `_COLORS`
- Modify: `project.godot` — global shader uniforms `weather_wetness: float = 0.0`, `cloud_shadow_strength: float = 0.0`
- Test: `tests/game/test_board_view.gd`, `tests/game/test_ground_surface.gd` (create)

**Interfaces:**
- Consumes: textures from Task 4.
- Produces: `GroundSurface.build(board: Board, margin: int) -> void` — one mesh covering cells `(-margin, -margin)` to `(W-1+margin, H-1+margin)` at `y = 0`; `margin` is `0` until Task 9.
- Produces: `GroundSurface.kind_image() -> Image` — `FORMAT_R8`, `(W + 2·margin) × (H + 2·margin)`, pixel = `Terrain.Kind` of the cell (out-of-board cells take the nearest edge cell's kind); uploaded as the shader's `kind_map`.
- Produces: `const TEX_LAYER_FOR_KIND: Dictionary` — `Terrain.Kind → texture layer` (ROAD→road, BRIDGE→road, FIELD→field, FOREST→forest, HILL→hill, MARSH→marsh, WATER→bank, BRIDGE_DESTROYED→bank, BUILDING→rubble, RUBBLE→rubble). Under `ground_state == MUD`, FIELD and HILL blend toward `mud` (factor is the builder's).
- `BoardView.kind_at`, contours and circles behave exactly as before.

- [ ] **Step 1: Write the failing tests**

```gdscript
# test_board_view.gd — replace the four MultiMesh-per-kind tests with:
func test_build_makes_exactly_one_ground_surface() -> void      # any board → 1 GroundSurface child
func test_build_is_idempotent() -> void                          # build twice → still 1
func test_rebuild_tiles_updates_the_kind_map_and_keeps_contours() -> void
	# set a cell ROAD→BRIDGE_DESTROYED, rebuild_tiles → kind_image() pixel at that cell == BRIDGE_DESTROYED; contours kept
# test_ground_surface.gd
func test_kind_image_matches_the_board() -> void                 # 4×3 board: every pixel == board.kind_at
func test_mesh_covers_the_board_at_y_zero() -> void              # AABB x∈[-0.5, W-0.5], z∈[-0.5, H-0.5], y≈0
```
Keep `test_no_apply_fog_and_no_vision_reference` as is.

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Shader: sample `kind_map` with `filter_nearest` at the 4 cells around the fragment, weight them bilinearly with the position perturbed by a noise texture (~0.3 tile amplitude) so borders are soft and irregular; sample the `Texture2DArray` with world-space UVs (~1 texture repeat per 3 tiles) for albedo and normal; roughness lowered and albedo darkened by `weather_wetness`; puddles on road/mud where a low-frequency noise < `weather_wetness` threshold (flat normal, roughness ~0.05).
- [ ] **Step 4: Run** `./run_tests.sh` → green; `$GODOT --headless --path . --import 2>&1 | grep -c "SHADER ERROR"` → `0`. Screenshot River at MAX and MIN zoom, with a unit selected (zone contours visible), publish beside the target frame.
- [ ] **Step 5: Commit** — `git commit -m "feat(board): суцільна земля з текстурами замість плиток"`

---

### Task 6: Water and reflections

**Files:**
- Create: `game/battle/water_surface.gd` (`class_name WaterSurface`, `extends MeshInstance3D`), `game/battle/shaders/water.gdshader`
- Modify: `game/battle/board_view.gd` — `build()` adds one `WaterSurface` and one `ReflectionProbe` (`update_mode = UPDATE_ONCE`, `cull_mask = 1`, box covering the board plus margin)
- Test: `tests/game/test_water_surface.gd` (create)

**Interfaces:**
- Consumes: `GroundSurface.kind_image()` (Task 5) as the water mask source.
- Produces: `WaterSurface.build(board: Board, margin: int, kind_map: ImageTexture) -> void` — one plane at `y = 0.02`, shader discards where the cell is not WATER / BRIDGE_DESTROYED (soft shoreline from the same noise as the ground).
- Produces: `BoardView.reflection_probe() -> ReflectionProbe`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_board_with_water_gets_one_water_surface() -> void       # River → 1 WaterSurface child of BoardView
func test_board_without_water_still_builds_one_hidden_water() -> void  # all-FIELD board → WaterSurface.visible == false
func test_reflection_probe_never_sees_units() -> void
	# reflection_probe().cull_mask & (1 << (UnitView.UNIT_LAYER - 1)) == 0
	# and update_mode == ReflectionProbe.UPDATE_ONCE
func test_unit_meshes_are_on_the_unit_layer_only() -> void
	# instantiate unit_view.tscn, bind a unit: every VisualInstance3D descendant has layers == 1 << (UNIT_LAYER - 1)
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Water: dark base colour, two scrolling normal maps plus rain ripple rings (procedural, strength × `weather_wetness`), fresnel blend to the probe's reflection; puddles in the ground shader also take the probe's reflection (radiance), so no screen-space pass is used.
- [ ] **Step 4: Run** suite + shader import check. Screenshot the river and the central bridge at MIN zoom, publish.
- [ ] **Step 5: Commit** — `git commit -m "feat(board): річка з відбиттями без SSR; зонд не бачить юнітів"`

---

### Task 7: 3D props (asset-manager / Tripo)

**Files:**
- Create: `assets/props/{tree_pine,tree_birch,tree_bare,house_a,house_b,house_c,house_ruin,bridge_span,bridge_broken,rocks,wall_fence}.glb`
- Create: `tools/prop_preview.tscn` + `tools/prop_preview.gd` — renders each GLB under the game camera (`IsoCameraRig` at MIN zoom) on a field tile and saves `user://prop_preview/<name>.png`
- Test: `tests/game/test_props_assets.gd` (create)

**Interfaces:**
- Produces: the GLBs above, each normalised with the `3d-modelling` skill: origin at the footprint centre on the ground, `y = 0` ground, front `−Z`, footprint ≤ 1.0 × 1.0 (bridge pieces exactly 1.0 along the road), houses ≤ 1.6 tall.
- Produces: `const PROP_FACE_LIMITS: Dictionary` in the test = trees 300, rocks 300, wall_fence 400, bridge pieces 1200, houses and ruin 2000 (Tripo `-p face_limit=` uses these).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_every_prop_exists_is_grounded_and_within_budget(p = use_parameters(PROP_NAMES)) -> void
	# load res://assets/props/<p>.glb, instantiate; merged AABB: min.y ≈ 0 (±0.02), x and z extents ≤ 1.05,
	# total triangle count ≤ PROP_FACE_LIMITS[group]
```
- [ ] **Step 2: Run, expect FAIL** (files missing).
- [ ] **Step 3: Generate** each asset with the `asset-manager` skill (`tripo-p1`, the face limits above, prompts derived from `docs/art/mood/river_target.jpg` and `docs/art-direction.md`: stone two-storey houses with dark slate roofs, a concrete road bridge segment, birch, pine, bare autumn tree, grey rocks, low stone wall with a wooden fence). Normalise each with `3d-modelling`. Render with `prop_preview`, publish each render; accept or re-roll (max 3).
- [ ] **Step 4: Run, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -m "feat(art): 3D-об'єкти поля бою — дерева, будинки, міст, каміння"`

---

### Task 8: Prop placement and occlusion fade

**Files:**
- Create: `game/battle/prop_layer.gd` (`class_name PropLayer`, `extends Node3D`), `game/battle/shaders/prop_fade.gdshader` (or a `next_pass`/material override that reads `INSTANCE_CUSTOM.a` and dithers)
- Modify: `game/battle/board_view.gd` — `build()` adds one `PropLayer`; add `func set_reveal_cells(cells: Array[Vector2i]) -> void` (forwards to the layer)
- Modify: `game/battle/battle_screen.gd` — after `_rebuild_units_for_active_player()` and after each event batch in `_on_events_ready()`, call `_board_view.set_reveal_cells(...)` with the cells of every unit currently shown
- Test: `tests/game/test_prop_layer.gd` (create), `tests/e2e/test_river_e2e.gd`

**Interfaces:**
- Consumes: GLBs from Task 7.
- Produces: `PropLayer.build(board: Board, margin: int) -> void`; `PropLayer.set_reveal_cells(cells: Array[Vector2i]) -> void`; `PropLayer.instances_on(cell: Vector2i) -> Array[Dictionary]` (`{model: StringName, transform: Transform3D, faded: bool}`, for tests); `PropLayer.triangle_count() -> int`.
- Produces: `static func cell_hash(cell: Vector2i, salt: int) -> int` — `hash(Vector3i(cell.x, cell.y, salt))`; all jitter derives from it.
- Placement: FOREST → 2–3 trees mixed pine/birch/bare; BUILDING → one house variant; RUBBLE → `house_ruin`; BRIDGE → `bridge_span`, BRIDGE_DESTROYED → `bridge_broken`, both oriented along the bridge's road axis; HILL → `rocks`; FIELD cells orthogonally next to ROAD → `wall_fence` on ~1 in 4 cells (by hash). Out-of-board margin cells get the same rules from their clamped kind.
- Fade: a unit cell `c` reveals props on `c`, `c + (1,0)`, `c + (0,1)`, `c + (1,1)` (the camera sits at +x, +z of its focus at yaw 45°).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_same_board_gives_identical_props() -> void            # build twice → instances_on() equal for every cell
func test_forest_cell_gets_two_or_three_trees() -> void
func test_bridge_swaps_when_demolished() -> void
	# BRIDGE cell → bridge_span; set BRIDGE_DESTROYED, BoardView.rebuild_tiles → bridge_broken on that cell
func test_reveal_fades_the_cell_and_its_camera_side_neighbours_only() -> void
	# forest 4×4, reveal (1,1) → faded on (1,1),(2,1),(1,2),(2,2); not faded on (0,0),(1,0),(0,1)
func test_reveal_replaces_the_previous_set() -> void
func test_river_props_fit_the_triangle_budget() -> void          # River with margin 0: triangle_count() <= 120000
func test_one_multimesh_per_model() -> void                       # MultiMeshInstance3D children <= 11
```
E2E (add to `test_river_e2e.gd`):
```gdscript
func test_a_unit_walking_into_a_forest_fades_the_trees_over_it() -> void
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** suite + shader import check. Screenshot River at MAX and MIN zoom, with the rifle squad inside the forest and inside the town, publish.
- [ ] **Step 5: Commit** — `git commit -m "feat(board): дерева, будинки й міст на карті; крона розчиняється над юнітом"`

---

### Task 9: Surroundings beyond the board

**Files:**
- Modify: `game/battle/board_view.gd` — `const SURROUND_MARGIN: int` (builder's value, start at 12); pass it to `GroundSurface`, `WaterSurface`, `PropLayer`
- Modify: `game/battle/shaders/ground.gdshader` — out-of-board fragments darken and desaturate with distance past the edge (soft, ~2 tiles to full effect)
- Test: `tests/game/test_board_view.gd`

**Interfaces:**
- Consumes: `IsoCameraRig.MAX_ZOOM`, `BOARD_MARGIN`, `_ray_ground_point` (Task 3).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_surroundings_fill_the_view_at_max_zoom_from_every_board_corner() -> void
	# River board; rig at MAX zoom; for each of the 4 board corners: centre_on(corner) then pan to the clamp;
	# ground point under each viewport corner lies inside the ground mesh AABB
```
- [ ] **Step 2: Run, expect FAIL** (margin 0).
- [ ] **Step 3: Implement.** If the river continues off both sides it must (clamped kinds already give that).
- [ ] **Step 4: Run** suite; recheck `test_river_props_fit_the_triangle_budget` still passes **with** the margin (raise the limit to 150000 only if the on-screen count measured in Task 11 stays under budget). Screenshot River corners at MAX zoom, publish.
- [ ] **Step 5: Commit** — `git commit -m "feat(board): місцевість за межами карти тоне в серпанку"`

---

### Task 10: Weather and light presets

**Files:**
- Create: `game/battle/look/battle_look.gd` (`class_name BattleLook`, `extends Resource`), `game/battle/look/river_rain.tres`, `game/battle/look/overcast_dry.tres`, `game/battle/look/map_looks.gd` (`class_name MapLooks`), `game/battle/look/weather_rig.gd` + `weather_rig.tscn` (`class_name WeatherRig`, `extends Node3D`)
- Create: `assets/vfx/rain_streak.png` (agy or procedural)
- Modify: `game/battle/battle_screen.tscn` / `battle_screen.gd` — replace the scene's lone `DirectionalLight3D` (`battle_screen.tscn:17`; there is no `WorldEnvironment` yet) with a `WeatherRig` that owns the light and the environment; `_wire_view` calls `_weather.apply(MapLooks.for_map_path(match_service.map_path))`; the rig follows the camera rig's focus for rain
- Test: `tests/game/test_weather_rig.gd` (create)

**Interfaces:**
- Produces: `BattleLook` exports: `light_color: Color`, `light_energy: float`, `light_pitch_deg: float`, `light_yaw_deg: float`, `ambient_color: Color`, `ambient_energy: float`, `fog_color: Color`, `fog_density: float`, `rain: bool`, `rain_amount: int`, `wetness: float` (0..1), `cloud_shadow_strength: float` (0..1), `cloud_shadow_speed: float`.
- Produces: `MapLooks.for_map_path(path: String) -> BattleLook` — `"river.tres"` basename → `river_rain.tres`; anything else (including `""`) → `overcast_dry.tres`.
- Produces: `WeatherRig.apply(look: BattleLook) -> void` — sets `DirectionalLight3D` (shadows on), `WorldEnvironment` depth fog, rain `GPUParticles3D.emitting = look.rain`, global shader uniforms `weather_wetness` and `cloud_shadow_strength`.
- Cloud shadows: the ground shader multiplies by `1 - cloud_shadow_strength · smoothstep(noise(world_xz · scale + TIME · speed))`, mostly clear with a passing patch every ~10–20 s.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_river_gets_rain_and_others_stay_dry() -> void
	# MapLooks.for_map_path("res://maps/river.tres").rain == true; for crossroads, ridge, "" → false
func test_apply_sets_the_global_wetness_and_rain() -> void
	# apply(river_rain) → RenderingServer.global_shader_parameter_get("weather_wetness") == look.wetness; rain.emitting
	# apply(overcast_dry) → wetness 0.0; rain.emitting == false
func test_a_look_has_no_rule_fields() -> void
	# BattleLook property list contains none of: vision, range, ap, cost, damage, penalty
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**, tuning `river_rain.tres` against `docs/art/mood/river_target.jpg` (cool overcast, light from the far side, haze greys out the distance).
- [ ] **Step 4: Run** suite + shader import check. Record a short frame sequence (`tools/ui_seq`) of River at MAX zoom: rain moves, a cloud shadow passes; publish frames beside the target.
- [ ] **Step 5: Commit** — `git commit -m "feat(look): дощ, мокрі поверхні, хмарні тіні — пресет Річки"`

---

### Task 11: Idle frame cap and budget measurement

**Files:**
- Modify: `game/battle/battle_screen.gd` — `const IDLE_FPS: int = 30`, `const IDLE_AFTER_S: float = 1.0`; uncapped (`Engine.max_fps = 0`) on any input event, while `IsoCameraRig` processes, and while `EventPlayer.is_playing()`; back to `IDLE_FPS` after `IDLE_AFTER_S` of none of these; restore the previous `Engine.max_fps` on `_exit_tree` (pattern: `game/ui/main_menu.gd:159-168`)
- Create: `tools/frame_budget.gd` — boots River at MAX zoom over each board quarter, prints `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` and `RENDER_TOTAL_PRIMITIVES_IN_FRAME` (max over the views)
- Create: `docs/performance.md` — the measured numbers, date, machine, renderer
- Test: `tests/game/test_battle_screen.gd`

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_battle_caps_the_frame_rate_when_idle() -> void       # simulate 1.2 s without input → Engine.max_fps == 30
func test_input_uncaps_the_frame_rate() -> void                # after an InputEventScreenTouch → Engine.max_fps == 0
func test_leaving_battle_restores_the_previous_cap() -> void
```
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement**; run `$GODOT --path . -s res://tools/frame_budget.gd` (windowed, Mobile renderer).
- [ ] **Step 4:** Draw calls < 100 and primitives < 150000 at every measured view; if not, cut (tree density, margin props, shadow casters) and re-measure. Write `docs/performance.md`. Run the suite → green.
- [ ] **Step 5: Commit** — `git commit -m "perf(battle): 30 fps у спокої; заміряний бюджет кадру Річки"`

---

### Task 12: Docs and final showing

**Files:**
- Modify: `CLAUDE.md` §8 — perspective camera (fixed yaw, pan, zoom with pitch easing 40°→55°), no permanent grid, reflections allowed via a once-captured probe (still no SSR), ground is one continuous surface, units on render layer 2; §5 renderer line stays as is (now true)
- Modify: `docs/art-direction.md` — same points; link `docs/art/mood/river_target.jpg`
- Modify: `docs/reference/blitzkrieg.md` — the class costing 100 is water/riverbank (sprites 49–75, `GameCanvas.java:2377-2379`), not built-up
- Modify: `docs/superpowers/plans/2026-08-09-advance-protocol-implementation.md` — Phase 5 table: mark 5.1, 5.3–5.7 (rain preset only) as done by this slice with a link to this plan

- [ ] **Step 1:** Edit the docs (`write` skill: English, project vocabulary).
- [ ] **Step 2:** Full verification: `./run_tests.sh` (note Scripts count), shader import check → 0 errors, `tools/frame_budget.gd` numbers match `docs/performance.md`.
- [ ] **Step 3:** Publish a final page: River at MAX zoom, MIN zoom, a selected unit with zones, a unit in the forest, the bridge, all beside `river_target.jpg`; plus Crossroads and Ridge at MAX zoom.
- [ ] **Step 4: Commit** — `git commit -m "docs: перспективна камера, вигляд поля бою, бюджет кадру"`
