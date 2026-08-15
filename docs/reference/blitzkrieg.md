# Resolving disputes about the rules

The detail behind §4 of CLAUDE.md — the reference of record, where to look in it, and every finding recovered from it so far.

[back to CLAUDE.md](../../CLAUDE.md)

When something in the specification is ambiguous, contradictory, or simply missing — and the answer
matters for balance or feel — **check how the original did it before inventing an answer.**

Reference of record, reverse-engineered Java MIDP sources:
<https://github.com/NaikSoftware/Blitzkrieg>

Where to look (the code is obfuscated; these are the mappings that have already been recovered):

| file | what is in it |
| --- | --- |
| `src/defpackage/class_3.java` | the unit — stat tables in `<clinit>`, damage in `method_160`, armour sector in `method_159`, engineer verbs in `method_16x–17x` |
| `src/defpackage/class_1.java` | the player — objectives, experience thresholds and level-up in `method_97` |
| `src/defpackage/class_2.java` | AI player, extends the player class |
| `src/defpackage/GameCanvas.java` | board, terrain cost (`method_70`), rendering, save format |

Field-name mappings recovered so far, for `class_3`: `field_221` attack · `field_222` vision ·
`field_223` max AP · `field_224` max HP · `field_225` range · `field_226` fire cost ·
`field_227` armour F/S/R · `field_228` cross-country · `field_248` current AP · `field_250` class
index · `field_257` this unit's max HP · `field_259` current HP. `GameCanvas.method_2(n)` is
`rand(0, n)`, returning 0 for `n <= 0`.

Note the two max-HP fields: `field_224` is the per-class stat table, `field_257` is the copy taken
at construction (`field_259 = field_257 = field_224[type]`, `class_3:342`) and is what the renderer
divides by and what repair clamps to. Anything reading "max HP" reads the per-unit copy.

Two rules about using it:

- **It is a reference, not a dependency.** No code and no assets are copied from it. Advance
  Protocol is its own implementation, in its own engine, with its own art.
- **It is not automatically right.** It has quirks that look like bugs. Where the specification
  knowingly departs, it says so. When you consult it and find something surprising, record the
  finding in this file rather than silently matching or silently ignoring it.

### Findings from the reference

- **Tank → artillery damage is quartered in the original — confirmed, and deliberately not
  adopted.** `class_3.method_160` carries a distinct `>>= 2` branch for attacker `TANK` against
  target `ARTILLERY`, separate from the `÷4` that both tanks and artillery take against infantry.
  This project stays at ×1.0, and the reason is now stronger than the original "an unarmoured
  immobile gun ought to be easy meat" instinct: **retaliation ([§3.3.1](../rules/combat.md)) did not exist when that
  note was written.** With both rules together, a tank firing on a field gun deals the floor of 10
  and takes a full-strength answer from a 200-attack weapon — roughly 120 through medium frontal
  armour. Tanks would strictly lose every exchange they started against artillery, nothing but
  infantry could threaten a gun, and the [§3.9](../rules/units.md) triangle would collapse. Two rules that are each
  defensible alone are not defensible together; this is the one that goes.

- **Vision is a Manhattan diamond, weapon range is a Euclidean circle — confirmed and adopted**
  ([§3.1](../rules/movement-and-terrain.md)). This closes the open question that used to sit here. Vision is not a distance comparison
  at all in the original: `class_1.method_121` is a recursive 4-directional flood fill with a
  decrementing budget seeded from the unit's `vision`, and its only guard is a bounds check — no
  terrain, no line-of-sight occlusion. A tile is reached with budget `vision − manhattan_distance`,
  so it is revealed exactly when `|dx| + |dy| <= vision`. Range, by contrast, is
  `method_175(x, y) <= range²` in `class_3.method_164` — a true squared-Euclidean test, and the
  original's own UI draws it as a 360° arc. The two metrics are genuinely different in the source;
  this is not a decompilation artefact.

- **The original gates everything on a single permanent *seen* grid — matched, after this project
  first departed from it and then reversed.** `field_172` is initialised to fogged and every later
  write clears it, never re-fogs. Enemy unit rendering and target selection test that same grid, so
  in the original, once a tile has ever been revealed, units standing on it are visible **forever**.

  This entry previously recorded the opposite decision, and the reversal is worth reading rather
  than just noting. [§3.5](../rules/vision-and-fog.md) does keep two grids — but `seen` is the one
  the rules read, and `visible` exists only to extend it, so the *behaviour* is the original's. The
  earlier version gated firing, retaliation, inspection and move planning on live vision, which
  made an enemy vanish the moment your last spotter looked away.

  What settled it is that permanence is what makes reconnaissance an investment. Under live vision,
  a scout that dies has bought you nothing; under `seen`, it has bought you everything it saw, and
  the scout car earns its place in the roster. The price is real and is written out in
  [§3.5](../rules/vision-and-fog.md): impunity from being unseen decays as the match runs, because
  the ground nobody has scouted only ever shrinks.

  **Two grids are still not pointless.** `visible` remains the live-vision highlight the view will
  draw, and it is what mine detection reads ([§3.11](../rules/vision-and-fog.md)) — a sapper
  searches where it stands, not everywhere it has ever been. That is the one place this project
  keeps a live-vision rule, and it is deliberate: it is also the one thing the fog still hides once
  `seen` has spread across the board.

- **Only engineers detect enemy mines** (`class_1`, guarded on `field_250 == 4`). Adopted ([§3.11](../rules/vision-and-fog.md)).
  Two deliberate differences:
  - The original tests that radius as a Euclidean circle even though its fog is a diamond, which
    can reveal a mine on a tile the player cannot see. This project uses the vision diamond for
    both, so a revealed mine is always on a visible tile.
  - **The original's search is triggered exclusively by the movement driver** — the detection call
    sits in the same per-hop routine as the mine-detonation check, so an engineer that does not
    move searches nothing. Here the search also runs at the start of the owning player's turn, so
    a stationary engineer sweeps its own vision diamond every turn. §3.11 describes detection as a
    property of presence rather than of movement, and a sapper standing one tile from a mine and
    never noticing it reads as a bug rather than as a rule.

- **The fire radius is a hold-to-peek overlay in the original, and it inspects enemies too.**
  Bound to `#` (`GameCanvas` keeps held keys as a bitmask; bit 128), drawn only while the key is
  down and only when the acting player is also the one whose fog is on screen. It draws for the
  unit **under the cursor** — the hit test filters on alive and not-fogged, with no ownership
  check — falling back to the player's own selected unit when the cursor is over empty ground. The
  circle itself is gated on nothing else: a unit with 0 AP still shows it. The target crosshairs
  inside it *are* AP-gated. [§3.13](../ui/overlays.md) adopts the on-demand split and the enemy inspection, remaps the
  interaction to a tap because there is no cursor or key-hold on a touch screen, and departs on the
  AP gate for enemies with the reason given there.

- **The original's own stat tables violate two of [§3.6](../rules/units.md)'s invariants.** Its max-AP table makes the
  **heavy tank the fastest** of all four tanks (56, against the medium's 44), and its armour table
  has **rear thicker than side on every tank**. §3.6 rejects both on purpose — mobility must pay
  for armour, and flanking must be rewarded or the game's main skill expression inverts. Recorded
  here so the departure stays a known one rather than being "corrected" toward the reference by
  someone checking the tables later.

- **Mines detonate on traversal, and mine damage is a roll.** Confirmed against `class_1.method_105`,
  which is called from the movement driver after *every* single-tile hop rather than once at the
  destination: when it finds a marker it applies `90 + rand(0, 90)` to the mover, consumes the
  marker, and returns `true`, which halts the path at that tile. So a minefield cannot be crossed
  by stopping past it, and the unit stops where it detonated — this project matches. The damage
  band is `90..180`, not the flat 120 the plan originally invented; adopted, because a flat number
  would make mines the only damage source in the game that does not roll. Caveat worth knowing:
  in the original the per-tile marker table appears to be shared between mines and objectives, so
  the two may not be distinct concepts there. They are distinct here.

- **Terrain penalties are widely spaced, and tracked vehicles ignore open ground.** Confirmed
  against `GameCanvas.method_68`: the original uses six buckets — `0` road, `5`, `10` ordinary
  ground, `20` rough, `100` built-up, `1000` impassable — and `method_70` is exactly
  `max(10, 10 + penalty - cross_country)`. Two consequences are easy to get wrong and were
  briefly got wrong here:
  - **The spacing is load-bearing.** With `cross_country` in the 5–13 band, any penalty below
    about 13 vanishes under the floor of 10. A compressed table (0–14) makes *every* terrain
    free for *every* tank, and the whole off-road model quietly stops existing.
  - **A medium tank pays the floor on open field, and that is correct.** Field is 10 against a
    cross-country of 12. Roads matter for wheels, artillery and engineers, not for tracks on
    open ground — do not "fix" this by inflating the field penalty.
  - Built-up terrain at 100 is effectively impassable to vehicles (a 48 AP tank cannot pay 98)
    while infantry still walks in at the floor of 10. Buildings are therefore infantry ground
    by arithmetic rather than by a special case. This is emergent, and it is worth keeping.

- **Firing turns the shooter, and so does answering — confirmed, adopted.** Facing there is real
  state, not a sprite: `field_247` is what the armour-sector routine reads. The attack state machine
  starts the attacker rotating onto its target *before* entering the state that resolves damage
  (animated one octant per tick, and damage waits for it). That state reads the target's sector from
  its old facing; only afterwards do the roles swap and the survivor rotate onto the original
  attacker, with the return shot after that.

  Both consequences are adopted: flanking keeps full value, and the return shot always lands on the
  attacker's front — direction snaps to the nearest of eight, at most 22.5° off, inside the 45°
  front cone.

  **Two details deliberately not adopted.** The original turns the survivor whenever it lives — the
  swap happens before it is known whether an answer is even legal, so a unit with no AP or out of
  range still turns. It also turns the selected unit toward any enemy the player taps, before
  deciding the tap was an attack. Here the turn is tied to the action instead: you turn because you
  fired. A turn granted for merely surviving, or for a tap, would be a free reorientation on someone
  else's turn for doing nothing.

- **The HP bar on the board is a dark full-width track with a left-aligned fill drawn over it, and
  it carries no numbers — confirmed, and adopted with one departure.** `GameCanvas.method_26` draws
  a bar of width `w` at `3 px` above the unit, `3 px` tall; the board loop calls it **twice**, first
  with `setColor(0)` and an explicit `field_57 - 1` (one full tile width, black) for *every* unit,
  then with `-1` for each player's units in turn, which makes the routine compute
  `(field_57 - 1) * hp / max`. So the black pass is the empty track and the second pass is the fill,
  growing from the **left edge**, never shrinking toward the centre. Proportions are roughly `20×3`
  px on a `240×320` screen — almost a tile wide and as thin as the display allows.

  Adopted for [§3.13](../ui/overlays.md)'s unit marks: the bar is `48×6` px of texture at
  `pixel_size 0.02` (≈ `0.96 × 0.12` world, near a full tile), a 1 px frame, a dark empty track, and
  a fill that starts at the left inner edge. **All of it in one texture on one `Sprite3D`** — three
  stacked billboard sprites at the same height would z-fight and rotate about three different
  centres, and §8 CLAUDE.md is counting draw calls.

  **Departure: the fill colour.** The original colours the fill by *owner* (`0x0000AC` for the first
  player's units, `0xAC0000` for the second) — the bar is a friend/foe marker that happens to encode
  length. Here the hull already carries the owner's colour, so the bar is free to spend its colour on
  the state that changes: red→green by HP ratio. Reading the original as "HP bars should be red and
  green" would be backwards — that red is a side, not a wound.

- **The `current/max` numerals exist in the original, but on the unit info screen, not over the
  unit.** Screen state `34` draws a `210×7` `drawRect` frame with a `207×4` green fill inset by 2 px
  — the same framed thin bar, an order of magnitude wider — and above it the two numbers, drawn as
  digit sprites either side of a hand-drawn diagonal `drawLine`, i.e. `88/400` assembled by hand.
  This project puts both the framed bar and the numerals over the unit on the board, by the owner's
  call: there is no cursor and no hold-a-key on a touch screen, so an info screen is a tap and a
  dismissal away, and §1.5 wants every number that decides a fight legible without one. Recorded so
  the placement stays a known departure rather than being "corrected" toward the reference later.

- **Retaliation is gated on the retaliator's *leftover* AP — confirmed, and kept.** Asked directly
  by the owner after a play test where nothing ever fired back. The counter-attack is state `13` of
  `class_1`'s attack machine: the shot resolves in state `12`, and if the target still has HP
  (`field_170.field_259 > 0`) the machine queues `field_168 = 13`, swaps the two unit references
  (`class_1:444-448`, attacker becomes target), turns the retaliator onto its attacker, and then
  gates the answer on `class_1:395` → `class_3.method_162` → `method_164(...) && field_248 >=
  field_258` — **in range, not an engineer, and current AP at least the fire cost.** `field_248` is
  live AP, not the maximum, and `class_1.method_107` (turn start) refills only the slice
  `field_159 .. field_159 + field_160`, i.e. **that player's own units**. A unit that spent its AP
  advancing therefore cannot answer during the enemy's turn, in the original exactly as here.

  The fire-cost table is identical too (`class_3:507`, `{10,10,18,18,18,20,20,25,20,14,14,20,30}`),
  so the thresholds are not merely analogous, they are the same numbers.

  **What this costs at the table, since it is not obvious:** a tank has 48 AP, pays 20 to fire and
  10 per clear tile, so four tiles of advance leave 8 and no answer, while two tiles leave 28 and a
  full-strength one. The threshold is exactly the gold movement zone of
  [§3.2](../rules/movement-and-terrain.md) — **stopping in gold keeps both this turn's shot and the
  right to answer; the red zone is disarmed until the unit's own turn.** The rule was already drawn
  on the board; nobody had said out loud that it was also the retaliation rule.
