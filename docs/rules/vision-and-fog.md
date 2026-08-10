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
- Every player keeps **two grids**, and `seen` is the load-bearing one:
  - **`seen`** — every tile this player has ever scouted. It is drawn as a fog tint over the ground
    nobody of theirs has reached, and **it is what gates the rules**: an enemy standing on a tile
    you have scouted is visible to you, can be fired on (§3.3), can be inspected (§3.13), and can
    fire back (§3.3.1). Scouting is permanent. Once a tile is in `seen` it never leaves.
  - **`visible`** — the tiles inside some unit's vision diamond *right now*. Its job is to extend
    `seen`; the rules do not read it directly.
- **Scouting is one-way, and that is the point.** A tile you looked at once stays open for the rest
  of the match, so reconnaissance is an investment rather than a chore — the scout car that dies
  on turn two has still bought you everything it saw. This matches the reference, which keeps a
  single permanent grid and draws enemy units from it.
- `visible` is recomputed for the active player from scratch at the start of their turn and after
  every move step, and unioned into `seen`. Never carry another player's grids into the renderer.

**What this costs, stated plainly, because it is the price of the rule above.** Three things in
this document lean on *not* being seen, and all three weaken as a match goes on:

- **§3.3.1's impunity** — "an attacker the defender cannot see fires with impunity" — now means
  ground the defender has **never scouted**. That is most of the map on turn one and very little of
  it by turn ten. Artillery firing without reply is an opening-game weapon, not a permanent one.
- **The firing envelope** is the range circle intersected with `seen`, not with the vision diamond.
  The diamond still decides how fast the map opens, which is why infantry's 5 matters — but it no
  longer decides what you may shoot.
- **§3.9's drone visibility check** is inert over scouted ground, exactly as it was before the
  metric split. It bites only on ground nobody has been to.

None of that is a defect; it is what "scouted stays open" means. It is written down so nobody
later reads §3.3.1 and concludes vision is doing more work than it is.

**And the first-order consequence, which is bigger than all three and must not be discovered in
playtest.** `seen` grows by roughly `(2·vision + 1) × path_length` tiles per moving unit per turn.
With a handful of units of vision 3–5 each covering three to six tiles a turn, `seen` approaches
the whole board within a few turns. **From that point the fog hides only mines.** Every enemy unit
is permanently visible, shootable, inspectable and able to retaliate, with no spotter anywhere.

Read plainly: **hiding enemy positions is an opening mechanic, not a standing one.** Retreating
into fog is impossible. Ambush is impossible. What the handover gate protects in the late game is
mine locations, AP residue and intent — not position. That is a real narrowing of pillar 2, and it
is the direct price of making reconnaissance permanent; the reference makes the same trade.

It is recorded rather than corrected, because correcting it means re-fogging tiles, which takes
back what a dead scout bought and is exactly the model this project moved away from. If playtest
says the late game is too transparent, the dial to reach for is **map size against roster size** —
a board nobody can sweep keeps unscouted ground on it — not a decay rule on `seen`. No maps exist
yet, so the crossover turn is unmeasured.
**`ERR_TARGET_NOT_VISIBLE` no longer describes its own condition.** It now means "the target stands
on ground you have never scouted". The identifier is kept because localisation may key on it, but
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
