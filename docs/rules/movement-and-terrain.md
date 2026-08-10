# Movement and terrain

The detail behind §3.1, §3.2 and §3.12 of CLAUDE.md — the grid, action points and ground state.

[back to CLAUDE.md](../../CLAUDE.md)

## Grid and space

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

Confirmed against the reference, which does exactly this ([§4](../reference/blitzkrieg.md)). One
consequence is worth stating because it is easy to mistake for a bug:

- **The two shapes disagree on diagonals, so a unit can have a target inside its range circle that
  it cannot see for itself.** At radius 5 the circle covers 81 tiles and the diamond 61; a tile at
  `(3, 4)` is inside a range-5 circle and outside a vision-5 diamond.

An earlier version of this passage drew two further conclusions from that, and both are now wrong:
that the firing envelope is the intersection of circle and diamond, and that this is what gives
[§3.9](units.md)'s drone visibility check its teeth. Neither survives, because **what may be fired
on is not decided by the diamond at all.**

**What decides it is `seen`** ([§3.5](vision-and-fog.md)) — every
tile the player has ever scouted, permanently — so over ground your side has already crossed, the
weapon's full circle is available and the diamond does not constrain it at all. The diamond decides
how fast `seen` grows, not what you may shoot.

So the table below is **the opening-turns picture**: a unit alone on fresh ground, spotting for
itself, with nothing scouted yet. A diamond of radius `r` sits inside the circle of radius `r`, so
there the intersection is just the diamond:

| class | range | vision | envelope was | is now | |
| --- | --- | --- | --- | --- | --- |
| infantry (rifle) | 3 | 5 | 29 | **29** | unchanged |
| light vehicle | 3 | 3 | 29 | 25 | −4 |
| tank | 4 | 4 | 49 | 41 | −8 |
| artillery | 5 | 3 | 29 | 25 | −4 |
| drone strike | 5 | 5 | 81 | 61 | −20 |

**A unit is untouched exactly when it sees further than it shoots**, which on the current roster
means the rifle squad (vision 5, range 3) and the engineer (vision 3, range 1 — absent from the
table above because it has no weapon to draw an envelope for). Note that this is a property of the
*weapon*, not of the class: the assault squad's ordinary rifle fire is untouched for the same
reason as the rifle squad's, while its **drone** loses more than anything else in the game. Being
infantry is not a shield here; out-ranging your own eyes is what costs you.

On fresh ground, then, the rifle squad is the only thing on the board whose whole envelope is
usable, and everything else has corners of its own weapon it cannot reach unaided. **That state
does not last.** Because scouting is permanent, those corners open up for good as soon as anyone
crosses them, and by mid-match most of the roster is firing its full circle.

So the rifle squad forward of the line is what lets the rest of your force *open* its full reach,
not what sustains it — and killing the enemy's spotters slows how fast their guns grow rather than
taking anything back. This is the same shape as the retaliation argument in
[§3.3.1](combat.md), and it decays the same way and for the same reason.

## Action points

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

**A move is planned from what you can see, and walked one tile at a time.** These are two separate
occupancies and conflating them is a bug in either direction:

- **Planning** — the zones, the path, and whether a destination is reachable at all — uses the full
  terrain, which is public (§3.5), and only the **units** the moving player can currently see, plus
  their own. Ground that looks empty is planned through. Terrain never surprises a move; only an
  enemy can.
- **Walking** uses the truth. Before entering each tile the mover checks what is really there; if
  a unit it could not see is standing in the way, the move **stops on the tile before it** and
  ends. Vision is recomputed at every step, so whatever emerged is visible from that moment on.

This is the same shape as the mine rule (§3.11), and deliberately so: the unit stops where reality
contradicted the plan. **AP is charged only for tiles actually entered** — a move cut short is
never more expensive than the distance covered.

**Walking sees, and what it saw is kept.** Because vision is recomputed at every tile rather than
once on arrival, a unit that drives past something and carries on has still seen it: the terrain
enters that player's `seen` grid, an engineer's mine search runs from every tile it passed, and an
objective glimpsed in the middle of the route is remembered. Recomputing only at the destination
would silently discard all of it — the unit would arrive having learned nothing about the ground
it had just crossed. This is a rules consequence rather than a presentation detail, and it is the
reason the refresh is inside the walk loop and not after it.

The alternative, planning against the true occupancy, is what a naive implementation does and it
leaks: the route silently detours around an invisible enemy, and the shape of the detour tells the
player exactly where it stands. Worse, the leak is *invisible to the person leaking it* — nothing
on screen says "an enemy is here", the path merely bends. **A destination that is really occupied
by a unit you cannot see is therefore a legal order**, not an error; you give it, and you find out.

**The two movement zones** are therefore the primary UI of the game:

| zone | meaning | suggested colour |
| --- | --- | --- |
| move-and-fire | reachable with `>= fire_cost` AP left | gold |
| move-only | reachable, but leaves `< fire_cost` AP | red |

Both zones are computed by a flood fill over the grid (Dijkstra on entry cost) and must be
recomputed after every action that changes AP or occupancy.

## Weather, time of day, and ground state

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
