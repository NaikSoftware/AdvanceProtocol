# Advance Protocol

Mobile-first, turn-based tactical warfare. Two or three players share **one device** and pass it
between turns (hot-seat / pass-and-play). Godot 4, 3D geometry under a fixed isometric camera,
realistic art direction.

There is no action layer. Nothing happens in real time, nothing is reflex-tested. The two things
that carry the game are **tactical depth** and **atmosphere**, and every technical decision below
is downstream of that.

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

**Setting is deliberately open.** The rules model is era-agnostic. It describes *archetypes* —
infantry, light vehicles, tanks, artillery, engineers — not specific historical machines, and
nothing in `core/` encodes a period. The unit names in §3.6 are role labels, free to be renamed
once a setting exists.

This is a live decision with one hard deadline: **the setting must be fixed before asset
generation starts.** It determines every model prompt, every material, and the whole lighting and
audio brief — cheap to decide now, expensive to revisit once a few dozen models exist. Until
then: keep terminology neutral in code, data and UI, and do not name a real army, nation or
vehicle anywhere.

---

## 3. The rules model

This section is the game. It is written out in full because it is the part that must not drift.

### 3.1 Grid and space

- **Square grid.** Movement is **4-directional** (orthogonal only). Diagonals are not moves.
- **Facing is 8-directional** — a unit can face a diagonal even though it cannot move onto one.
  Facing exists solely to feed the armour model.
- Logical coordinates are integer `(x, y)`. World space maps to `(x, 0, y)` in Godot; the camera
  supplies the isometric look, the grid itself is axis-aligned. Never bake the 45° into the data.
- Range and vision use **Euclidean radius**, compared as squared distance to avoid `sqrt`:
  `dx*dx + dy*dy <= r*r`.

### 3.2 Action points

Every unit has `max_ap`, refilled at the start of its owner's turn. AP pays for movement and for
firing.

**Terrain entry cost:**

```
cost(unit, tile) = max(10, 10 + tile.penalty - unit.cross_country)
```

One number per unit (`cross_country`) against one number per tile (`penalty`) — deliberately not
a unit×terrain matrix. Infantry has a huge `cross_country` (80), so it effectively pays the floor
of 10 everywhere and terrain simply does not bother it. Vehicles sit in the 5–13 range and feel
every hedgerow. Engineers are the worst off-road (−5) and live on roads.

Impassable tiles are modelled as an infinite penalty, not as a special case in the mover.

**Firing** requires `fire_cost` AP available, and **sets the unit's AP to 0**. A unit fires at most
once per turn, and firing ends its activity. This is the central tension of a turn: how far can I
go and still shoot?

**Movement is spent, not committed.** A unit may move several times in one turn, in as many
separate steps as it likes, for as long as AP remains — walk two tiles, look around, walk two
more. Only firing ends it. Nothing tracks "has already moved", and nothing may: after each step
the two zones are simply recomputed from the unit's new position and remaining AP, so the gold
zone shrinks as the unit spends. The same applies to the engineer's verbs, which cost `fire_cost`
and end the unit's activity exactly as a shot does. Every AP-consuming action other than movement
is therefore a decision to stop moving.

**The two movement zones** are therefore the primary UI of the game:

| zone | meaning | suggested colour |
| --- | --- | --- |
| move-and-fire | reachable with `>= fire_cost` AP left | gold |
| move-only | reachable, but leaves `< fire_cost` AP | red |

Both zones are computed by a flood fill over the grid (Dijkstra on entry cost) and must be
recomputed after every action that changes AP or occupancy.

### 3.3 Combat

Damage, in order. `A` = attacker's `attack`, `V` = attacker's class veterancy level (§3.7):

```
dmg  = 0.75*A + rand(0, A/4)

if attacker.class != ENGINEER:
    dmg += A * V / 8                        # +12.5% per veterancy level

if attacker.class == INFANTRY:
    if dist_sq <= 2: dmg *= 4               # close assault — grenades, demolition charges
    # note: no armour subtraction at all for infantry attacks
else:
    R = target.armour[sector]               # front / side / rear, see 3.4
    dmg -= 0.75*R + rand(0, R/4)

if attacker.class == ARTILLERY:
    if target.class == TANK:          dmg += rand(0, A/2)
    if dist_sq <= 4:                  dmg /= 2      # minimum-range penalty
    if target.class == LIGHT_VEHICLE: dmg /= 2

if target.class == INFANTRY and attacker.class in (TANK, ARTILLERY):
    dmg /= 4                                # armour-piercing rounds against dug-in infantry

dmg = max(10, dmg)
```

The shape this produces is the intended one: infantry is nearly harmless at range and lethal when
it gets adjacent, and it ignores armour entirely — so armour is answered by *closing*, not by
out-shooting. Artillery hits hardest but must stay back and is helpless against anything that
reaches it. Tanks dominate the middle band.

The assault squad's **drone strike** does not use this formula at all — it is a separate action
with its own damage roll and no armour term. See §3.9.

**A shot never depends on how much AP the unit has left.** Movement does not degrade accuracy.
Keep it that way unless a playtest says otherwise — it keeps the two-zone UI honest.

**Minimum damage is 10.** Nothing is ever fully immune.

### 3.4 Directional armour

Each unit carries three armour values: `front`, `side`, `rear`. The sector is chosen from the
angle between the target's facing vector and the vector from target to attacker:

- roughly beyond 45° off the facing axis → **side**
- behind the target (negative dot product) → **rear**
- otherwise → **front**

Implement with integer dot products against the 8 unit direction vectors, no trigonometry:

```
v   = attacker_pos - target_pos
f   = DIRS_8[target_facing]
dot = f.x*v.x + f.y*v.y
sector = SIDE if 2*dot*dot <= len_sq_f * len_sq_v      # cos²θ <= 1/2, i.e. 45° or wider
         else (REAR if dot < 0 else FRONT)
```

The comparison is cross-multiplied rather than divided. An earlier form of this rule scaled
`cos²` by 32 and compared against 16; integer division truncated the quotient, so the band
`cos² ∈ [0.5, 0.53125)` — angles between 43.1° and 45° — fell into SIDE when it belonged to
FRONT or REAR. The two forms first disagree at a separation of 23.35 tiles, which no weapon in
the game can reach (longest range is 5), so this changes no shot that can actually be taken. The
cross-multiplied form is kept because it is exact, has no division, and cannot drift.

Flanking is the main skill expression in the game. The UI must always show which sector a shot
will land in **before** the player commits.

### 3.5 Vision and fog of war

- Each unit has a `vision` radius. Infantry sees furthest (5), artillery least (3) — scouts are
  infantry, not vehicles.
- Every player keeps **two grids**: `visible` (in someone's vision right now) and `seen` (ever
  observed — remembered terrain, drawn dimmed, without live unit positions).
- Visibility is recomputed for the active player from scratch at the start of their turn and after
  every move step. Never carry another player's visibility into the renderer.
- **The handover gate is mandatory.** Between turns the board is blanked and a full-screen
  "Pass the device to Player N" panel is shown; the board only comes back on an explicit confirm.
  Do not make this skippable, do not animate through it, and do not let the camera position from
  the previous player's turn leak the location of their units — recentre on the incoming player's
  first unit.

### 3.6 Unit classes and roster

Five classes drive all the matchup rules above:

| class | role |
| --- | --- |
| `INFANTRY` | spots, holds ground, ignores armour; kills armour in close assault, or at range with drones (§3.9) |
| `LIGHT_VEHICLE` | fast, thin, takes and screens ground |
| `TANK` | the main line; slow, armoured, hits hard |
| `ARTILLERY` | longest reach, biggest hit, helpless up close and very slow |
| `ENGINEER` | no weapon; mines, demining, bridges, repair |

Starting balance table. Once `core/unit_types.gd` exists **that file is the source of truth** and
this table is documentation only.

| # | unit | class | atk | ap | hp | range | fire | armour F/S/R | x-country | vision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | rifle squad | INF | 15 | 30 | 100 | 3 | 10 | 0/0/0 | 80 | 5 |
| 1 | assault squad | INF | 15 | 30 | 100 | 3 | 10 | 0/0/0 | 80 | 5 |
| 2 | armoured car | LIGHT | 60 | 68 | 250 | 3 | 18 | 27/18/10 | 5 | 3 |
| 3 | troop carrier | LIGHT | 70 | 68 | 250 | 3 | 18 | 36/31/7 | 7 | 3 |
| 4 | scout car | LIGHT | 55 | 48 | 200 | 3 | 18 | 35/15/7 | 8 | 3 |
| 5 | medium tank | TANK | 95 | 48 | 400 | 4 | 20 | 37/27/18 | 12 | 4 |
| 6 | tank destroyer | TANK | 130 | 44 | 400 | 4 | 20 | 45/14/8 | 11 | 4 |
| 7 | light tank | TANK | 108 | 56 | 300 | 4 | 25 | 37/16/10 | 13 | 4 |
| 8 | heavy tank | TANK | 121 | 40 | 350 | 4 | 20 | 56/25/20 | 9 | 4 |
| 9 | field gun | ARTY | 200 | 24 | 200 | 5 | 14 | 15/0/0 | 6 | 3 |
| 10 | howitzer | ARTY | 180 | 24 | 200 | 5 | 14 | 15/0/0 | 6 | 3 |
| 11 | engineer squad | ENG | 0 | 68 | 200 | 1 | 20 | 10/5/5 | −5 | 3 |
| 12 | engineer vehicle | ENG | 0 | 76 | 200 | 1 | 30 | 10/5/5 | −5 | 3 |

Squad-level units (infantry, engineers) are represented by a **single model on the tile**, not a
crowd — draw-call budget, and it keeps the grid readable.

**Tank mobility is strictly ordered** light → medium → tank destroyer → heavy, in both AP and
cross-country. A heavy that outruns a medium makes armour a free choice; the heavy's 56 front
armour has to be paid for with something, and mobility is that price. If the heavy still feels
too strong in playtest, its AP is the first dial to turn.

**The tank destroyer is a front-arc specialist:** the thickest frontal plate of any tank (45)
over paper sides and rear (14/8). It wins any fight it sees coming and dies to anything that gets
past it. That trade is the reason the class exists — do not "round it out" into a second medium
tank.

**Armour must decrease front → side → rear.** `front >= side >= rear`, for every unit. The whole
flanking model rests on it: if a rear plate is thicker than a side plate, going the long way round
an enemy is punished instead of rewarded, and the most skill-expressive move in the game becomes a
mistake.

**The whole roster satisfies this today, and it is a hard invariant from here on.** Once
`core/unit_types.gd` exists it gets a test that walks every entry and asserts the ordering — a new
unit that violates it is a failing build, not a balance discussion.

### 3.7 Veterancy

Progression is **per unit class, per player**, and it is earned by fighting, not bought.

- Each class has an XP pool. Damage dealt by a unit adds that amount to its class's pool.
- Levels 0→5. On crossing a threshold the pool is reduced by the threshold and the level goes up.
- Each level is worth `+A/8` damage (+12.5% of base attack).
- Thresholds, per class (infantry, light, tank, artillery):

```
INFANTRY       150,   375,   938,  2344,  5859
LIGHT_VEHICLE  700,  1750,  4375, 10938, 27344
TANK          1000,  2500,  6250, 15625, 39063
ARTILLERY     2000,  5000, 12500, 31250, 78125
```

- Engineers have no veterancy (they deal no damage).
- In skirmish, veterancy is **per match** — it starts at 0 and does not persist between matches.
  Persistent profiles belong with the campaign, not before it.

### 3.8 Engineers

The engineer is the only unit with a verb list instead of a gun. All actions are on an
**orthogonally adjacent** tile and require `fire_cost` AP:

- **Lay mine** / **clear mine**
- **Repair or demolish a bridge** — a demolished crossing reshapes the whole map, and this is the
  single highest-leverage action in the game
- **Repair a damaged friendly unit** — heals `(40 + rand(0, ap_left - fire_cost)) / 2`, so an
  engineer that drove all turn repairs badly. This is the one place where unspent AP matters.
- **Capture / demolish an objective** (§3.10)

### 3.9 Drone strike — assault squad only

The assault squad (#1) is otherwise identical to the rifle squad. What separates it is a
**drone strike**: a separate action, not a modifier on its normal attack.

```
Drone strike
  requires  : target is currently visible to the attacking player
  targets   : vehicle classes only — LIGHT_VEHICLE, TANK, ARTILLERY, ENGINEER
              (a drone cannot be used against infantry)
  range     : 5                       # out-reaches every direct-fire unit in the game
  damage    : 120 + rand(0, 60)       # armour is ignored entirely — the drone comes down
                                      # from above, so no facing sector is computed
  cost      : all remaining AP, exactly like a shot, plus one drone
  ammo      : 2 drones per squad per match, not replenishable
```

The squad's ordinary attack (15, range 3, ×4 in close assault) is unchanged and remains its only
option against infantry.

This is deliberately the single most dangerous thing a 100 HP unit can do. Three constraints keep
it from breaking the game, and **none of them may be removed without replacing it with another**:

- **Ammo.** Two strikes per squad, ever. Unlimited armour-deletion at range 5 would make tanks
  unplayable. The remaining drone count must be visible on the unit at all times.
- **It cannot touch infantry.** A drone squad screened by rifle squads is a hard problem, and that
  is the intended counter-play.
- **The squad is still infantry.** 100 HP, no armour, 3 tiles of movement, and it is fully exposed
  once it fires.

The resulting triangle is the spine of the game's matchups, and it is worth protecting:
**drones beat tanks → light vehicles beat infantry → tanks beat light vehicles.** Light vehicles
are the answer to a drone squad precisely because they are the one armoured class that does *not*
take the ÷4 penalty against infantry.

Veterancy from drone damage accrues to the `INFANTRY` pool like any other infantry damage.

### 3.10 Objectives and victory

A map carries up to 15 objective markers (villages, depots, bridges, crossroads). Each is owned or
neutral, and each is either intact or taken. An engineer adjacent to one flips it.

An objective is **revealed to an opponent only once they have seen it** — objectives obey fog like
everything else.

Victory, checked at end of turn:
- an opponent has no units left, **or**
- the map's objective condition is met (usually: hold N of M objectives)

Last player standing wins. In 3-player games an eliminated player is skipped in the turn order,
and the match continues between the remaining two.

### 3.11 Mines

- Laid by engineers, invisible to everyone except the owner.
- A mine becomes visible to a player once one of their units passes near it — visibility is
  **per player**, tracked on the mine, exactly like tile fog.
- Driving onto an unrevealed mine detonates it.

### 3.12 Weather, time of day, and ground state

Two separate systems, deliberately:

**Weather and time of day are cosmetic.** Rain, fog, snowfall, overcast, dawn/dusk/night — they
change the light, the particles, the wet-surface response and the audio bed. They **do not touch
any number**. This is a deliberate call: in a hot-seat game with hidden information, a rule that
silently shrinks your vision radius feels like cheating when you cannot see it. Atmosphere gets
the whole visual budget and none of the rules budget.

**Ground state is a rule, and it is explicit.** Each map has `ground_state ∈ {dry, mud, frozen}`,
shown as a labelled icon in the HUD at all times. It offsets off-road terrain penalty:

| state | off-road penalty | notes |
| --- | --- | --- |
| `dry` | baseline | |
| `mud` | +heavy for anything with wheels or tracks | infantry unaffected; roads become vital |
| `frozen` | reduced | marsh becomes passable; ice over water is a later feature |

Roads are never affected by ground state — that is the point of a road.

---

## 4. Resolving disputes about the rules

When something in this document is ambiguous, contradictory, or simply missing — and the answer
matters for balance or feel — **check how the original did it before inventing an answer.**

Reference of record, reverse-engineered Java MIDP sources:
<https://github.com/NaikSoftware/Blitzkrieg>

Where to look (the code is obfuscated; these are the mappings that have already been recovered):

| file | what is in it |
| --- | --- |
| `src/defpackage/class_3.java` | the unit — stat tables in `<clinit>`, damage in `method_160`, armour sector in `method_159`, engineer verbs in `method_16x–17x` |
| `src/defpackage/class_1.java` | the player — objectives, veterancy thresholds and level-up in `method_97` |
| `src/defpackage/class_2.java` | AI player, extends the player class |
| `src/defpackage/GameCanvas.java` | board, terrain cost (`method_70`), rendering, save format |

Field-name mappings recovered so far, for `class_3`: `field_221` attack · `field_222` vision ·
`field_223` max AP · `field_224` max HP · `field_225` range · `field_226` fire cost ·
`field_227` armour F/S/R · `field_228` cross-country · `field_248` current AP · `field_250` class
index · `field_259` current HP. `GameCanvas.method_2(n)` is `rand(0, n)`, returning 0 for `n <= 0`.

Two rules about using it:

- **It is a reference, not a dependency.** No code and no assets are copied from it. Advance
  Protocol is its own implementation, in its own engine, with its own art.
- **It is not automatically right.** It has quirks that look like bugs. Where this document
  knowingly departs, it says so. When you consult it and find something surprising, record the
  finding in this file rather than silently matching or silently ignoring it.

### Known open questions

- **Tank → artillery damage.** The original quarters it, which inverts the expected relationship
  (an unarmoured, immobile gun ought to be easy meat for a tank). Left at ×1.0 here. Do not
  "fix" this in either direction without a playtest.
- **Vision shape.** Euclidean radius here. Confirm against the original before tuning vision
  values, since a diamond and a circle of the same radius are very different maps.

- **Mines detonate on traversal, and mine damage is a roll.** Confirmed against `class_1.method_105`,
  which is called from the movement driver after *every* single-tile hop rather than once at the
  destination: when it finds a marker it applies `90 + rand(0, 90)` to the mover, consumes the
  marker, and returns `true`, which halts the path at that tile. So a minefield cannot be crossed
  by stopping past it, and the unit stops where it detonated — this project matches. The damage
  band is `90..180`, not the flat 120 the plan originally invented; adopted, because a flat number
  would make mines the only damage source in the game that does not roll. Caveat worth knowing:
  in the original the per-tile marker table appears to be shared between mines and objectives, so
  the two may not be distinct concepts there. They are distinct here.

- **Terrain penalties are widely spaced, and tracked vehicles ignore open ground.** Confirmed
  against `GameCanvas.method_68`: the original uses six buckets — `0` road, `5`, `10` ordinary
  ground, `20` rough, `100` built-up, `1000` impassable — and `method_70` is exactly
  `max(10, 10 + penalty - cross_country)`. Two consequences are easy to get wrong and were
  briefly got wrong here:
  - **The spacing is load-bearing.** With `cross_country` in the 5–13 band, any penalty below
    about 13 vanishes under the floor of 10. A compressed table (0–14) makes *every* terrain
    free for *every* tank, and the whole off-road model quietly stops existing.
  - **A medium tank pays the floor on open field, and that is correct.** Field is 10 against a
    cross-country of 12. Roads matter for wheels, artillery and engineers, not for tracks on
    open ground — do not "fix" this by inflating the field penalty.
  - Built-up terrain at 100 is effectively impassable to vehicles (a 48 AP tank cannot pay 98)
    while infantry still walks in at the floor of 10. Buildings are therefore infantry ground
    by arithmetic rather than by a special case. This is emergent, and it is worth keeping.

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
$GODOT --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit   # tests
$GODOT --headless --path . --export-release "Android" build/advance-protocol.apk
```

---

## 6. Architecture

The single most important structural rule:

> **`core/` contains the entire game. It does not import Godot node types and does not know a
> renderer exists.**

Everything under `core/` is plain data and functions: the board, the units, the rules, the turn
order. It can be run headless in a test with no scene tree. Everything under `game/` is Godot
scenes that *display* what `core/` decided.

This buys four things that are hard to retrofit: hot-seat fog correctness (visibility is a pure
function of state and active player, not of what happens to be on screen), a testable damage
model, replays, and — if online ever happens — a state model that is already deterministic and
serialisable.

**The flow of a player action:**

```
input → intent → Command → Rules.validate() → Rules.apply() → [BattleEvent] → view animates
```

- A `Command` is a value object (`MoveCommand`, `FireCommand`, `EngineerCommand`, `EndTurn`).
- `apply()` mutates `BattleState` and returns an ordered list of `BattleEvent`s
  (`UnitMoved`, `ShotFired`, `DamageDealt`, `UnitDestroyed`, `TileRevealed`, `MineTriggered`…).
- The view consumes events and plays them back over time. **The view never computes an outcome.**
  If a shell is in flight for 400 ms, the damage was already decided before it left the barrel.

**Events are not filtered per player, and that is a debt online would call in.** `apply()` returns
one ordered list describing everything that happened. In hot-seat this is harmless: one screen,
one active player, and the board is blanked at the handover. But some events carry information
their subject should not have — `MineTriggered` reveals that a mine existed to anyone replaying
the list, and the same will be true of anything that fires on an opponent's turn. If online ever
happens, the transport cannot broadcast this list as-is; it needs a per-observer filter, and the
place to build it is here in `core/`, not in the view. Keep that in mind when adding event types:
an event that only the acting player may see should be recognisable as such.

**Determinism.** One `RandomNumberGenerator`, seeded per match and stored in `BattleState`. Every
roll goes through a single `Rules.roll()` helper. Never call the global `randi()` / `randf()`
anywhere in `core/`.

### Layout

```
project.godot
core/                    # pure rules — no Node, no scene tree, no rendering
  battle_state.gd
  unit.gd
  unit_types.gd          # the stat table — source of truth
  terrain.gd
  rules.gd               # damage, terrain cost, armour sector, vision
  pathing.gd             # Dijkstra flood fill for the two movement zones
  commands/
  events.gd
game/                    # Godot scenes and nodes
  battle/                # board view, unit views, selection, zone overlay
  ui/                    # HUD, unit inspector, handover gate
  camera/                # fixed-angle rig: pan, clamped zoom
  fx/                    # weather, smoke, wrecks, impacts
  audio/
maps/
assets/
  models/ materials/ textures/ audio/
tests/                   # GUT specs against core/
tools/                   # map editor
docs/
```

---

## 7. Agent Team workflow

**Primary mode: work in Agent Team mode.** Spawn child agents for implementation, research,
verification and other separable subtasks. Keep the main context focused on analyzing child-agent
results, making decisions, integrating outputs and validating the final state.

Choose the child-agent model based on the task:

| task | model |
| --- | --- |
| Simple, mechanical work | Sonnet |
| Complex reasoning, architecture, tricky implementation | Opus |
| Image generation and visual asset work | Agy |
| Cross-model review and independent verification | Agy |

Coordination rules:

- Give every child agent a discrete subtask with clear inputs, outputs and acceptance criteria.
- Use separate worktrees/branches when several child agents modify the repo in parallel.
- Ask child agents to report concise findings, changed files, validation commands and blockers.
- Do not let child agents make final product/design calls independently; the main context decides.
- The main context owns integration, review, final validation and any user-facing summary.

---

## 8. Rendering and mobile budget

The camera is a fixed orthographic rig, roughly 45° yaw and 50–55° pitch. Pan and clamped zoom
only; no free rotation (90° snaps are acceptable if playtests ask for them). Because the angle is
fixed, **undersides are never seen and backs rarely are** — judge every asset from that angle.

Budget on a mid-range phone at 60 fps: under ~100 draw calls and ~150k triangles on screen.

Techniques that buy atmosphere cheaply here:

- **Bake** static terrain lighting. One directional light with shadows for units only.
- Time of day is a **per-map baked preset**, not a dynamic cycle.
- Weather = particles + a screen overlay + a wind parameter on foliage shaders + an audio bed.
- Skip volumetric fog. A depth-based fog gradient reads nearly as well and costs almost nothing.
- Wetness is a material parameter (roughness + normal blend) driven by the weather controller.
- Post-processing: a colour-grade LUT, light vignette, minimal grain. **No SSAO, no SSR.**
- **Persistent battle scars.** Wrecks stay. Smoke columns linger for several turns. Craters and
  mud ruts accumulate. This is the cheapest atmosphere in the game and it doubles as information:
  the map should tell you where the fighting has been.

Turn-based means the screen is usually static — enable low-processor mode and drop the frame rate
hard when nothing is animating. Battery life is a feature for a game passed between people.

3D asset generation, poly budgets and the GLB pipeline are covered by the **`asset-manager`
skill** — read it before generating anything, and do not duplicate its guidance here.

---

## 9. Conventions

- Typed GDScript everywhere: `var hp: int = 0`, `func fire(target: Unit) -> Array[BattleEvent]:`.
- `snake_case` files and members, `PascalCase` for `class_name`.
- No `get_node("../../Foo")` path strings in gameplay code; wire dependencies explicitly.
- Rules never run in `_process`. If gameplay logic is in a frame callback, it is in the wrong file.
- Signals go view-ward only. `core/` returns events; it does not emit Godot signals.
- UI: tap targets ≥ 48 dp, respect notch/safe areas, every rule-relevant number visible somewhere.
- Localisation from day one: Ukrainian and English, no hard-coded display strings.
- Tests are required for anything in `core/`. The damage table in particular gets golden tests —
  it is the thing most likely to be "improved" by accident. The roster gets a structural test too:
  `front >= side >= rear` for every unit (§3.6).

---

## 10. Before you build something

- If it changes a number a player can be killed by, it belongs in `core/` and it needs a test.
- If the rule cannot be shown in the UI, reconsider the rule.
- If it is ambiguous, check the reference in §4 before inventing.
- If it is a new mechanic rather than a listed one, ask first — the combat model is small on
  purpose and every addition has to earn its place against the two movement zones.
