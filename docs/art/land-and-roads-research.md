# Land surfaces and roads research (Phase 5a, 2026-10-24)

The owner says the dirt road and the hill/rubble patch beside the river on the River map look "strange and unnatural". Both show streaky texture smeared in one direction. visual-critic also saw a cell-aligned field rectangle, stripes on a hill top, and road and field textures that follow the cell grid.

**The terrain look is decoupled from the tile grid.** Cells exist only for the rules and pathfinding. A tile may show several surfaces, and no grid may be visible anywhere.

This document diagnoses the renderer (`game/battle/shaders/ground.gdshader`), gives measured real-world numbers, and sets a brief a screenshot can be checked against. It complements [ground-texture-research.md](ground-texture-research.md), whose CC0 decisions stand (see "CC0 decisions").

Files are in `art-refs/refs/land/`:

- one folder per id, each with `source.txt`
- `sources.txt`: every URL, licence and author, plus the rejections
- `sheet.jpg`: 21 references plus the two mood frames
- `diag/`: crops of the current renders and contact sheets of the shipped macro textures

All photos are reference-only. Only the Poly Haven scans may be shipped.

## 1. Diagnosis

Renders checked: `art-refs/relief/natural/` b1, b3, b4, close, far and top. Crops are in `diag/close_crop.jpg` and `diag/b3_crop.jpg`. The shipped macros are in `diag/macro_current*.jpg`.

### 1a. Hill, rubble and bank streaks: swapped tri-planar weights (a shader bug)

In `fragment()`, lines 453–494, the steep-slope branch samples two world planes:

- `pxy = world_pos.xy`, a projection along Z, which is correct for faces whose normal points along ±Z
- `pzy = world_pos.zy`, a projection along X, which is correct for faces whose normal points along ±X

The weights are crossed. `tx = |n.x|^4` weights the XY sample (`sa`), and `tz = |n.z|^4` weights the ZY sample (`sb`):

```
ra = mix(ra, (sa * tx + sb * tz) / tn, steep);   // line 480; same at 481, 493, 494
```

Take a slope facing +X. Walking across it along Z changes neither x nor y, so the XY sample is constant along Z: one texel is smeared across the whole flank. The division by `tn` then normalises that sample to 100 % even when `tx + tz` is tiny. The branch switches on at `slope_tan` 0.5–0.8 (27–39°), which covers the river-cut hill flanks and the banks.

The prediction matches both views:

- On the south-facing bank in `top.png`, the streaks run horizontally along x.
- On the hill flank in `close.png`, they run diagonally along the contour (`diag/close_crop.jpg`).

**Fix:** XY weighted by `|n.z|^k` and ZY by `|n.x|^k`. Also blend the planar top projection by `|n.y|^k` rather than by `steep` alone, so the three weights sum honestly.

This is the "rubble/hill patch" the owner meant. Its pale 1 m blobs come from the hill macro, stretched 3–10× along the contour.

### 1b. Dirt road smear: a directional macro, re-offset every ~4 m, inside an 8 m cell strip

The cause has four parts, which compound.

1. **The texture.** `dirt_albedo_0/1` is a world-space macro (12 m per repeat, `MACRO_TILES = 1.5`, line 79). It carries baked tyre tracks running along v, and it is itself a 2×2 mosaic with a repeated 3 m puddle. Variants 0 and 1 are the same file.
2. **The sampling.** The macro is sampled through hex tiling (lines 110–139, 157). Every hex vertex, about 3.5–4 m apart, gets its own random offset of up to 8 repeats. The rotation is forced to the road axis, so the tracks stay parallel, but their lateral position jumps every ~4 m. The three-way blend preserves contrast, so 2–3 misregistered track sets overlay one another. On screen that reads as long, parallel, broken streaks, a "planked" smear (`diag/b3_crop.jpg`).
3. **The geometry.** The road is a whole cell wide. `road_w` comes from the per-cell `kind_map` blend, so the strip is 8 m plus the ±3.6 m jitter. A real track is 2.4–5 m. The edges are long and straight, and the corners are 90° (b1, top right).
4. **More streaks on top.**
   - The procedural ruts (lines 526–556) are a second, straight pair at ±0.9 m. They are computed per cell from the unwarped `pc = floor(p + 0.5)` (line 380), while the surface boundary uses the warped `q`. The ruts therefore stop at cell edges, vanish at corners and disagree with the baked ruts.
   - The mud verge (line 349) puts the `mud` macro on both sides of every road. That macro has long diagonal tyre tracks crossing the whole frame, which is exactly the fault that got `aerial_mud_1` rejected. It is randomly rotated per hex cell, which adds more smears.

**Fix:** make the road its own geometry.

- Take a centreline spline through the road cells, with a distance field and road-local (u, v).
- Draw the ruts, puddles and centre grass in road-local UV, per brief B4, continuously along u.
- Draw the road soil with a non-directional, isotropic texture.
- Do not use a world-space macro with baked tracks, and drop the mud-verge macro.

### 1c. Not the cause: texture scale

The 512 px over 12 m macros give 2.3 cm per texel, which mips cleanly at 7–22 cm/px, and their features are roughly real-size: hill boulders 0.6–0.9 m and rubble bricks about 0.25 m.

One latent scale fault remains. `MACRO_TILES` is a single constant, so the CC0 picks would be squeezed or stretched:

- `coast_land_rocks_01` is 20 m and would shrink to 12 m (0.6×).
- `dirt_aerial_03` is 25 m and would shrink to 0.48×.

The macro repeat must become per-layer metres, as `repeat_m` already is for detail.

### 1d. Why boundaries follow cells

| # | where | what it does |
| --- | --- | --- |
| 1 | lines 298–321 and `terrain_noise` | The surface comes from `kind_map` per cell, blended bilinearly. `border_warp` moves the boundary by at most 0.45 tile (3.6 m) at about a 10 m wavelength (`fbm(p * 0.8)`), plus 0.06 tile at 2 m. Since that is less than half a cell, every rectangle of N cells keeps its corners near the cell corners and its sides read as straight lines with a regular wobble. The noise is axis-aligned value noise, which reinforces this. |
| 2 | `BORDER_SOFTNESS = 0.22` | Every transition is the same 3.5 m ramp, sharpened by the height blend to about 1–1.5 m. Real edges are sharp locally (0.15–0.5 m) and irregular in plan. The shader does the opposite: it blurs the width and keeps the plan regular. |
| 3 | `hex_rand(..., quarter)` for ROAD and FIELD | Rotations are limited to multiples of 90°. The shipped field macros carry long straight lines: `field_0` has a starburst and a 2×2 seam, `field_1` has diagonal bands. Those lines snap to the grid axes and diagonals. |
| 4 | lines 338–343 | The mud cover `near` reads `layer_at` at ±1.5 cells, so it is piecewise constant per cell, and the mud threshold steps at cell borders. |
| 5 | wear and `along_x` | The road axis, the ruts and the corner fade are all per cell (1b). |
| 6 | `terrain_height.gd` 246–258 | The hill mask is a per-cell 0/1 grid, warped ±0.3 cell and blurred anisotropically. Hills therefore come out as rounded rectangles aligned to the axes. |

### 1e. Shipped macros with generator faults (not all in the owner's list)

| macro | fault |
| --- | --- |
| `field_0` | starburst lines and a 2×2 mosaic |
| `field_1` | diagonal streak bands |
| `mud_0` | long diagonal tracks that cross the frame |
| `dirt_0/1` | 2×2 mosaic with baked ruts |
| `road_0` | the asphalt tile repeats 3×3 inside the 12 m macro |
| `bank_0` | a visible vertical split |
| `rubble_0/1` | a visible lattice of about 4 m |

`hill_0/1` is not `coast_land_rocks_01`: the CC0 picks of 2026-10-22 have not been shipped yet.

## 2. References (`sheet.jpg`)

| id | content, view | licence, author | used for |
| --- | --- | --- | --- |
| r1 | Belarus gravel road, ground level, overcast | CC BY-SA 4.0, Budgawl | gravel surface, verge mix, width by comparison |
| r2 | Belarus sand track with dead grass | CC BY-SA 4.0, Budgawl | two-rut track wandering in plan; verge = the meadow itself |
| r4, r5 | German gravel lane, nadir | CC BY-SA 4.0, D. Rabich | **measured**: width, edge, verge |
| r6 | Belarus track, November, grass centre, brick ruin | CC BY 4.0, Aleks Senno | late-autumn palette, centre strip, rubble at a ruin |
| r7 | Belarus two-track through a dead meadow | CC BY-SA 4.0, Д. Гаврилюк | ragged verges and curves of a track |
| r8 | Belarus village gravel road, overcast | CC BY-SA 4.0, Bsivko | width and colour of a village road |
| r9 | Belarus rutted mud forest road | CC BY-SA 3.0, A. Kuźniečyk | wet ruts and puddle shapes (mud state) |
| r10 | Ukraine two-track | CC BY 3.0, EugeneLoza | gauge and centre grass |
| r11 | Germany, November, oblique road between fields | CC BY-SA 4.0, D. Rabich | field-to-field balks, curve read at the game angle |
| r12 | winding autumn road, oblique | CC0, A. Burden | bend radius against road width, leaf-covered edges |
| r13 | road junction from the air | CC BY 4.0, J. Gómez Fernández | plan form of a junction (shape only, not colour) |
| l1, l2 | Belarus, oblique: road, meadow, scrub, forest edges | CC BY-SA 4.0, Budgawl | organic surface boundaries at the game angle |
| l3 | Germany, November, forest edge with leaf litter | CC0, L. Lenz | colour of the litter fringe |
| l4 | Germany, November, nadir forest edge, about 3.6 cm/px | CC BY-SA 4.0, D. Rabich | **measured**: forest edge |
| l5 | Germany, November, oblique forest and field edge | CC BY-SA 4.0, D. Rabich | headland strip |
| l6 | Germany, January, nadir frosted meadow with a track | CC BY-SA 4.0, D. Rabich | dead-meadow patch scale |
| k1 | Switzerland, stone pile with a boulder | CC BY 4.0, Arkelin | rocky-patch clast sizes |
| PH | Poly Haven `coast_land_rocks_01` (20 m), `aerial_rocks_02` (50 m), 12 m crops | CC0 | shippable rocky-ground source |

Rejected, with reasons in `sources.txt`:

- r3: buildings and spring green
- o1: a readable sign
- snow frames
- frames with a speed-limit sign
- Commons full-text searches for "aerial dirt road" and "forest edge drone": nearly empty, so don't retry

## 3. Measured numbers (metres; pixels at 7 / 22 cm/px)

Scale for r5 assumes a standard 3.0 m Wirtschaftsweg, giving 2.1 cm/px. For l4, the tramline gauge (about 1.8 m) gives 3.6 cm/px.

One tile is 8 m: 114 px at the closest zoom and 36 px at the farthest.

### Roads

| quantity | value | px (7 / 22 cm) | source |
| --- | --- | --- | --- |
| gravel lane width | 3.0 m; standard deviation 3.4 %, p5–p95 0.96–1.08 × mean | 43 / 14 | r5 |
| East-European gravel village road | 4–6 m (estimated: two wheel pairs plus about 1 m) | 57–86 / 18–27 | r1, r8 |
| two-rut track | 2.4–3.0 m overall; gauge 1.5–1.8 m; rut 0.3–0.6 m; centre grass 0.4–0.8 m | rut 4–9 / 1.4–3 | r2, r6, r7, r10, m2 |
| edge raggedness, maintained gravel | standard deviation 0.06 m, p95 0.12 m (1–4 m wavelength) | about 1 / sub-px | r5 |
| edge raggedness, dirt track | ±0.2–0.5 m with grass tufts biting 0.3–1 m in, every 1–3 m (estimated) | 3–7 / 1–2 | r6, r7, r9 |
| gravel-to-grass transition (10–90 %) | median 0.17 m, p90 0.44 m | 2–6 / 1–2 | r5 |
| verge, Western lane | 3.4–5.3 m of grass to the crop edge | | r4, r5 |
| verge, East-European track | 0.5–1.5 m of trampled sparse grass with spilled gravel, then the meadow | | r6, r7, r8 |
| plan form | bend radius 4–6 road widths (about 15–25 m) in forest; 30–80 m in fields; wander ±0.5–1 m over 20–40 m even on "straight" runs | | r12, r13, l1 |
| junction | the inner corner is an arc of 6–12 m radius; no 90° corners | | r13 |
| puddles (wet state) | 0.3–0.5 × 1–4 m in ruts; whole-width 2–5 m in low spots; 30–50 % of rut length | | r9, B4 |

### Surface boundaries

| boundary | edge sharpness (10–90 %) | shape noise | source |
| --- | --- | --- | --- |
| field to field | crop edge 0.3–1 m | almost straight over 50–200 m; a 1–3 m grass balk between; wavers ±0.3 m | r11, l5, r13 |
| meadow to meadow, or meadow to dead-grass patch | 1–3 m tone blend | blotches 2–6 m inside 10–30 m patches; no straight run | l6, l1, l2 |
| meadow to forest | the crown edge is sharp (under 0.3 m) | crown lobes ±3–5 m at 10–20 m; fine fringe ±0.3–0.6 m at 1–3 m (measured standard deviation 0.6 m, range 2.6 m on the crop side) | l4 |
| forest floor to meadow (ground only) | litter and herb fringe 1–3 m | follows the crown lobes | l3, l4, l5 |
| road to verge | see Roads | | |

### Hills, rocky patches and rubble

- **Lowland hills (moraine)** (l1, l2, r2):
  - 3–10 m high, 30–200 m across, oval, aspect ratio 1–2.5.
  - Flanks are 5–15°, at most 20–25°.
  - They are covered in the same meadow as their surroundings, perhaps 2–4 L\* drier on the crests.
  - Bare soil or sand shows only on eroded cuts steeper than about 25° and on river cuts.
- **Rocky patch** (k1, PH):
  - Clusters 3–8 m across.
  - Boulders 0.3–1.5 m (4–21 px close, 1.4–7 px far), with 0.1–0.4 m stones between.
  - Cover 30–60 % inside a cluster and 10–25 % over a whole hill.
  - Grass is continuous between clusters, and cluster edges fray over 0.5–1 m.
- **Rubble at a ruin** (r6):
  - Extends 2–5 m beyond the wall footprint.
  - Brick fragments of 0.1–0.3 m read as tone only at the far zoom; chunks are 0.5–1.5 m.
  - It fades into dead grass over 1–2 m, with tufts growing into it.

### Colour (L\*a\*b\*: 10th percentile / median / 90th percentile)

| sample | L\* | a\* | b\* |
| --- | --- | --- | --- |
| mood target, field | 27 / 35 / 39 | 0.9 | 9.7 |
| mood target, track | 17 / 33 / 56 (puddles reach 56) | −1 | 1 |
| mood target, dark field patch | 9 / 20 / 35 | 0.4 | 6 |
| current render, dirt road | 27 / 33 / 36 | 0.2 | 3.8 |
| current render, field | 24 / 29 / 35 | −0.2 | 5.2 |

The render's mean values are close. Its range is too narrow: the track lacks the dark ruts and the bright puddles, and the field is about 4 b\* too grey.

## 4. Brief

```
ASSET: ground shader — natural surfaces and roads, grid-free
USE: macro ground + procedural road layer   COVERS: whole board incl. outer ring
SOURCE REFS: r5/r4 (road width, edge, verge), r6/r7/r10 (track ruts, centre grass, ragged verge),
  r9 (wet ruts, puddles), r12/r13/l1 (curves, junction arcs), l4/l5 (forest edge), r11/l6 (field and
  meadow boundaries), k1 + PH coast_land_rocks_01/aerial_rocks_02 (rocky patch), mood target (colour)
VIEW: game angle 50–55°, judged at closest (7 cm/px), default and farthest (22 cm/px) zoom, plus
  one orthographic nadir debug frame with a toggleable cell-grid overlay
CONTENT:
  - surface boundaries from a continuous field, not from per-cell lookup: blend/warp noise with
    two scales, ±2–4 m at 15–30 m wavelength and ±0.3–0.6 m at 1–3 m, rotated (not axis-aligned)
    noise; local edge 10–90 % width 0.3–1.0 m (field/meadow), 1–3 m (meadow tone patches)
  - roads as their own layer: centreline spline through road cells, corners filleted with radius
    4–12 m, centreline wander ±0.3–0.8 m at 20–40 m; width per road type (track 2.4–3.0 m, gravel
    3–5 m) varying ±5–10 %; edge noise ±0.1–0.3 m (gravel) / ±0.2–0.5 m with 0.3–1 m grass bites
    every 1–3 m (track); verge 0.5–1.5 m of sparse grass and spilled gravel
  - ruts, centre grass and puddles in road-local (u,v) per B4, continuous along u through corners
    and junctions; the road soil is an isotropic texture (no baked tracks), no mud-verge macro
  - hills are relief, not a texture: meadow continues over them; rocky clusters 3–8 m with
    0.3–1.5 m boulders only where slope > ~25° or on crests, 10–25 % hill cover; hill outline oval
    from smooth noise, not a blurred cell mask
  - triplanar on steep faces with correct weights (XY ← |n.z|, ZY ← |n.x|, top ← |n.y|)
  - macro repeat in metres per layer (CC0 scans at their stated size: 20 m, 25 m, …)
COLOUR: field L* 27–39 median ~33, b* 8–12; track median L* 30–35 with ruts ΔL* −8…−12 and wet
  puddles reaching L* 50–56 (mood target); hill same as field ±4 L*
MUST NOT: any surface edge, rut or tone step that lines up with cell edges; straight axis-aligned
  road edges and 90° road corners; baked tracks in a world-space macro; texture stretched along a
  slope or contour; road a full tile wide; one uniform transition width everywhere; quarter-turn-only
  rotation of macros with linear features; starbursts, 2×2 mosaics, internal lattices in macros
TILING: no visible repeat within 50 m; no periodic feature at the 8 m tile frequency
DELIVERABLE: shader + GroundSurface/TerrainHeight changes; no generated images
```

**Accept if** each line below can be measured on the screenshot set:

- **No grid, spectrum.** On the nadir debug frame (16 × 16 tiles, without the overlay), average the absolute horizontal and vertical luminance gradients into column and row profiles. Their FFT has no peak at 1/tile or 2/tile that is more than 1.5× the median of the 5 neighbouring bins.
- **No grid, boundaries.** Of the traced surface-boundary length, at most 25 % lies within ±0.1 tile of a grid line. That is chance level: a ±0.1-tile band around every grid line covers 36 % of the area. No boundary segment is straight and axis-aligned for more than 1 tile.
- **No streaks.** In 2 × 2 m windows on ground other than road (nadir and default zoom, including slopes over 30° and banks), the structure-tensor coherence (λ1−λ2)/(λ1+λ2) has a median below 0.3 and stays under 0.6 in at least 98 % of windows.
  - On a slope of 30° or more, a feature's extent along the fall line and across it differs by at most 1.3×.
  - Inside the road, coherence is allowed only along the road axis.
- **Roads.** Across 10 cross-sections over 50 m:
  - The mean width is 2.4–3.0 m for a track (34–43 px close) or 3–5 m for gravel, never above 0.65 tile. The coefficient of variation of the width is 5–15 %.
  - The road edge 10–90 % is 0.15–0.5 m (2–7 px close).
  - Every 90° turn in the cell path renders as an arc with a centreline radius of 4–12 m.
  - The ruts run unbroken through at least 3 consecutive tiles and through every corner, with a gauge of 1.5–1.8 m.
  - On the wet frame, the luminance profile across the track shows rut minima at least ΔL\* 6 below the centre strip.
- **Organic boundaries.** Along a 40 m field or meadow boundary, the edge 10–90 % width is 0.3–1.0 m. Its lateral deviation from a fitted straight line has a standard deviation of 0.8–2.5 m and contains both scales: at least one lobe over 2 m wide at 15–30 m, and at least 5 bites of 0.3–0.6 m at irregular spacing (coefficient of variation ≥ 0.3).
- **Scale.** At the closest zoom, the boulders of a rocky patch measure 4–21 px and the puddles in the ruts 4–7 px wide. No texture feature repeats at less than 12 m, which means no identical blob twice in a 114 px tile.
- **Hills.** Measured on the nadir frame:
  - A hill outline traced at half its height has a circularity (4πA/P²) of 0.6–0.95, with no straight segment longer than 1 tile.
  - Rock cover is 10–25 % of the hill area, and 0 % on hill tops that are not steeper than 25°.

## CC0 decisions

The diagnosis puts the cause in the shader and the shipped generated macros, not in the CC0 picks of 2026-10-22, so those decisions stand. Two conditions apply:

1. **Macro size per layer.** The macro repeat must become per-layer metres, otherwise the 20–25 m scans ship squeezed into 12 m.
2. **The dirt road is no longer a world-space macro.** Brief B4 and `aerial_ground_rock` (20 m, isotropic soil) are used in road-local UV, as already decided.

No new asset needs generation for this task. The hill and rocky patches can use `coast_land_rocks_01` and `aerial_rocks_02` (CC0, already downloaded in `refs/round2/ph/`) as the rock layer under a slope and cluster mask.

## Rules learned

- Natural boundaries are sharp locally (0.15–1 m) and irregular in plan, at two scales. A per-cell lookup blurred with a fixed ramp produces the opposite: wide, uniform blends along regular lines.
- A world-space macro with directional content (ruts, furrows, streaks) breaks under hex tiling, even with an axis-locked rotation, because the random offsets still shift it laterally every hex cell.
- Tri-planar projection: the XY plane belongs to Z-facing faces. Swapped weights stretch along the contour, and normalising by the weight sum hides how small the weights are.
- On Commons, the useful drone sets are by Budgawl (Belarus) and Dietmar Rabich (Dülmen and Nottuln, with dated November and January drone frames). Full-text searches for "aerial dirt road" or "forest edge drone" return almost nothing, so search by photographer or month instead.
