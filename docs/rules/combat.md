# Combat

The detail behind §3.3, §3.3.1, §3.4 and §3.7 of CLAUDE.md — the damage formula, retaliation, directional armour and experience.

[back to CLAUDE.md](../../CLAUDE.md)

Damage, in order. `A` = attacker's `attack`, `V` = attacker's class experience level (§3.7):

```
dmg  = 0.75*A + rand(0, A/4)

if attacker.class != ENGINEER:
    dmg += A * V / 8                        # +12.5% per experience level

if attacker.class == INFANTRY:
    if dist_sq <= 2: dmg *= 4               # close assault — grenades, demolition charges
    # note: no armour subtraction at all for infantry attacks
else:
    R = target.armour[sector]               # front / side / rear, see 3.4
    dmg -= 0.75*R + rand(0, R/4)

if attacker.class == ARTILLERY:
    if target.class == TANK:          dmg += rand(0, A/2)
    if dist_sq <= 4:                  dmg /= 2      # minimum-range penalty
    if target.class == LIGHT_VEHICLE: dmg /= 2

if target.class == INFANTRY and attacker.class in (TANK, ARTILLERY):
    dmg /= 4                                # armour-piercing rounds against dug-in infantry

dmg = max(10, dmg)
```

The shape this produces is the intended one: infantry is nearly harmless at range and lethal when
it gets adjacent, and it ignores armour entirely — so armour is answered by *closing*, not by
out-shooting. Artillery hits hardest but must stay back and is helpless against anything that
reaches it. Tanks dominate the middle band.

The assault squad's **drone strike** does not use this formula at all — it is a separate action
with its own damage roll and no armour term. See [§3.9](units.md).

**A shot never depends on how much AP the unit has left.** Movement does not degrade accuracy.
Keep it that way unless a playtest says otherwise — it keeps the two-zone UI honest.

**Minimum damage is 10.** Nothing is ever fully immune.

## Retaliation

**A target that survives a shot fires back, immediately, in the same exchange.** Confirmed against
the reference (`class_1.java`, the attack state machine: after the shot resolves, if the target's
HP is still above zero the roles swap and the same damage path runs in reverse).

```
Retaliation
  triggers  : an attack resolved and the target is still alive
  requires  : retaliator has >= fire_cost AP, and the original attacker is within
              the retaliator's range; ENGINEER never retaliates (it has no weapon)
  damage    : the ordinary damage formula, no reduction — armour sector computed
              from the original attacker's facing, as for any shot
  cost      : sets the retaliator's AP to 0, exactly as firing does
  frequency : at most once per exchange; a retaliation never provokes another
```

**What the AP cost actually buys, stated carefully because it is easy to overclaim.** Firing back
zeroes the retaliator's AP for the remainder of the *attacker's* turn, so it cannot answer a second
shot before its own turn comes round. It does **not** cost the unit its own turn: `refill_ap()`
restores both AP and the fired flag at the start of its owner's turn, exactly as the reference
does. A unit that retaliated moves and shoots normally when its turn arrives.

**Retaliation is not free for the defender, and this paragraph used to say it was.** The AP that
gates the answer is whatever the unit *did not spend on its own turn*, so the price is paid in
advance, in movement. A tank has 48 AP, fires for 20 and pays 10 per clear tile: four tiles of
advance leave 8 and no answer at all; two leave 28 and a full-strength one. **The threshold is
exactly the gold movement zone of [§3.2](movement-and-terrain.md)** — a unit that stops in gold
keeps this turn's shot *and* the right to answer, a unit that runs into red is disarmed until its
own turn. Confirmed against the reference, which gates its counter-attack on live AP the same way
and refills only the active player's units ([§4](../reference/blitzkrieg.md)); kept on the owner's
call after a play test where nothing fired back.

The defender's other exposure is that it cannot answer twice in the same round.

An earlier version of this section claimed the retaliator forfeits its next turn. That was never
what the code or the reference did; it was a rationale written into the spec rather than read out
of it, and it is corrected here rather than implemented, on the owner's call.

**The retaliator must be able to see its attacker.** A return shot obeys the same visibility rule
as any other shot, and that rule reads `seen` ([§3.5](vision-and-fog.md)): the original attacker's
tile has to be **ground the retaliating player has scouted at some point** — not ground anyone is
watching right now. The reference gates its counter-attack on AP, range and class alone, and
requiring visibility at all is a deliberate departure from it, recorded in
[§4](../reference/blitzkrieg.md).

The consequence is the point: **an attacker the defender has never scouted fires with impunity.**
That makes reconnaissance a weapon rather than a convenience — but it is an **opening-game**
weapon, and the wording matters, because an earlier version of this section said "cannot see at
that moment" and meant something much stronger and much more permanent.

Scouting is one-way, so the ground a player has never looked at only ever shrinks. Impunity is
widest on turn one and close to gone by the time both sides have driven across the map:

- Artillery has range 5 and vision 3, and firing from maximum range at a gun whose owner has never
  scouted your firing position is genuinely free. Two guns at range 5 do not trade **while the
  ground between them is unscouted** — once either side has swept it, they trade normally, and
  counter-battery fire becomes a question of who shoots first rather than who has eyes.
- Infantry sees furthest (5) of anything in the game, which makes it the fastest opener of ground
  rather than the permanent enabler of everyone else's shots.
- Killing the enemy's spotters no longer takes their vision away — what they have scouted, they
  keep. It slows the *growth* of what they can shoot at, which is worth most early and least late.

This reshapes the economics of shooting, and that is the point:

- Firing on a healthy target inside its range invites a full-strength answer.
- Artillery finally has a concrete reason to hold maximum range: at 5 against a tank's 4, it
  shoots without reply. The same is true of the drone strike at range 5.
- Finishing a wounded unit becomes a rule rather than a habit — the dead do not shoot back.
- Flanking costs more than it did: closing to a side or rear arc usually puts you inside the
  target's own range.

Retaliation damage feeds the retaliator's class experience pool like any other damage.

## Facing in an exchange

Firing turns the shooter. Being shot does not turn the target. The order is the rule:

1. The attacker turns onto its target, **before** its shot resolves.
2. The target is hit in the sector it faced **when the shot was fired** — it has not turned yet, so
   flanking pays in full.
3. A retaliator turns onto its attacker **after** the damage lands, and only if it actually fired
   back. No AP, out of range, an engineer, or an attacker it cannot see — no answer, no turn.
4. The drone strike turns the squad too, though it computes no sector. One rule, no exceptions.

Turning is free and is never an action on its own. A shooter already facing its target does not
turn — the turn event means the facing changed, not that someone fired.

**Retaliation therefore always lands on the attacker's front.** Arithmetic, not tendency: facing
snaps to one of eight directions, at most 22.5° off, and the front sector runs to 45°, so the return
vector cannot leave it. You cannot shoot from a flank and be answered in one.

The whole unit turns, hull included. Turning only a turret was considered and deferred — armour
rides on the hull, so a fixed hull would keep flanking paying in full. That is a different rule, not
a different animation.

**What it costs:** a static flank is now a one-shot asset. The defender ends the exchange pointed at
whoever shot it, for zero AP, on someone else's turn — so the second through fourth shots from the
same tile are worth 24–52% less than the first.

**What it buys:** orientation becomes steerable. A cheap shot from one axis pulls the target's front
onto itself; the real shot comes from another axis into the plate that just swung away, up to +94%
better. Position stops meaning *hold the rear arc* and starts meaning *choose which arc they show
you* — a play with two units in it instead of one. That is the trade, and it is why the cost is
accepted rather than softened.

**Watch in playtest:** an armoured car needed 10 shots to kill a heavy tank and now needs 31, mostly
sitting on the damage floor. The floor invariant holds; whether light vehicles should be this
helpless against heavy armour is a question for the table, not the formula.

## Directional armour

Each unit carries three armour values: `front`, `side`, `rear`. The sector is chosen from the
angle between the target's facing vector and the vector from target to attacker:

- roughly beyond 45° off the facing axis → **side**
- behind the target (negative dot product) → **rear**
- otherwise → **front**

Implement with integer dot products against the 8 unit direction vectors, no trigonometry:

```
v   = attacker_pos - target_pos
f   = DIRS_8[target_facing]
dot = f.x*v.x + f.y*v.y
sector = SIDE if 2*dot*dot <= len_sq_f * len_sq_v      # cos²θ <= 1/2, i.e. 45° or wider
         else (REAR if dot < 0 else FRONT)
```

The comparison is cross-multiplied rather than divided. An earlier form of this rule scaled
`cos²` by 32 and compared against 16; integer division truncated the quotient, so the band
`cos² ∈ [0.5, 0.53125)` — angles between 43.1° and 45° — fell into SIDE when it belonged to
FRONT or REAR. The two forms first disagree at a separation of 23.35 tiles, which no weapon in
the game can reach (longest range is 5), so this changes no shot that can actually be taken. The
cross-multiplied form is kept because it is exact, has no division, and cannot drift.

Flanking is the main skill expression in the game. The UI must always show which sector a shot
will land in **before** the player commits.

## Experience

Progression is **per unit class, per player**, and it is earned by fighting, not bought.

- Each class has an XP pool. Damage dealt by a unit adds that amount to its class's pool.
- Levels 0→5. On crossing a threshold the pool is reduced by the threshold and the level goes up.
- Each level is worth `+A/8` damage (+12.5% of base attack).
- Thresholds, per class (infantry, light, tank, artillery):

```
INFANTRY       150,   375,   938,  2344,  5859
LIGHT_VEHICLE  700,  1750,  4375, 10938, 27344
TANK          1000,  2500,  6250, 15625, 39063
ARTILLERY     2000,  5000, 12500, 31250, 78125
```

- Engineers have no experience (they deal no damage).
- In skirmish, experience is **per match** — it starts at 0 and does not persist between matches.
  Persistent profiles belong with the campaign, not before it.
