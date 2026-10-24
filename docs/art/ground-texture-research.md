# Ground texture research (Phase 5a, 2026-10-22)

The downloaded files live in `art-refs/` at the repository root. It is local-only (about 1 GB, git-ignored, with a `.gdignore` so Godot skips it). If it is missing, this file is enough to fetch everything again. Use the `art-researcher` agent for that.

Layout of `art-refs/`:

- `refs/cc0/<surface>/<id>/`: CC0 candidates from pass 1, with `cc0_sources.txt` and `cc0_sheet.jpg`.
- `refs/round2/`:
  - `ph/<id>/`: the Poly Haven large and aerial scans.
  - `macro_sheet.jpg`: candidates over an 8 m tile at 10 cm/px.
  - `ship_preview.jpg`: the ship picks after colour matching.
- `refs/photos/`: reference-only photos, with `sources.txt`.
- `tripo_tex/`, `macro_raw*/`, `macro_regen/`, `macro_pick/`: generated textures and the raw sources behind `assets/terrain/macro/`.
- `relief/`, `review1/`, `rings/`: checkpoint frames, the owner review page and the map sketches.

## Decisions per surface

| surface | pick | source, size | notes |
| --- | --- | --- | --- |
| hill | ship | Poly Haven `coast_land_rocks_01`, 20 m | match to L\* 33, C ≤ 7 |
| mud | ship | Poly Haven `dirt_aerial_03`, 25 m | no ruts; the shader draws puddles; match to L\* 30, C 5 |
| river bank | ship | Poly Haven `coast_sand_05`, 25 m | match to L\* 28, C 4 |
| asphalt | ship + shader | Poly Haven `aerial_asphalt_01`, 30 m | remove the violet cast, L\* 28; wear is procedural (see below) |
| cobble | ship | Poly Haven `cobblestone_large_01`, 4 m | needs hex tiling |
| dirt road | compose | `aerial_ground_rock` (soil), `coast_land_rocks_01` (grass strip) | sampled in road-local UV, brief B4 |
| meadow, marsh, ploughed | generate | briefs B1–B3 | no CC0 aerial source exists |
| forest, rubble | keep the current macro | n/a | no defects found |

Stubble was removed by the owner and must not come back.

Rejected, so don't retry them:

- `aerial_mud_1` and `aerial_wood_snips` carry tyre tracks across the whole frame.
- `farm_furrows` tiles as a hard grid.
- The ambientCG `Road00x` set has lane markings.

ambientCG has no ground texture larger than 7.5 m.

## Rules learned

- Macro textures must cover real ground at their stated size. Close-up 2–3 m photos tile into a visible lattice at 7–22 cm/px.
- Any periodic feature under about 0.45 m, such as furrows or drill rows, aliases into stripes at 22 cm/px. Keep its contrast at ΔL\* ≤ 4 and let 2–6 m patches carry the read.
- Directional road features belong in road-local UV or the shader, never in a world-space macro.
- The camera distance is `zoom_level / 0.768`: 7.8 at the closest zoom, 15.6 at the default and 26 at the farthest. Any effect faded out between 14 and 24 is invisible at the default zoom.

## Asphalt wheel-path wear (procedural)

- **Geometry.** Two paths per lane, centred ±0.85 m from the lane centre and 0.7 m wide. Each path is solid for its middle 0.3 m and falls to zero at ±0.45 m. Anti-alias with `fwidth`. **No distance fade.**
- **Wet.** Paths are albedo ×0.80 with roughness 0.10. The centre and edge strips are albedo ×1.12 with roughness +0.10. On screen, the paths must be at least ΔL\* 8 darker than the centre.
- **Dry.** Paths are albedo ×1.08. Add a 0.4 m oil band at ×0.85 on each lane centre.
- **Variation.** Intensity runs 0.6–1.0 along the road, from noise with a 20–40 m wavelength. The paths wander ±0.1 m over 15–30 m and fade out at corners and junctions.
- **Accept if** a luminance profile across a straight road shows minima at least ΔL\* 6 deep at every zoom.

## Briefs

Every brief asks for a 12 × 12 m area (except B4) in a straight top-down nadir view under overcast light. Each output is a raw 2048² PNG, seamless, with no generator post-processing. Check every output for a hidden 2×2 repeat: the quadrant mean difference must be above 3.

**B1, meadow.** Dead late-autumn meadow:

- Patches of matted straw-tan grass, 0.5–3 m (L\* 38–42).
- Darker wet olive-brown hollows, 1–4 m (L\* 24–30).
- Under 15 % grey-green live grass.
- Tussocks of 0.2–0.4 m scattered at random, and 0–2 bare spots.

Mean L\* 31–34, C 6–10. No rows, mowing stripes, tracks, starbursts or lines longer than 2 m. Accept if the L\* standard deviation after a 1 m blur is 2.5–5.

**B2, marsh.**

- Sedge and rush tussocks of 0.3–0.6 m, covering 40–60 %, clustered rather than gridded.
- Dark wet peat and silt between them (L\* 15–22).
- 2–4 open-water patches of 0.5–2 m.

Mean L\* 22–28, C 3–7. At least 25 % of pixels below L\* 20. No tussocks in rows.

**B3, ploughed.**

- Furrows about 0.35 m apart, wavering ±0.1 m, with very low contrast (ΔL\* ≤ 4).
- Clods of 0.05–0.3 m.
- The read comes from 2–6 m patches of wetter soil (ΔL\* 5–8).

Mean L\* 26–32, C 8–14. No high-contrast stripes and no tramlines.

**B4, dirt road strip.** It covers 8 m along the road by 5 m across, with the road along the long axis. The deliverable is 1024 × 640 px, seamless along the road only. Working out from the centre:

| zone | distance from centre | content | L\* |
| --- | --- | --- | --- |
| centre strip | \|v\| < 0.35 m | raised, sparse dead grass | 30–36 |
| ruts | ±0.85 m (gauge 1.7 m), 0.5 m wide | wet; 30–50 % of their length holds sky puddles of 0.3–0.5 × 1–4 m | 20–26 (puddles 45–60) |
| shoulders | to 1.6 m | gravel of 2–5 cm | 32–38 |
| verges | to 2.5 m | dead grass | n/a |

No tread pattern, no perspective, no converging ruts.

## Reference photos (reference only, never shipped)

These are Wikimedia Commons photos, licensed CC BY or CC BY-SA. The full list with authors is in `art-refs/refs/photos/sources.txt`.

| id | content |
| --- | --- |
| a1 | Dülmen field track, oblique drone shot |
| a2 | Burgos dirt-road junction, aerial |
| a3 | Lincolnshire farm track: ruts and a grass centre |
| b1 | Nottuln asphalt seen top-down |
| b2 | Dülmen wet asphalt by a ploughed field |
| c1 | Dorsten stubble, top-down |
| c2 | Dülmen tilled field, top-down |
| c3, c4 | ploughed fields |
| d1 | Nuthurst mud ruts |
| m1, m2 | Nottuln tramlines |

Measured on m2: tyre track 0.6 m wide, gauge about 1.5 m.
