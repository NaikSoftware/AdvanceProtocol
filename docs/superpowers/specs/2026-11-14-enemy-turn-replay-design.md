# Replay of the opponents' turns

After the handover gate, the incoming player watches a fast replay of what the opponents did since
that player's last turn, limited to what their side could see at the moment it happened. It is
styled as reconnaissance-drone footage.

## Intent

Hot-seat today shows nothing of the opponent's turn: the gate goes up, the gate comes down, and the
board has changed. A tank is gone and you have to work out what killed it. The replay gives the
player the story of the turn they missed, and it is atmosphere (pillar 4): you watch your own
recon footage of the enemy advancing.

It must never show more than the player's side was entitled to see (pillar 2). The drone-footage
look carries this inside the fiction: this is what your reconnaissance recorded, so it shows only
ground your side has scouted.

**The original game does not have this.** Against the AI, the AI's turn plays live: the camera
pans to each acting unit, even across fog, which tells you where the unseen enemy is. A Skip key
makes the rest of the turn instant. Hot-seat has only a black "Player N takes turn" screen, with no
replay (`class_2.java:494-498`, `794-796`; `GameCanvas.java:2015-2035`). This finding goes into
`docs/reference/blitzkrieg.md`, and the live camera pan is recorded there as a leak this design
avoids.

## Goals

- After the gate, the incoming player sees every opponent action their side could see at the
  moment it happened, in order, fast, with the camera moving from one action to the next.
- Everything that hit the player's own units or mines is shown.
- The player can skip ahead or skip the whole replay.
- It survives save and Continue.

## Non-goals

- Re-watching a replay later in your own turn, rewinding, or pausing on a frame.
- Replaying your own turn.
- AI and online play. The per-viewer filter is written so online can reuse it, but nothing else is
  built for online.
- Sound. A drone-feed sound bed may come later, through the audio brief.

## Anti-goals: the replay fails, however well it plays, if

- it takes time, moves the camera, increments a counter or pauses for an action the viewer may not
  see. Silence would reveal that something happened there.
- the camera ever starts on, passes over, or lingers near ground where an unseen action took place.
- it shows a squad entering a building where it is hidden (§3.5, cover in buildings).
- it shows anything to a player other than the one who confirmed the gate.

## Rules: what the viewer sees

This changes §3.5. Update `CLAUDE.md` §3.5 and `docs/rules/vision-and-fog.md` with it, as a new
section on the replay.

**Ground scouted once stays scouted** (§3.5), so an enemy on `seen` ground is visible at every
moment of its turn. The replay shows exactly what the viewer would have seen watching live, and no
more. One thing is new knowledge: **an enemy route across scouted ground is now visible**, including
where the unit left it for the fog. This is intended, because it makes scouting worth more. By
mid-match most of the board is `seen`, and the replay hides little beyond mines and squads in cover.

**One rule decides each action: it is shown if the viewer can see the actor at that moment
(`BattleState.can_see_unit(viewer, actor)`, evaluated on the state at that step), or if it hit
something of the viewer's.** In detail:

| case | shown |
| --- | --- |
| enemy move | only the steps on tiles where the viewer can see the unit; it appears out of the fog and vanishes into it at the edge |
| a squad that **ends any move** hidden in a building | none of its movement in the span up to that move is shown, even if it got there in several separate moves (§3.2): it vanishes from the tile it stood on at the start of the span, when its first move starts. The viewer learns what they would learn today: it was there, now it is gone. Showing the earlier moves would name the building it walked up to |
| a move that passes through a building tile and leaves it | the per-step rule applies: hidden while in cover and not found, visible again after |
| a shot or drone strike at the viewer's unit | always. The shooter is revealed by the existing hit rule (§3.3.1) before the damage lands, so it shows on its tile |
| the viewer's unit retaliating | always, as part of that exchange |
| a bridge demolished under the viewer's unit | the collapse and the unit's death, always. The engineer only if the viewer can see it: there is no hit-reveal for engineers (§3.3.1 covers shots) |
| an enemy unit detonating **the viewer's** mine | the blast on the mine's tile, always: the viewer knows where the mine was and will see that it is gone. The unit only if it is visible there |
| the viewer's mine cleared by an engineer the viewer cannot see | not shown. The mine is simply gone at the end, as today |
| a bridge demolished, forest broken, wreck left, by an actor the viewer cannot see | not shown. The end state applies when the replay ends, as today |
| an exchange between two opponents (three players) | each unit by its own visibility. A visible shooter firing into the fog: the shot leaves, the target is not drawn and no numbers show. An unseen shooter hitting a visible unit: the tracer comes in out of the fog, and the hit, the damage, the turn and any wreck show on the target. The shooter itself is not drawn. The bearing the tracer gives away is accepted: the target turns onto its attacker anyway (§3.4), and hit effects already follow the shooter's weapon class whoever can see it |
| turning in place | by the same actor rule |

**Fogged actions take zero time.** They produce no frame, no camera move and no count.

**Scope in time:** everything from the viewer's last end of turn to the start of their new turn. With
three players this is two opponents' turns, played in order. Eliminated opponents' turns are
included up to their elimination. The first player of a match has no replay on turn 1. If nothing
is visible, there is no replay and the turn starts as today.

**When the match ends inside the span** (the last opponent falls, or the viewer is eliminated),
there is no replay: the results screen comes up as today. An eliminated player has no turn, so no
replay either. A "how it ended" replay may come later.

## Playback

- It starts **after** the gate is confirmed and before the turn begins. The gate contract
  (`game/ui/handover_gate.gd`) still holds: nothing of the previous player's view may show when the
  gate lifts. The replay runs on a copy of the viewer's world at the start of the replayed span (see
  Architecture), and its first camera position is the first visible action, never the previous
  player's camera.
- It plays by itself, fast: about 2.5× the live speed of moves, shots and effects. The exact factor
  is left to the builder and tuned on the device. The camera pans between actions at the fixed
  angle, keeping the player's zoom clamped to a readable range.
- **A tap anywhere** jumps to the next visible action. A **«Пропустити» / "Skip"** button (≥ 48 dp,
  inside the safe area) ends the replay. Nothing in the replay is time-sensitive (pillar 1). It
  plays on its own because it is presentation, not a rule.
- When it ends (or is skipped), the board shows the true current state for the viewer, and the
  camera centres on the viewer's first unit, as the gate does today.
- Floating damage numbers and HP changes show as in live play. No AP numbers anywhere, and no
  ground state, as everywhere else in the UI.

## Look: reconnaissance-drone footage

- A screen grade: muted, slightly cold colour, light film grain, light vignette.
- An overlay: corner brackets, a red dot with **«ЗАПИС» / "REC"**, a running timecode, and the label
  **«Хід N · <side name>»** for the turn being replayed.
- **Units and side markers keep full colour** so a unit and its side read at ~100 px under the
  grade. Achieving this is left to view-engineer. Acceptable fallback: grade everything 3D, and keep
  the side markers and HP rings on a layer above the grade.
- Any counter or progress indicator counts **visible actions only**. The timecode is the replay's
  own clock, not game time.
- It must run on `gl_compatibility`, with small visual differences accepted (§5).
- All strings are localised in Ukrainian and English.

## Architecture

The approach: **record the commands, re-run them on a copy, filter the events for the viewer in
`core/`.**

Considered and not chosen:

- *Record the events as they happen and filter them.* The view still needs the world as it was at
  the start of the replayed span, so a snapshot is needed anyway. Events would also have to be
  serialisable for save. Commands are fewer, smaller and already value objects.
- *A static end-of-turn summary* (losses list, markers on the board). Cheap, but it is not what was
  asked for: no story, no atmosphere.

### Recording

- `MatchService.submit()` is the single point every command passes through. It appends each applied
  command to a log.
- At match start, and at each player's end of turn, a snapshot of the state is taken with `BattleSerializer.to_dict()`.
  It already carries the board (bridges), units with `found_by`, mines, wrecks, broken forest,
  every player's `seen`, and the RNG state. A player's replay span is the log since their own
  snapshot. Keep one snapshot per player and trim the log behind the oldest one. The match-start
  snapshot is needed because `MatchService.begin()` starts the first turn outside any command, so
  players 2 and 3 on turn 1 have no end of turn of their own yet.
- Commands need `to_dict` / `from_dict` so that snapshot and log go into the save. Continue at the
  gate still shows the replay.

### Re-run and filter (`core/`, tested)

- Restore the snapshot with `BattleSerializer.from_dict()` and apply the logged commands in order.
  The seeded RNG makes the result exact. **After the re-run, the copy must equal the real state**
  (`to_dict` equality). This is a test, and an assertion in debug builds. It is also a standing
  check on determinism.
- A per-viewer filter in `core/` turns the full event stream into what the viewer may see, by the
  rules table above. It evaluates visibility on the copy's state at each step, not at the end, and
  it runs over the whole re-run span at once, because the cover row needs look-ahead: a squad's
  earlier moves are hidden by where it ends up later. It may cut a `UnitMoved` path into visible
  segments and may emit a "vanished" marker. It is a replay filter. The live per-observer filter
  that online play would need (`docs/architecture.md`) cannot look ahead and is not built here.
- Tests cover every row of the rules table, plus three-player order, an elimination mid-span, the
  first-turn case, and save → load → replay.

### View (`game/`)

- `battle_screen.gd` reads `state.active_player` for fog in about 28 places, `input_controller.gd`
  in about 11 and `hud.gd` in about 5. During the replay, the world on screen belongs to the viewer,
  who is not the active player of the copy. The view needs an explicit viewer in place of
  `active_player` wherever it decides what to show. It also reads `_match_service.state` directly
  (about 36 times in `battle_screen.gd`, 6 in `input_controller.gd`), so it needs a state source
  that can point at the replay copy. Together this is the bulk of the view work. `EventPlayer`
  already has a `viewer` field.
- **What is rewound to the start of the span:** units, wrecks, mines, bridges and the viewer's
  known broken forest, the things that carry a rule. Scars, crushed props, fallen soldiers and
  roofs stay as they are now: they are view-only, not in the snapshot, and rebuilding the whole
  board on a phone costs more than a rut appearing a few seconds early is worth. They are already
  filtered by the viewer's knowledge, so nothing leaks. Effects are cleared before the replay, as
  at the gate.
- `EventPlayer` plays the filtered list with a speed factor and a "jump to next action" call.
  UnitViews are rebuilt after every event batch, so keep any per-unit replay state keyed by unit id.
- Input on the board is off during the replay, except tap-to-advance and the Skip button.

## Left to the builder

- The speed factor, camera pan timing, and the zoom range used during the replay.
- How the grade keeps units in colour, and the grain and vignette amounts. A visual-critic pass is
  required, judged at both zooms.
- The exact event shape of the filtered stream (cut paths, the vanish marker).
- Where the snapshot and log live (`MatchService` or `BattleState`), as long as save covers them.
