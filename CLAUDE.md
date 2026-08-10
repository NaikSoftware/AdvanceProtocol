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

### Setting — fixed

**Near-future conventional war, roughly the 2030s, between fictional states.** Decided ahead of
asset generation, which is the deadline that mattered: the setting drives every model prompt,
every material, and the whole lighting and audio brief.

It follows the rules rather than leading them. The drone strike (§3.9) is already load-bearing —
it is one corner of the matchup triangle — and a contemporary setting simply *has* drones. The
alternative was a mid-century setting with a weapon that does not belong to it, which is a rule
bent to fit a mood; here the mood fits the rules.

What this fixes, concretely:

- **Materials:** modern composite and appliqué armour, slat cages, rubber-padded tracks, thermal
  optics, antenna clusters. Not riveted plate.
- **Palette:** contemporary digital-pattern camouflage, low-saturation greys, greens and tans.
  Dust, rain and mud are the only things that dirty a vehicle.
- **Light and audio:** overcast northern-European daylight as the default preset, turbine and
  diesel notes, radio chatter as texture rather than language.
- **Infantry:** plate carriers, ballistic helmets, optics on rifles.

What stays forbidden, exactly as before: **no real army, nation, flag, insignia or identifiable
vehicle**, anywhere in code, data, UI or assets. The sides are fictional and stay fictional.
Era-neutrality in the *rules* also stands — nothing in `core/` encodes a period, and the unit
names in §3.6 remain role labels. The setting is an art-direction decision, not a rules one.

---

## 3. The rules model

This section is the game. It is written out in full because it is the part that must not drift.

### 3.1 Grid and space

- **Square grid.** Movement is **4-directional** (orthogonal only). Diagonals are not moves.
- **Facing is 8-directional** — a unit can face a diagonal even though it cannot move onto one.
  Facing exists solely to feed the armour model.
- Logical coordinates are integer `(x, y)`. World space maps to `(x, 0, y)` in Godot; the camera
  supplies the isometric look, the grid itself is axis-aligned. Never bake the 45° into the data.
**Range and vision are measured differently, and that is deliberate.**

| | shape | test |
| --- | --- | --- |
| weapon range | Euclidean circle | `dx*dx + dy*dy <= r*r` — squared, never `sqrt` |
| vision | Manhattan diamond | `abs(dx) + abs(dy) <= r` |

A gun fires in a straight line, so its reach is a circle. A scout covers ground on foot, and on a
4-directional grid "three tiles away" means three *moves* away — a diamond. Vision therefore has
the same shape as movement, which is what makes a vision radius legible: it is a step count, not
an abstract distance.

Confirmed against the reference, which does exactly this (§4). Two consequences worth stating
because they are easy to mistake for bugs:

- **The two shapes disagree on diagonals, and a unit can have a target in range that it cannot
  see.** At radius 5 the circle covers 81 tiles and the diamond 61; a tile at `(3, 4)` is inside
  a range-5 circle and outside a vision-5 diamond. Since firing requires visibility, the effective
  firing envelope is the *intersection* of the two.
- **This is what gives §3.9's drone visibility check its teeth.** It was inert while both shapes
  were circles of radius 5.

A diamond of radius `r` is always contained in the circle of radius `r`, so **the intersection is
just the vision diamond** wherever vision is the tighter of the two. In tile counts, for a unit
firing on what it can see by itself, with no spotter:

| class | range | vision | envelope was | is now | |
| --- | --- | --- | --- | --- | --- |
| infantry (rifle) | 3 | 5 | 29 | **29** | unchanged |
| light vehicle | 3 | 3 | 29 | 25 | −4 |
| tank | 4 | 4 | 49 | 41 | −8 |
| artillery | 5 | 3 | 29 | 25 | −4 |
| drone strike | 5 | 5 | 81 | 61 | −20 |

**Infantry is the only class this does not touch**, because it is the only one that sees further
than it shoots. Everything else now has corners of its own weapon envelope that it cannot use
unaided. That is the same argument §3.3.1 makes about retaliation, arriving from a different
direction: the rifle squad forward of the line is what lets the rest of your force use its full
reach, and killing the enemy's spotters shrinks their guns rather than merely blinding them.

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

### 3.3.1 Retaliation

**A target that survives a shot fires back, immediately, in the same exchange.** Confirmed against
the reference (`class_1.java`, the attack state machine: after the shot resolves, if the target's
HP is still above zero the roles swap and the same damage path runs in reverse).

```
Retaliation
  triggers  : an attack resolved and the target is still alive
  requires  : retaliator has >= fire_cost AP, and the original attacker is within
              the retaliator's range; ENGINEER never retaliates (it has no weapon)
  damage    : the ordinary damage formula, no reduction — armour sector computed
              from the original attacker's facing, as for any shot
  cost      : sets the retaliator's AP to 0, exactly as firing does
  frequency : at most once per exchange; a retaliation never provokes another
```

**What the AP cost actually buys, stated carefully because it is easy to overclaim.** Firing back
zeroes the retaliator's AP for the remainder of the *attacker's* turn, so it cannot answer a second
shot before its own turn comes round. It does **not** cost the unit its own turn: `refill_ap()`
restores both AP and the fired flag at the start of its owner's turn, exactly as the reference
does. A unit that retaliated moves and shoots normally when its turn arrives.

So retaliation is close to free for the defender, and deliberately so — the cost of shooting falls
on the *attacker*, who takes a full-strength answer for opening fire on a healthy target inside its
range. The defender's only exposure is that it cannot answer twice in the same round.

An earlier version of this section claimed the retaliator forfeits its next turn. That was never
what the code or the reference did; it was a rationale written into the spec rather than read out
of it, and it is corrected here rather than implemented, on the owner's call.

**The retaliator must be able to see its attacker.** A return shot obeys the same visibility rule
as any other shot: the original attacker's tile has to be visible to the retaliating player at
that moment. The reference gates its counter-attack on AP, range and class alone, and this is a
deliberate departure from it — recorded here as §4 requires.

The consequence is the point: **an attacker the defender cannot see fires with impunity.** That
makes vision a weapon rather than a convenience, and it gives the roster's asymmetries teeth:

- Artillery has range 5 and vision 3. Firing from maximum range at something that has no spotter
  covering the gun is genuinely free — and two guns at range 5 do *not* trade, because neither
  sees the other. Counter-battery fire needs eyes, not just range.
- Infantry sees furthest (5) of anything in the game. A rifle squad forward of the line is what
  turns your armour's shots into safe ones and the enemy's into answered ones.
- Killing the enemy's spotters is therefore an attack on their ability to shoot back at all.

This reshapes the economics of shooting, and that is the point:

- Firing on a healthy target inside its range invites a full-strength answer.
- Artillery finally has a concrete reason to hold maximum range: at 5 against a tank's 4, it
  shoots without reply. The same is true of the drone strike at range 5.
- Finishing a wounded unit becomes a rule rather than a habit — the dead do not shoot back.
- Flanking costs more than it did: closing to a side or rear arc usually puts you inside the
  target's own range.

Retaliation damage feeds the retaliator's class veterancy pool like any other damage.

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

- Each unit has a `vision` radius, measured as a Manhattan diamond (§3.1) — a step count on the
  4-directional grid, not the same shape as weapon range. Infantry sees furthest (5), artillery
  least (3) — scouts are infantry, not vehicles.
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

Squad-level units (infantry, engineers) are **one asset per tile** — one mesh, one draw call, one
tile footprint. That mesh may well sculpt three or four figures sharing a base, and it should: a
squad is a squad, and a lone figure reads as the wrong thing. What is forbidden is several
*independently instanced and animated* soldiers per unit, which multiplies the draw-call cost of
the most numerous class in the game, and any arrangement that spills across a tile boundary, which
makes it ambiguous which tile the unit occupies.

The test is the one from §1: at ~100 px from directly above, it must read as a single unit
standing on a single square.

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

**The visibility requirement below is real, and it is real because of geometry rather than
numbers.** The squad's vision and the drone's range are both 5 — but range is a circle and vision
is a diamond (§3.1), so the drone out-reaches the squad's own eyes on every diagonal. A target at
`(3, 4)` is inside the drone's range and outside the squad's vision, and the strike is refused
unless *someone else* is spotting it.

That is the intended shape of the action: the longest reach in the game is also the one most
dependent on the rest of your force. An earlier version of this document noted the check had no
bite, which was true while both shapes were circles.

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

**A map with no objective condition sets `hold_target` to 0**, and then only annihilation can end
the match. Most maps will set it; a pure annihilation map will not.

**When both conditions resolve on the same end of turn, elimination decides.** Not because it is
better, but because it is unconditional: a player with no units is out of the match whatever the
map says, whereas an objective hold is a condition the map opted into. In practice the two almost
always name the same winner — a player who has just lost their last unit is not holding anything —
so this rule exists to make the rare case deterministic rather than to express a preference.

**The objective condition is checked for one player only: the one whose turn just ended.**
Elimination is still checked globally — a player with no units is out whoever was playing — but an
objective win is claimed, not awarded, and you claim it on your own turn.

This closes what used to be an open question here. If two players both held enough objectives, the
lower player index won, which is loop order rather than a rule. Rather than pick a tie-break, the
tie is made unreachable: only one player can ever be the one whose turn just ended, so two players
can never claim on the same check.

The side effect is the better half of the change. Capturing the winning objective no longer ends
the match on the spot — you have to still be holding it when your next turn ends, and every
opponent gets a full round to take it back or kill the engineer standing on it. A victory you have
to survive is worth more than one you trigger.

### 3.11 Mines

- Laid by engineers, invisible to everyone except the owner.
- **Only an engineer finds an enemy mine**, and it finds one within its own `vision` radius —
  the same diamond as tile fog (§3.1), so a revealed mine is always on a tile you can actually
  see. Visibility is **per player**, tracked on the mine, exactly like tile fog.
- Driving onto an unrevealed mine detonates it.

The engineer restriction is the reference's rule and it is adopted deliberately (§4). It is what
makes a minefield a threat rather than an inconvenience: without a sapper leading, a column drives
in blind, and the engineer finally has a reason to be at the front of the advance rather than
behind it. The trade is that the radius is the engineer's full vision (3) rather than one tile —
fewer units can search, but the one that can, searches properly.

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

### Findings from the reference

- **Tank → artillery damage is quartered in the original — confirmed, and deliberately not
  adopted.** `class_3.method_160` carries a distinct `>>= 2` branch for attacker `TANK` against
  target `ARTILLERY`, separate from the `÷4` that both tanks and artillery take against infantry.
  This project stays at ×1.0, and the reason is now stronger than the original "an unarmoured
  immobile gun ought to be easy meat" instinct: **retaliation (§3.3.1) did not exist when that
  note was written.** With both rules together, a tank firing on a field gun deals the floor of 10
  and takes a full-strength answer from a 200-attack weapon — roughly 120 through medium frontal
  armour. Tanks would strictly lose every exchange they started against artillery, nothing but
  infantry could threaten a gun, and the §3.9 triangle would collapse. Two rules that are each
  defensible alone are not defensible together; this is the one that goes.

- **Vision is a Manhattan diamond, weapon range is a Euclidean circle — confirmed and adopted**
  (§3.1). This closes the open question that used to sit here. Vision is not a distance comparison
  at all in the original: `class_1.method_121` is a recursive 4-directional flood fill with a
  decrementing budget seeded from the unit's `vision`, and its only guard is a bounds check — no
  terrain, no line-of-sight occlusion. A tile is reached with budget `vision − manhattan_distance`,
  so it is revealed exactly when `|dx| + |dy| <= vision`. Range, by contrast, is
  `method_175(x, y) <= range²` in `class_3.method_164` — a true squared-Euclidean test, and the
  original's own UI draws it as a 360° arc. The two metrics are genuinely different in the source;
  this is not a decompilation artefact.

- **The original has no "visible now" grid, and this project deliberately does.** `field_172` is a
  single permanent *seen* grid: it is initialised to fogged and every later write clears it, never
  re-fogs. Enemy unit rendering and target selection test that same grid — so in the original, once
  a tile has ever been revealed, units standing on it are visible **forever**. §3.5's two grids
  (`visible` and `seen`) are a departure, and the one this game's hidden information rests on.
  Remembered terrain without live unit positions is the entire point of the fog model here.

- **Only engineers detect enemy mines** (`class_1`, guarded on `field_250 == 4`). Adopted (§3.11).
  One deliberate difference: the original tests that radius as a Euclidean circle even though its
  fog is a diamond, which can reveal a mine on a tile the player cannot see. This project uses the
  vision diamond for both, so a revealed mine is always on a visible tile.

- **The original's own stat tables violate two of §3.6's invariants.** Its max-AP table makes the
  **heavy tank the fastest** of all four tanks (56, against the medium's 44), and its armour table
  has **rear thicker than side on every tank**. §3.6 rejects both on purpose — mobility must pay
  for armour, and flanking must be rewarded or the game's main skill expression inverts. Recorded
  here so the departure stays a known one rather than being "corrected" toward the reference by
  someone checking the tables later.

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
