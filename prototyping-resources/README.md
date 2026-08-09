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
- **No national markings, flags or identifiable real vehicles.** The setting is deliberately not
  fixed yet (§2), so everything is an era-neutral archetype.

**What it gets wrong — fix on the next pass:**

- **No fog of war.** The whole board is lit and visible. The single most distinctive thing about
  this game is that each player has their own fog on a shared screen, with remembered terrain
  drawn dimmed and *without* live units (§3.5). The concept dodges it by making the map a floating
  diorama island on a neutral background.
- Infantry is drawn as several separate figures. A squad is **one model on the tile** (§3.6) — for
  draw calls and for grid readability.
- Top-left is a menu button where a turn indicator belongs.
