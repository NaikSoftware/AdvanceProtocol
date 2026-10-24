# Surroundings beyond the board — reference and brief

What the 12-tile `outer:` ring looks like on screen: the play-area outline, the out-of-play grade,
the rain haze that hides the world's edge, and how cheap the ring may be. Taken as
fixed: the hand-authored ring ([tools/maps/README.md](../../tools/maps/README.md)), a thin red
outline on the board edge, and rain haze further out, with a slight darkening and desaturation
that comes in only with the haze.

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
  only together with the haze and on the same curve: smoothstep(3, 11, d), d the Euclidean distance
  from the board rectangle. Up to 3 tiles out the ground is exactly the ground of the board; the red
  line alone marks the edge. Ramp ends are flat (smoothstep), so there is no visible start or end.
MUST NOT: be screen-space (a vignette); get darker towards the screen edge; be applied to the board;
  change any tone at or near the board edge, or run ahead of the haze.
ACCEPT IF: (1) luminance sampled along a line crossing the edge is flat (same material) for the first
  3 tiles out; (2) beyond that it changes gradually with no kink; (3) panning shows the grade fixed to
  the ground, not to the frame.
```

```
ASSET: edge haze + skirt   USE: same shader term on all ring materials + one unlit quad
SOURCE REFS: P1 (cool, low-chroma airlight), M (haze value), P2 (why this is stylised)
CONTENT: h = smoothstep(3, 11, d), where d is the Euclidean distance in tiles from the board
  rectangle (so the corners are rounded and no diagonal seam shows). Clear to 3 tiles (24 m), 50 % at
  7 tiles (56 m), 100 % at 11 tiles (88 m), one tile before the ring ends. Inside the board h = 0 at
  every zoom: do not use camera-depth fog for this, because the camera is 63–362 m from the ground
  and depth fog would grey the board differently at each zoom.
  Skirt: one quad, unshaded, exactly the haze colour, from the ring's outer edge to ≥ 40 tiles
  beyond the board (screen corners reach 34.8 tiles at 20:9, zoom 20).
COLOUR: linear (0.10, 0.135, 0.155), L* ≈ 43, b* slightly negative. That is 0.5–0.7× the sky
  shader's horizon (0.20, 0.21, 0.22), bluer, and 8–15 L* above the wet ground, as in M and P1.
  Haze is applied after the grade, so far out it lightens rather than darkens: it does not frame.
  Rain particles continue over the ring unchanged.
MUST NOT: show the skirt edge or the clear colour anywhere at any zoom or pan; band; leave a river or
  road lit brighter than the haze (water needs the same term).
ACCEPT IF: (1) at zoom 20 with the focus clamped at each board corner, no pixel shows the clear
  colour or a skirt edge (20:9 and 16:9); (2) pixels at d ≥ 11 tiles are within 2/255 of the haze
  colour; (3) the river at 8 tiles out is within 10 % of the haze value.
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

## Conflicts with the fixed decisions

1. **The red outline and the red move-only contour.** A move-only zone that reaches the board edge
   puts its contour (#c94f3f) about 0.5 m from the outline. The brief separates them by value
   (L* 36 against 50), width (3 px against 5–13 px), solidity and side of the edge. The owner should
   still look at the two together on River before signing off.
2. **The ring alone cannot hide the world's edge.** With the pan clamp, screen corners reach
   15.7–34.8 tiles out, so the skirt is required. Haze must be full by about tile 11, which means
   authored ring content past about 8 tiles is mostly unseen (≥ 74 % haze).
3. **The "rain haze" is stylised.** Real overcast or rain haze changes things by under 2 L* within
   400 m (P2). Koschmieder gives 9–31 % at 96 m for 1–4 km visibility. Reaching 100 % at 88 m needs a
   visibility of about 115 m, which is fog. It reads as a fog bank at the edge, which suits the
   mood, but it is not physical rain haze.
