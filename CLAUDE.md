# Advance Protocol

Mobile-first, turn-based tactical warfare. Two or three players share **one device** and pass it
between turns (hot-seat / pass-and-play). Godot 4, 3D geometry under a fixed isometric camera,
realistic art direction.

There is no action layer. Nothing happens in real time, nothing is reflex-tested. The two things
that carry the game are **tactical depth** and **atmosphere**, and every technical decision below
is downstream of that.

**This file is the map, not the territory.** It holds what you must not get wrong; the reasoning,
the tables and the evidence live in [`docs/`](docs/README.md) and are linked from each rule. When
you are about to change a rule, read the linked document first — most of them record a decision
that was already argued, and several record one that was got wrong once and corrected.

---

## 1. Design pillars

1. **Turns are read, not raced.** A player should be able to put the phone down mid-turn.
   No timers drive rules. No input is time-sensitive.
2. **Hidden information is sacred.** Each player has their own fog of war on a shared screen.
   The handover gate between turns is a correctness feature, not a UI nicety.
3. **Position beats stats.** Facing, terrain, range bands and line of approach decide fights more
   than raw numbers. A flanked heavy tank should lose to a light one.
4. **Atmosphere is the reward loop.** Rain on a burning wreck, mud ruts, a smoke column still
   standing three turns after the fight — this is what the player came for.
5. **Legible on a phone.** Silhouette-from-above must identify a unit at ~100 px. Every rule that
   affects a die roll must be visible as a number or an icon somewhere in the UI.

### Non-goals

- Real-time or semi-real-time play. No physics driving gameplay.
- Free camera. The camera angle is fixed; only pan and clamped zoom.
- Photoreal at any cost. Realism serves mood; it loses to frame time and readability every time.
- Online multiplayer in v1 (the architecture keeps the door open — see §6).

---

## 2. Scope

**v1 ships:** hot-seat skirmish for 2–3 players, a set of hand-made maps, and the map editor.

**Explicitly later:** AI opponent, campaign, online play. The AI is a large piece of work on its
own — fog of war plus directional armour makes for a hard search problem — and it must not be
allowed to distort the combat model before the combat model is proven in hot-seat.

**Setting: near-future conventional war, roughly the 2030s, between fictional states.** Fixed,
because it drives every model prompt, material and lighting brief. It follows the rules rather
than leading them: the drone strike (§3.9) is already load-bearing, and a contemporary setting
simply has drones. Materials, palette and the audio brief are in
[docs/art-direction.md](docs/art-direction.md).

**No real army, nation, flag, insignia or identifiable vehicle** — anywhere in code, data, UI or
assets, now or later. The sides are fictional and stay fictional. The *rules* remain era-neutral:
nothing in `core/` encodes a period, and the unit names in §3.6 are role labels.

---

## 3. The rules model

This section is the game. What is written out here is what must not drift; everything else —
worked examples, the arguments, the balance reasoning — is in [`docs/rules/`](docs/README.md).

### 3.1 Grid and space → [details](docs/rules/movement-and-terrain.md)

- **Square grid.** Movement is **4-directional** (orthogonal only). Diagonals are not moves.
- **Facing is 8-directional**, and exists solely to feed the armour model.
- Logical coordinates are integer `(x, y)`; world space is `(x, 0, y)`. The camera supplies the
  isometric look. **Never bake the 45° into the data.**
- **Range and vision use different shapes, deliberately:**

| | shape | test |
| --- | --- | --- |
| weapon range | Euclidean circle | `dx*dx + dy*dy <= r*r` — squared, never `sqrt` |
| vision | Manhattan diamond | `abs(dx) + abs(dy) <= r` |

A diamond of radius `r` sits inside the circle of radius `r`, and firing requires visibility, so
**the effective firing envelope is the intersection** — the diamond, wherever vision is the
tighter of the two. Infantry is the only class this does not constrain, being the only one that
sees further than it shoots.

### 3.2 Action points → [details](docs/rules/movement-and-terrain.md)

- `cost(unit, tile) = max(10, 10 + tile.penalty - unit.cross_country)`. One number per unit
  against one number per tile — **not** a unit×terrain matrix. Impassable is an infinite penalty,
  not a special case in the mover.
- **Terrain penalties are widely spaced on purpose** (`0 / 5 / 10 / 20 / 100 / impassable`).
  Compressing them makes every terrain free for every vehicle and silently deletes the off-road
  model.
- **Firing sets the unit's AP to 0.** A unit fires at most once per turn, and firing ends its
  activity. Every AP-consuming action other than movement is a decision to stop moving.
- **Movement is spent, not committed.** A unit may move in as many separate steps as its AP
  allows. Nothing tracks "has already moved", and nothing may.
- **The two movement zones are the primary UI of the game:** gold = reachable with `>= fire_cost`
  AP left, red = reachable but cannot act. Recomputed after every action that changes AP or
  occupancy.

### 3.3 Combat → [formula and worked reasoning](docs/rules/combat.md)

The damage formula is written out in full in the linked document and is the single thing in this
project most likely to be "improved" by accident. It has golden tests; do not edit it without
them. The shape it produces, which is the intended one:

- Infantry is nearly harmless at range, lethal adjacent (×4), and **ignores armour entirely** —
  so armour is answered by *closing*, not by out-shooting.
- Artillery hits hardest, must stay back, and is helpless against anything that reaches it.
- Tanks dominate the middle band.
- **Minimum damage is 10.** Nothing is ever fully immune.
- **A shot never depends on how much AP the unit has left.** Movement does not degrade accuracy —
  this is what keeps the two-zone UI honest.

### 3.3.1 Retaliation → [details](docs/rules/combat.md)

**A target that survives a shot fires back immediately, in the same exchange**, at full strength,
if it has the AP, the range, and **can see its attacker**. Engineers never retaliate. It costs the
retaliator its AP for the rest of the attacker's turn, not its own next turn.

The consequence is the point: **an attacker the defender cannot see fires with impunity.** Vision
is a weapon, not a convenience.

### 3.4 Directional armour → [details](docs/rules/combat.md)

Three armour values per unit — `front`, `side`, `rear` — with the sector chosen by integer dot
product against the target's facing. No trigonometry, no division.

- **`front >= side >= rear` for every unit. Hard invariant, enforced by a test.** If a rear plate
  is thicker than a side plate, flanking is punished instead of rewarded and the most
  skill-expressive move in the game becomes a mistake.
- The UI must always show which sector a shot will land in **before** the player commits.

### 3.5 Vision and fog of war → [details](docs/rules/vision-and-fog.md)

- Every player keeps **two grids**: `visible` (in someone's vision right now) and `seen`
  (remembered terrain, drawn dimmed, **without** live unit positions).
- Recomputed for the active player from scratch at turn start and after every move step.
  **Never carry another player's visibility into the renderer.**
- **The handover gate is mandatory.** Not skippable, not animated through, and the camera must not
  leak the previous player's positions — recentre on the incoming player's first unit.

### 3.6 Unit classes and roster → [roster table and balance notes](docs/rules/units.md)

Five classes drive every matchup rule: `INFANTRY` (spots, holds ground, ignores armour),
`LIGHT_VEHICLE` (fast, thin, screens), `TANK` (the main line), `ARTILLERY` (longest reach,
helpless up close), `ENGINEER` (no weapon; mines, bridges, repair).

**`core/unit_types.gd` is the source of truth for the numbers.** The table in the linked document
is documentation. Two invariants hold there and are tested:

- `front >= side >= rear`, every unit (§3.4).
- **Tank mobility is strictly ordered** light → medium → tank destroyer → heavy, in both AP and
  cross-country. Armour must be paid for with mobility.

Squad-level units are **one asset per tile** — one mesh, one draw call, one tile footprint. That
mesh may sculpt three or four figures sharing a base, and it should.

### 3.7 Veterancy → [thresholds](docs/rules/combat.md)

Per unit class, per player, earned by damage dealt. Levels 0→5, each worth `+A/8` damage.
Engineers have none. **In skirmish it is per match** and does not persist.

### 3.8 Engineers → [verb list](docs/rules/units.md)

No gun; a verb list instead. All actions are on an **orthogonally adjacent** tile and cost
`fire_cost` AP: lay/clear mine, repair/demolish bridge, repair a friendly unit, capture/demolish
an objective. Repair is the one place where unspent AP matters.

### 3.9 Drone strike — assault squad only → [details](docs/rules/units.md)

Range 5, `120 + rand(0, 60)`, **armour ignored entirely**, vehicles only, **2 per squad per match**.
Deliberately the most dangerous thing a 100 HP unit can do. Three constraints keep it in check —
ammo, it cannot touch infantry, and the squad is still infantry — and **none may be removed
without replacing it with another.**

The triangle it produces is the spine of the game's matchups:
**drones beat tanks → light vehicles beat infantry → tanks beat light vehicles.**

### 3.10 Objectives and victory → [details](docs/rules/objectives.md)

Up to 15 markers per map, owned or neutral, intact or taken; an adjacent engineer flips one.
Objectives obey fog. Checked at end of turn: an opponent has no units left, **or** the map's
objective condition is met.

- **The objective condition is checked for one player only — the one whose turn just ended.**
  Elimination stays global. This makes a simultaneous objective win unreachable rather than
  tie-broken. It does **not** make a captured objective something you must survive a round to
  keep — see the linked document.
- A map with no objective condition sets `hold_target` to 0.
- When both conditions resolve together, **elimination decides**.

### 3.11 Mines → [details](docs/rules/vision-and-fog.md)

Laid by engineers, invisible to everyone except the owner, **found only by an engineer** within
its own vision diamond. Driving onto an unrevealed mine detonates it — **on entry, not at the
destination**, so a minefield cannot be crossed by stopping past it.

### 3.12 Weather, time of day, and ground state → [details](docs/rules/movement-and-terrain.md)

**Weather and time of day are cosmetic and touch no number.** In a hot-seat game with hidden
information, a rule that silently shrinks your vision feels like cheating when you cannot see it.

**Ground state is a rule and it is explicit.** `dry / mud / frozen`, shown as a labelled HUD icon
at all times, offsetting off-road penalty. Roads are never affected — that is the point of a road.

### 3.13 What the board shows, and when → [details](docs/ui/overlays.md)

- **Movement zones: always on**, selected unit only, drawn as two nested **contours** rather than
  filled tiles, so terrain and battle scars stay visible underneath.
- **Fire radius: on demand** — tap a unit to see its reach. **Any visible unit, including an
  enemy's**, because with retaliation "is it safe to shoot this" is the central question of a turn.
- An enemy's marks ignore its AP and are computed from **that unit alone**, never from its owner's
  vision network — the network is hidden, and drawing from it would reveal unseen spotters. The
  forecast is therefore **a floor, not a ceiling**, and the UI must say so.
- **The drone strike gets its own ring and its own marks**, and an enemy squad's remaining drones
  count towards the threat it is shown to pose. Ammo is already public (§3.9), so this leaks
  nothing, and omitting it would under-report the most dangerous action in the game.
- Both computations live in `core/`. **Neither may be re-derived in the view.**

---

## 4. Resolving disputes about the rules

When something here is ambiguous, contradictory, or missing — and the answer matters for balance
or feel — **check how the original did it before inventing an answer.**

Reference of record, reverse-engineered Java MIDP sources:
<https://github.com/NaikSoftware/Blitzkrieg>. Where to look, which obfuscated fields map to what,
and every finding recovered so far: **[docs/reference/blitzkrieg.md](docs/reference/blitzkrieg.md)**.

- **It is a reference, not a dependency.** No code and no assets are copied from it.
- **It is not automatically right.** It has quirks that look like bugs, and this project departs
  from it in several places on purpose. When you consult it and find something surprising, **record
  the finding** in the reference document rather than silently matching or silently ignoring it.

---

## 5. Tech stack

| | |
| --- | --- |
| Engine | Godot **4.7.1 stable** |
| Language | GDScript, statically typed |
| Renderer | Mobile (Vulkan); `gl_compatibility` fallback for old devices |
| Targets | Android and iOS, **landscape** |
| Tests | GUT, run headless |
| 3D assets | GLB, generated via the `asset-manager` skill |

If Godot is not on `PATH`, point `$GODOT` at the binary and set `GODOT_PATH` to the same value —
the Godot MCP server defaults to `/usr/bin/godot` and fails with `ENOENT` otherwise.

```bash
$GODOT --path .                                   # run
./run_tests.sh                                    # tests (needs $GODOT)
$GODOT --headless --path . --export-release "Android" build/advance-protocol.apk
```

---

## 6. Architecture → [details](docs/architecture.md)

The single most important structural rule:

> **`core/` contains the entire game. It does not import Godot node types and does not know a
> renderer exists.**

Everything under `core/` is plain data and functions, runnable headless with no scene tree.
Everything under `game/` is Godot scenes that *display* what `core/` decided.

```
input → intent → Command → Rules.validate() → Rules.apply() → [BattleEvent] → view animates
```

**The view never computes an outcome.** If a shell is in flight for 400 ms, the damage was already
decided before it left the barrel.

**Determinism.** One `RandomNumberGenerator`, seeded per match and stored in `BattleState`. Every
roll goes through `Rules.roll()`. **Never call global `randi()` / `randf()` anywhere in `core/`.**

**Known debt:** events are not filtered per observer. Harmless in hot-seat; online would have to
build that filter in `core/`, not in the view.

---

## 7. Agent Team workflow

**Primary mode: work in Agent Team mode.** Spawn child agents for implementation, research,
verification and other separable subtasks. Keep the main context focused on analyzing child-agent
results, making decisions, integrating outputs and validating the final state.

| task | model |
| --- | --- |
| Simple, mechanical work | Sonnet |
| Complex reasoning, architecture, tricky implementation | Opus |
| Image generation and visual asset work | Agy |
| Cross-model review and independent verification | Agy |

- Give every child agent a discrete subtask with clear inputs, outputs and acceptance criteria.
- **Every implementation gets a review pass by a separate agent**, rotated across reviewers. An
  implementer's own report of its work is not a review, however detailed.
- Use separate worktrees/branches when several child agents modify the repo in parallel, and
  **never commit in a tree where a child agent is working.**
- Ask child agents to report concise findings, changed files, validation commands and blockers.
- Do not let child agents make final product/design calls; the main context decides, owns
  integration, final validation and any user-facing summary.

---

## 8. Rendering and mobile budget → [details](docs/art-direction.md)

Fixed orthographic rig, ~45° yaw and 50–55° pitch, pan and clamped zoom only. **Undersides are
never seen and backs rarely are** — judge every asset from that angle.

Budget on a mid-range phone at 60 fps: **under ~100 draw calls and ~150k triangles on screen.**
Bake static terrain lighting; one directional light with shadows for units only. No SSAO, no SSR,
no volumetric fog. **Persistent battle scars** — wrecks, lingering smoke, craters, ruts — are the
cheapest atmosphere in the game and double as information.

Turn-based means the screen is usually static: enable low-processor mode and drop the frame rate
hard when nothing is animating. Battery life is a feature for a game passed between people.

3D asset generation, poly budgets and the GLB pipeline are covered by the **`asset-manager`
skill** — read it before generating anything.

---

## 9. Conventions

- Typed GDScript everywhere: `var hp: int = 0`, `func fire(target: Unit) -> Array[BattleEvent]:`.
- `snake_case` files and members, `PascalCase` for `class_name`.
- No `get_node("../../Foo")` path strings in gameplay code; wire dependencies explicitly.
- Rules never run in `_process`. If gameplay logic is in a frame callback, it is in the wrong file.
- Signals go view-ward only. `core/` returns events; it does not emit Godot signals.
- UI: tap targets ≥ 48 dp, respect notch/safe areas, every rule-relevant number visible somewhere.
- Localisation from day one: Ukrainian and English, no hard-coded display strings.
- Comments explain **why**, not what, and are written in Ukrainian in `core/`.
- Tests are required for anything in `core/`. The damage table gets golden tests; the roster gets
  a structural test for `front >= side >= rear`.

---

## 10. Before you build something

- If it changes a number a player can be killed by, it belongs in `core/` and it needs a test.
- If the rule cannot be shown in the UI, reconsider the rule.
- If it is ambiguous, check the reference (§4) before inventing.
- If it is a new mechanic rather than a listed one, ask first — the combat model is small on
  purpose and every addition has to earn its place against the two movement zones.
