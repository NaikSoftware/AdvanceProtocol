# Units

The detail behind §3.6, §3.8 and §3.9 of CLAUDE.md — the roster, the engineer's verbs and the drone strike.

[back to CLAUDE.md](../../CLAUDE.md)

## Unit classes and roster

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

## Engineers

The engineer is the only unit with a verb list instead of a gun. All actions are on an
**orthogonally adjacent** tile and require `fire_cost` AP:

- **Lay mine** / **clear mine**
- **Repair or demolish a bridge** — a demolished crossing reshapes the whole map, and this is the
  single highest-leverage action in the game
- **Repair a damaged friendly unit** — heals `(40 + rand(0, ap_left - fire_cost)) / 2`, so an
  engineer that drove all turn repairs badly. This is the one place where unspent AP matters.
- **Capture / demolish an objective** ([§3.10](objectives.md))

## Drone strike — assault squad only

The assault squad (#1) is otherwise identical to the rifle squad. What separates it is a
**drone strike**: a separate action, not a modifier on its normal attack.

**The visibility requirement below is real, and it is real because of geometry rather than
numbers.** The squad's vision and the drone's range are both 5 — but range is a circle and vision
is a diamond ([§3.1](movement-and-terrain.md)), so the drone out-reaches the squad's own eyes on every diagonal. A target at
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
  unplayable. **The remaining drone count is public.** It is shown on the unit at all times, to
  every player who can see that unit — not only to its owner. That is a deliberate rules decision,
  not merely a UI one: the counter-play to a drone squad is to screen it with infantry or to rush
  it, and both are decisions about whether the threat is still live. A hidden counter would also
  be unknowable rather than bluffable in a three-player match, since a drone spent on the third
  player happens behind the handover gate where nobody else can count it.
- **It cannot touch infantry.** A drone squad screened by rifle squads is a hard problem, and that
  is the intended counter-play.
- **The squad is still infantry.** 100 HP, no armour, 3 tiles of movement, and it is fully exposed
  once it fires.

The resulting triangle is the spine of the game's matchups, and it is worth protecting:
**drones beat tanks → light vehicles beat infantry → tanks beat light vehicles.** Light vehicles
are the answer to a drone squad precisely because they are the one armoured class that does *not*
take the ÷4 penalty against infantry.

Veterancy from drone damage accrues to the `INFANTRY` pool like any other infantry damage.
