# Vision, fog of war and mines

The detail behind §3.5 and §3.11 of CLAUDE.md — what each player can see, and what is hidden under the ground.

[back to CLAUDE.md](../../CLAUDE.md)

## Vision and fog of war

- Each unit has a `vision` radius, measured as a Manhattan diamond ([§3.1](movement-and-terrain.md)) — a step count on the
  4-directional grid, not the same shape as weapon range. Infantry sees furthest (5), artillery
  least (3) — scouts are infantry, not vehicles.
- **The fog hides enemy units, not the map.** Terrain is public from the first turn: the whole
  board is drawn, at full brightness, whether or not anyone has been near it. What the fog conceals
  is the enemy — where their units are, and the mines they have laid. Wrecks
  ([§3.14](movement-and-terrain.md#wrecks)) follow the same `seen` rule as units: a player knows a
  wreck only on ground they have scouted, and plans a vehicle's route as if unscouted ground held
  none.
- This is a deliberate design choice and not an oversight. Hiding the ground would make the opening
  of a match an exercise in map discovery, and it would make the two movement zones (§3.2) lie:
  a route planned across unscouted ground would be a guess, and the gold contour would have to
  bend around obstacles the player is not supposed to know about — which is itself a tell. With
  the terrain public, the zones say exactly what they mean, and the only thing that can surprise a
  move is an enemy.
- **Broken forest is the one piece of terrain behind the fog.** A tile a tank has felled
  ([§3.2](movement-and-terrain.md#action-points)) is known as broken only once it is in the
  player's `seen` grid. Because breaking and scouting are both permanent, that knowledge only ever
  lags: a tile the player believes standing may be broken, never the reverse. The zones stay honest
  — they under-report a path rather than invent one — and terrain still never surprises a move.
- Every player keeps **two grids**, and `seen` is the load-bearing one:
  - **`seen`** — every tile this player has ever scouted. It is drawn as a fog tint over the ground
    nobody of theirs has reached, and **it is what gates the rules**: an enemy standing on a tile
    you have scouted is visible to you, can be fired on (§3.3) and can be inspected (§3.13).
    Scouting is permanent. Once a tile is in `seen` it never leaves.
  - **A hit is a second way into `seen`.** Every shot that resolves against a target, the drone
    strike included, adds the attacker's tile to the `seen` of the target's side before the damage
    lands (§3.3.1). Only that side learns it; a third player does not.
  - **`visible`** — the tiles inside some unit's vision diamond *right now*. Its job is to extend
    `seen`; the rules do not read it directly.
- **Scouting is one-way, and that is the point.** A tile you looked at once stays open for the rest
  of the match, so reconnaissance is an investment rather than a chore — the scout car that dies
  on turn two has still bought you everything it saw. This matches the reference, which keeps a
  single permanent grid and draws enemy units from it.
- `visible` is recomputed for the active player from scratch at the start of their turn and after
  every move step, and unioned into `seen`. Never carry another player's grids into the renderer.

**What this costs, stated plainly, because it is the price of the rule above.** Two things in
this document lean on *not* being seen, and both weaken as a match goes on. Return fire is not one
of them: retaliation reads no vision at all, because the hit has already revealed the shooter
(§3.3.1), so being unscouted protects a unit only until it fires.

- **The firing envelope** is the range circle intersected with `seen`, not with the vision diamond.
  The diamond still decides how fast the map opens, which is why infantry's 5 matters — but it no
  longer decides what you may shoot.
- **§3.9's drone visibility check** is inert over scouted ground, exactly as it was before the
  metric split. It bites only on ground nobody has been to.

None of that is a defect; it is what "scouted stays open" means. It is written down so nobody
later reads §3.3.1 and concludes vision is doing more work than it is.

### Cover in buildings

Infantry on a `BUILDING` tile (not `RUBBLE`, never a vehicle) is **hidden from every enemy side
even on `seen` ground**, until that side *finds* it. While hidden it is not visible, cannot be fired
on or struck by a drone, cannot be inspected, and is left out of that side's planning occupancy —
a route that bent around the house would tell the player who is inside. A move walked into it
stops on the tile before, exactly as it does for an unseen enemy.

A side finds a unit in cover when:

- **any living unit of that side stands in one of the eight cells around it** (`dx*dx + dy*dy <= 2`).
  This is checked for every side after every move step of any unit — the walker passing a house,
  and the squad itself entering a house next to an enemy — and at turn start; or
- **it hits a unit of that side** — a shot, a retaliation or a drone strike, at the same moment the
  hit reveals the shooter's tile (§3.3.1), before the damage lands.

**Found stays found until the unit leaves that tile.** The finders may walk away; the squad stays
visible to them. Any move off the tile clears every side's finding, and entering a building again
hides it from everyone until it is found anew. Off a building, the normal `seen` rule applies.

The one query for "does this player know about this unit" is `BattleState.can_see_unit()`; every
rule that asks it goes through there.

**`ERR_TARGET_NOT_VISIBLE` no longer describes its own condition.** It now means "the target stands
on ground you have never scouted", or an enemy in cover that side has not found. The identifier is kept because localisation may key on it, but
the UA and EN strings must be written against the *meaning*, not the name — "you have not scouted
that ground" rather than "you cannot see that". A player who has watched an enemy walk into the
open and is then told they cannot see it will read the game as broken.
- **The handover gate is mandatory.** Between turns the board is blanked and a full-screen
  "Pass the device to Player N" panel is shown; the board only comes back on an explicit confirm.
  Do not make this skippable, do not animate through it, and do not let the camera position from
  the previous player's turn leak the location of their units — recentre on the incoming player's
  first unit.

## Mines

- Laid by engineers, invisible to everyone except the owner.
- **The search runs at the start of the engineer's owner's turn and from every tile the engineer
  passes through** — not only from the tile it stops on. An engineer sweeps as it advances, so a
  mine glimpsed in the middle of a route is found even if the engineer drives on past it.
- **A tile occupied by a unit is never entered** (§3.2), so a unit standing on a mine keeps it from
  detonating: whoever is blocked stops in front and takes nothing, and the mine stays buried.
- **Only an engineer finds an enemy mine**, and it finds one within its own `vision` radius —
  the same diamond as tile fog (§3.1), so a revealed mine is always on a tile you can actually
  see. Visibility is **per player**, tracked on the mine, exactly like tile fog.
- Driving onto an unrevealed mine detonates it.
- **A known enemy mine is an obstacle**: planning treats it like an occupied tile,
  so routes and both movement zones bend around it and its tile is not a legal destination. Your
  own mines never are.
- **An engineer that finds a mine on its route mid-walk stops in front of it**, with the same halt
  as for an unseen unit, and pays only for the tiles it entered.

The engineer restriction is the reference's rule and it is adopted deliberately ([§4](../reference/blitzkrieg.md)). It is what
makes a minefield a threat rather than an inconvenience: without an engineer leading, a column
drives in blind, and the engineer finally has a reason to be at the front of the advance rather than
behind it. The trade is that the radius is the engineer's full vision (3) rather than one tile —
fewer units can search, but the one that can, searches properly.
