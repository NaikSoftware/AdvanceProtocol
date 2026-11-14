# The battle HUD

The chrome around the board: what is always on screen, what a tap and a press-and-hold show, where
plates dock, and the handover gate and pause menu. It expands §1.5, §3.4 and §3.5 of CLAUDE.md.
What is drawn **on the board** (movement zones, fire and drone rings, crosshairs, engineer target
cells, HP bars and labels over units) is [overlays.md](overlays.md), not this file.

[back to CLAUDE.md](../../CLAUDE.md)

Three rules hold everywhere below:

- **The HUD computes no outcome.** Every number it shows (sector, damage bounds, heal,
  `armour_ignored`, `in_cover`, verb availability) arrives ready from `core/` through
  `InputController`. The only path to an action is Confirm → `InputController.confirm_pending()`.
- **It never covers a unit the player can see**, and it never dodges one the player cannot (see
  [Hidden information](#hidden-information)).
- **Nothing runs per frame.** Layout reruns on an event: selection, preview, mode change, the
  camera coming to rest (`Hud.VIEW_SETTLE_SECONDS`), an event batch, a resize.

1 dp is one logical pixel after `UiScale`. Sizes are fixed; the layout adapts from 800 × 360 to
1280 × 800 dp by anchoring to corners, never by scaling.

## Files

| file | owns |
| --- | --- |
| `game/ui/hud.gd`, `hud.tscn` | chip, pause, End turn, toast, modes, calls to docking and tag placement |
| `game/ui/hud/hud_docking.gd` | `HudDocking`: where the cluster, verb plate, armed strip and hold card go |
| `game/ui/hud/tag_placement.gd` | `TagPlacement`: where the unit tag goes, and its leader |
| `game/ui/hud/unit_screen_box.gd` | `UnitScreenBox`: screen rects of a `UnitView` as the engine draws it |
| `game/ui/hud/unit_tag.gd`, `hold_card.gd`, `preview_plate.gd`, `armed_strip.gd` | the plates |
| `game/ui/hud/armour_glyph.gd`, `drone_pips.gd` | drawn-by-code glyphs |
| `game/ui/hud/hud_bake.gd` | `HudBake`: bakes a plate into one texture, one draw call |
| `game/ui/engineer_panel.gd`, `drone_button.gd` | verb plate + verb strip; the Дрон button |
| `game/ui/handover_gate.gd`, `pause_menu.gd` | gate and pause |
| `game/ui/theme/hud_theme.tres` | the HUD theme; its header lists every type variation |

## Always on screen

| element | place | size (dp) | notes |
| --- | --- | --- | --- |
| player chip | top-left (24, 12) | 151 × 36 | player-colour bar, «Гравець N», «Хід N» |
| pause | top-right (right 24, top 8) | 48 × 48 | icon only |
| End turn | bottom-left (24, bottom 12) | 161 × 48 | fixed; nothing else docks there |

Idle chrome is about 4 % of a 985 × 442 screen. **Ground state is shown nowhere in the UI**: not on
the HUD, the gate or the pause menu. It is fixed per map
([§3.12](../rules/movement-and-terrain.md)), and every movement zone and move preview already
includes it. **Action points are shown nowhere either**, own or enemy: the gold and red
movement zones already show how far a unit can go.

## Tap and press-and-hold

A tap selects; a press-and-hold inspects. They show different things on purpose.

| | tap: **unit tag** | press-and-hold: **hold card** |
| --- | --- | --- |
| who | the selected unit | any visible unit, own or enemy |
| content | class silhouette · name · drone pips (squads) | owner-colour tab · name, class, silhouette · АТАКА / ДАЛЬНІСТЬ / ОГЛЯД · armour glyph + Лоб/Борт/Корма table, or «Броня немає» for infantry · drones row · floor caption |
| AP | never, own or enemy: the movement zones show the reach | never |
| HP | never: the board label is the HP number | never |
| place | beside the unit, by [tag placement](#unit-tag-placement) | top-left (24, 58) or top-right (right 24, top 64) |
| input | `MOUSE_FILTER_IGNORE` on the tag, its children and leader: a tap lands on the tile below | ignores input |

- **Drone pips are public** (§3.9): the tag and the hold card show them for any visible squad. The
  hold card keeps the drones row at 0 (two outlined pips), because the board drone marker hides at 0.
- **The floor caption** («Щонайменше: …») shows exactly when `Targeting.inspection()` returns
  `is_floor = true`; the view never re-derives it.
- **An engineer has no gun:** АТАКА and ДАЛЬНІСТЬ read «—», never 0 and 1.
- **The card is one width** (`HoldCard.WIDTH`) for every unit type and caption.
- **The card opens only for a unit that has a `UnitView`** for the active player; a press on a hidden
  unit shows nothing.
- **While the card is up, the selected unit's tag hides**, and comes back in the same spot on
  release. Any cluster, verb plate, strip or Дрон button under the card is hidden and taken out of
  input (`PROCESS_MODE_DISABLED`), so a second finger cannot reach an invisible Confirm.
- **Card corner:** the lower cost wins. Cost = overlap of the card (grown 8) with the held unit and
  its marks, plus ring arc length under the card × 4, plus 4 × overlap with the finger (press point
  ± 60). A tie goes to the corner farther from the finger (`HudDocking.choose_card`).

## Action previews

A shot, drone or unit-repair preview opens the cluster: the **preview plate** (285 wide, `plate_solid`) over the **action row**. A pending move and the clear-mine and bridge verbs have **no plate**: only the action row (Cancel, Confirm) shows, docked the same way with a zero-height plate.
Every value comes from `core/`:

| action | plate content | source |
| --- | --- | --- |
| move | no plate: the row alone | the zones already show the reach |
| shot | target row (owner-colour tab, name, «ЦІЛЬ») · glyph · «СЕКТОР БРОНІ» + sector word · «ШКОДА» `min–max` | `FireCommand.preview()`: `sector`, `min`, `max`, `armour_ignored`, `in_cover` |
| drone strike | target row · drone icon · «БРОНЯ» «не діє» · «ШКОДА» `120–180` | `Rules.drone_damage_bounds()` |
| repair unit | target row (own colour) · «МІЦНІСТЬ» `hp/max` · «РЕМОНТ» `min–max` | `EngineerCommand.repair_bounds()` |
| clear mine, repair or demolish bridge | no plate: the row alone, and Confirm carries the verb name and icon | no numbers: these verbs have none |
| lay mine | no preview: it executes on the tap | |

**Every shot shows its sector before Confirm** (§3.4), whoever shoots: a target that survives
turns onto the shooter, so the flank is spent whatever the damage.

| | target is a vehicle | target is `INFANTRY` |
| --- | --- | --- |
| glyph | `ArmourGlyph`, the `sector` wedge lit (turret drawn for `TANK`) | infantry silhouette: no armour to light |
| sector word | always | always |
| «броня не діє» under the word | when `armour_ignored` (an infantry shooter) | never |
| «УКРИТТЯ ½» marker | never: vehicles take no cover | when `in_cover` |

The target's class picks only the icon. The wedge, the note and the cover marker come from the
preview fields; the glyph's geometry never decides a sector.

## Cancel, Confirm and End turn

- **The action row** is [Cancel 126][16][Confirm 143] = 285, bottom-right by default. Confirm is the
  only element with a bone frame.
- **Confirm names the pending action**, word and icon together, set by `Hud.show_preview()` from the
  preview type: shot «Вогонь» / Fire (`btn_fire.svg`), drone «Удар» / Strike (`btn_drone.svg`), move
  «Рухатися» / Move (`btn_move.svg`), unit repair «Ремонтувати» / Repair (`btn_repair_unit.svg`), and
  the engineer verbs with their own name and icon (clear mine, repair bridge, demolish bridge).
  **One icon family:** every `btn_*.svg` is cropped so its ink is ~17.5 dp on its longest side inside
  one 18 dp box at ~1.5 dp stroke, so the button uses a single size with no per-action sizes. The
  plain `fire/drone/…svg` stay for the engineer tile and the Дрон button. **One gap:** ~10 dp from the
  ink edge to the word (a 9 dp box gap plus glyph side bearings); only the labels that would not fit at 800 dp (repair and demolish bridge) drop to
  8 dp, leaving ≥ 7 dp from the button's outer edge to the ink. The label is a localisation key in an auto-translating Label. The 143 dp width holds
  the longest label untruncated at all four probe sizes in both locales
  (`tests/game/test_hud_action_labels.gd`).
- **End turn is fixed bottom-left, and Confirm never docks there.** Confirm is tapped many times a
  turn and End turn once; the turn hand-off cannot be taken back, so a thumb aiming at Confirm must
  never land on it. No docking option puts the row bottom-left.
- **Exactly one Cancel when something can be cancelled.** The row's while a preview waits
  (`InputController.has_cancelable()`); the armed strip's while armed with nothing pending
  (`is_armed_waiting()`); none for a plain selection.
- **Armed strips** (drone or engineer verb armed) are [Cancel | armed cell], right-anchored,
  `ArmedStrip.MIN_WIDTH` 285 or wider, growing leftwards, **48 dp tall like the row**. **Cancel sits
  on the row's Cancel slot** with the same centred icon-and-word group, so it does not move between
  arming and the pending row,
  and the inert armed cell sits where Confirm appears one tap later. With Cancel on the right, a
  player backing out with a second tap would fire a drone or demolish a bridge. The armed cell stops
  the tap and does nothing; it does not fall through to the board.
- **The Дрон button** (own squad selected, nothing armed) takes the bottom-right slot, 133 × 48.
- **The toast** (an `ERR_*` refusal) sits right-aligned 8 dp above whatever occupies the
  bottom-right slot, or in the slot itself when it is empty. One at a time, 2.0 s, 150 ms fade.

## Docking

Every board-covering plate docks by a fixed order. There is no camera nudge: the order is the rule.

**Protected:** every visible unit's box (`UnitScreenBox.of`, grown `HudDocking.UNIT_MARGIN` 2 dp). A
plate that hides part of a unit is a defect, because the board label is the only HP number on
screen. **Targets** are kept clear by `TARGET_GROW` 8 dp: the previewed target with its crosshair,
the verb's target tile, or the move's path and destination.

| plate | order (`HudDocking`) |
| --- | --- |
| cluster (preview + row) | **a** plate over row, bottom-right → **a@4** same, targets grown only 4 → **b** row bottom-right, plate top-right (right 24, top 64) → **c** whole cluster top-right → **d** whole cluster top-left (24, 56) |
| engineer verb plate | bottom-right → bottom-left, 16 right of End turn |
| armed strip | bottom-right → top-right → top-left |

Take the first option that covers no unit and clears the targets. **a@4** keeps the plate and the
row together under the thumb when a target ends just short of the plate. When nothing is clear:
least unit overlap, then least target overlap, then the order. A verb plate that cannot clear arms
`InputController.tap_guard_ms` (`Hud.ENGINEER_TAP_GUARD_MS`) against a double tap through it.

## Unit tag placement

`TagPlacement` places the tag; `Hud._update_tag` runs it after selection, mode change, camera rest
and event batches. The tag follows its unit on pan; it is hidden while an event batch plays
(`Hud.hold_tag`).

1. **Hard obstacles.** Every other visible unit's box with its marks, all HUD chrome at its docked
   place (each grown `OBSTACLE_GROW` 8), the line of fire to a previewed target (grown 10), the safe
   area, and polygons grown `POLY_GROW` 5: an engineer's four target cells from selection on, and a
   pending move's path and destination. The tag stays ≥ `MIN_GAP` 8 from its own unit.
2. **Beside, no leader.** Each side of the unit box at 8 and 12 dp, slid in 11 steps, plus the
   corners. A leaderless tag must be ≥ 8 dp nearer its own unit than any other.
3. **With a leader.** Any 4-dp grid position more than `LEAD_AT` 12 dp from the model plus HP bar (`UnitScreenBox.core`), not the unit box, with a
   leader ≤ `MAX_LEAD` 60 dp. The leader is a 1-dp bone line ending in a 5 × 5 square on the unit's
   HP bar + model outline (`UnitScreenBox.core_poly`), never on the drone icon, or on a row of points just above the engine's
   HP label (the gap the engineer's cells leave open), never on the label itself. It stays 4 dp
   off other units and **does not cross a polygon from rule 1**, so its end never reads as a
   waypoint. Only when no spot exists at that level may the leader cross an engineer's target cell;
   its end square then still stays out of every target cell (square's half-diagonal plus `END_CLEAR` 2 dp from the cell) and lands on the
   unit-box edge farthest from them. The last resort ignores the polygons for the tag.
4. **Score, lowest wins.** Contour and ring overlap under the tag weighs most (`MARK_WEIGHT`), then
   contour corners under it, distance, a leader (a leader touching a contour adds `TOUCH_COST` 300; past `LONG_LEAD_FROM` 40 dp each dp costs `LONG_LEAD_PER_DP` 12), crowding another unit or the chrome, and reading
   nearer another unit than its own. A tag both within `CROWD_AIR` 12 dp of another unit and nearer
   to it than to its own pays `NEAR_OTHER_CROWDED_COST` 6000, more than any contour or corner cover,
   so it reads as that unit's label only when no other spot exists. The weights are the constants at the top of `TagPlacement`.
5. **Hysteresis.** The tag keeps its offset from its unit while that rect stays legal at the level
   it was found at, and moves when it becomes illegal or when a spot kept under relaxed rules has a
   stricter level that now finds one, or when it covers zone contours or ring arcs and a fresh
   search finds a spot covering less (a first selection made while the camera was still easing
   must end where a later identical selection does). That cover-based re-search runs only after a
   camera pan or zoom settles, never on a mode change (drone, verb, preview), so arming the drone
   does not move the tag. This departs from the design spec's rule 5, which recomputes only when
   the rect becomes illegal. Because an engineer's target cells are
   obstacles from selection on, arming a verb never moves its tag.

With no legal spot at any level the tag hides rather than covering a unit or a plate.

## Hidden information

Everything placed or dodged on screen uses **only units that have a `UnitView` for the active
player** (`BattleScreen` creates one only when `state.can_see_unit(viewer, unit)`). Never build
obstacles, protected boxes or "nearest other unit" from `state.units`: a tag or plate that dodges an
invisible enemy shows where it stands, the same leak §3.2 forbids for routes.

- AP is never shown for anyone, in the tag, the card or any plate; a test scans every Label under the HUD.
- `Hud.set_active_player` clears the selection and preview when the player changes, so nothing of
  the previous player survives a hand-off for even a frame.
- Engineer verbs and the Дрон button appear only for the active player's own unit.

## Colour, type and theme

Colour tokens (Godot `Color` hex):

| token | value | use |
| --- | --- | --- |
| `plate` | `121516e6` (90 %) | chip, pause, End turn, Cancel, Дрон |
| `plate_solid` | `121516` | every plate that carries rule numbers or verbs |
| edges | top `575e61`, bottom `040505`, side `2f3537` | 1 dp each, the plate's hardware edge |
| `hair` | `3a4043` | dividers inside a plate |
| `press` | `1e2325` | pressed fill |
| `text` (bone) | `e3dfd3` | labels, numbers, lit armour wedge, primary frame |
| `dim` | `8f918a` | captions, `/48`, muted verbs, silhouettes |
| `p1` / `p2` / `p3` | `3a6ea5` / `a54a3a` / `5a8a4a` | `UnitView.PLAYER_COLORS`: chip bar, target and card tabs, gate rules |
| gate scrim | `0d1013` | under the gate plate |

**Hue is reserved for rules.** The chrome is neutral grey and bone. Gold and red belong to the
movement zones on the board and never appear in the chrome. Player colours mark ownership only and
are **never a text colour**.

**Plates** are 8 × 8 9-slice textures (`game/ui/theme/plate*.png`, `StyleBoxTexture`, margins 3):
`texture_filter = NEAREST` on each plate `Control`, `LINEAR` on icons and labels. A plate button
(`HudKit.group_content`) keeps its icon and label in `LINEAR` children, since a button draws its native icon with its own filter. A linear-filtered plate shows
a 2–3 px gradient at its edge instead of a crisp 1-dp line.

**One family: Fira Sans Condensed** 500 / 600 / 700. Every number uses a `FontVariation` with
OpenType `tnum = 1` and `kern = 0`, so «1111» is as wide as «0000» and stats and the
armour table do not jitter. `kern = 0` is required too: Fira kerns pairs of tabular ones. The type
variations (`HudCaption`, `HudNumber*`, `HudPrimaryButton`, …) and their weights and sizes are
listed in the header of `hud_theme.tres`. The theme is HUD-scoped; `ap_theme.tres` (menus) is
separate.

**Strings** live in `assets/i18n/strings.csv` (`hud_*`, `handover_*`, `pause_*`, `eng_*`, `ERR_*`).
HUD uk strings use `ʼ` (U+02BC) as the apostrophe.

**Draw calls are a hard budget:** selecting a unit may add at most 4 and a shot preview at most 8
over the same scene on the old HUD (the commit before the rebuild, `922fa30e`; the measured baseline is in the header of `tools/hud_budget.gd`). The tag and the preview plate are `HudBake` plates for this
reason. Measure one run at a time with `tools/godot_run.sh --solo --path . res://tools/hud_budget.tscn
-- <map>`; its header holds the baseline.

## Handover gate and pause

The gate is opaque from its first frame, not skippable, and lifts only after the camera has
recentred on the incoming player's first unit and enemy views are rebuilt for their `seen` (the
ordering contract in the header of `handover_gate.gd`, §3.5).

- **Backdrop:** a per-map mood plate, `assets/ui/gate/<map>.webp` (1600 × 720), named after the map
  resource (`maps/river.tres` → `river.webp`). A map without one (the map editor makes new maps)
  falls back to `default.webp`, a generic dark plate. **Never a runtime render of the board.**
- **Stack:** «ПЕРЕДАЙТЕ ПРИСТРІЙ» · nameplate (6-dp player-colour rules, «Гравець N» 700/40, a
  player-colour horizon line behind it) · info plate [ХІД][КАРТА] · «Готово». Nameplate and info plate share one width, at least
  `HandoverGate.MIN_WIDTH` 400 on every map.
- **Team strength** (`game/ui/gate_strength.gd`), no numbers, labels or icons, not in the pause menu. The starting total is recorded by `BattleState.start()` (`start_hp`) and saved; a state without it derives the sum from unit max HP.
  The share is core's `BattleState.team_hp(p) / team_hp_start(p)`: current HP of the player's living
  units over the max HP of every unit they started with; the view only maps ints to widths.
  - **Two players (A):** the horizon line is replaced by two 2-dp lines out from the nameplate,
    left = Player 1, right = Player 2, each in its player colour. Solid for the remaining share, the
    rest a dotted `#3a4043` line (dots on whole device pixels, one gap's width left before the solid
    end and before the square), an 8 × 8 player-colour square at the outer end. They open with the
    entrance tween like the horizon did.
  - **Three players (C):** the horizon stays (incoming player's colour). A 4-dp bar runs along the
    bottom edge of the info plate, exactly its width: one segment per living player in turn order,
    each as wide as its share of all teams' remaining HP, 2-dp dark gaps, 1-dp bone ticks at the
    thirds, both always drawn (a tick within 2 dp of a gap snaps onto the gap), snapped to whole
    device pixels at one width. An eliminated player has no segment. It shows the balance only: two crippled teams read
    alike.
  - It uses every team's true HP, so it reveals aggregate losses the viewer did not witness.
    Accepted.
- **Entrance:** one 350-ms tween moves the accents only; «Готово» ignores input until it ends, so the
  outgoing player's double tap on End turn cannot also lift the gate.
- **Pause:** opaque, over the same map plate; «Пауза» + map name, Продовжити (primary),
  Налаштування, Зберегти й вийти, and a muted, unfilled Здатися with its own confirmation. The info
  line shows only «Хід 3».

### Baking a plate for a new map

A plate is baked offline from a capture with **no units in it**, so it cannot leak a position:

```bash
tools/godot_run.sh --path . res://tools/hud_shot.tscn -- <dir> <map> 1600x720 uk mood hud=off
python3 -I tools/bake_gate.py <dir>/<map>_1600x720_mood_nohud.png assets/ui/gate/<map>.webp [--rain]
tools/godot_run.sh --headless --path . --import && git checkout project.godot
```

State `mood` removes every unit and centres the camera on the board at zoom 16. `bake_gate.py`
removes the red board-edge line, darkens by about 55 %, takes 35 % of the chroma (the player colour
owns the hue), and adds scrims to `0d1013` at the bottom and top. `--rain` adds streaks for a rainy
map; `--band` darkens a soft band behind the caption when a pale wall sits under it. Check the
printed luminance against the shipped plates (River: mean 24, max 60; Crossroads 30 / 118; Ridge
33 / 95) and the caption contrast on a `handover` capture before committing.

## Capturing HUD frames

`tools/hud_shot.gd` drives the real battle screen through the real input path
(`select_unit`, `tap_cell`, `arm_engineer`, `arm_drone`, `peek_cell`), so a frame shows exactly what a
player sees. Run it windowed, never `--headless`:

```bash
tools/godot_run.sh --path . res://tools/hud_shot.tscn -- <out_dir> <map> <WxH> <locale> <states|all> [hud=on|off|both] --ui-dpi=<N>
```

| target | window | `--ui-dpi` | logical size |
| --- | --- | --- | --- |
| phone | 1496x672 | 243 | ≈ 985 × 442 dp |
| strict minimum | 1600x720 | 320 | 800 × 360 dp |

States are listed in `STATES` at the top of `tools/hud_shot.gd` (`idle`, `own_tank`, `move_preview`,
`shot_preview`, `engineer`, `engineer_armed`, `engineer_pending`, `squad`, `drone`,
`drone_preview`, `hold_enemy`, `hold_enemy_squad`, `pause`, `handover`, `mood`, toasts and more).
Files land as `<out_dir>/<map>_<WxH>_<state>[_nohud][_<locale>].png`. `tools/hud_shots.sh
<out_dir>` captures the full set for River and Crossroads and a subset for Ridge, at both sizes, plus an
English pass.

When reviewing frames: check both sizes, compare each state with the previous capture of the same
state, sample plate edge rows for a crisp 1-dp edge, and check every engineer-state leader against
the target cells.
