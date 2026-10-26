# Battle damage effects — reference and brief

What the board shows when something is hit, killed or burnt out: real sizes in metres and on screen,
how long each effect lasts, colours under both lighting presets, which CC0 sources can ship, and what
still has to be made. Setting from [art-direction](../art-direction.md): the 2030s, fictional
states, overcast, wet, late-autumn Eastern-European countryside. Realistic, never cartoon.

Contact sheets (gitignored, local only): `art-refs/damage-fx/wreck_sheet.jpg`,
`art-refs/damage-fx/column_sheet.jpg`, `art-refs/damage-fx/hit_sheet.jpg`. The ids below are the
labels on those sheets. `r_` = real photo, `g_` = game screenshot, `u_` / `k_` / `ph_` = shippable
CC0 candidate.

## Scope

1. **A vehicle that is damaged but still alive shows no persistent damage, smoke or fire.** It shows
   only the hit moment (§ Hit moments). There are no HP stages.
2. **A destroyed vehicle leaves a wreck that blocks its cell.** That is a rule change for `core/`
   and is outside the scope of this brief. Here it means one thing: the wreck must read as an
   obstacle from above at both zooms, and it must look burnt out once its fire and smoke are gone.
3. **Killed infantry visibly dies**: fallen figures on the squad base plus a small scorch or crater.
   Kept restrained and realistic, with no blood.

## Camera facts this brief is sized from

1 tile = 8 m. 7 cm/px at the closest zoom (pitch 38°), 22 cm/px at the farthest (pitch 55°),
`IsoCameraRig.pitch_for`. On screen, a vertical height `h` spans `h·cos(pitch)`. A length along the
view direction spans `L·sin(pitch)`. A length across the view spans its full `L`.

| feature | real size | px at 7 cm/px | px at 22 cm/px | consequence |
| --- | --- | --- | --- | --- |
| tank hull / wreck | 7.5 × 3.6 m | 107 × 51 | 34 × 16 | the obstacle read at far zoom has to come from value and shape, not detail |
| tank turret, thrown | 3.5 m | 50 | 16 | readable at both zooms |
| debris fragment | 0.3–1.5 m | 4–21 | 1–7 | the near zoom shows pieces. At far zoom they are only texture in the scorch |
| wreck scorch (blast + fuel) | 10–14 m Ø | 143–200 | 45–64 | this marks the blocked cell |
| HE crater, 152–155 mm | 1.5–2 m dark core, ~4.5 m with ejecta | 21–29 / 64 | 7–9 / 20 | measured on r_c13 (below) |
| crater, tank HE / field gun | 1–1.5 m core, 2.5–3 m with ejecta | 14–21 / 36–43 | 5–7 / 11–14 | |
| small-arms spark | 0.05–0.3 m | 1–4 | < 1.5 | **sub-pixel at far zoom.** Draw streaks 0.5–0.8 m long, or drop sparks at far zoom |
| bullet dirt puff | 0.3–0.6 m | 4–9 | 1–3 | readable only as a cluster of 6–12 puffs |
| tank muzzle / impact flash | 2–5 m | 29–71 | 9–23 | |
| HE ground-burst cloud | 10–15 m wide, 10–15 m tall | 143–214 | 45–68 | |
| catastrophic fireball | 10–15 m | 143–214 | 45–68 | |
| smoke column, 25 m tall | width 3 m at base → 8 m at top | 282 tall × 43–114 | 65 tall × 14–36 | upright, it covers 3–4 tiles of the screen above the wreck; leaning 20° towards the camera, 2–2.7. See the occlusion note |
| wreck fire, flames | 1–3 m tall | 11–34 | 3–8 | at far zoom it is an orange dot, so the column carries the read |
| standing figure | 1.8 m | 20 | 5 | |
| fallen figure, lying | 1.8 × 0.5 m | 26 × 7 | 8 × 2 | **a short dark dash at far zoom.** It needs value contrast and a contact shadow |

**Measured on r_c13** (oblique drone frame; the vehicle on the track is ≈6.7 m long and 40 px in the
960 px frame): crater ejecta ring ≈ 25 px ≈ 4.2 m, dark core ≈ 10 px ≈ 1.7 m. The killed vehicle's
scorch is a blot ≈ 80–90 px ≈ 13–15 m with radial dark streaks and scattered debris. The frame is
oblique, so allow ±25 %.

## Shortlist

Reference only unless marked **ship**. Every image here has been looked at.

| id | source | licence | what to take |
| --- | --- | --- | --- |
| **r_c05** ★ | [Dolyna after invasion 02](https://commons.wikimedia.org/wiki/File:Dolyna_(Kramatorsk_Raion)_after_Russian_invasion_(2022-12-05)_02.jpg), O. Ivanets / ArmyInform | CC BY 4.0 | Burnt-out tank in a late-autumn field under overcast sky: rust + char + ash palette, turret displaced, gun still level |
| **r_c15** ★ | [Передмістя Києва 35](https://commons.wikimedia.org/wiki/File:Передмістя_Києва_після_російської_окупації_35.jpg), KMDA / O. Samsonov | CC BY 4.0 | Burnt hull on a road: char-black body, rust only on thin plates, burnt road surface around it |
| **r_c19** ★ | [Холодноярівці … 03](https://commons.wikimedia.org/wiki/File:Холодноярівці_розбили_техніку_окупанта_на_Харківщині_03.jpg), ArmyInform | CC BY 4.0 | Turret blown off and lying beside the hull; 0.5–2 m debris on the asphalt; overcast February light |
| r_c16 | [Передмістя Києва 40](https://commons.wikimedia.org/wiki/File:Передмістя_Києва_після_російської_окупації_40.jpg), KMDA | CC BY 4.0 | Thrown turret upside down. It carries painted symbols: **shape only, never the markings** |
| r_c08 | [Lyman after the battle 01](https://commons.wikimedia.org/wiki/File:Lyman_after_the_battle_(2022-10-06)_01.jpg), National Police of Ukraine | CC BY 4.0 | Wrecks weeks later, turned fully rust-orange; gives the far end of the ageing range |
| **r_c13** ★ | [Zaporizhzhia counter-attack 012](https://commons.wikimedia.org/wiki/File:ВС_РФ_на_Запорожском_направлении_пресекли_попытку_контратаки_ВСУ_012.png) | CC BY 4.0 | **Drone view at about the game pitch**: crater size and spacing, a wreck's scorch blot at 2× hull length. Contains track ruts: **do not copy those** |
| r_c04 | [Damage to a target tank, 1983](https://commons.wikimedia.org/wiki/File:Damage_to_a_target_tank,_1983.JPEG), USAF | PD | Near-top-down debris scatter: 0.2–1 m pieces spread over 10–20 m, sparse |
| r_c10 | [Type 69 Operation Desert Storm](https://commons.wikimedia.org/wiki/File:Type_69_Operation_Desert_Storm.jpg) | PD | Burning tank: flames come out of the hatches and engine deck, not the whole hull. A black column with a brown fringe |
| r_c02 | [Burning Iraqi tanks](https://commons.wikimedia.org/wiki/File:Burning_Iraqi_tanks.JPEG), PHC Holmes | PD | Wind lays the plumes over within ~2 hull heights. Columns lean, they do not stand straight |
| r_c00 | [AGM-65 M-48 post impact](https://commons.wikimedia.org/wiki/File:AGM-65_M-48_post_impact.jpg), USAF | PD | Catastrophic kill: turret airborne, fireball ≈ 2–3× hull, black smoke lobes |
| r_c06 | [Hellfire Tank-explosion](https://commons.wikimedia.org/wiki/File:Hellfire_Tank-explosion.jpg) | PD | Top-attack hit: a black-cored fireball sitting on the hull |
| r_c21 | [Milan striking a target](https://commons.wikimedia.org/wiki/File:Milan_anti-tank_missile_striking_a_target.JPEG), USAF | PD | Ground impact: grey-brown dust dome, dark chunks thrown 5–10 m, a short orange core |
| r_c07 | [Iraqi tank exploding](https://commons.wikimedia.org/wiki/File:Iraqi_tank_exploding.JPEG), PHC Holmes | PD | Spark streaks. It is a long exposure, so **in game the streaks must be much shorter** |
| g_coh3_08 ★ | Company of Heroes 3, [Steam](https://store.steampowered.com/app/1677280) | © Relic, reference only | **At the game angle**: irregular dark scorch blots under impacts, brown dirt ejecta, fallen figures as small dark shapes. Its white starburst sparks are too strong: **do not copy them** |
| g_coh3_14 | same | © reference only | Iso burnt wreck: greyed hull, small separate ground fires, a dark ring |
| g_coh3_06 | same | © reference only | Smoke/dust burst seen from above: a dome, not a column |
| **g_reg_01** ★ | Regiments, [Steam](https://store.steampowered.com/app/1109680) | © MicroProse, reference only | Wreck columns: thin, ~6–8 hull lengths tall, a fire point at the base, slight lean. **The target read** |
| g_sd2_06 / g_sd2_08 | Steel Division 2, [Steam](https://store.steampowered.com/app/919640) | © Eugen, reference only | One column per wreck, all leaning one way with the wind, a small flame at the base |
| g_reg_23 | Regiments | © reference only | Fires and columns seen from high: the columns rise towards the camera and cover what lies behind them |
| g_warno_13 / g_warno_00 | WARNO, [Steam](https://store.steampowered.com/app/1611600) | © Eugen, reference only | Flash and debris on a hull hit; impact dust plumes across a field |
| **u_Explosion02** ship | [Unity Labs VFX flipbooks](https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks), T. Iché 2016 | CC0 (see caveat) | 5×5 frames, 1024², RGBA. White-hot ball → fire → black smoke. Used for the kill fireball and the shell burst |
| **u_Explosion01-nofire** ship | same | CC0 (caveat) | 5×5, 1024². A dark billowing burst with no fire. Tinted brown, it becomes the dirt burst |
| **u_Flame02** ship | same | CC0 (caveat) | 16×4, 2048×1024, a looping flame. Used for the wreck fire |
| **u_WispySmoke01** / **u_Cloud02** ship | same | CC0 (caveat) | 8×8, 1024², looping rolling smoke. Used for column puffs and lingering smoke |
| k_pp ship | [Kenney Particle Pack 1.1](https://kenney.nl/assets/particle-pack) | CC0 (license file checked) | **trace_01–07** = spark streaks; **smoke_04/07/08** = single puffs; **dirt_03** = chunk spray (tiny on screen only); **fire_01** = a hot core |
| **ph_rust_coarse_01** ship | [Poly Haven](https://polyhaven.com/a/rust_coarse_01), 2.2 m | CC0 | Rust layer of a burnt hull (L* 27, a* 10, b* 14 median) |
| ph_burned_ground_01 ship | [Poly Haven](https://polyhaven.com/a/burned_ground_01), 1.0 m | CC0 | Detail breakup inside a scorch only. It is 1 m and dry, so a scorch would repeat it 10–14 times. It is **never** the scorch shape |
| ph_rusty_metal_04 | Poly Haven, 2.0 m | CC0 | Alternative rust and bare-metal mix for ash-bleached plates |

**Unity Labs caveat.** The blog says "we release *some* of these sequences under CC0" and lists 28
downloads on the same page without saying which are meant. The zips contain no licence file. Treat them as CC0 per the
publisher's page, record that page as provenance, and ship nothing whose licence is unclear.

**Rejected on sight.** Kenney *Smoke Particles* pack (CC0, but flat painterly blobs with a baked dark
halo, plus "fart" sprites); Kenney Particle Pack `scorch_*`, `star_*`, `magic_*`, `spark_*` (radial
starbursts and lightning); `muzzle_*` (flat cartoon shapes); Unity `FireBall01` (additive, burnt out
to white). Commons fire/smoke aerials r_c20/c22/c23 (forest and prairie fires: wrong scale and
colour). OpenGameArt smoke sheets (stylised; none realistic). Most WARNO, Broken Arrow and Steel
Division frames are ground-level marketing shots and say nothing about the top-down read.

**`assets/vfx/smoke_puff.png`** (256², white soft puff, added with the menu) matches no Kenney file.
**Its provenance is unrecorded.** Establish it before reusing it here.

## Colours (CIE L*a*b*, sampled from the refs and our ground)

| element | overcast (default preset) | sunny | source |
| --- | --- | --- | --- |
| wreck char | L* 3–15, a/b ≈ 0 | same; specular glints on edges L* 60 | r_c15, r_c08 p10 |
| wreck rust | L* 27–36, a* 10–19, b* 14–28 | +8 L* on lit faces | r_c05 median, ph_rust_coarse_01 |
| wreck ash / heat-bleached plate | L* 55–72, neutral | L* 70–80 | r_c05 p90 |
| wreck mix after fire | ~45 % char, ~40 % rust, ~15 % ash, **no team colour, no camo pattern left** | same | r_c05, r_c15 |
| scorch on wet ground | core L* 10–15, edge fades over 2–4 m into ground (field L* 31, mud L* 30) | core L* 15–20, grey ash flecks L* 45–55 | ground albedo measured; r_c19 road |
| smoke column, dense | L* 12–27, a* ≈ 0, b* −3…+4 (mood smoke L* 20) | shadow side L* 12–15, lit side L* 45–55 with b* +10…+17 (warm) | mood, r_c10 |
| smoke column, thinning top | L* 35–45, opacity ≤ 0.35 | L* 55–70 | r_c10 p90 |
| fire | core #FFD9A0 → edge #E0702A (mood fire L* 46, a* 31, b* 35); **emissive, the brightest thing on screen** | same hue, read reduced by daylight. Raise the flame quad's alpha, not its size | mood, u_Flame02 |
| dirt burst | brown-grey L* 28–38, a* 2–4, b* 6–10 (= wet loam), clearing to grey L* 45–50 | L* 45–60, b* 8–12, drier and dustier | mud albedo; r_c21 |
| flash | #FFF4D8 for 2–4 frames, then fire colours | same | u_Explosion02 frame 0 |
| sparks | #FFE6B0 core, life ≤ 0.15 s | same, half the count reads | r_c07 |
| fallen figure | L* 20–28 (darker than field L* 31), low chroma, plus a baked contact blob L* −8 under it | same | measured ground |

## Hit moments (all one-shot, ≤ 1.5 s, since `EventPlayer` awaits each animation)

Weapons by roster class. Sizes are real metres; durations are seconds. Every row is `GPUParticles3D`
with `one_shot`, plus at most one flipbook quad and, where marked, an `OmniLight3D` held for 3–5
frames, then `queue_free` (art-direction).

| weapon (roster) | on armour | on infantry / soft ground | on light vehicle |
| --- | --- | --- | --- |
| **Rifle / MG** (rifle squad, assault squad) | 4–8 spark streaks 0.5–0.8 m (k trace_*), in 2–3 bursts over 0.8 s. No flash, no light. Far zoom: 2–3 streaks per burst | 6–12 dirt puffs 0.3–0.6 m (k smoke_07 tinted wet loam) scattered over 4 × 4 m around the base; each rises 0.5 m and fades in 0.6 s | sparks as on armour, plus 1–2 grey puffs 0.5 m |
| **Autocannon** (armoured car, troop carrier) | 3–5 rounds at 0.15 s spacing; each a flash 0.8–1.2 m (u_Explosion02 frames 0–2 scaled), a spark cone 1.5–2 m, a grey puff 1.5 m drifting up; total 1.2 s | each round a dirt puff 1–1.5 m (u_Explosion01-nofire, brown tint) | as armour; the last round leaves a 2 m grey puff for 1.5 s |
| **Tank gun** (all tanks) | flash 2–3 m for 0.06–0.1 s + `OmniLight3D` r = 10 m; spark/fragment cone 4–6 m; grey-brown cloud 4 m → 7 m over 1.2 s, alpha 0 at 1.5 s | HE: flash 2 m, dirt burst 6–8 m wide and 5–6 m tall (u_Explosion01-nofire brown), 10–20 chunks 0.2–0.5 m thrown ≤ 8 m, leaves a 2.5–3 m crater mark | as armour; the cloud is darker (fuel, paint) |
| **Field gun / howitzer** | 152–155 mm HE: flash 3–5 m + light r = 15 m, dirt column 10–15 m wide × 10–15 m tall, chunks 15–25 fall within 1.5 s, residual grey cloud 12 m drifts with the wind and fades by 1.5 s (cut short; the real one lasts 10 s) | same burst; leaves a 4.5 m crater mark (r_c13) | same |
| **Drone strike** (assault squad, vehicles only) | **top attack**: flash 1.5–2 m on the roof (not the side), a black-cored puff 3–4 m (r_c06), sparks downward. No ground burst. If it kills, the kill sequence follows | — (cannot target infantry) | same as armour |
| **Muzzle** (firing side) | tank 3–5 m flash 0.07 s + a dust ring 10–15 m on the ground under the gun, 1 s; autocannon 0.5 m flashes; rifles none (sub-pixel) | | |

**Kill sequence (vehicle)** replaces `play_destroyed()`'s shrink-to-zero. Flash and light → u_Explosion02
at 10–15 m for tanks (6–8 m light vehicle, 5–6 m towed gun) in 1.2 s → the wreck is already
in place under it → fire and column start. For tanks the turret is thrown in about **1 kill in 3**.
The wreck is a **new node**, spawned from the unit's type, tile and facing before the container frees
the `UnitView`. "The live unit's own mesh" in the brief means the same mesh resource, not the same node.

## Persistent states (in rounds; one round = every player has had one turn)

| | round 0 (kill) | 1 | 2 | 3 | 4 | 5+ |
| --- | --- | --- | --- | --- | --- | --- |
| **tank** | fireball, then hatch and engine-deck fire (2–3 flame quads, 1.5–3 m) | fire (1–2 quads) + dense column | dense column, one small flame | column thinning (opacity ×0.6) | wisp (×0.3) | burnt wreck only |
| **light vehicle** | fireball 6–8 m, whole-body fuel fire | fire + column | column | thinning | burnt wreck only | |
| **towed gun / howitzer** | ammo flash, small fire (tyres, charges) 1 m | column (thinner, 2 m base) | thinning | burnt wreck only | | |
| **engineer vehicle** | as light vehicle | | | | | |
| **infantry squad** | figures fall (0.5 s). Rifle/MG kill: figures only. Autocannon: + stamp D (2–3 m scorch). Tank HE, field gun, howitzer: + stamp D + stamp C crater | — | — | — | — | fallen figures persist (see brief) |

The wreck and every ground scar stay for the whole match. They are the battle scars of §8.

## Technique

- **Smoke column = stacked flipbook billboards in one `MultiMeshInstance3D`**, not a particle system
  and not a generated strip. A column is 6–10 Y-axis billboards placed along a curve, 3 m wide at
  the base and 8 m at 25 m height, leaning 15–25° downwind. Each plays u_Cloud02 / u_WispySmoke01
  with its own phase, and the puffs scroll up the curve with time. Positions are a pure function of
  (age, seed), so nothing is simulated. **All columns on the map share one MultiMesh = one draw
  call**. All wreck fires share a second MultiMesh (u_Flame02). Per-instance custom data = age and
  opacity. This satisfies art-direction's "a column is a mesh with a shader" and needs no generated
  texture.
- **Soft particles** (depth fade 1–2 m) on every billboard that touches the ground or the wreck.
  The dirt burst and the column base cut the ground on a hard line without it.
- **Budget.** Persistent: 2 draw calls total (columns, fires) + 1 per wreck mesh + 1 per thrown turret (or route all
  thrown turrets of one type through a MultiMesh). Cap at **8 columns
  on screen**; past that, the oldest drops to its next stage early. Hit moments: ≤ 2 particle systems
  alive at once, ≤ 40 particles each, ≤ 1 light. Overdraw is the cost, not the count: a near-zoom
  column is about 280 × 110 px at ≤ 0.85 alpha. Six of them cover about 7 % of a 2400 × 1080 screen.
- **Low-processor mode.** Columns and fires animate, so the screen is never truly static while a
  wreck burns. Step the flipbooks at **8 fps with cross-fade** between frames. When only ambient
  effects are animating, cap `Engine.max_fps` at ~10 and restore 60 on input or events. Once
  everything has burnt out (round 5+), nothing animates and the cap drops to idle again.
- **Occlusion.** On screen a column of height h leaning φ away from the camera spans h·cos(pitch − φ),
  and leaning towards the camera it spans h·cos(pitch + φ). Upright, a 25 m column covers 3–4 tiles of
  the screen above its wreck (pitch 55° → 38°). Leaning 20° towards the camera, it covers 2–2.7. Fade columns to ≤ 0.35 opacity while a unit is selected and the column's screen rectangle
  overlaps its zones, or while the fire radius is held (§3.13). Set the map wind **towards the camera (screen-bottom)**:
  the lean then shortens the column on screen. Wind towards screen-top would make it longer. Columns cast no shadow (one light,
  units only).
- **Ground scars cannot be `Decal` nodes on this ground.** Godot's Mobile renderer applies at most
  **8 decals per Mesh resource**, and Compatibility supports none
  ([docs](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html)).
  `GroundSurface` is **one mesh**, so the whole board would get eight scars, and none on the
  fallback renderer. This contradicts the "craters and scorching are `Decal` nodes" line in
  art-direction.md. **Recommendation:** a *scar map*, an RGBA8 texture at 0.25 m per texel
  (32 px per tile), stamped on the CPU when an event lands and sampled by `ground.gdshader`
  alongside `class_map*`. R = scorch darkness, G = crater (darkening and normal), B = debris mask,
  A = ash. It costs no draw calls, has no count limit, works on both renderers, and saves as an
  image. The alternative is height-conforming quads using `TerrainHeight`, which brings back
  z-fighting and costs a draw call each. **This is a controller decision.**
- **Cosmetic randomness** (turret thrown or not, debris layout, puff phases) comes from a hash of
  (match seed, unit id) in the view, **never from `Rules.roll()`**. Drawing cosmetics from the rules
  RNG would shift every later roll. A hash also means every player sees the same wreck.

## Fog of war (§3.5)

- **Hit moments**: already safe. `EventPlayer` resolves the view by lookup, and a missing view
  (unit outside the viewer's `seen`) is a no-op. **The attacker's muzzle flash must follow the same
  rule.** A flash or dust ring at an unseen attacker would reveal it, and that breaks §3.3.1.
- **Wrecks, columns, fires and scars outlive the unit**, so they need their own gate. Each one is
  drawn only if its tile is in the **active player's `seen`** grid. Re-evaluate at every handover
  and rebuild the column and fire MultiMesh instance lists per viewer. For the scar map, multiply
  by a per-viewer `seen` mask (1 texel per tile, linear-filtered) in the shader. A column on
  unscouted ground is the worst leak: it is 25 m tall and visible from across the map.
- **Rule question for `core/` (not decided here).** If a wreck blocks its cell but is hidden on
  unscouted ground, planning must treat it like an unseen enemy: the route ignores it, and the walk
  stops on the tile before. That keeps the zones honest from what the player can see.

## Briefs

**No generation needed (ship CC0 after acceptance):** all hit moments, the kill fireball, the wreck
fire, the smoke columns (u_* + k_pp), the rust layer (ph_rust_coarse_01) and the scorch detail
(ph_burned_ground_01).
**Needs making:** the wreck variants (a mesh and material spec, not image generation), the scar stamp
atlas, and the squad fallen-figure variant.

```
ASSET: wreck_<vehicle> (one per vehicle GLB: light vehicles, tanks, field gun, howitzer, engineer)
USE: prop (persistent, blocks its cell)   COVERS: the vehicle's own footprint, inside one 8 × 8 m tile
SOURCE REFS: r_c05 (palette, displaced turret), r_c15 (char body), r_c19 / r_c16 (thrown turret),
  r_c08 (rust extreme), g_coh3_14 (iso read)
VIEW: game angle 38–55°, judged from above; undersides never seen
CONTENT: the live unit's own mesh, not a new model. Requirement for the unit GLB pipeline: turret and
  gun are separate nodes. Changes: burnt material (below); gun depressed 5–10°; tank tracks and road
  wheels sagged, hull lowered 0.1–0.2 m; slat cages, antennas, stowage and every part < 0.3 m removed
  (sub-pixel at 22 cm/px, and they would keep the "alive" silhouette); hatches open.
  Thrown turret (tanks, 1 in 3): offset 1.5–2.5 m, yaw ±30–150°, tilt 10–25° or inverted. It stays
  **inside the wreck's own tile** (a turret in a neighbouring tile would read as blocking that tile).
  Towed gun: trails splayed, one wheel off, barrel down to the ground.
MATERIAL: tri-planar blend of char (L* 3–15) / ph_rust_coarse_01 (L* 27–36, a* 10–19, b* 14–28) /
  ash (L* 55–72) in ~45/40/15 %, driven by a world-space noise at 0.5–1.5 m patches; roughness 0.8–0.95.
  Applied **from the first frame**: fire and smoke hide it, and it is already burnt out when they fade.
  No team colour, no camouflage, no markings.
COLOUR: overall L* 15–28, well below a live unit's camo and below the ground (L* 30–31), so the
  obstacle reads by value at 34 px
MUST NOT: team colour or player tint; HP bar; any insignia, number or letter; a recognisable real
  vehicle shape; small parts that flicker at far zoom; a turret outside the tile
DELIVERABLE: GLB per vehicle class + the shared burnt ShaderMaterial; same origin and scale as the
  unit (1 tile = 1.0 unit, ground y = 0, front −Z)
ACCEPT IF: (1) at 22 cm/px the wreck is a 30–36 px dark blob distinguishable from a live unit beside
  it in a greyscale screenshot (mean L* difference ≥ 12); (2) at 7 cm/px the turret, gun and sagging
  tracks read, at ~107 px; (3) nothing of the wreck or turret crosses the tile edge by more than
  0.5 m; (4) with fire and column off, it looks burnt (rust + char visible, no camo); (5) triangle count
  ≤ the live unit's
```

```
ASSET: scar_stamps (atlas of ground scars, stamped into the scar map)
USE: detail / ground stamps   COVERS: per stamp, in metres (below)
SOURCE REFS: r_c13 (crater and wreck-scorch size from above), g_coh3_08 (scorch blot shapes at game
  angle), r_c04 (debris density), r_c19 (scorch on asphalt), ph_burned_ground_01 (fine breakup only)
VIEW: straight top-down orthographic, flat lighting, no cast shadows
CONTENT, 4 × 2 atlas, 512 px per cell, greyscale masks (R darkness, G crater depth, B debris):
  A wreck scorch 14 × 14 m: irregular dark blot 10–12 m across, a soft 2–3 m edge, 5–9 radial
    streaks 3–6 m long of uneven length (not symmetric, not a star); ash flecks 0.2–0.5 m inside
  B HE crater 152 mm 5 × 5 m: dark core 1.5–2 m slightly off-centre, a lighter churned ejecta ring to
    4–4.5 m with a ragged outer edge, 6–15 clods 0.2–0.5 m beyond it
  C small crater 3 × 3 m: core 1–1.5 m, ring to 2.5–3 m
  D infantry scorch 3 × 3 m: a dark irregular patch 2–3 m, no crater
  E debris scatter 10 × 10 m: 25–40 metal fragments 0.2–1.5 m, denser towards one side, random
    orientation, no two alike
  F–H second variants of A, B, C
COLOUR: masks only; the shader takes colour from the scorch/crater values in the colour table, so the
  stamps match the current ground under both presets
MUST NOT: perspective; radial starburst symmetry; concentric rings; grids or 2×2 repeats; props,
  vehicles, trees, shadows or tyre ruts in a stamp; features bigger than stated; painterly soft blobs
TILING: none (each stamp fades to 0 at least 8 % from its cell edge); no feature touches the cell edge
DELIVERABLE: 2048 × 1024 PNG, 8-bit RGB masks, linear; raw output, no post-processing by the
  generator. Procedural in Blender/Python from noise is acceptable, and preferable to an image model.
ACCEPT IF: (1) A's dark area is 70–85 % of its 14 m cell and has no rotational symmetry (rotate it
  90°: it is clearly different); (2) B's core is 1.5–2 m (≈ 150–200 px of 512) and its ring 4–4.5 m;
  (3) no cell contains a straight line longer than 1 m except debris edges; (4) every cell is black
  in its outer 8 %
```

```
ASSET: squad_<type> fallen-figure variant (rifle squad, assault squad)
USE: prop (part of the squad's one mesh, one draw call)   COVERS: the squad base, ~3 × 3 m
SOURCE REFS: g_coh3_08 (how fallen figures read at the game angle), the art-direction infantry kit
VIEW: game angle 38–55°
CONTENT: the squad mesh holds 4 standing figures and 4 lying figures in the same places; the shader
  shows standing figure i while i < alive and lying figure i otherwise (vertex colour or UV2 carries
  i), so the figure count changes with no extra draw call. Figures alive = ceil(4 × hp / max_hp).
  Lying poses: prone, on the side, or face up, 1.8 m long, ≤ 0.35 m high, a rifle lying beside 1 of
  them, a helmet off on 1 of them; a baked contact blob 2.2 × 0.8 m under each. Destroyed squad = 4
  lying figures; + stamp D if the kill was autocannon or HE; + stamp C if HE (tank, field gun,
  howitzer). A small-arms kill leaves the figures only.
COLOUR: uniform L* 20–28, low chroma (darker than field L* 31); contact blob −8 L*
MUST NOT: blood, wounds or gore; dismemberment; figures standing taller than 0.35 m when dead; any
  vertical mass that reads as an obstacle (dead infantry does not block); any insignia
DELIVERABLE: squad GLB with both figure sets, ≤ the existing squad triangle budget
ACCEPT IF: (1) at 22 cm/px a lying figure is a ~8 × 2 px dash, visible against field and mud in a
  greyscale shot; (2) at 7 cm/px a viewer can count living versus fallen figures; (3) nothing gory
  at 4× zoom-in; (4) one draw call per squad
```

## Settled

1. Ground scars go into a scar map read by the ground shader, not `Decal` nodes.
2. A wreck blocks vehicles only, burns out after a few rounds and is known where the viewer's
   `seen` covers it (CLAUDE.md §3.14).
3. A damaged squad loses figures as its HP falls; fallen figures and scars stay for the match.
4. Unity Labs flipbooks are reference only (unclear licence); ship Kenney CC0 sprites or
   flipbooks rendered offline in Blender.
5. `assets/vfx/smoke_puff.png` has no recorded source; replace it before release.

## Measured real footage: the burst and the smoke after it

Real-speed clips only (a real-time HE fireball lasts 1–2 frames and debris falls at 9.8 m/s²; slow-motion
sections give sizes, never times). Sizes against a known vehicle in the same frame, ±10–30 %; times ±1 frame.
References only, nothing shipped.

| what | measured | source |
| --- | --- | --- |
| 155 mm HE on soil | fireball 2 frames (0.07 s), then a neutral black ball 12 m wide by +0.1 s (L* 17–27); cloud top 6.6 m → 9.9 m (+2 s) → 15.8 m (+5 s); width 12 → 17 → 24 m (+6 s); **not faded at +7.8 s**; the dust skirt along the ground is wider than 40 m by +0.13 s | [YouTube -M2-Yr7iaKI](https://www.youtube.com/watch?v=-M2-Yr7iaKI), burst at 2.87 s, truck 5.2 m for scale |
| tank-gun hit on a turret (120 mm) | frame saturated 0.04–0.08 s; fireball 4.3 × 3 m at +0.12 s; flames gone by 1.2 s; blue-grey smoke over the whole tank by +0.8 s, below 20 % opacity at ≈ 3 s | [YouTube URCtPPdslXk](https://www.youtube.com/watch?v=URCtPPdslXk) 7.79 s |
| HEAT on a light armoured vehicle (stands in for the drone) | black cloud ≥ 6.7 m wide, ≥ 5 m tall by +0.4 s, still dense at +3.6 s | [YouTube tm_Evn0KLMQ](https://www.youtube.com/watch?v=tm_Evn0KLMQ) ≈ 15.2 s |
| 30 mm autocannon on soil | 0.1 s between rounds; each a jet 2–2.5 m wide, 3–4.4 m tall at +0.17 s; dust visible 4–5 s (dry desert: shorter on wet ground) | [YouTube Xu-YFwMV7_8](https://www.youtube.com/watch?v=Xu-YFwMV7_8) 33.1 s |
| rifle / MG on wet grass | dark clods 0.2–0.3 m high, 0.4–0.5 s in the air, no lingering dust | [YouTube 0NOFp08Q4c4](https://www.youtube.com/watch?v=0NOFp08Q4c4) 45 s (240 fps) |
| tank gun firing | flash ≈ 5 × 4.4 m, 1 saturated frame, 0.07–0.1 s in all; dust 2–3 m tall, ≥ 10 m long under the gun, still visible at +3 s | [YouTube putRj-2hP2Q](https://www.youtube.com/watch?v=putRj-2hP2Q) 14.43 s |
| ammunition cook-off (drone view) | white core 25–30 m within 0.1 s, saturated ≈ 0.5 s; a burning piece (turret) lands 15–25 m away | [YouTube s_9SAg_h9K0](https://www.youtube.com/watch?v=s_9SAg_h9K0) 20.5 s |

**What we take, and where we depart.** The burst order and the snap to full volume in 0.1–0.2 s are as
measured. The smoke follows the art-direction rule (rise with deceleration, widen, thin evenly to zero in
3–6 s), which matches a tank-gun hit puff and autocannon dust; a real 155 mm or HEAT cloud keeps rising
faster and stays opaque past 8 s, so ours is shorter on purpose — a cloud that hangs for 8 s over a cell
hides the board. The kill fireball stays at 12 m (the cook-off is 25–30 m): a fireball wider than three
tiles hides the units around it.
