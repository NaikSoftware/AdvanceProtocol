# Replay of the Opponents' Turns: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After the handover gate, the incoming player watches a fast, fog-filtered replay of the
opponents' turns since their own last turn, styled as reconnaissance-drone footage.

**Architecture:** `MatchService` logs every applied command and snapshots the state at each
player's end of turn. `core/` re-runs a viewer's span on a copy, and a per-viewer filter cuts the
events into visible beats, each carrying the state after it. `battle_screen.gd` plays the beats
through the existing `EventPlayer` under a faster `Engine.time_scale`, reading the beat's state in
place of the live one, under a drone-feed overlay.

**Tech Stack:** Godot 4.7.2, typed GDScript, GUT (`./run_tests.sh`, needs `$GODOT`).

**Spec:** `docs/superpowers/specs/2026-11-14-enemy-turn-replay-design.md`. Read it first. Its
rules table is the contract for Task 3.

## Global Constraints

- `core/` imports no Node types and never calls global `randi()` / `randf()`. Every roll goes
  through the state's RNG (CLAUDE.md §6).
- Typed GDScript everywhere. `snake_case` files, `PascalCase` `class_name`.
- Comments in `core/` are in Ukrainian and explain why. No dates, task numbers, "owner ruling" or
  history in comments or docs. Grep the diff for them before every commit.
- Every display string goes in `assets/i18n/strings.csv` (`keys,uk,en`), in Ukrainian and English.
- Tap targets ≥ 48 dp, inside the safe area.
- No AP numbers and no ground state anywhere in the replay UI.
- It must run on `gl_compatibility`, with small visual differences accepted.
- Tests: `./run_tests.sh -gtest=res://tests/<path>.gd`. The full suite is `./run_tests.sh`. Check
  that the "Scripts" count includes every new test file: GUT silently skips files that fail to
  parse. `--import` rewrites `project.godot`, so run `git checkout project.godot` after any run.
- Godot launches: ≤ 180 s each, ≤ 2 at once (`tools/godot_run.sh`).
- **`MatchService.state` is never replaced by a replay copy.** `submit()` always acts on the real
  state.

## Review Focus

1. **Leaving mid-replay** (pause, save and exit, the screen freed) must restore
   `Engine.time_scale = 1.0`. Otherwise the menu and the next match run fast. Test in Task 6.
2. **A save from before this feature, or with a corrupt `.replay` sidecar,** loads with no replay
   and no error. Test in Task 4.
3. **A tap or Skip during the camera flight, or Skip pressed twice,** ends the replay exactly once.
   After it, a board tap acts on the real state. Test in Task 6.
4. **Viewer units that die inside the span** are drawn alive at the start and die on screen. Their
   ids then vanish from every later lookup without a null crash. Tests in Tasks 3 and 6.
5. **A squad that goes into cover and comes out again in the same span** is hidden only up to the
   move that put it in cover. Test in Task 3.

---

### Task 1: Command serialisation

**Files:**
- Create: `core/commands/command_codec.gd`
- Test: `tests/core/test_command_codec.gd`

**Interfaces:**
- Produces: `class_name CommandCodec`, with
  `static func to_dict(c: Command) -> Dictionary` and
  `static func from_dict(d: Dictionary) -> Command`. The latter returns `null` for an unknown
  kind or missing or mistyped fields.
- Dict shape: `{"kind": <String>, ...fields}`. Kinds and fields:
  - `move`: `unit_id`, `x`, `y`
  - `turn`: `unit_id`, `x`, `y`
  - `fire`: `unit_id`, `target_id`
  - `drone`: `unit_id`, `target_id`
  - `engineer`: `unit_id`, `action`, `x`, `y`
  - `end_turn`
  - `concede`

- [ ] **Step 1: Write the failing tests.**
  - `test_every_command_round_trips`: for one instance of each of the seven commands,
    `from_dict(to_dict(c))` has the same script and the same fields.
  - `test_round_trip_survives_json`: same as above, but through
    `JSON.parse_string(JSON.stringify(d))`. JSON turns ints into floats, so `from_dict` must accept
    whole floats.
  - `test_unknown_kind_is_null`.
  - `test_missing_field_is_null`.
  - `test_engineer_action_out_of_enum_is_null`.
- [ ] **Step 2: Run them.** `./run_tests.sh -gtest=res://tests/core/test_command_codec.gd`.
  Expected: FAIL, `CommandCodec` not found.
- [ ] **Step 3: Implement `CommandCodec`.** Build the commands with their existing `create(...)`
  constructors.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(core): серіалізація команд`

### Task 2: Command log, snapshots and re-run

**Files:**
- Create: `core/replay_log.gd`
- Test: `tests/core/test_replay_log.gd`

**Interfaces:**
- Consumes: `CommandCodec` (Task 1), `BattleSerializer.to_dict/from_dict`.
- Produces `class_name ReplayLog extends RefCounted`:
  - `func mark(player: int, state: BattleState) -> void`: snapshots `state` for `player` at the
    current end of the log, replacing that player's earlier snapshot, then trims commands older
    than the oldest snapshot.
  - `func record(c: Command) -> void`: appends an applied command.
  - `func span(viewer: int) -> Array[Command]`: the commands since the viewer's snapshot. Empty if
    there is none.
  - `func rerun(viewer: int) -> Array[Dictionary]`: restores the viewer's snapshot and applies
    `span(viewer)` in order. Each command is asserted valid before it is applied. The result has
    one entry per command: `{"actor": int, "turn": int, "events": Array[Events.BattleEvent],
    "after": BattleState}`. `actor` and `turn` are the active player and turn number before the
    command. `after` is an independent copy (`from_dict(to_dict(...))`) taken after it. The
    result is empty if there is no snapshot.
  - `func start_state(viewer: int) -> BattleState`: a fresh copy of the viewer's snapshot.
  - `func to_dict() -> Dictionary` and `static func from_dict(d: Dictionary) -> ReplayLog`. The
    latter returns `null` if anything is invalid.

- [ ] **Step 1: Write the failing tests.** Use the open-map fixture style of
  `tests/core/test_full_match.gd`, and play only through commands.
  - `test_span_is_commands_since_viewers_snapshot`: marks for players 0 and 1, then
    moves, fires and end-turns. `span(1)` holds exactly the commands after `mark(1, ...)`.
  - `test_rerun_reaches_the_real_state`: play a turn with a move, a shot with a random roll, and
    end turn. The last entry's `after` gives the same
    `JSON.stringify(BattleSerializer.to_dict(...), "", true)` as the real state.
  - `test_rerun_after_copies_are_independent`: changing one entry's `after` leaves the others
    unchanged.
  - `test_mark_trims_behind_oldest_snapshot`.
  - `test_round_trip_through_json_keeps_rerun_equal`.
  - `test_invalid_dict_is_null`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement `ReplayLog`.** Store the snapshots as `BattleSerializer.to_dict`
  dictionaries keyed by player, each with its absolute command index.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(core): журнал команд і повторний прогін для повтору`

### Task 3: Per-viewer replay filter, and the rules docs

**Files:**
- Create: `core/replay_filter.gd`
- Test: `tests/core/test_replay_filter.gd`
- Modify: `CLAUDE.md` §3.5 (one bullet), `docs/rules/vision-and-fog.md` (new section "Replay of
  the opponents' turns" with the spec's rules table), `docs/reference/blitzkrieg.md` (the
  finding: the original has no replay, its AI turn pans the camera across fog, and hot-seat shows
  only a black screen; cite `class_2.java:494-498`, `794-796` and `GameCanvas.java:2015-2035`),
  and `docs/architecture.md` (a replay filter exists; the live per-observer filter for online
  still does not).

**Interfaces:**
- Consumes: `ReplayLog.rerun()` and `ReplayLog.start_state()` (Task 2), and
  `BattleState.can_see_unit()`, `Rules.in_cover()`, `Vision.is_seen()`.
- Produces `class_name ReplayFilter`:
  - `class Appeared extends Events.BattleEvent`: `unit_id: int`, `pos: Vector2i`, `facing: int`.
    The unit comes into view here.
  - `class Vanished extends Events.BattleEvent`: `unit_id: int`. The unit goes out of view.
  - `class Beat`: `events: Array[Events.BattleEvent]`, `focus: Vector2i`, `actor: int`,
    `turn: int`, `after: BattleState`.
  - `class Result`: `start: BattleState`, `beats: Array[Beat]`.
  - `static func build(log: ReplayLog, viewer: int) -> Result`. It returns `null` when there is no
    visible beat, when the span contains `MatchEnded`, or when the viewer has no snapshot.

**What the filter keeps:** everything the spec's rules table shows, by event type. Visibility is
evaluated per step, on the copy's state at that point. Moves use the board kind, the viewer's
`seen`, and the `UnitFound` events with `at_step` for the viewer. Shots use the state after the
command, because the hit reveal has already landed then.

| event | kept when |
| --- | --- |
| `UnitMoved` | cut into maximal runs of visible steps. `Appeared` comes before a run that starts from the fog, `Vanished` after a run that ends before the path does |
| `UnitTurned`, `MoveBlocked`, `UnitRepaired` | the actor is visible |
| `ShotFired`, `ShotRetaliated`, `DroneLaunched` | the shooter or the target is visible, or the target is the viewer's |
| `DamageDealt`, `UnitDestroyed`, `WreckLeft` | the unit is visible or the viewer's |
| `MineTriggered` | the mine was the viewer's, or the unit is visible |
| `MineCleared` | the mine was the viewer's and the engineer is visible |
| `MinePlaced`, `MineRevealed`, `ApChanged`, `TileRevealed` for other sides | never |
| `TileRevealed` / `UnitFound` for the viewer | always |
| `BridgeChanged` | the engineer is visible, or a viewer's unit died with the bridge |
| `ForestBroken`, `WreckRemoved` | the tile is in the viewer's `seen` |
| `TurnEnded`, `TurnStarted`, `PlayerEliminated` | dropped from beats. `actor` and `turn` carry the label |

- **Cover look-ahead.** For each squad, find its last move in the span that ends with it in cover
  and not found by the viewer. Drop every movement event of that squad up to and including that
  move. If it was visible at that point, emit `Vanished` at its first move.
- **The span ends at `TurnStarted(viewer)`.** Everything from it on belongs to the live turn
  start and is not replayed.
- A command with no kept event makes no beat. Its effects reach the screen only through the next
  beat's `after` and the final rebuild.
- `focus`: the first kept event's tile. For a shot, use the shooter's tile if the shooter is
  visible, otherwise the target's.

- [ ] **Step 1: Write the failing tests**, one for each row of the spec's table, on small boards
  built in the test:
  - `test_move_on_seen_ground_is_shown_whole`
  - `test_move_from_fog_appears_at_the_fog_edge`
  - `test_move_into_fog_vanishes_at_the_edge`
  - `test_move_entirely_in_fog_makes_no_beat`
  - `test_squad_ending_hidden_in_building_shows_no_move_even_over_two_commands`
  - `test_squad_crossing_a_building_is_hidden_only_inside`
  - `test_squad_leaving_cover_later_in_span_is_shown_from_that_move`
  - `test_shot_at_viewer_unit_from_fog_is_shown_with_shooter_appeared`
  - `test_viewer_retaliation_is_shown`
  - `test_bridge_demolished_under_viewer_unit_by_unseen_engineer_shows_collapse_not_engineer`
  - `test_enemy_on_viewer_mine_in_fog_shows_blast_without_unit`
  - `test_viewer_mine_cleared_by_unseen_engineer_is_not_shown`
  - `test_mine_laying_is_never_shown`
  - `test_three_players_visible_shooter_into_fog_keeps_no_target_events`
  - `test_three_players_unseen_shooter_on_visible_unit_has_no_shooter_appeared`
  - `test_ap_changed_never_kept`
  - `test_viewer_unit_killed_in_span_is_alive_in_start_and_destroyed_in_beats`
  - `test_three_players_span_holds_both_turns_in_order`
  - `test_first_player_first_turn_has_no_replay`
  - `test_match_ended_in_span_gives_null`
  - `test_nothing_visible_gives_null`
  - `test_events_after_viewers_turn_started_are_cut`
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement `ReplayFilter.build`.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Update the four docs above.** Grep `docs/` for other places that describe what a
  player learns between turns, and update them too.
- [ ] **Step 6: Commit.** `feat(core): фільтр повтору за тим, хто дивиться; правила туману`

### Task 4: MatchService recording and save

**Files:**
- Modify: `game/autoload/match_service.gd` (`start_match`, `begin`, `submit`, `save_current`,
  `delete_save`, `load_saved`)
- Test: `tests/game/test_match_service.gd` (extend)

**Interfaces:**
- Consumes: `ReplayLog` (Task 2), `ReplayFilter.build` (Task 3).
- Produces:
  - `var replay_log: ReplayLog`, reset in `start_match`.
  - `func replay_for(viewer: int) -> ReplayFilter.Result`. In debug builds it asserts that the last
    re-run state equals `state` (sorted JSON of `to_dict`).
- Recording:
  - In `begin()`, after `begin_turn()`, mark every player other than the active one.
  - In `submit()`, before applying an `EndTurnCommand` or `ConcedeCommand`, call
    `mark(state.active_player, state)`.
  - After every successful apply, call `record(command)`.
- Save: `path + ".replay"` holds `JSON.stringify(replay_log.to_dict())`. On load, a missing or
  invalid sidecar gives a fresh `ReplayLog`, which means no replay.

- [ ] **Step 1: Write the failing tests.**
  - `test_replay_for_second_player_after_first_turn`
  - `test_replay_survives_save_and_load`
  - `test_old_save_without_sidecar_loads_with_no_replay`
  - `test_corrupt_sidecar_loads_with_no_replay`
  - `test_delete_save_removes_sidecar`
  - `test_rejected_command_is_not_recorded`
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: Run them, then the full suite.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(match): запис команд і збереження повтору`

### Task 5: Battle screen reads an explicit viewer and state

Behaviour-preserving refactor. It is reviewable on its own: nothing visible changes.

**Files:**
- Modify: `game/battle/battle_screen.gd`

**Interfaces:**
- Produces, in `battle_screen.gd`:
  - `func _state() -> BattleState`: returns `_replay_state` when it is set, otherwise
    `_match_service.state`.
  - `func _viewer() -> int`: returns `_replay_viewer` when `_replay_state` is set, otherwise
    `_state().active_player`.
  - `var _replay_state: BattleState = null` and `var _replay_viewer: int = -1`.
- Every read in `battle_screen.gd` that decides what is drawn, or feeds `EventPlayer` lookups and
  callbacks, goes through these two. That covers units, wrecks, mines, forest, roofs, the board
  rebuild, `_unit_for()` and `EventPlayer.viewer`. Calls that act on the match (`submit`, `save`)
  keep using `_match_service`.
- `input_controller.gd` and `hud.gd` are not changed. During the replay the HUD is hidden and the
  board takes no input (Task 6).

- [ ] **Step 1: Run the full suite** to record the baseline pass count.
- [ ] **Step 2: Route the reads through `_state()` / `_viewer()`.**
- [ ] **Step 3: Run the full suite.** Expected: the same count, all passing.
- [ ] **Step 4: Commit.** `refactor(battle): явний глядач і джерело стану на екрані бою`

### Task 6: Replay playback

**Files:**
- Modify: `game/battle/battle_screen.gd` (`_on_gate_confirmed`, new `_play_replay`,
  `_end_replay`, `_exit_tree` or the existing exit path), `game/battle/event_player.gd`
- Test: `tests/game/test_battle_screen.gd` (extend), `tests/e2e/test_replay_e2e.gd` (new, using
  `tests/e2e/e2e_helpers.gd`)

**Interfaces:**
- Consumes: `MatchService.replay_for` (Task 4), `_state()` / `_viewer()` (Task 5), and
  `ReplayFilter.Appeared` / `Vanished` / `Beat` (Task 3).
- `EventPlayer` gains:
  - Two constructor callables, `unit_appeared(unit_id: int, pos: Vector2i, facing: int)` and
    `unit_vanished(unit_id: int)`, dispatched for the two new events.
  - `func cancel() -> void`: ends the current `play()` early and leaves the player usable.
    `stop()` stays terminal, for when the screen leaves.
- Constants in `battle_screen.gd`: `REPLAY_SPEED: float = 2.5` and
  `REPLAY_FAST_FORWARD: float = 20.0`, both applied through `Engine.time_scale`.

**Flow.** On gate confirm:

1. Call `replay_for(active)`. If it returns `null`, keep today's path unchanged.
2. Otherwise set `_replay_state = result.start` and `_replay_viewer = active`. Clear `BattleFx`
   and rebuild units, wrecks, mines, board and forest from `_state()` for `_viewer()`.
3. Hide the HUD, show the overlay (Task 7), `center_on(beats[0].focus)`, and only then hide the
   gate. The gate contract still holds.
4. Set `Engine.time_scale = REPLAY_SPEED`. For each beat:
   - set `_replay_state = beat.after`, the same as live play, where the state is already
     post-command while its events play;
   - `await` `fly_to(beat.focus)`;
   - `await` `_event_player.play(beat.events)`.

   Nothing is rebuilt between beats.
5. `_end_replay()`: set `Engine.time_scale = 1.0`, clear `_replay_state`, hide the overlay, show
   the HUD, clear `BattleFx`, rebuild everything from the real state, and `center_on` the
   viewer's first unit.

**Input during the replay:**
- A tap anywhere sets `REPLAY_FAST_FORWARD` until the current beat finishes.
- Skip calls `_event_player.cancel()`, then `_end_replay()`, exactly once.
- Board taps never reach `InputController`.

- [ ] **Step 1: Write the failing tests.**
  - `test_gate_confirm_with_replay_hides_gate_only_after_camera_is_on_first_focus`
  - `test_replay_ends_on_real_state_and_first_unit`
  - `test_skip_twice_ends_replay_once`
  - `test_tap_during_replay_never_submits`
  - `test_time_scale_restored_when_screen_exits_mid_replay`
  - `test_viewer_unit_killed_in_span_dies_on_screen`
  - `test_appeared_creates_and_vanished_frees_a_unit_view`
  - `test_no_replay_keeps_todays_gate_flow`
  - e2e `test_two_player_turn_is_replayed_after_gate`
  - e2e `test_three_player_replay_shows_both_opponents`
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement the flow above.**
- [ ] **Step 4: Run the new tests, then the full suite.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(battle): повтор ходів противників після гейта`

### Task 7: Drone-footage look

**Files:**
- Create: `game/ui/replay_overlay.tscn`, `game/ui/replay_overlay.gd`, and a grade shader under
  `game/battle/shaders/`
- Modify: `game/battle/battle_screen.tscn` (an overlay `CanvasLayer` under the gate's layer),
  `assets/i18n/strings.csv`
- Test: `tests/game/test_replay_overlay.gd`

**Interfaces:**
- Consumes: called from Task 6's `_play_replay` / `_end_replay`.
- Produces `class_name ReplayOverlay`:
  - `func begin(total_beats: int) -> void`
  - `func show_beat(index: int, actor: int, turn: int) -> void`
  - `func finish() -> void`
  - `signal skip_pressed`
- Strings: `replay_rec` = «ЗАПИС» / "REC"; `replay_turn` = «Хід %d · Гравець %d» /
  "Turn %d · Player %d"; `replay_skip` = «Пропустити» / "Skip".
- What the overlay shows, per the spec's Look section:
  - a muted, slightly cold grade, light grain, light vignette;
  - corner brackets, a red dot with REC, a running timecode on the replay's own clock;
  - the turn label;
  - the Skip button, ≥ 48 dp, inside the safe area.

  Units and side markers keep their colour. The fallback is to grade the 3D world only, with the
  markers on a layer above it. Any progress shown counts beats only.

- [ ] **Step 1: Write the failing tests.**
  - `test_skip_button_is_at_least_48dp_and_inside_safe_area`
  - `test_labels_come_from_translation_keys`
  - `test_progress_counts_beats_only`
  - `test_finish_hides_everything`
- [ ] **Step 2: Implement it.** The implementer judges its own frames at both zooms first, on
  River and Crossroads, with the Mobile renderer and `gl_compatibility`.
- [ ] **Step 3: Visual-critic pass** on those frames, in light and dark scenes. Unit silhouettes
  and sides must read at ~100 px.
- [ ] **Step 4: Run the full suite.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(ui): вигляд повтору як запис із дрона`
