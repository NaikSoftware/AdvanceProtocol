# Prototyping resources

Generated visual references. **Nothing here is a shipping asset** — these exist to pin down art
direction and to argue about, not to be imported.

## `battlefield-concept-01.jpg`

First target for how a turn should look on screen. Generated from a prompt built out of the rules
as they stood after Phase 1's core layer, so most of what it shows is a real mechanic rather than
decoration.

**What it gets right, and what each thing is:**

- **Fixed orthographic isometric camera**, roughly 45° yaw and 52° pitch. Not a style choice — the
  whole poly budget assumes undersides are never seen (§8).
- **The two movement zones** (§3.2): gold immediately around the selected vehicle for tiles it can
  reach *and still act from*, red beyond it for tiles that would leave too little AP. This is the
  primary UI of the game and the concept treats it as such.
- **Dashed path with a facing arrow** — facing is an explicit player choice because it feeds the
  directional armour model (§3.4).
- **Persistent battle scars** (§8): a burnt-out wreck with its smoke column still standing,
  craters, deep mud ruts holding water. The map is supposed to tell you where the fighting was.
- **Ground state in the HUD** as a labelled `MUD` icon (§3.12) — the one weather-ish thing that
  touches the numbers, so it must always be visible.
- **Unit card** with silhouette, HP bar and AP pips; **one greyed-out action button**, because a
  rule that cannot be shown in the UI is a rule to reconsider (§10).
- **No national markings, flags or identifiable real vehicles.** That prohibition is permanent —
  the sides are fictional and stay fictional (§2).

**What the next pass must change, now that the setting is fixed.** This image was generated while
§2 was still open, so it is era-agnostic by default rather than by design. The setting is now
**near-future conventional war between fictional states** — so the next concept needs composite
and slat armour, thermal optics, digital-pattern camouflage and modern infantry kit, none of which
this image commits to.

**What it gets wrong — fix on the next pass:**

- **No fog of war.** The whole board is lit and visible. The single most distinctive thing about
  this game is that each player has their own fog on a shared screen, with remembered terrain
  drawn dimmed and *without* live units (§3.5). The concept dodges it by making the map a floating
  diorama island on a neutral background.
- Top-left is a menu button where a turn indicator belongs.

**Not a defect, though it looks like one at first glance:** the infantry is drawn as a small group
of figures rather than a lone soldier. That is correct and wanted — a squad should look like a
squad. §3.6 asks for *one asset per tile* (one mesh, one draw call, one tile footprint), not one
figure; several figures sharing a base satisfy it. What would be wrong is independently instanced
and animated soldiers, or a group spilling over a tile boundary so you cannot tell which square
the unit is on. Neither happens here.
