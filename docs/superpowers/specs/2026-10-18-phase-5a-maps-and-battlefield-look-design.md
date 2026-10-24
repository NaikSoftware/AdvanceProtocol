# Phase 5a — new maps and the battlefield look

The first slice of Phase 5 (plan: `docs/superpowers/plans/2026-08-09-advance-protocol-implementation.md`,
"Фаза 5"). Units, battle scars, explosions and the burning-tank smoke column are **not** in this slice;
they come next, onto a map that already looks finished.

## Intent

The owner's picture of the game: **rain, wet asphalt, a tank burning, smoke standing in a column.**
Atmosphere is the reward loop (CLAUDE.md §1, pillar 4). Right now the board is coloured boxes and the
maps are small enough that the sides meet on turn one or two, so fights are shoot-outs. This slice
fixes both: three larger maps where manoeuvre matters, and a battlefield that looks like the target
frame below.

**Target frame:** `docs/art/mood/river_target.jpg` (copy of the approved concept frame "B": high
camera, overcast rain, wet asphalt, muddy ruts with standing water, birch and pine, stone two-storey
houses with dark slate roofs, some ruined, a concrete bridge over a dark river). Two alternates are
kept beside it for reference only: `river_close.jpg` (low close view — what the camera should feel
like zoomed in) and `river_dusk.jpg` (not chosen).

## Owner decisions (fixed)

1. **Maps.** The five old maps in `maps/` (forest, mountain, open, skirmish_bridge, urban) are
   deleted. Three new maps replace them:
   - **A "River" (`river.tres`)** — a river across the middle, three crossings (central town bridge,
     two flank bridges), a town on both banks around the central bridge.
   - **B "Crossroads" (`crossroads.tres`)** — a solid town block in the centre that vehicles can only
     cross by streets; one open flank behind a pond, one forest-and-hills flank.
   - **C "Ridge" (`ridge.tres`)** — a wooded ridge on the diagonal between the bases; one road pass
     in the centre and two narrow gaps near the edges; a hamlet on one slope.
2. **Two players only.** No three-player map in this slice. Nothing is added to handle that in
   the setup screen — the existing `MatchSetup.map_supports` simply offers no map for three.
3. **Six units per side**, as on the current maps.
4. **Size about 26×22.** Balance by numbers, not by mirroring (owner, 2026-10-24): a map may be
   almost symmetric, or its halves may differ with features of equal weight — a mirrored world
   everywhere is unrealistic. Pace target: scouts meet around turn 2–3, main
   forces around turn 3–4. No straight base-to-base road.
5. **Visual work is aimed at map A.** (See "What B and C get" below.)
6. **Perspective camera**, replacing the orthographic rig. Fixed yaw, pan, pinch/scroll zoom between
   a wide view (target frame) and a close view. This overrides CLAUDE.md §8 and
   `docs/art-direction.md`; both get updated in this slice.
7. **No permanent tile grid** on the ground. Tiles become legible only through the selected unit's
   movement-zone contours, which already exist.
8. **Reflections are allowed** (water, puddles, wet asphalt).
9. **Weather for A: rain**, with **clouds drifting over now and then** (their shadows sliding over
   the ground).
10. Generated 2D (textures, backgrounds, reference art) comes from **agy**; 3D from the
    **`asset-manager`** skill (Tripo). **Every generated reference or texture is shown to the owner
    in a browser page as it is made.**

## Goals

- Three balanced, hand-made maps replacing the old five, covered by tests.
- Map A in the game looks recognisably like the target frame, at 60 fps on a mid-range phone.
- Everything a player needs to read (units, zones, path, target marks, the HUD ground-state icon)
  stays at least as readable as today.

## Non-goals (this slice)

- 3D unit models, wrecks, craters, ruts, explosions, the smoke column, muzzle effects — next slice.
- Time-of-day presets other than A's overcast rain; snow, fog and the weather controller as a
  general system beyond what A needs.
- Audio (ambient bed, rain sound) — Phase 5.10. *(Builder: nothing to do here.)*
- Post-processing LUT / vignette / grain — Phase 5.9.
- Map editor.

## Anti-goals (a failure even if it "works")

- A visual that changes any number. Weather and look are cosmetic (CLAUDE.md §3.12). Ground state
  (`MapData.ground_state`) is the only rule and it stays as data.
- Anything that leaks hidden information: props, shadows or reflections must never reveal an enemy
  unit the active player cannot see. Units stay hidden by the existing visibility path; nothing in
  this slice may render a unit outside it (a reflection of a hidden unit in a puddle is a leak).
- Units disappearing behind trees or houses. Readability beats mood (pillar 5).
- The look differing between the two players at the same place — prop placement must be the same
  every time the map is drawn.
- Blowing the budget: < ~100 draw calls, < ~150k triangles on screen (CLAUDE.md §8).

## Part 1 — the maps (core data)

- Built from the sketches the owner approved (`docs/art/map_sketches.py` — run it to regenerate the HTML
  with turn counts). The sketches fix the *idea*; exact tiles are the builder's to
  tune, within these rules:
  - Crossroads and Ridge keep 180° rotational symmetry of tiles. River is asymmetric: its halves
    differ and must be equal by numbers for each player — comparable pace to the 1st, 2nd and 3rd
    crossing (within ~5 %), comparable counts of slow and vehicle-closed cells
    (`test_map_sides_are_balanced`). Spawns still mirror with facing rotated 180°.
  - Every bridge has road on both banks (`test_every_bridge_has_road_on_both_banks`).
  - No straight road from base to base.
  - Every unit of both sides can reach the enemy base area (water/marsh/buildings never wall a
    vehicle in).
  - Measured pace (Dijkstra over the real cost formula, unit AP and cross-country from
    `core/unit_types.gd`): armoured car base-to-base ≈ 4–6 turns, medium tank ≈ 6–8.
- Six units per side, the same set on all three maps: rifle squad, assault squad, armoured car,
  medium tank, field gun, engineer vehicle. Bridges are a mechanic of map A, so the engineer is
  mandatory.
- Ground state per map: River = `MUD`, Crossroads = `DRY`, Ridge = `DRY`. *(Author's call at
  review: Ridge was proposed `FROZEN`, but a passable frozen marsh drawn as wet marsh tells the
  player the opposite of the rule, and a frozen look is out of this slice. Revisit with snow.)*
- **Pace is measured under each map's own ground state** — on River (`MUD`) off-road costs more,
  so the sketched River layout will need retuning to hit the targets.
- Names via `assets/i18n/strings.csv` (uk + en): `map_river`, `map_crossroads`, `map_ridge`; the
  old keys removed.
- Tests: `tests/game/test_maps.gd` keeps its well-formedness and reachability checks; add symmetry
  (symmetric maps), side-balance (asymmetric maps) and pace checks so a later edit cannot quietly unbalance a map. Existing tests and e2e scenarios
  that load an old map by path move to one of the new maps — except the three-player ones
  (`test_maps.gd`'s `map_supports(m, 3)` assertion, `tests/e2e/test_three_players_e2e.gd`,
  three-player cases in `test_match_flow.gd`): they move to a **test-only three-player fixture map
  under `tests/`**, so the three-player code stays covered. Three players remain in v1 scope
  (CLAUDE.md §2 unchanged); a shipped three-player map is later work.
- A small script that turns an ASCII layout into the `.tres` is fine and should be kept in `tools/`
  so maps stay editable until the map editor exists (Phase 6).

## Part 2 — the battlefield look

### Renderer (first task of Part 2)
`project.godot` has run phones on `gl_compatibility` since the scaffold commit (1f4b5b9), with no
recorded reason, while CLAUDE.md §5 makes Mobile (Vulkan) primary and Compatibility the fallback.
**Follow CLAUDE.md:** switch `rendering_method.mobile` to `mobile`. The look is designed for the
Mobile renderer; under Compatibility it must still run and stay readable, with effects degraded
(no reflections beyond a plain fresnel tint, fewer rain particles) rather than matched.

### Frame rate while idle
CLAUDE.md §8 calls battery life a feature, but rain and cloud shadows animate constantly. Rule for
this slice: during input, camera motion and event playback the battle runs uncapped (vsync);
otherwise ambient effects keep animating at a **30 fps cap**, the same mechanism the main menu
uses (`game/ui/main_menu.gd`, `FRAME_CAP_FPS`). Ambient effects read their own time, so a capped
or paused frame rate never changes how they look, only how smooth.

### Camera
- `game/camera/iso_camera_rig.gd` switches to `PROJECTION_PERSPECTIVE`. Yaw stays 45°.
- Zoom moves the camera along its view axis (or changes distance), not `size`. **Owner-approved
  proposal:** pitch eases from ~55° when zoomed out to ~40° when zoomed in, so the far view reads
  like the target frame and the near view like `river_close.jpg`. Exact angles, FOV and limits are
  the builder's, tuned on screenshots.
- Picking (`screen_point_to_cell`), `unproject`, panning bounds, recentring and the handover
  recentre must keep working — they already go through a ground ray, which perspective supports;
  re-verify every one of them.

### Ground
- Replace the per-kind box tiles in `BoardView` with **one continuous ground surface** for the
  playable area.
- **The look is decoupled from the grid** (owner, 2026-10-23). Cells exist only for rules and
  pathfinding; the board shows no squares, straight cell edges or 90° steps anywhere. Each part
  has its own geometry:
  - **River and ponds** (`RiverCourse`): a smoothed centreline through the water cells with
    varying width and an irregular shore; ponds and lakes as organic areas. Every water cell is
    partly wet, through smooth shore bulges only — no isolated puddles, pits or islets; real land
    enclosed by water stays land. Bed depth follows the true distance to the shore, so the bed
    never shows through mid-channel. Steep cut bank on outer bends, gentle point bar inside.
  - **Roads** (`RoadCourse`): curved strips of real width (dirt 2.7 m with ruts, asphalt 4.6 m,
    cobble 4.4 m, a 2-wide band is one town street, compact blocks are plazas). Ruts, wheel paths
    and puddles live in road-local coordinates, never in a world-space texture. Every road cell
    lies under the drawn road.
  - **Surface boundaries**: a smoothed class field with two-scale noise; no 90° texture rotations.
  - Brief and measured numbers: `docs/art/river-banks-research.md`,
    `docs/art/land-and-roads-research.md`.
- Textures ship at their real size per layer (`GroundSurface.MACRO_M`): CC0 Poly Haven scans where
  one exists, generated textures otherwise (`docs/art/ground-texture-research.md`). Roughness drives
  wetness: the rain preset lowers roughness and darkens albedo; puddles sit in road ruts.
- **Cosmetic relief** (`TerrainHeight`): small undulation, raised hills, a sunk river bed. Height
  changes no rule; units, contours, overlays and picking follow it. A hill rises only on its HILL
  cells and their neighbours, and every HILL cell centre keeps most of the hill's height.
- The existing overlays (zones, path, targets, inspect ring, mine marks) must still draw above
  the ground and stay readable on it.

### Water and reflections
- River: water shader with rain ripples and a fresnel reflection of a captured environment
  (reflection probe or equivalent). The look approved in commit f875785 is the baseline: overcast
  sky reflection, not darkness, separates water from land. Ripples are wind-driven and share one
  direction across the board; they do not follow the river's flow.
- Puddles and wet asphalt reflect the same captured environment.
- **No SSR** stays the rule unless measured cheap on a phone — the owner allowed reflections, not
  a specific technique. Reflections must not show hidden units (see anti-goals).

### Props (3D, `asset-manager`)
- Placed by the view from the map's tile kinds, deterministically (hash of tile position — never
  `Rules.roll`, never global random), so both players see the same scene:
  - FOREST → 2–4 trees per tile from 2–3 tree models (birch, pine, bare tree), scale/rotation jitter.
  - BUILDING → a two-storey stone house with a slate roof (2–3 variants), one per tile or one per
    2×1 block if the builder prefers.
  - RUBBLE → ruined house variant / debris pile.
  - BRIDGE → concrete road-bridge segment; BRIDGE_DESTROYED → broken segment. Demolish/repair at
    runtime (engineer verbs) must swap the segment.
  - HILL → rocks and scrub; roadsides → a few poles/fences/low stone walls as dressing.
- MultiMesh per model to hold the draw-call budget.
- **Occlusion:** a tree or roof between the camera and a unit fades (dither) so the unit stays
  readable. Applies to the selected unit and any visible unit.
- Rough Tripo volume: ~8–12 generations (3 trees, 3 houses, 1 ruin, 2 bridge pieces, rocks, a
  fence/wall set) plus **at most 3 re-rolls per asset**. The main context accepts each asset from
  a render at the game camera; if 3 re-rolls do not fix it, take the best and note why.
- **Showing the owner is show-and-continue, not a gate:** every generated texture, reference and
  accepted asset render goes onto a browser page for the owner as it is made, and work goes on.
  The owner stops it by saying so.

### Surroundings
- The board must not float in a void: the same landscape continues past the map edge (fields,
  forest, the river running off both sides) and fades into rain haze. The out-of-bounds area is
  visibly not playable (darker/desaturated or haze) but the border is soft.
- A distant backdrop only if the camera can actually see the horizon at its lowest pitch.

### Weather and light (preset for A)
- One cool overcast directional light; shadows for units and props within budget. Static lighting
  may be baked if that is what holds the budget.
- Depth-based haze (no volumetric fog).
- Rain: particle streaks near the camera, splash/ripple on water and puddles, wet materials.
- Drifting cloud shadows: a scrolling noise darkening the ground every so often.
- All of it lives in a small weather preset resource the map refers to; B and C get a dry overcast
  preset (no rain).

### What B and C get
The ground shader, props and camera are generic — driven by tile kinds — so B and C come out
textured and dressed automatically. The tuning effort (and the screenshots shown to the owner) are
for A. B and C only need to look correct, not tuned.

## Verification

- `./run_tests.sh` green; check the GUT script count (a test file that fails to parse is skipped
  silently).
- After any shader change also `$GODOT --headless --path . --import`: GUT runs on the dummy
  renderer and never compiles GLSL, so a broken shader passes the suite.
- Phone-size screenshots through a SubViewport (`tests/game/layout_probe.gd`) or `tools/ui_shot` —
  `--write-movie` ignores `--resolution`.
- Performance: there is no phone in the loop for this slice, so the budget is checked as a
  desktop proxy (draw calls, triangles, frame time from the monitors) and every effect starts from
  the conservative option. On-device measurement is Phase 7.7.
- The `SettingsService.quality` setting stays unwired in this slice.
- New/changed player-facing behaviour gets an e2e scenario in `tests/e2e/` (owner rule): at least a
  match started on River, a move and a shot through real input with the perspective camera.
- Screenshots of map A at zoomed-out and zoomed-in, with and without a selected unit, at the
  layout sizes (800×360 … 1280×800), shown to the owner in the browser next to the target frame.
- A draw-call and triangle count on map A at the widest zoom, recorded in `docs/`.
- Independent review pass for every implementation (CLAUDE.md §7).

## Docs to update in this slice

- CLAUDE.md §8 and `docs/art-direction.md`: perspective camera; no permanent grid; reflections
  allowed; ground is a continuous surface.
- `docs/reference/blitzkrieg.md`: the reference's terrain class costing 100 is water/riverbank,
  not built-up (found while researching this slice).

## Left to the builder

Exact tile layouts within the rules above; FOV, pitch range and zoom limits; texture resolution;
how the ground blend is built; whether static light is baked; number of tree/house variants
within the Tripo volume above; the out-of-bounds treatment; task order inside the slice — though
**maps first, then camera, then ground, then props, then weather** is the owner's stated
simple-to-complex order.
