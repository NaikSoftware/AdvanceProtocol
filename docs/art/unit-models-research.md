# Unit models — reference research and generation brief

Brief for the twelve roster models ([CLAUDE.md §3.6](../../CLAUDE.md), `core/unit_types.gd`).
Scale and camera: 1 tile = 8 m = 1.0 unit; 7 cm/px (closest zoom) to 22 cm/px (farthest), pitch
40–55°, roofs and turret tops dominate, undersides never seen. A 7.5 m tank is ~100 px at the
closest zoom and ~34 px at the farthest. Anything under ~15 cm is texture; a feature must be
≥ 0.5 m to change the silhouette.

## 1. Family: South Korea (primary)

Korea is the one Western/East-Asian family that fields **two towed guns still in service**
(105 mm and 155 mm) **and** three visibly different tracked tank designs, plus a 4×4 / 6×6 / 8×8
wheeled line and a dedicated engineer vehicle on a tank hull. Every role but the tank destroyer
has a real in-service model. Two entries are extrapolated and say so: the tank destroyer (no
eligible family fields a tracked one) and the 30 mm turret on the 6×6 armoured car.

Real names are private reference only — they never appear in code, data, UI or assets.

| # | role | real reference (private) | in-game name | real L × W × H, m | must read from above at 100 px |
| --- | --- | --- | --- | --- | --- |
| 0 | rifle squad | ROK infantry, digital "granite" uniform, rifle with optic | Line Section | 1.8 m figure | 4 helmets, rifles held low, plate-carrier backs |
| 1 | assault squad | same, one figure with backpack drone launcher/case | Strike Section | 1.8 m figure | the drone case: a 0.6 × 0.4 × 0.3 m box on one back |
| 2 | armoured car | K806 6×6 hull (real) **+ 30 mm unmanned turret (invented fit**, of the kind offered on Korean export 6×6s) | Kite | 6.6 × ~2.7 × 2.7 (hull) | 3 axles, flat-roofed boat hull, small offset turret with short 30 mm barrel |
| 3 | troop carrier | K808 8×8 | Drover | 7.2 × ~2.7 × 2.7 | 4 axles, long flat roof with hatches, RWS cupola, rear ramp |
| 4 | scout car | K153 (armoured K151 4×4 with RWS) | Wren | 4.9 × 2.2 × 2.0 | bonnet + cab, roof ring with RWS, 4 wheels clear of body |
| 5 | medium tank | **derived:** the heavy tank's hull and running gear, scaled down, with a compact turret | Basalt | ~6.5 hull × 3.3 × ~2.7 | the turret set forward (centre ~38 % of the hull from the bow), a flat louvred engine deck over the rear half, a gun shorter than the heavy's |
| 6 | tank destroyer | **invented:** turretless gun carriage on a tracked MBT-class chassis, a tall fixed armoured box aft (the self-propelled-howitzer layout) | Obsidian | ~6.8 hull × 3.5 × ~3.2 | no turret: low empty front hull, a big box over the rear 55–60 %, the longest gun of the set (overhang ~0.5 × hull) with a muzzle brake |
| 7 | light tank | **derived:** the K1-type hull with a small low turret (the previous tank-destroyer model) and a short 105 mm gun | Flint | ~5.6 hull × 2.9 × ~2.3 | the smallest and lowest; a small low turret; the shortest gun (overhang ~0.17 × hull) |
| 8 | heavy tank | K2 | Monolith | 7.5 hull (10.8 gun fwd) × 3.6 × 2.4 | boxy wedge-front turret with long bustle, sight block on roof, side skirts |
| 9 | field gun | KH178 105 mm towed | Squall | 4.48 (Wikipedia, verify) × 2.1 × 2.8 | split trail open in a V, shield, short barrel, two road wheels |
| 10 | howitzer | KH179 155 mm towed | Gale | 10.39 travel × 2.44 × 2.36 | long 155 mm barrel (~6 m), split trail in a wide V, two road wheels, firing base under carriage |
| 11 | engineer vehicle | K600 CEV (K1A1 hull, no turret) | Mattock | ~10.0 with plough × 3.6 (5.0 plough) × 2.6 | full-width mine plough with tines, excavator arm folded on the rear-left deck, flat turretless deck |

Sources for sizes: Wikipedia infoboxes (K1 overall/width/height, K2, K808/K806, K151, KH178,
KH179); ARMSNET for K21-105 and K600. The K1 hull length is not in the infobox. K808/K806 width
is listed as 2.1 m on Wikipedia, not plausible for an 8×8 — use ~2.7 m from the photos. The
silhouettes in `game/battle/unit_silhouettes.gd` are hull sizes and stay the source for in-game
scale.

**Tanks from above, by shape alone** (the owner colour is on the HP bar, never on the model).
Light (Flint): the smallest and lowest, a small low turret, the shortest gun. Medium (Basalt):
the heavy's hull smaller, the turret set forward, a flat engine deck over the rear half, a
medium gun. Tank destroyer (Obsidian): no turret, a big box at the rear closed by a flat rear
plate, an empty front deck, the longest gun. Heavy (Monolith): the largest, a broad turret with
a long bustle and roof sights. Pillar 5 depends on these four staying separable at 34 px.

**Second best:** USA — Stryker ICV, Stryker 30 mm / LAV-25, JLTV, M1A2 SEPv3, M10 Booker,
M1150 ABV, M119A3, M777A2; gaps at medium tank and tank destroyer; all DoD photos are public
domain. Turkey (Boran / Panter, Altay, Kaplan MT, Kunduz) is third. Germany, Japan, France and
Poland field no towed 105 + 155 pair.

## 2. Generation prompts (Tripo text/image-to-3D)

Tripo ignores metres and ignores negatives. The prompts give **proportions as ratios** and
positive content; the implementer scales uniformly (spread ≤ 1.1) and fixes proportions in
Blender, then splits wheels / tracks / turret / barrel into separate nodes so they can turn.
Every prompt ends with the shared suffix:

> Shared suffix: *realistic contemporary military vehicle, hard-surface, game-ready, clean
> quads, PBR, plain unmarked painted surfaces, low-saturation digital-block camouflage in muted
> olive green, brown, khaki and near-black, light dust on the lower hull and running gear, matte
> paint, single object on a neutral background, three-quarter view from above.*

**Camouflage — open question.** Korean vehicles carry a four-tone disruptive scheme (olive,
brown, sand, black in large soft bands; parade vehicles add thin white outlines). The art
direction asks for digital-pattern, low-saturation camouflage. Recommendation: the four Korean
colours in pixel blocks, no white outlines (the suffix above). The alternative is the real
banded scheme, desaturated.

| # | prompt (before the shared suffix) | must not |
| --- | --- | --- |
| 0 | One adult soldier standing naturally, weight on one leg, rifle with a compact optic held low across the body, muzzle down; ballistic helmet with a cloth cover, plate carrier with magazine pouches, small assault pack; digital-pattern uniform in muted green-grey; boots; height 1.8 m, shoulders 0.5 m | A-pose or T-pose; patches, flags, name tapes, rank; bright face paint; oversized hands or gun |
| 1 | Same soldier, plus a rigid rectangular drone case on the back (ratio 3 : 2 : 1.5, 0.6 m long), lid seams and two carry handles, a folded quad-rotor clipped on top; tablet controller on the chest | the drone flying; propellers larger than the case; case hidden by the body from above |
| 2 | Six-wheeled armoured car, boat-shaped flat-roofed hull, proportions L : W : H 2.5 : 1 : 1 (hull), three evenly spaced axles with large off-road tyres, small unmanned turret set back of centre with a short 30 mm cannon (barrel 0.3 × hull length), smoke grenade dischargers, periscopes, rear door | eight wheels; a tank-sized turret; a long gun; dual rear wheels; truck cab |
| 3 | Eight-wheeled armoured personnel carrier, long boxy hull with sloped glacis, L : W : H 2.7 : 1 : 1, four evenly spaced axles, flat roof with two square troop hatches and a remote weapon station with a heavy machine gun forward-right, rear ramp, stowage boxes on the sides | a turret with a cannon; six wheels; tracks; open-top body |
| 4 | Armoured 4×4 light tactical vehicle, L : W : H 2.2 : 1 : 0.9, short bonnet, four-door armoured cab with thick small windows, roof ring with a remote weapon station with a machine gun, short cargo bed behind the cab, spare wheel on the rear | civilian SUV look; chrome; light bars; road-car wheels |
| 5 | Not generated: built from the heavy tank's source (see §1); the pipeline shortens the turret from the back, flattens and narrows it and fits a thinner, shorter gun | — |
| 6 | Tracked armoured self-propelled gun with NO rotating turret: a low sloped front hull on the front 40 % with only a flat engine deck and driver hatch; a large tall slab-sided armoured box fixed on the rear 55 %, its flat roof the highest point, two small low hatches; one very long large-calibre gun projecting straight forward and level from the centre of the box's front face, with a muzzle brake, about as long as the hull; side skirts, seven road wheels | a turret ring or rotating turret; a gun on the roof; tall kit on the front deck |
| 7 | Not generated: built from the K1-type source with the small low turret (§1); the pipeline fits a short 105 mm gun (a thin barrel with a fume extractor and a small muzzle brake) | — |
| 8 | Heavy main battle tank, hull L : W 2.1 : 1, broad turret 0.6 × hull length with wedge-shaped front armour and a long ammunition bustle, panoramic sight block on the roof, 120 mm long smoothbore gun with thermal sleeve reaching 0.45 × hull length past the bow, six road wheels, rubber-padded tracks, full side skirts with armour modules | rounded cast turret; short gun; slat cage covering the turret |
| 9 | Towed 105 mm field gun in firing position, split trail opened to a 50° V with spades, small flat gun shield, barrel 0.65 × trail length, two road wheels with off-road tyres, sight on the left | self-propelled chassis; three trail legs; wheels lifted off the ground |
| 10 | Towed 155 mm howitzer in firing position, long barrel with muzzle brake 1.1 × trail length, recuperator cylinders above the barrel, two long box-section trail legs opened in a wide V, firing platform lowered under the carriage, two large road wheels, auxiliary power unit on the trail | single box trail; barrel shorter than the trail; tracks |
| 11 | Turretless combat engineer vehicle on a main-battle-tank hull, hull L : W 2.1 : 1, full-width mine plough at the bow (1.4 × hull width) with a row of tines, hydraulic excavator arm with bucket folded on the rear-left deck, armoured commander cupola with machine gun, six road wheels, rubber-padded tracks | a gun or turret; crane boom taller than the hull is long; bulldozer-only front |

## 3. References

Downloaded (reference only, never shipped) to `~/.cache/ap-scratch/units/research/refs/<slug>/`
with a `meta.json` of page URL, licence and author per file (k600 and the earlier slugs).
"Viewed" means looked at for this brief.

| # | slug | file / page | licence | viewed | take from it |
| --- | --- | --- | --- | --- | --- |
| 5 | k1a2 | [ROK parade K1A1, high three-quarter](https://commons.wikimedia.org/wiki/File:2013.10.1_%EA%B1%B4%EA%B5%B0_%EC%A0%9C65%EC%A3%BC%EB%85%84_%EA%B5%AD%EA%B5%B0%EC%9D%98_%EB%82%A0_%ED%96%89%EC%82%AC_The_celebration_ceremony_for_the_65th_Anniversary_of_ROK_Armed_Forces_(10078235484).jpg) (`01.jpg`) | CC BY-SA 2.0, ROK Armed Forces | yes | turret roof, bustle basket, camo bands (ignore roundels and numbers) |
| 5 | k1a2 | [K1A1 firing, side](https://commons.wikimedia.org/wiki/File:2014.5.29_%EC%9C%A1%EA%B5%B0_20%EC%82%AC%EB%8B%A8_K1A1_Republic_of_Korea_Army_21th_Division_(14148181190).jpg) (`06.jpg`) | CC BY-SA 2.0 | yes | low hull profile, gun length vs hull |
| 8 | k2 | [K2 frontal, defence expo](https://commons.wikimedia.org/wiki/File:2014_%EB%8C%80%ED%95%9C%EB%AF%BC%EA%B5%AD_%EB%B0%A9%EC%9C%84%EC%82%B0%EC%97%85%EC%A0%84(DX_Korea)_%EC%9C%A1%EA%B5%B0%EC%9D%98_%EB%AA%85%ED%92%88_%EB%AC%B4%EA%B8%B0%EC%99%80_%EC%9E%A5%EB%B9%84_%EC%86%8C%EA%B0%9C_(15393852929).jpg) (`05.jpg`) | CC BY-SA 2.0 | yes | wedge turret front, roof sight blocks; K1A1 beside it for comparison |
| 8 | k2 | [K2 column in dust](https://commons.wikimedia.org/wiki/File:11%EC%82%AC%EB%8B%A8_%EC%A4%91%EB%8C%80%EC%A0%84%ED%88%AC%ED%9B%88%EB%A0%A8_1_(24818999659).jpg) (`00.jpg`) | CC BY-SA 2.0 | yes | dusty finish, skirt modules, gun overhang |
| 7 | k21-105 | [K21-105 model, front](https://commons.wikimedia.org/wiki/File:Hanhwa_K21-105_Medium_Tank_-_Front_at_ADAS_2018.jpg) (`00.jpg`) | CC BY-SA 4.0, Rhk111 | yes | turret placement aft, front-left grille, slab hull |
| 7 | k21-105 | [same, rear](https://commons.wikimedia.org/wiki/File:Hanhwa_K21-105_Medium_Tank_-_Rear_at_ADAS_2018.jpg) (`01.jpg`) | CC BY-SA 4.0 | no | turret bustle, rear door |
| 3 | k808 | [K808 river crossing](https://commons.wikimedia.org/wiki/File:ROKA_K808_APC_river_crossing_training_-_March_2021.jpg) (`06.jpg`) | KOGL Type 1 | yes | 4 axles, boat glacis, RWS position |
| 11 | k600 | [K600 at a ground forces festival](https://commons.wikimedia.org/wiki/File:Ground_Forces_Festival_2025_-_0055.jpg) (`02.jpg`) | PD | yes | plough with tine row and lift arms, folded excavator arm rear-left, cupola MG |
| 11 | k600 | [Wet gap crossing](https://commons.wikimedia.org/wiki/File:Freedom_Shield_25_-_ROK-US_Joint_Force_Wet_Gap_Crossing_(8925857).jpg) (`00.jpg`) | PD | no | — |
| 10 | kh179 | [KH-179 firing, rear three-quarter](https://commons.wikimedia.org/wiki/File:1_stage_firing.png) (`00.jpg`) | CC BY-SA 4.0, WiaMil | yes | two road wheels, long box-section trail legs, barrel at high elevation |
| 10 | kh179 | [KH-179 155mm](https://commons.wikimedia.org/wiki/File:KH-179_155mm_Howitzer.jpg) | CC BY-SA 4.0 | no | barrel vs trail in travel |
| 9 | kh178 | [KH-178](https://commons.wikimedia.org/wiki/File:KH-178.jpg); [allied exercise photo](https://commons.wikimedia.org/wiki/File:Super_Garuda_Shield_2024_%E2%80%93_Artillery_Range_(Photo_ID_8626101).jpg) | CC BY-SA 4.0; PD | no | trail V, shield |
| 4 | k151 | [K153 armoured recon](https://commons.wikimedia.org/w/index.php?curid=172964523); [K-151 LTV (1)](https://commons.wikimedia.org/wiki/File:Kia_K-151_LTV_ROKA_(1).jpg) | PD; CC BY-SA 4.0 | no | cab + roof RWS |
| 2 | k806 | Commons `Category:K806 White Tiger` | — | no | API returned no files; search by hand |
| 0–1 | soldiers | not collected | — | no | — |

Rejected on sight: `k808/07.jpg` (a person and a hovercraft wall, no vehicle). All ROK photos
carry roundels, unit numbers and flags: take shapes only.

**Quality bar (copyrighted, link only, not viewed):** World of Tanks K-2 review page
<https://worldoftanks.com/news/general-news/how-to-play-k-2>, WoT screenshots
<https://www.mobygames.com/game/52092/world-of-tanks/screenshots>. Target: crisp panel lines,
readable hatches and sights at 100 px, dirt gradient on running gear, never flat-shaded boxes.

**Still to do:** the contact sheet `~/.cache/ap-scratch/units/research/contact.png`, soldier
references, WoT frames, and downloads for kh178, k151, k806 (their files are empty; kh179 has one
file and no `meta.json`). Commands, from `~/.cache/ap-scratch/units/research/tools/`:
`python3 -I grab.py <slug> "Category:<name>" 10` (categories: `KH178 howitzer`,
`Kia K-151 Raycolt KLTV`, `KH179 howitzer`) with a pause between slugs (Commons rate-limits), then
`python3 -I mont.py ../refs/<slug> ../view/<slug>.jpg`, view each, keep 2–4.

## 4. Owner marking

Units carry no team colour: the side is shown by the colour of the HP bar fill (#3a6ea5, #a54a3a, #5a8a4a, lightened for contrast on
the bar's dark back). Identity at the far zoom comes from silhouette alone, so no panel, band or
tape is modelled.

## 5. National sets

Three sets, one per player slot: slot 0 fields the Korean family above, slot 1 a Russian family,
slot 2 an American one. The set follows the slot; there is no choice screen. The tanks come
first; until a set has its own model for a role, that role falls back to the slot 0 model.

All three sets keep the same role cues in the same order, so a role reads the same whichever
side fields it: the light is the smallest and lowest with the shortest gun, the medium has its
turret set forward over a flat engine deck, the tank destroyer has no turret and a box at the
rear with the longest gun, the heavy is the largest. A set differs from the others in what does
not carry the role: the turret's plan and bustle, the deck furniture, the skirts, the hull front.
The stats are the same for every set until per-set rosters are designed.

Each set has its own paint, one tone across the whole set: slot 0 is olive camo with small
brown-black blocks, slot 1 a plain low-chroma grey-green, slot 2 a plain muted sand. Paint marks
the nation, not the player — the HP bar still marks the player. Every paint must stand apart from
both grass and ploughed soil at the far zoom, by value or by hue, and every set carries the same
wear: edge wear, metre-scale roughness spread, vertical streaks, dirt on the lower hull — painted
metal, never plastic and never a polished can.

Slot 0's up-facing tops fade the olive base to a light olive (L* about 55, hue about 97–113°
depending on the map's grade) while the brown-black blocks stay dark: a dark olive top sits at
the grass's value and fails the gate below, a neutral grey or cream fade loses the olive read.
Slots 0 and 2 then share lightness and b* and are told apart by a* alone, so their tops must keep
a ΔE of at least about 9.5 on every map; re-measure it whenever either paint moves.

**Contrast gate for every vehicle model.** A unit must stand out on every map — Crossroads
(sunny), River (overcast rain) and Ridge (early autumn) — on grass, on ploughed soil and against
a forest edge. Measured at the farthest zoom on in-game frames: the median colour of the model's
up-facing top differs from the ground right around it by ΔE (CIELAB) ≥ 15; a measured median of
14.5 passes, the rest is measurement noise. A model that passes on one map and fails on another
fails. The top is the up-facing surface without the cast shadow; the body median without the
shadow is reported beside it as the cautious figure. Where a sunny map has ground in a canopy's
cast shadow at least 3 L* darker than open meadow, one sample stands there, measured against the
shaded ground; tree shadows that faint add nothing to measure. A unit under the canopy itself, or
with a pole or prop between it and the camera, is not a contrast sample. One tool measures every
model: `tools/unit_contrast_gate.py`.
Set 1's green is a low-chroma grey-green of middle value: dark enough to read as protective
green, light enough to separate from River's dark ground.
