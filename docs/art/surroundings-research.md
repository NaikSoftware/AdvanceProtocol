# Surroundings beyond the board — reference and brief

What the 12-tile `outer:` ring looks like on screen: the play-area outline, the out-of-play grade,
the fog bank that hides the world's edge, and how cheap the ring may be. Taken as
fixed: the hand-authored ring ([tools/maps/README.md](../../tools/maps/README.md)), a thin red
outline on the board edge, and a textured, slowly billowing fog bank further out, with a slight
darkening and desaturation that comes in only under the fog. The fog itself is specified in
[Fog bank](#fog-bank); where this brief says haze, h or haze density, it means that fog's alpha.

Contact sheet: `art-refs/surroundings/surroundings_sheet.jpg` (gitignored, local only).

## Camera facts this brief is sized from

Computed from `IsoCameraRig` (FOV 42° vertical, pitch 38°→55°, zoom 6→20, focus clamped 2 cells
beyond the last board cell) at 1920×1080:

| zoom | pitch | distance to focus | cm/px at centre (depth) | cm/px at top edge | farthest reach of a screen corner past the board edge, 16:9 / 20:9 |
| --- | --- | --- | --- | --- | --- |
| 6 | 38° | 63 m | 7.2 | 27.8 | 15.7 / 17.5 tiles |
| 12 | 45° | 125 m | 12.5 | 32.5 | 23.3 / 26.3 tiles |
| 20 | 55° | 208 m | 18.1 | 33.8 | 30.5 / 34.8 tiles |

- **The ring's outer edge is on screen at every zoom.** The 12-tile ring cannot hide the world's edge by
  itself. The haze has to be fully opaque before the ring ends, and an unlit skirt in the haze colour
  has to fill everything beyond it.
- **The sky is never in frame.** The top ray is at least 17° below the horizon even at zoom 6.
  Nothing has to blend into a horizon.

## Shortlist

| id | source | licence | what it shows | verdict |
| --- | --- | --- | --- | --- |
| **G1** ★ | Company of Heroes 3, Steam store shot 14, <https://store.steampowered.com/app/1677280> | © Relic, reference only | Territory line draped on terrain. Measured: opaque core 3 px at 1080p, 1 px anti-aliasing, sRGB (175,33,33) = linear (0.43,0.015,0.015), no glow | **Line model.** Solid, thin, mid-dark red that reads on busy ground without dominating it |
| G2 | Headquarters: World War II, shot 07, <https://store.steampowered.com/app/1840800> | © Starni, reference only | Red contour with a 4 px near-white core plus 3 px glow, unbroken across a river and a bridge | Copy the continuity over water and bridges. Do not copy the neon glow: on a dark frame it becomes the brightest thing on screen |
| G3 | WARNO, shot 01, <https://store.steampowered.com/app/1611600> | © Eugen, reference only | 12 px zone outline with a translucent fill | Avoid. A UI frame, not a map edge |
| G4 ★ | Panzer Corps 2, shot 07, <https://store.steampowered.com/app/1072040> | © Flashback/Slitherine, reference only | Out-of-sight area beyond a dark 2 px edge, same grass both sides. Measured: luminance −48 %, chroma −30 % | **Out-of-play model.** It grades the world rather than framing it, and it moves with the map. Its strength suits fog of war; ours should be about half |
| G5 | Panzer Corps 2, shot 03 (same page) | © reference only | 3 px red outline with a soft inner tint, plus a dark out-of-sight edge | Confirms 3 px solid reads well from a high oblique camera |
| P1 ★ | [Fog above Taberlaane village](https://commons.wikimedia.org/wiki/File:Fog_above_Taberlaane_village.jpg), Rait Koch | Public domain | Drone at about 120 m over fields, river and forest in dim light. Forest L* 10 → 16 → 27 at about 0.15, 0.4 and 1 km; airlight cool blue | **Haze colour model**: cool, low-chroma, lighter than the ground |
| P2 | [Hausdülmen, Ortsansicht 2014 4385](https://commons.wikimedia.org/wiki/File:D%C3%BClmen,_Hausd%C3%BClmen,_Ortsansicht_--_2014_--_4385.jpg), Dietmar Rabich | CC BY-SA 4.0 | Late-autumn oblique aerial. Forest L* 10 at 0.4 km, 17 at 0.8 km, 33 at 2 km, 55 at 5 km | Real haze is under 2 L* within 400 m (see conflicts) |
| M | `docs/art/mood/river_target.jpg` | project | Ground L* 24–34; far haze L* 42–44, linear ≈ (0.10, 0.14, 0.16) | Target for the haze colour |

Rejected on sight: most store screenshots of Steel Division 2, Gates of Hell, Men of War II, Broken Arrow and
Wargame, because they are cinematic low shots with no map edge in frame. Total War and Combat Mission
boundary frames could not be found as images, so they are left out rather than described from memory.

## Brief

```
ASSET: board outline   USE: overlay in the ground and water shaders   COVERS: board perimeter
SOURCE REFS: G1 (width, colour, solid, no glow), G2 (unbroken over water and bridge)
VIEW: game angle, pitch 38–55°
CONTENT: one solid line, constant 3 px at 1080p (= 0.28 % of viewport height; clamp 2–4 px),
  anti-aliased over 1 px. In metres that is 0.22 m at zoom 6 centre, 0.54 m at zoom 20 centre and
  about 1.0 m at the top edge at zoom 20, so the width must be screen-space (fwidth), not world-space.
  The inner edge sits exactly on the board boundary (cell −0.5 / W−0.5) and the line grows outward,
  never over a board cell. Square corners. Drawn on whatever surface is at the edge (ground, water,
  bridge deck, road) without a break; buildings and trees occlude it (depth-tested).
COLOUR: linear (0.38, 0.015, 0.012) ≈ sRGB (166, 32, 28), L* ≈ 36, alpha 0.9, unshaded, and
  untouched by the out-of-play grade and the haze.
MUST NOT: glow, bloom, pulse, dashes, fill, or a world-space width that thins to under 1 px far away.
  Must not look like the move-only contour (#c94f3f, L* ≈ 50, 0.96 m wide pieces inside the cell).
ACCEPT IF: (1) width on a 1080p capture is 2–4 px at zoom 6, 12 and 20; (2) mean line pixel is within
  ΔE 6 of sRGB (166,32,28) on ground with L* 25–35; (3) unbroken across the river at both board
  edges of River; (4) at least 3 px of ground between it and a move-only contour on an edge cell
  at zoom 20.
```

```
ASSET: out-of-play grade   USE: post-lighting term in every ring material (ground, water, props)
SOURCE REFS: G4 (grade the world, not the screen; strength halved), mock on the contact sheet
CONTENT: luminance ×0.80 (−20 %) and saturation ×0.65 (−35 %) at most, both in linear light, applied
  only under the fog and in proportion to its alpha (Fog bank), d the Euclidean distance from the
  board rectangle. Up to 2 tiles out the ground is exactly the ground of the board; the red
  line alone marks the edge. Ramp ends are flat (smoothstep), so there is no visible start or end.
MUST NOT: be screen-space (a vignette); get darker towards the screen edge; be applied to the board;
  change any tone at or near the board edge, or run ahead of the haze.
ACCEPT IF: (1) luminance sampled along a line crossing the edge is flat (same material) for the first
  2 tiles out; (2) beyond that it changes only where the fog is, with no kink; (3) panning shows
  the grade fixed to the ground, not to the frame.
```

```
ASSET: edge haze + skirt   USE: same shader term on all ring materials + one unlit quad
SOURCE REFS: P1 (cool, low-chroma airlight), M (haze value), P2 (why this is stylised)
CONTENT: h = the fog bank's alpha (see Fog bank): its envelope is smoothstep(2.5, 11, d), where d
  is the Euclidean distance in tiles from the board rectangle (so the corners are rounded and no
  diagonal seam shows). Nothing at d < 2 tiles (16 m), lobes from ~3 tiles, closed by 11 tiles
  (88 m), one tile before the ring ends. Inside the board h = 0 at
  every zoom: do not use camera-depth fog for this, because the camera is 63–362 m from the ground
  and depth fog would grey the board differently at each zoom.
  Skirt: one quad, unshaded, the haze colour with the fog's value texture, from the ring's outer
  edge to ≥ 40 tiles
  beyond the board (screen corners reach 34.8 tiles at 20:9, zoom 20).
COLOUR: mean linear (0.10, 0.135, 0.155), L* ≈ 43, b* slightly negative; value texture per Fog
  bank. That is 0.5–0.7× the sky
  shader's horizon (0.20, 0.21, 0.22), bluer, and 8–15 L* above the wet ground, as in M and P1.
  Haze is applied after the grade, so far out it lightens rather than darkens: it does not frame.
  Rain particles continue over the ring unchanged.
MUST NOT: show the skirt edge or the clear colour anywhere at any zoom or pan; band; leave a river or
  road lit brighter than the haze (water needs the same term).
ACCEPT IF: (1) at zoom 20 with the focus clamped at each board corner, no pixel shows the clear
  colour or a skirt edge (20:9 and 16:9); (2) at d ≥ 11 tiles alpha ≥ 0.98 and the mean is
  within 2/255 of the haze colour (luminance cv 0.06–0.10); (3) the river at 8 tiles out is within
  10 % of the haze value.
```

```
ASSET: ring mesh + props   USE: static, baked, culled in chunks
CONTENT: the board uses 7 quads/tile (98 tris/tile), and 1 728 ring tiles at that density would be
  169k tris, which is the whole budget. Use bands instead:
    0–1 tile out: 7 quads/tile, vertices welded to the board edge (no seam)  ≈ 9.8k tris
    1–6 tiles:    2 quads/tile (4 m spacing)                                   ≈ 5.0k
    6–12 tiles:   1 quad/tile (8 m; under ≥ 50 % haze)                         ≈ 2.0k
    skirt:        2 tris
  ≈ 17k tris in 4 side chunks + the skirt = 5 draw calls.
  Props: same assets as the board. Full board density 0–3 tiles, so there is no density step at the line;
  50 % at 3–9 tiles; none beyond 9 tiles (haze ≥ 84 %), where forest is a dark canopy texture. Trees
  share the board's MultiMesh where possible. Ground texture detail finer than 0.3 m can drop
  beyond 4 tiles, since nothing under 28–34 cm/px resolves there.
ACCEPT IF: ≤ 20k extra tris and ≤ 6 extra draw calls at zoom 20; no visible seam or density step at
  the board edge at zoom 6; faceting is visible only where haze is ≥ 50 %.
```

## Fog bank

The world past the ring is hidden by a fog bank, not by a flat gradient: lobes and wisps with a
lit top, thin in front, closed behind, drifting slowly. It is the only thing that changes the
ground's tone outside the board, so the colour shift comes and goes with each lobe and never lines
up with the board edge.

Contact sheet: `art-refs/surroundings/fog_sheet.jpg`; mock over the mood frame:
`art-refs/surroundings/fog_mock.png` (both gitignored, local only). The mock is scaled as zoom 20
(12 → 30 cm/px, so the painting's houses read about 18 m) and has no height term: houses are fogged
like the ground, where in the game tall props would stand out of it (see Technique).

### References

| id | source | licence | what it shows | verdict |
| --- | --- | --- | --- | --- |
| **F1** ★ | [Vetla village in fog](https://commons.wikimedia.org/wiki/File:Vetla_village_(Estonia)_in_fog,_september_2021.jpg), Sillerkiil | CC BY-SA 4.0 | Drone, ~45° oblique over forest and farm. Bank goes from clear to ~80 % over ~65 m (scale: 12–15 m farmhouse); inside the bank opacity 0.2–0.95, luminance cv 0.39 | **Edge model**: width of the transition and how patchy it stays |
| **F2** ★ | [IJssel, morning mist, 8 Nov 2020, frame 26](https://commons.wikimedia.org/wiki/File:Deventer_-_Ijssel_-_morning_with_mist_-_8_nov_2020_-_DJI_mavic_mini_drone_-_aerial_imagery_-_break_of_the_day_-_26.jpeg), Daanvr | CC BY 4.0 | Late-autumn drone over a river and floodplain. Rounded lobes 18–45 m across (scale: 10 m tree crowns), each lobe's edge soft over 3–7 m; wisps 4–9 m break off the front | **Lobe model**: size and edge softness of the billows |
| F3 | [Souyeaux, early morning mist](https://commons.wikimedia.org/wiki/File:Souyeaux_village_in_the_early_morning_mist,_looking_West.jpg), MikeCaffyn | CC BY-SA 4.0 | Drone over fields and houses. Wisps 8–13 m wide and ~40 m long (scale: 10 m houses), 3–5× longer along the drift than across | Wisps are stretched along the wind |
| **F4** ★ | [Izborsk valley, fog](https://commons.wikimedia.org/wiki/File:Izborsk_Valley._landscapes10.Fog.jpg), Strokin.ru | CC BY 3.0 | Overcast blue light, conifers standing out of layered fog. Opaque top: luminance cv 0.08; thin layer over the ground: opacity 0.06–0.46 | **Colour and light model** for our overcast; the top of a closed bank is nearly flat in value |
| F5 | [Fog in the Ural river valley](https://commons.wikimedia.org/wiki/File:Fog_in_the_Ural_river_valley.jpg), Deniska000 | CC BY-SA 4.0 | Valley band from a high window: opacity 0.13–0.85 with clear gaps between bands | Gaps stay open even deep in a bank |
| V1 | [Drone video of foggy Vetla village](https://commons.wikimedia.org/wiki/File:Drone_video_of_foggy_Vetla_village_in_Estonia.ogv) | CC0 | 3.5 s of static camera, then flight. Over 3 s, mean change 6.8/255; the difference image shows streaks changing shape in place | Fog changes shape faster than it travels |
| V2 | [Fog.ogv](https://commons.wikimedia.org/wiki/File:Fog.ogv) | CC BY-SA 4.0 | Static camera, 15 s, wisps over a scrub slope. Phase correlation finds no rigid shift; wisps form and dissolve in 5–15 s | Animate by morphing, not only by scrolling |
| **G1** ★ | Frostpunk 2, Steam shot 13, <https://store.steampowered.com/app/1601580> | © 11 bit, reference only | High oblique city view; the frame's far edge is billowing low cloud, luminance cv 0.42 | **Closest game model**: the world ends in textured cloud, not a gradient |
| G2 | Frostpunk 2, shot 22 (same page) | © reference only | Night; cloud banks with lit tops drift over the far districts | Lit tops and dark troughs give the volume |
| G3 | Anno 117, shot 01, <https://store.steampowered.com/app/3274580> | © Ubisoft, reference only | Far corner of a marsh under patchy ground fog, cv 0.24; near ground untouched | Fog at the far edge only, ground near the player at full contrast |

How these games build it cannot be read from store shots, so no technique is attributed to them.
Store shots of Farthest Frontier, Manor Lords, Anno 1800 and three Total War games show no map
edge and are not used. Bad North, Northgard and Against the Storm are stylised and are not references.
Rejected on sight: a Kherson bridge video (no fog, real place) and a Vermont foliage video (no
overcast, burnt-in caption).

### Measurements

| feature | real size | tiles | at 18–34 cm/px (where the fog sits on screen) |
| --- | --- | --- | --- |
| wisp, across × along the drift | 4–13 m × 30–55 m | 0.5–1.6 × 4–7 | 12–70 px × 90–300 px |
| lobe (billow) | 18–45 m | 2–6 | 55–250 px |
| clear gap or thick patch inside a bank | 60–150 m | 8–19 | the whole ring |
| edge of one lobe, clear → its full value | 3–7 m | 0.4–0.9 | 9–40 px |
| whole bank, clear → ~80 % | 50–90 m | 6–11 | matches the 3 → 11 tile ramp |

- **Opacity inside the transition** varies widely at any one distance: 0.2–0.95 (F1), 0.13–0.85
  (F5). A ramp that varies by less than ±0.2 around its mean reads as a gradient.
- **Value of a closed bank** varies little: cv 0.08 in overcast (F4), against 0.24–0.42 where
  ground still shows through (F1, G1, G3). Under overcast the top is lit from above: thick parts are
  lighter, thin parts take on the dark ground.
- **Speed.** Radiation fog thickens in winds of 2–7 kt (1–3.6 m/s) and a stronger breeze prevents
  it; advection fog runs at 3–9 kt and lifts into stratus above 9 kt (NWS fog forecasting guide, <https://www.weather.gov/media/zhu/ZHU_Training_Page/fog_stuff/fog_guide/fog.pdf>).
  The videos show no rigid translation measurable over 3–15 s: the change is in density and shape,
  with wisps re-forming in 5–15 s.
- Detail under ~2 m is irrelevant: it is under 6 px at 34 cm/px, and fog has no hard edges.

### Technique

**Recommended: noise in the existing ring shaders, no new geometry.** `haze_density()` and
`haze_rgb()` in `surroundings.gdshaderinc` are the only places that know what the haze is, and the
ground, water, deck and skirt shaders already call them; the fog bank replaces those two functions.
Extra cost: 4 texture fetches and ~30 ALU per ring fragment, zero draw calls, zero overdraw.

Rejected: alpha cards over the ring. At zoom 20 the ring and skirt cover 30–50 % of the screen, so
two card layers add 0.6–1.0 full-screen blended passes (1.2–2 M fragments at 1080p), and the cards cut
hard lines through trees and houses unless they read the depth buffer, which is another full-screen
cost. Procedural hash noise (the `fbm` in `terrain_noise.gdshaderinc`) costs 4 hashes per octave;
nine octave evaluations per fragment is too much ALU for the far third of the screen.

The model, in world metres (d = distance from the board in tiles, as now):

```
noise texture: NoiseTexture2D, seamless, 512², R8, fBm 4 octaves, gain 0.7, generated at load
  mapped to 256 m (0.5 m/texel), so its repeat (32 tiles) is longer than the visible ring
  octave wavelengths 48 / 24 / 12 / 6 m; the 12 and 6 m octaves stretched 2× along the wind
warp:     w = (noise(p/3 rotated 37°) - 0.5) * 2 * 12 m, sampled twice (x, y), scrolling 0.36 m/s
density:  q = p + w - wind * 0.8 m/s * t;  n = noise(q), remapped to 0..1 over its 5-95 % range
coverage: c = smoothstep(2.5, 11, d)
puff:     smoothstep(1 - c - 0.12, 1 - c + 0.12, n)       # lobes appear in front, merge behind
alpha:    max(puff * (0.25 + 0.75 c), 0.45 c^2)            # front wisps thin, a veil under the lobes
          max(alpha, smoothstep(10, 11.5, d)); alpha = 0 where d < 2
value:    haze_color * (1 + 0.10 relief + 0.08 (n - 0.5)) * (0.94 + 0.08 puff)
          relief = clamp((n(q) - n(q - 6 m along the view direction on the ground)) / 0.04, -1, 1)
grade:    surround_grade() takes alpha, not smoothstep(3, 11, d): the ground darkens under a lobe
          and is untouched in a gap
```

The envelope (coverage) is fixed to the board; only the pattern inside it moves. Lobes roll along
the bank, grow and shrink, and the bank never advances onto the board. The yaw is fixed, so the
relief offset is a constant vector. The skirt (d ≥ 12) runs only the value term (2 fetches): a
flat skirt next to a textured ring would show its edge. If props are added to the ring, they take
the same term with alpha × (1 − smoothstep(0.5 H, H, y)), H = 6 m at d = 3 rising to 20 m at d = 11,
so tall trees stand out of the fog as in F2 and F4.

### Motion and battery

- **Speed: drift 0.8 m/s** (acceptable 0.5–1.5), slower than real fog on purpose, so the edge
  stays calm during a long turn; the warp scroll makes lobes re-form over about 30 s. Where the fog
  sits on screen (18–34 cm/px) that is 2.4–4.4 px/s. Below about 1.5 px/s with no re-forming it
  reads as a still texture; this threshold is an estimate to confirm on a phone.
- **Low tick rate works.** In the mock, a 0.1 s step (10 Hz) changes no pixel by more than 2/255
  (p99 1/255); 0.2 s (5 Hz) by at most 4/255 (p99 1/255); 0.5 s (2 Hz) reaches 10/255 on the
  sharpest lobe edges, which shows as stepping. Tick at 10 Hz, never below 5 Hz.
- **Do not use `TIME` in the fog.** In Godot 4 the Mobile renderer requests a redraw for every
  frame in which a visible material uses `TIME` (`render_forward_mobile.cpp`, "request a redraw if
  one of the shaders uses TIME"), and low-processor mode skips a frame only when nothing has
  changed (`main.cpp`). Drive the fog from a global shader uniform `fog_time` advanced by a 10 Hz
  timer; each update costs one frame, so an idle board draws 10 frames per second. `water`,
  `ground` (ripples, cloud shadow) and `rain` use `TIME`, so the battle screen already never
  idles; the fog's 10 Hz pays off only once those move to the same tick.

### Brief

```
ASSET: fog bank   USE: haze_density / haze_rgb in surroundings.gdshaderinc (ground, water, deck,
  skirt; ring props if added)   COVERS: d = 2 tiles to the skirt's end
SOURCE REFS: F1 (transition width, patchiness), F2 (lobe size, edge softness), F3 (wisps stretched
  along the wind), F4 (overcast colour, flat value of a closed top), G1 (world edge in cloud)
VIEW: game angle, pitch 38–55°, fixed yaw
CONTENT: lobes 18–45 m (2–6 tiles) with edges soft over 3–7 m; wisps 4–13 m wide and 30–55 m long
  in front of them, thin (alpha ≤ 0.3); behind 9 tiles the lobes merge into a closed top. Noise and
  numbers as in the Technique section; the envelope is smoothstep(2.5, 11, d) and nothing at d < 2.
COLOUR: haze_color linear (0.10, 0.135, 0.155), L* ≈ 43; thick parts up to +8 % lighter,
  thin parts toward the ground; on the closed top luminance cv 0.06–0.10 (F4: 0.08). The ground
  grade (luminance ×0.80, saturation ×0.65 at most) follows the same alpha.
MUST NOT: be a smooth gradient with a wavy edge; tint or darken anything at d < 2 tiles; repeat a
  lobe shape within 32 tiles; show a band where the ring meets the skirt; drift the envelope onto
  the board; use TIME; flicker or step at the tick rate; read brighter than the mood haze (L* > 48).
TILING: world-space, seamless 256 m texture; no screen-space term.
DELIVERABLE: shader functions + one NoiseTexture2D (512², R8, generated at load) + a 10 Hz fog_time
  driver. No new meshes or draw calls.
ACCEPT IF: (1) ground at d < 2 tiles matches the same material on the board (ΔE < 1) at any
  fog_time; (2) at d = 5–9 tiles the alpha p5–p95 spread is ≥ 0.5 and at least 3 separate lobes show
  along a 20-tile stretch of edge; (3) at d ≥ 11 alpha ≥ 0.98, mean within 2/255 of haze_color,
  luminance cv 0.06–0.10; (4) consecutive ticks differ by ≤ 2/255 per pixel, while 20 s apart the
  p99 difference is ≥ 15/255; (5) with all other TIME uses removed, an idle board draws 10 ± 1
  frames per second (Engine.get_frames_drawn over 10 s).
```

## Conflicts with the fixed decisions

1. **The red outline and the red move-only contour.** A move-only zone that reaches the board edge
   puts its contour (#c94f3f) about 0.5 m from the outline. The brief separates them by value
   (L* 36 against 50), width (3 px against 5–13 px), solidity and side of the edge. The owner should
   still look at the two together on River before signing off.
2. **The ring alone cannot hide the world's edge.** With the pan clamp, screen corners reach
   15.7–34.8 tiles out, so the skirt is required. Haze must be full by about tile 11, which means
   authored ring content past about 8 tiles is mostly unseen (≥ 74 % haze).
3. **The edge is fog, not rain haze.** Real overcast or rain haze changes things by under 2 L* within
   400 m (P2). Koschmieder gives 9–31 % at 96 m for 1–4 km visibility; reaching 100 % at 88 m needs a
   visibility of about 115 m, which is fog. So the edge is drawn as a fog bank lying beyond the
   board, with fog's texture and motion, while rain keeps falling over the board unchanged.
4. **Motion against battery life.** A moving fog keeps the frame from idling. The Fog bank section
   holds it to a 10 Hz uniform tick, which costs 10 frames per second on an idle board.
