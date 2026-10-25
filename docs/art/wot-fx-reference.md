# World of Tanks / WoT Blitz battle effects: measured reference

What the owner's benchmark games do with a hit, a kill and a burning wreck, measured from official
Wargaming media and gameplay footage, and translated to our camera. **Reference only.** No frame,
texture, sound or shape from these games is copied or shipped. They are © Wargaming.

Companion to [`damage-fx-research.md`](damage-fx-research.md), which holds the real-world sizes,
the CC0 sources we can ship and the per-weapon/per-round tables. This file adds **what WoT does on
top of reality to make an effect read**, and where we fall short of it.

Contact sheet (internal, not shipped, not in git): `/home/naik/.cache/ap-scratch/fx-ref/wot_fx_sheet.jpg`.
The ids below (W1, K3, B5 …) are the labels on that sheet.

## How the numbers were taken

- Sizes are measured in **hull lengths** on frames where the target's hull is visible next to the
  effect, then converted at **1 hull = 7.5 m** (our tank). WoT hulls are 6–10 m, so allow ±25 %.
  Frames are side-on, so heights are true and widths along the view are foreshortened.
- Times are read from the 30 fps official clips frame by frame (±0.03 s) and from 60 fps gameplay
  at 5–8 fps sampling (±0.1 s).
- Colours: CIE L\*a\*b\* (D65), p10/p50/p90 of a sampled patch, from frames decoded at full size.
  Video compression and WoT's colour grade shift them; treat as ranges.
- **WoT exaggerates.** Its hit bursts are 2–3× the real size from `damage-fx-research.md`. We take its
  *structure, order and timing*; for size we land between reality and WoT (the "ours" column), because
  our tile is 8 m and a burst that wipes the tile hides the board.

## Sources

| id | source | what it shows | timestamps |
| --- | --- | --- | --- |
| WG24 | Wargaming, *The Battle in Detail: Visual Effects and Sound Upgrades* (WoT 2.4), <https://worldoftanks.eu/en/news/general-news/2-4-upgraded-vfx-sfx/>. Clips: `https://content-wg.gcdn.co/eu-content/update-2-4/vfx-sfx/VFX_VIDEO_<AP\|APCR\|HEAT\|HE>_<PEN\|NON-PEN\|RICOCHET>.mp4`, 1920×1080, 30 fps, 12 s | Official per-shell × per-result demos; the page's "Shell Breakdown" table | each clip: distant shot 1.9–4.5 s, close kill 7.6–10 s, pen-hole close-up 10–12 s |
| JOE | WoTB Joe, *Ammo rack exploded!*, <https://www.youtube.com/watch?v=AkkorStaF9M> (Blitz, 60 fps) | Two Blitz ammo-rack kills, flash to burning wreck | 0:29.8–0:35, 0:50.4–0:55 |
| BR | WoT Blitz Best Replays, *Full HP Ammo Rack Compilation*, <https://www.youtube.com/watch?v=wLKyUs5yFsQ> | Blitz fireballs, a wreck burning ≥ 20 s in view, old wrecks' columns | 0:19, 0:37–0:57, 1:01–1:06 |
| DLS | DLSLIVE, *Ammo Rack Compilation 3 [World of Tanks]*, <https://www.youtube.com/watch?v=462Qsin25uA> | PC wreck fire on snow; engine-deck fire on a live tank | 1:06, 4:58–5:03 |
| ARTY | WOT Saint Grizz, *FV3805 Gameplay*, <https://www.youtube.com/watch?v=Cd-_ZjkfXfQ> | WoT artillery view — **straight top-down**, the only WoT view close to ours | 4:00, 4:30, 8:00 |
| 80LV-20 | *World of Tanks Blitz: Mobile Game Development at Wargaming*, 80.lv, 22 Jun 2020 (P. Busko, Y. Krasyukov, I. Shelkovyy), <https://80.lv/articles/world-of-tanks-blitz-mobile-game-development-at-wargaming> | How Blitz builds fire/smoke cheaply | text |
| 80LV-21 | *Making Graphics More Realistic in World of Tanks Blitz*, 80.lv, 14 Jun 2021 (A. Cherepanov, A. Babey) | Blitz 7.0: soft particles, dynamic shadows, hit marks | text |
| 80LV-22 | *Setting Up Graphical Improvements in World of Tanks Blitz*, 80.lv, 20 Sep 2022 | Dynamic resolution, PBR cost, one draw call per grass LOD | text |
| WG10 | *Update 1.0: Graphics Settings Explained*, <https://worldoftanks.eu/en/news/general-news/update-1-0-graphics-settings/> | The Effects quality setting | text |

Not found: any WoT/Blitz talk or note with **particle counts** or **wreck burn durations**. The
durations below are therefore observed, not documented.

## Camera translation (applies to every section)

Our camera: 7 cm/px at the closest zoom (pitch 38°), 22 cm/px at the farthest (pitch 55°). A height
`h` spans `h·cos(pitch)` on screen; a width across the view spans its full length.

| feature | m | close: px | far: px |
| --- | --- | --- | --- |
| tank hull | 7.5 × 3.6 | 107 × 51 | 34 × 16 |
| flame tongue, 2.5 m tall × 1.5 m | | 28 tall × 21 | 9 × 7 |
| hit burst envelope, 7 m | | 100 | 32 |
| kill fireball, 12 m | | 170 | 55 |
| smoke column, 25 m tall | | 280 tall | 65 tall |

What transfers from a third-person game and what does not:

- **Transfers:** the order of layers (white flash → coloured burst → dark smoke → lingering grey), the
  timing, the colour-coding of hit results, the localised wreck fire, the charcoal wreck.
- **Does not transfer:** the full-screen white-out and bloom (K1, B3) — in third person the kill is
  next to the camera; in ours it is 1 % of the screen, and blanking the board hides other units.
  Keep the flash **local** (≤ 2 hull lengths) and let an `OmniLight3D` on the ground do the rest.
  Side-on dark smoke domes that hide the whole tank (W5, K3) also do not transfer: from above, a dome
  over a cell hides the unit the player is about to act on.
- **Gained from our angle:** the ground. In WoT's top-down artillery view (A1) the battle reads mostly
  through **dark, irregular scorch blots, roughly 1.5–2.5 m wide** (estimated against house roofs taken as 10–12 m; not measured against a hull) on the ground and grey-blue smoke haze, not
  through flames. Our scar map is the right tool; fire is small at far zoom (9 px), the column and
  the scorch carry the read.

## 1. Burning destroyed tank

**Where the fire comes from.** Never the whole hull. One source, sometimes two, at an opening:
the turret ring after the turret is gone (B5), the engine deck (B2, B4, DLS 1:06), a hatch or the
penetration hole (K3, K4, W3). The flame starts *inside* the hull and comes out of the opening.

**Size.**

| | WoT/Blitz | ours |
| --- | --- | --- |
| flame bed width | 0.4–0.6 hull (B5: 0.5) | 2.5–3.5 m, the width of the opening |
| flame height above the deck | 0.3–0.5 hull (B2: tongue ≈ 1 turret height) | 2–3 m |
| first 1–2 s after the kill | taller, 0.6–0.8 hull (B1, K4) | 4–5 m, then settles |
| second source | small, 0.1–0.2 hull (K3 hatch) | ≤ 1 m, optional |

**Colour gradient (B5, sampled).** Base white-yellow to orange: L\* 69–74, a\* 28–31, b\* 50–52
(#F19049–#FBA05A), p10 #C5753A. Above the flame the tongue turns translucent brown-grey
(L\* 33–39, a\* 4–5, b\* 9–12) and then neutral grey smoke (L\* 29–36, a/b ≈ 0). There is **no
hard edge** between flame and smoke: the top 30–40 % of the flame is already smoke-tinted.

**The hull stays visible.** The flame covers at most the opening and 0.5 hull above it. The hull
itself is a dark charcoal (B5: L\* 26–41, a\*/b\* ≈ 0, edges lighter) and its top near the fire is lit
orange. Nothing but the fire glows. The wreck is never hidden by its own flames or smoke.

**Glow.** The deck around the opening (≈ 1 m) picks up orange; the ground beside a big fire (P1)
darkens rather than lights — it is a scorch, not a lit patch. One small warm light, not a big one.

**Smoke column.** Rises from the **top of the flame**, not from a separate point.
- Fresh (first ~5 s): black, L\* 20–25 with a cool cast from the sky (K4, W8: #233442–#2A3B47).
- Older wrecks (B6, BR 0:41–0:57): mid grey L\* 40–55, broad and soft, all leaning the same way with
  the wind, still with a small orange point at the base.
- Width grows 2–3× with height; opacity falls with height. Leans 20–40° downwind within 2–3 hull
  lengths of the base (B6).

**Over time (observed; WoT documents none of it).**

| stage | WoT/Blitz | ours, in rounds (see `damage-fx-research.md`) |
| --- | --- | --- |
| burning | big flame + black column for the first 2–5 s, then a steady flame | round 0–1 |
| smouldering | flame shrinks to a point 0.1 hull, column turns grey; seen ≥ 20 s after the kill (BR 0:37→0:57) | round 2–3 |
| smoking | grey wisp, no fire (B6 background) | round 3–4 |
| burnt out | charcoal hull only | 5+ |

**Burnt hull look.** Charcoal grey, neutral, edges slightly lighter, no camouflage and no team
colour left (B2, B5, P1). Blitz swaps the whole hull to this look at the moment of the kill.

**Must have:** one fire source at an opening · flame rising vertically and flickering · white-yellow
base, orange body, smoke-tinted top · column born from the flame top · charcoal hull, orange only
near the fire · column black when fresh, grey later, always leaning downwind.
**Must avoid:** a flame sprite sitting on top of the hull like an icon · the same flame shape on
every wreck · a static or radially symmetric flame (a starburst) · fire covering the whole hull ·
a column that starts beside the flame · smoke so opaque the wreck vanishes.

## 2. Shell hit on armour

WG24's own table, verbatim:

| | AP | APCR | HEAT | HE |
| --- | --- | --- | --- | --- |
| On impact | Grey smoke cloud | Thick white smoke cloud | Bright electric-blue flash with an expanding ring of black smoke | — |
| Non-penetration | Spray of glowing red-hot metal fragments | Spray of incandescent white-hot core fragments | Spray of glowing yellow-green fragments | Large fireball with a slow-moving shower of sparks |
| Penetration | Focused flames erupting from the penetration point, followed by smoke | Sharp, high-pressure flame jets … followed by smoke | Intense flame burst with sparks … followed by smoke | Large flame plume bursting through the penetration point, followed by smoke |

The principle: **the result is readable from the effect alone** — red sparks = it bounced, flame from
the hull = it went in. That suits our "every rule visible" pillar. Our shell types are not a rule, so
take only the pen / non-pen split.

**Penetration (W1–W3, AP pen distant shot, impact at clip t = 2.2 s):**

| t after impact | WoT | ours |
| --- | --- | --- |
| 0–0.07 s | orange-white burst ≈ 2 hull (≈ 15 m) with a spray of fine sparks | white core 2–3 m (L\* 95+), spark spray to 6–8 m |
| 0.1–0.3 s | sparks fly out ≈ 1–2 hull, grey smoke starts | sparks gone by 0.3 s |
| 0.3–1.8 s | grey smoke dome grows to ≈ 3 hull, L\* 43–56, a\* −6…−2, b\* −10…−5 (cool grey); a small fire point (≤ 0.1 hull) at the hole | grey cloud 4 → 7 m, L\* 35–50 |
| 1.8–4 s | smoke thins, hull visible through it | alpha 0 by 1.5 s (EventPlayer awaits) — or let it outlive the event |

**Non-penetration / ricochet (W4, W5):** a red-orange spark burst (L\* 50–60, strongly red) with
**long radial streaks**, some 1–3 hull long; a dark grey puff rises from the hit into a short column
(W5) and the whole thing is gone by ≈ 3 s. For us: 6–12 streaks 1–3 m long, bright core #FFE6B0
fading to red-orange, deflected to one side (a ricochet goes on, not back), no ember, no fire.

**Pen hole decal (K5):** a dark hole with a **red-hot rim** cooling over ≈ 2 s. On our hull at
close zoom a 0.3 m hole is 4 px: skip it.

**Must have:** white-hot core for 2–3 frames · sparks that are streaks, not dots · a smoke puff that
outlives the flash · a visible difference between "went in" (fire point, grey smoke) and "bounced"
(red streaks, no fire).
**Must avoid:** a fireball without a white core · sparks as round blobs · a flat bottom edge where the
quad meets the ground (soft particles) · the hull hidden for longer than 0.3 s.

## 3. HE / shell hit on the ground

**WoT HE (W6–W8, impact at clip t ≈ 2.3 s):**

| t | WoT | colour |
| --- | --- | --- |
| 0–0.2 s | white ball ≈ 1 hull, sparks | L\* 92–99, b\* 2–22 (white to cream) |
| 0.2–0.7 s | orange ball with a dark rim, same size | core L\* 63, a\* 34, b\* 43 (#E17F4D); rim grey L\* 36 |
| 0.7–1.7 s | **black ball** ≈ 1.3 hull rising, ember inside, grey dust low on the ground | L\* 21–24, a\* −3, b\* −10 |
| 1.7–3 s | black thins and drifts | |

WoT's ground hits in gameplay are brown-grey dirt sprays; the official HE clip is a hull hit. In the
top-down artillery view (A1, ARTY 4:00) shell impacts leave **dark, irregular blots, roughly 1.5–2.5 m wide (estimate, see above)**
with no radial pattern, scattered, overlapping; nothing marks them as perfect circles.

**Ours:** keep the dirt burst of `damage-fx-research.md` (6–8 m wide, brown-grey L\* 28–38), add the
WoT order in front of it: a white flash 2 m for 0.06–0.1 s → a short orange core 0.2 s → dark
brown-black inner smoke (L\* 20–28) → the lighter dirt dome. Stamp the scar map with an irregular blot
1.5–2.5 m (tank HE) or ~4.5 m with ejecta (155 mm).

**Must have:** a flash before the dirt · dark core, lighter dome · dirt clods falling back ·
an irregular, dark scorch left behind.
**Must avoid:** orange fire on a ground hit beyond 0.2 s (dirt does not burn) · a round, symmetric
burst · a scorch shaped like a circle or a star.

## 4. Destruction (ammo rack / turret pop)

**WoT, close kill (K1–K4, clip `VFX_AP_PEN` t = 7.65 s):**

| t after detonation | what | size |
| --- | --- | --- |
| 0–0.1 s | white-out flash with bloom | ≈ 3 hull (screen-filling in 3rd person) |
| 0.1–0.25 s | red-orange fireball with black smoke lumps already inside it; **20–40 dark debris chunks** 0.2–1 m flying out to 1–2 hull, sparks | fireball ≈ 2 hull wide × 1.5 tall |
| 0.25–0.5 s | fire collapses; **black-blue smoke dome** (L\* 20–25) ≈ 3 hull wide × 2 tall; **the hull stays visible** inside its lower part; one flame tongue at a hull opening | |
| 0.5–1.5 s | dome lifts and thins from the bottom up; debris still falling | |
| 1.5–2.5 s | dome turns into a leaning column rooted on the hull; flame steady | column |

**Blitz (JOE 0:50.4, 0:29.8; BR 0:19, 0:37):** the same sequence, shorter and simpler.
White flash 0.1–0.2 s → orange-red fireball 1.5–2 hull with brown-black smoke for 0.2–0.6 s → by
≈ 1 s a single vertical flame tongue from the deck/turret ring and a black column above it; the hull is
already charcoal. Debris is a few dark specks (BR 0:19), not a shower. Turret throw: rare and
short in the footage sampled; WoT PC shows it more often (K2, turret rises with the fireball).

**Ours:**
- 0–0.08 s: white core 4–5 m (L\* 95+) + `OmniLight3D` r 15 m, warm white, then off by 0.15 s.
- 0.08–0.4 s: fireball 10–12 m (1.4–1.6 hull; 55 px at far zoom), orange core L\* 63–74, a\* 30, b\* 45,
  dark lumps inside, edges going brown.
- 0.1–1.2 s: 20–30 dark debris pieces 0.3–1 m, thrown 5–15 m, falling under gravity; at far zoom
  only the 8–10 largest matter (≥ 3 px).
- 0.3–1.5 s: black smoke dome 10 m → lifts and becomes the column. Keep its lower 1.5 m thin so the
  wreck under it stays readable.
- From ≈ 1 s: the wreck fire of § 1, already in place; the hull swapped to charcoal at t = 0.
- Turret thrown about 1 kill in 3 (`damage-fx-research.md`), up 3–6 m, landing 4–8 m away.

**Must have:** the flash within the first 0.1 s (not after a ramp) · a fireball clearly bigger than the
hull · black inside the fire within 0.25 s · debris · the wreck readable again by 1.5 s.
**Must avoid:** a fireball that takes more than 0.15 s after impact to reach its peak · an all-orange fireball with no
white core and no black · a full-screen flash · fireball and wreck flame that look like the same
sprite.

## 5. How Blitz keeps it cheap (documented)

- **Fire and smoke are simulated offline and baked into atlases**: "We employ FumeFX and Houdini to
  simulate the said effects and export them into the texture atlas" (80LV-20, VFX artist I. Shelkovyy).
  Dynamics are set in the in-engine particle editor. Our `art-direction.md` flipbook rule matches.
- **Blending:** "the standard Alpha Blend shader, or an Alpha Additive shader" for brighter smoke
  (80LV-20). Fire/flash additive, smoke alpha-blended.
- **Soft particles** since Blitz 7.0, paid for by a depth prepass ("we added it for soft particles"),
  later read from tile memory on some GPUs (80LV-20, 80LV-21).
- **Lighting:** "Only tanks are being dynamically lit"; the environment is baked into lightmaps
  (80LV-20). Whether fireballs use a real light is not documented; in the footage the ground under a
  Blitz fireball turns orange (B1), which an additive sprite alone would also produce.
- **Fill rate:** dynamic resolution, because fragment cost dominates on mobile (80LV-22). Large
  overlapping smoke quads are the costliest thing an effect does.
- **Effect quality scales with the device** ("some visual effects may appear simplified to maintain
  performance", WG24; Effects quality setting, WG10).
- **Particle counts are not published.** From the footage: tens of debris pieces, one fireball made of a
  handful of large sprites, smoke made of large soft sprites rather than many small ones.

For us that means: big flipbook quads with depth fade, few of them; fire additive, smoke
alpha-blended; one short light per kill; the persistent column a mesh, not particles (already in
`art-direction.md`).

## 6. Our current frames vs the reference — gaps, worst first

Compared against the battle-fx-atlas captures (`kill_river_z6/z20`, `kill_crossroads_*`,
`hits_river_z6/z20`, `hits_crossroads_z6`).

1. **The kill fireball has no white core, no black and no debris.** Timing is not the problem: the
   123 ms flare is the attacker's muzzle, the shell lands at ≈ 0.2–0.3 s, and by 323 ms the fireball is
   already hull-sized at the target. But it peaks at L\* 67 (pinkish orange, a\* 29, b\* 41) where WoT
   peaks at L\* 99; it is ≈ 1 hull wide where WoT/Blitz are 1.5–2 hull; and it is a flat, noisy
   "cauliflower" blob with no black lumps inside and no debris. This is the single biggest gap: the
   moment of the kill does not land. **Caveat:** the captures are ≈ 100 ms apart, so a flash or light
   shorter than ≈ 80 ms at impact could fall between frames. Confirm in the scene or with a
   higher-rate capture before adding one.
2. **The wreck fire is an icon.** Every wreck carries the same small (≈ 1.5 m) spiky orange tuft on a
   corner of its roof — it reads as a starburst sprite, not as fire coming out of the hull. The refs
   have a vertical, flickering tongue 2–3 m tall from an opening, white-yellow at the base, with
   smoke growing out of its top.
3. **The column starts beside the flame, not from it**, and at the close zoom it is a uniform dark rope
   from base to top. Refs: born from the flame top, black only while fresh, widening 2–3×, greying
   to L\* 40–55 as the wreck ages.
4. **No black smoke dome and no debris at the kill**, so the fireball jumps straight to the column.
5. **Hit flashes have a flat bottom edge** (hits_01/02: the quad is clipped by the ground — no soft
   particles) and no white core; armour hits show no spark streaks and nothing distinguishes a hit
   that went in from one that bounced.
6. **The ground hit dirt dome is the closest to the reference** (brown-grey, soft, right size). It lacks
   only the flash-then-dark-core in front of it, and the scorch it leaves is faint.
7. Minor: the wreck hull's red-orange cast (L\* 18–25, a\* 8–16) reads as glowing metal everywhere; refs
   keep the hull neutral charcoal and limit orange to the area around the fire.
