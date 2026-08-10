# Vision, fog of war and mines

The detail behind §3.5 and §3.11 of CLAUDE.md — what each player can see, and what is hidden under the ground.

[back to CLAUDE.md](../../CLAUDE.md)

## Vision and fog of war

- Each unit has a `vision` radius, measured as a Manhattan diamond ([§3.1](movement-and-terrain.md)) — a step count on the
  4-directional grid, not the same shape as weapon range. Infantry sees furthest (5), artillery
  least (3) — scouts are infantry, not vehicles.
- **The fog hides enemy units, not the map.** Terrain is public from the first turn: the whole
  board is drawn, at full brightness, whether or not anyone has been near it. What the fog conceals
  is the enemy — where their units are, and the mines they have laid.
- This is a deliberate design choice and not an oversight. Hiding the ground would make the opening
  of a match an exercise in map discovery, and it would make the two movement zones (§3.2) lie:
  a route planned across unscouted ground would be a guess, and the gold contour would have to
  bend around obstacles the player is not supposed to know about — which is itself a tell. With
  the terrain public, the zones say exactly what they mean, and the only thing that can surprise a
  move is an enemy.
- Every player keeps **two grids**: `visible` (in someone's vision right now) and `seen` (ever
  observed). `visible` is the load-bearing one — it decides which enemy units are drawn, which can
  be shot at (§3.3), which can be inspected (§3.13), and whether a retaliation is possible
  (§3.3.1).
- **`seen` records what the player has scouted, and the view draws it.** The terrain under it is
  not a secret — the map is public — but *whether you have been there* is real information and the
  player is entitled to see it at a glance. It is drawn as a fog tint over unscouted ground: the
  board is legible everywhere, and the tint says "no one of yours has been here". The reference
  keeps the same grid.
- Visibility is recomputed for the active player from scratch at the start of their turn and after
  every move step. Never carry another player's visibility into the renderer.
- **The handover gate is mandatory.** Between turns the board is blanked and a full-screen
  "Pass the device to Player N" panel is shown; the board only comes back on an explicit confirm.
  Do not make this skippable, do not animate through it, and do not let the camera position from
  the previous player's turn leak the location of their units — recentre on the incoming player's
  first unit.

## Mines

- Laid by engineers, invisible to everyone except the owner.
- **The search runs at the start of the engineer's owner's turn and from every tile the engineer
  passes through** — not only from the tile it stops on. A sapper sweeps as it advances, so a mine
  glimpsed in the middle of a route is found even if the engineer drives on past it.
- **A tile occupied by a unit is never entered** (§3.2), so a unit standing on a mine keeps it from
  detonating: whoever is blocked stops in front and takes nothing, and the mine stays buried.
- **Only an engineer finds an enemy mine**, and it finds one within its own `vision` radius —
  the same diamond as tile fog (§3.1), so a revealed mine is always on a tile you can actually
  see. Visibility is **per player**, tracked on the mine, exactly like tile fog.
- Driving onto an unrevealed mine detonates it.

The engineer restriction is the reference's rule and it is adopted deliberately ([§4](../reference/blitzkrieg.md)). It is what
makes a minefield a threat rather than an inconvenience: without a sapper leading, a column drives
in blind, and the engineer finally has a reason to be at the front of the advance rather than
behind it. The trade is that the radius is the engineer's full vision (3) rather than one tile —
fewer units can search, but the one that can, searches properly.
