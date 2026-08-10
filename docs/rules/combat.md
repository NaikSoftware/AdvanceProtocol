# Combat

The detail behind §3.3, §3.3.1, §3.4 and §3.7 of CLAUDE.md — the damage formula, retaliation, directional armour and veterancy.

[back to CLAUDE.md](../../CLAUDE.md)

Damage, in order. `A` = attacker's `attack`, `V` = attacker's class veterancy level (§3.7):

```
dmg  = 0.75*A + rand(0, A/4)

if attacker.class != ENGINEER:
    dmg += A * V / 8                        # +12.5% per veterancy level

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

So retaliation is close to free for the defender, and deliberately so — the cost of shooting falls
on the *attacker*, who takes a full-strength answer for opening fire on a healthy target inside its
range. The defender's only exposure is that it cannot answer twice in the same round.

An earlier version of this section claimed the retaliator forfeits its next turn. That was never
what the code or the reference did; it was a rationale written into the spec rather than read out
of it, and it is corrected here rather than implemented, on the owner's call.

**The retaliator must be able to see its attacker.** A return shot obeys the same visibility rule
as any other shot: the original attacker's tile has to be visible to the retaliating player at
that moment. The reference gates its counter-attack on AP, range and class alone, and this is a
deliberate departure from it — recorded here as [§4](../reference/blitzkrieg.md) requires.

The consequence is the point: **an attacker the defender cannot see fires with impunity.** That
makes vision a weapon rather than a convenience, and it gives the roster's asymmetries teeth:

- Artillery has range 5 and vision 3. Firing from maximum range at something that has no spotter
  covering the gun is genuinely free — and two guns at range 5 do *not* trade, because neither
  sees the other. Counter-battery fire needs eyes, not just range.
- Infantry sees furthest (5) of anything in the game. A rifle squad forward of the line is what
  turns your armour's shots into safe ones and the enemy's into answered ones.
- Killing the enemy's spotters is therefore an attack on their ability to shoot back at all.

This reshapes the economics of shooting, and that is the point:

- Firing on a healthy target inside its range invites a full-strength answer.
- Artillery finally has a concrete reason to hold maximum range: at 5 against a tank's 4, it
  shoots without reply. The same is true of the drone strike at range 5.
- Finishing a wounded unit becomes a rule rather than a habit — the dead do not shoot back.
- Flanking costs more than it did: closing to a side or rear arc usually puts you inside the
  target's own range.

Retaliation damage feeds the retaliator's class veterancy pool like any other damage.

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

## Veterancy

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

- Engineers have no veterancy (they deal no damage).
- In skirmish, veterancy is **per match** — it starts at 0 and does not persist between matches.
  Persistent profiles belong with the campaign, not before it.
