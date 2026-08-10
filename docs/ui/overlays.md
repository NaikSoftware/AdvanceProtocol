# What the board shows, and when

The detail behind §3.13 of CLAUDE.md — the movement zones, the fire radius, and unit inspection.

[back to CLAUDE.md](../../CLAUDE.md)

Two overlays answer two different questions, and they are deliberately not shown the same way.

**The movement zones are always on** ([§3.2](../rules/movement-and-terrain.md)), for the selected unit only, recomputed after every
action. **Drawn as two nested contours, not as filled tiles.** A fill would hide the terrain and
the battle scars underneath, and those are both the atmosphere budget ([§8](../art-direction.md)) and real information —
the map is supposed to tell you where the fighting has been. Contours are also cheaper on a phone
screen and do not fight the fog, which is itself a darkening of tiles.

The reference draws these zones the same way, as contours, and splits them on exactly the same
test (`remaining_ap >= fire_cost`). It colours them green and red; this project keeps gold and red
from §3.2, because red/green is the most common colour-vision deficiency and the two zones are the
primary UI of the game.

**The fire radius is on demand: tap a unit to see its reach.** Not always on — it would sit on top
of both movement zones as a third overlay on a phone screen. Movement is what you are choosing
continuously; range is a question you ask occasionally. The reference makes the same split, with
range bound to hold-a-key.

**Any visible unit can be inspected, including an enemy's.** This is the feature worth porting.
Tapping an enemy shows *its* range and which of **your** units stand inside it. With retaliation
([§3.3.1](../rules/combat.md)) that is not a convenience, it is the information the central decision of a turn rests on:
firing on a healthy target inside its range invites a full-strength answer, and you cannot judge
that without seeing the answer's reach. Fog still applies — a unit standing on ground you have
never scouted cannot be inspected ([§3.5](../rules/vision-and-fog.md)). Note that this is a weaker
bar than it sounds: once the ground has been scouted, the enemy on it stays inspectable whether or
not anyone of yours is still watching.

**Own unit and enemy unit are gated differently, and this is a deliberate departure from the
reference.**

| inspecting | ring | marked units |
| --- | --- | --- |
| your own | always, even at 0 AP | enemies it can fire on **right now** — range, visibility and AP all checked |
| an enemy | always | your units inside its range and seen by **that unit alone** — **AP deliberately not checked** |

**The drone strike counts as reach, for both rows.** It is a separate action with its own range,
its own list of legal targets and its own ammunition ([§3.9](../rules/units.md)), so it gets its
own ring and its own marks rather than being folded into the ordinary shot — showing a firing
mark where no ordinary shot exists would be a lie about a different action.

For an inspected **enemy** assault squad that still has drones, the forecast must include them.
Leaving them out under-reports the single most dangerous action in the game, and does so precisely
for the units it endangers: a squad shown as a range-3 threat actually reaches 5, ignores armour
entirely, and by [§3.3.1](../rules/combat.md) shoots without reply. A squad with no drones left is
forecast at its ordinary range and no further.

**Gating the forecast on ammunition reveals nothing, because the drone count is public** — shown
on any visible unit to every player, not only its owner ([§3.9](../rules/units.md)). The forecast
is reading a number already on screen.

That rule was written down precisely because of this overlay. An earlier version of this document
asserted the same conclusion by *interpreting* §3.9's "visible on the unit at all times" as
meaning public to everyone, which it did not say. In a two-player match the distinction is idle —
you witnessed every strike your opponent made, because it landed on you. In a three-player match
it is not: player 1 can spend a drone on player 2 behind the handover gate, and had the count been
private, the disappearing drone ring would have reported to player 0 an action they never saw.
That is the same shape as the AP residue this document refuses to show, so it could not be
answered the opposite way by assertion. Making the count genuinely public resolves it rather than
trading one flaw for another — and the matchup triangle wants it anyway, since screening a drone
squad with infantry is a response to a threat that has to be known to be live.

The drone's marks obey the action's own rules, not the ordinary shot's: vehicle classes only, so
the observer's infantry is never marked as a drone target. **Two different gates are in play here
and they must not be confused.** Whether a unit can be *inspected at all* is decided by `seen`; the
marks drawn inside an inspected **enemy's** ring are computed from that unit's own vision diamond,
because the forecast may not read its owner's network (below). For **your own** squad the ring
answers the same question as the gun's — what can I hit right now — so ammunition gates it too: a
squad out of drones has no drone ring.

**The drone is where the floor understates the most, and the UI copy should say so.** A strike
needs the *owner's* vision like any other shot, so a squad whose network sees a tank outside its
own diamond genuinely can hit it — and the forecast, computed from that one squad alone, will not
mark it. The gap between forecast and reality is therefore widest on exactly the action that
ignores armour, out-reaches everything, and draws no reply. Under-reporting is still the right
trade against leaking where the spotters are, but the player must be told that the drone ring is
the squad's *unaided* reach, not its real one.

The reference gates both on the shooter's current AP. For an enemy that leaks state: AP is only
refilled at the start of its owner's turn, so "this unit is spent" is the residue of actions you
may not have witnessed — it retaliated on someone else's turn, behind the handover gate. It is
also the less useful reading. What you want from an enemy is the **threat forecast** — who does
this thing hit when its turn comes — and it will have full AP by then regardless. So an enemy's
marks answer "who is in danger", and your own unit's marks answer "what can I shoot now".

**An enemy's marks are computed from that unit alone, never from its owner's vision.** A shot
needs the *owner's* vision, not the shooter's — a spotter elsewhere on the map extends what the
whole force can fire on (§3.3.1). But that network is hidden, and drawing marks from it would
reveal that an unseen spotter exists. So the forecast uses only the inspected unit's own range and
own vision, which is information the player could work out by hand from a public roster and a
position they can already see.

The consequence must be stated in the UI rather than hidden: **the marks are a floor, not a
ceiling.** A unit not marked can still be shot. That is the honest version — the alternative is an
overlay that quietly leaks the position of scouts.

**The gap is much wider than "the enemy might have a spotter you have not found", and it widens as
the match runs.** The forecast measures the inspected unit's reach with its own vision diamond,
because that is all it may read. The enemy's *real* reach is their range circle intersected with
their `seen` grid ([§3.5](../rules/vision-and-fog.md)) — a grid that only grows, and that by
mid-match may cover most of the board. So by then a tank forecast as threatening a handful of tiles
is in practice threatening everything inside its circle. The UI copy must not promise more than
"these are certainly in danger"; a player who reads the unmarked tiles as safe will be wrong, and
increasingly wrong the longer the match goes on.

Both computations belong in `core/` and neither may be re-derived in the view. **The envelope is a
range circle intersected with the observer's `seen` grid** ([§3.5](../rules/vision-and-fog.md)) —
*not* a circle intersected with a vision diamond, which is what this paragraph used to say and what
a renderer would most plausibly guess. The diamond appears in exactly one place here: the marks
inside an enemy's ring, which are deliberately computed from that unit alone. A second
implementation of either geometry in the renderer is exactly the drift this document exists to
prevent.

**The movement zones are drawn from the fog-filtered occupancy, which is also what the move is
planned against** ([§3.2](../rules/movement-and-terrain.md)). The overlay and the order agree by
construction: what you are shown as reachable is exactly what the game will attempt.

That matters more than it looks. Had the zones been drawn from the true occupancy — every live
unit, including invisible ones — an unseen enemy would punch a unit-shaped hole in the gold
contour and give away its position. Had the *order* been planned against the true occupancy
instead, the route would silently detour around it, which leaks the same fact in a subtler and
harder-to-notice way.

So the zones are, like the enemy forecast above, a **best case**: a path shown as open can turn
out to be blocked by something you had not seen, and the move stops on the tile before it. That is
the honest failure, and it is the trade this whole section makes — a player may be surprised by
what they could not know, but never informed by it.
