# Vision, fog of war and mines

The detail behind §3.5 and §3.11 of CLAUDE.md — what each player can see, and what is hidden under the ground.

[back to CLAUDE.md](../../CLAUDE.md)

## Vision and fog of war

- Each unit has a `vision` radius, measured as a Manhattan diamond ([§3.1](movement-and-terrain.md)) — a step count on the
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

## Mines

- Laid by engineers, invisible to everyone except the owner.
- **Only an engineer finds an enemy mine**, and it finds one within its own `vision` radius —
  the same diamond as tile fog (§3.1), so a revealed mine is always on a tile you can actually
  see. Visibility is **per player**, tracked on the mine, exactly like tile fog.
- Driving onto an unrevealed mine detonates it.

The engineer restriction is the reference's rule and it is adopted deliberately ([§4](../reference/blitzkrieg.md)). It is what
makes a minefield a threat rather than an inconvenience: without a sapper leading, a column drives
in blind, and the engineer finally has a reason to be at the front of the advance rather than
behind it. The trade is that the radius is the engineer's full vision (3) rather than one tile —
fewer units can search, but the one that can, searches properly.
