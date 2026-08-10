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

Confirmed against the reference, which does exactly this ([§4](../reference/blitzkrieg.md)). Two consequences worth stating
because they are easy to mistake for bugs:

- **The two shapes disagree on diagonals, and a unit can have a target in range that it cannot
  see.** At radius 5 the circle covers 81 tiles and the diamond 61; a tile at `(3, 4)` is inside
  a range-5 circle and outside a vision-5 diamond. Since firing requires visibility, the effective
  firing envelope is the *intersection* of the two.
- **This is what gives [§3.9](units.md)'s drone visibility check its teeth.** It was inert while both shapes
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
unaided. That is the same argument [§3.3.1](combat.md) makes about retaliation, arriving from a different
direction: the rifle squad forward of the line is what lets the rest of your force use its full
reach, and killing the enemy's spotters shrinks their guns rather than merely blinding them.

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
