# River and bank research (Phase 5a, 2026-10-24)

The owner says the river looks "like Minecraft, built from rectangles" and the banks look like plastic. This document gives the real-world shape and colour of a lowland river 8–25 m wide, measured from photos, and a brief that a screenshot can be checked against. Nothing here is shipped. All references are reference-only.

The files are in `art-refs/refs/river/`: one folder per id, `sources.txt` (URL, licence, author, date) and `sheet.jpg` (11 photos plus the mood target).

## References

| id | river, view | licence, author | used for |
| --- | --- | --- | --- |
| is1 | Isloch (BY), nadir drone, June | CC BY-SA 4.0, Budgawl | plan form: meander, width and bar ratios |
| is2 | Isloch (BY), oblique ~40°, overcast, Feb | CC BY-SA 4.0, Budgawl | overcast water colour, cut banks at the game's angle |
| is4 | Isloch/Berezina (BY), oblique ~45° | CC BY-SA 4.0, Budgawl | overhang, abrupt grass edge |
| is6 | Isloch (BY), nadir, overcast, kayaks for scale | CC BY-SA 4.0, Budgawl | absolute width, edge notches, shallow vs deep colour |
| st4, st5 | Stviha (BY), oblique and nadir | CC BY-SA 4.0, Budgawl | point bar and its underwater shelf, outer bank |
| na1 | Orlanka/Narew (PL), oblique, 31 Oct | CC BY-SA 4.0, K. M. Różański | late-autumn reed and sedge edge, dark water |
| cb2 | Otter (UK), ground level | CC BY-SA 2.0, Derek Harper | vertical cut face with a gravel toe |
| cb6 | Derwent (UK), ground level, Feb overcast | CC BY-SA 2.0, David Lally | straw grass to the waterline, overcast water |
| pb3 | Valgejõgi (EE), ground level | Public domain, Hannu | sand cut bank opposite a low point bar |
| ge1 | Schwinge (DE), ground level | CC BY-SA 3.0, Sven Segler | roots and undercut on a cut bank |

Rejected:

- The Steam screenshots of CoH3, WARNO and Men of War II (64 frames). None shows a river at the game's angle, and most show real-army vehicles.
- Commons Dülmen brooks: 2–4 m wide, too small.
- Trent and Lippe aerials: 40–60 m wide, too large.
- na2: contains religious buildings.

## Camera, before measuring

At 7–22 cm/px, a feature of 0.3 m or more covers at least 1.4 px at the farthest zoom. Individual reed stems, roots and ripples under 0.1 m fall below a pixel and do not matter. What reads on screen:

- the plan shape of the channel and its width changes
- bars
- the tone bands at the edges (wet margin, cut face, shelf)
- tussocks and reed clumps of 0.3–1 m
- overhanging crowns

A vertical face of height h shows on screen as about h·cos(52°) ≈ 0.6 h. A 1 m cut bank is therefore 8 px tall at the closest zoom and 3 px at the farthest, and only on banks that face the camera.

## Measured numbers

W is the local channel width. Ratios come from the nadir frames is1, is6 and st5. Absolute scale comes from is6: a two-seat kayak of about 4.8 m spans 163 px, giving 2.9 cm/px, and the Isloch there is 11.8–13 m wide. is1 is the same river, so W ≈ 12 m.

**Plan form**

| quantity | measured | in game units |
| --- | --- | --- |
| bend radius (centreline) | 1.5–1.8 W (is1, tight); 2.3 W (st5) | ≥ 2 tiles for a 1-tile river; never < 1.5 W |
| meander wavelength | ≈ 9 W (is1, tortuous); textbook 10–14 W | 1-tile river: 8–14 tiles; 3-tile river: 24–42 tiles, so only gentle bends fit a map |
| amplitude (peak to peak) | 2–6 W moderate (st4, is4); up to 12 W tortuous (is1, is2) | 2–6 W |
| straight reach between bends | 1–3 W (is1, is4) | no straight edge longer than 3 W |

**Width variation along the river**

- is1: 0.65–1.55 × the mean width. The channel is widest in the pools at bend apices and narrowest at the crossings between bends.
- is6: ±10 % over 40 m of a straight reach.
- is2: the bends are about 1.5× as wide as the crossings.
- Target: the local width wanders ±15–30 % around the logical width, at a period of 1–3 W, and is wider at the bend apices.

**Cut bank (the outer side of a bend)**

- Height above water is 0.5–1.5 m.
  - cb2: the face is about 1.2 m, 1.5 times the height of the 0.8 m wheat on top.
  - ge1, cb4: about 0.8–1 m.
- Slope:
  - The upper 0.3–0.8 m is 60–90°, often undercut, with roots or a grass lip overhanging 0.2–0.5 m.
  - Below that is a slump or debris toe at 30–45°.
- In plan (is6 nadir), the exposed face shows as a strip 0.6–1.2 m wide, which implies a slope of 50–65° for a 1–1.5 m face.
- High sand terraces (pb3, is1 at the forest edge, 3–8 m) are a separate landform and do not belong on a lowland bank.

**Point bar (the inner side)**

- The exposed bar is 0.2–0.4 W wide in is1 (2–5 m) and up to 0.5–0.8 W in st5 at low water. It runs 1–1.5 W along the bend (10–20 m).
- Below the water it continues as a shelf 0.15–0.25 W wide, which reads as a lighter, warmer band.
- Slope:
  - The bar surface is about 3–10° (1:6 to 1:20).
  - The shelf edge drops into the pool at 15–30°.

**Shoreline irregularity**

| scale | what it is | size | spacing or wavelength | sources |
| --- | --- | --- | --- | --- |
| large | edge deviation from the smooth bend | ±0.05–0.1 W | 1–3 W | is1, is2 |
| small | notches, slump scallops and tussock bites | depth 0.3–1 m, width 0.5–2 m | every 1–4 m | is6, na1 |

A short straight edge is normal. A stair-step edge never occurs.

**What lines the bank**

| bank | lining | sources |
| --- | --- | --- |
| cut banks | dark damp soil or sand face, roots, a grass lip, fallen branches and trunks lying across the water | ge1, cb2, is6 |
| point bars | wet sand or silt, then a sparse strip of sedge or straw | st5, pb3 |
| low reaches (most of the length in late autumn) | dead reed and sedge, or straw grass, right to the water, with no soil visible | na1, cb6 |

Gravel appears only as a toe under a cut face (cb2), 1–2 m wide, with cobbles of 5–15 cm.

**Vegetation overhang**

- Willow and alder crowns overhang the channel by 2–6 m and in places cover up to half of a 12 m channel (is1, is4).
- Reed and sedge fringes lean 0.3–1 m over the water (na1).
- In late autumn the branches are leafless. Expect 1–3 fallen trunks per 100 m (is2, is6, cb6).

**Water colour (L\*a\*b\*, 10th/median/90th percentile in each sampled patch)**

| sample | L\* | a\* | b\* |
| --- | --- | --- | --- |
| is6 deep, overcast nadir | 17 / 23 / 37 | 2 | 4 |
| is6 mid-channel | 23 / 26 / 29 | 3 | 5 |
| is6 sand shallow under water | 28 / 31 / 34 | 4.5 | 10 |
| is2 overcast oblique, mid-channel | 11 / 14 / 21 | 5 | 11 |
| is2 under the inner bank, shaded | 7 / 11 / 16 | 2 | 3 |
| is2 shallow margin on the outer side | 17 / 21 / 26 | 7 | 14 |
| na1 deep, late Oct | 15 / 18 / 21 | 0 | −3 |
| st5 deep (summer, blue sky) | 27 / 30 / 33 | 5 | −16 |
| cb6 sky reflection at ground level | 51 / 71 / 83 | −1 | −4 |
| mood target, river in the foreground | 9 / 19 / 31 | −3.5 | −3 |
| **current build, water** | 25 / 39–40 / 46 | ~0 | ~0 |

How to read the table:

- At the game's angle, overcast lowland water is dark: median L\* 14–26.
- It is tea-brown from bog humics (a\* 2–7, b\* 3–14).
- Over sand shallows it is 5–10 L\* lighter and warmer.
- The sky reflection reaches L\* 50+ only at grazing angles (ground level, or the far edge of an oblique frame).
- At the game's oblique angle, Fresnel lifts this to about L\* 32–35. The owner-approved water (commit f875785) is the baseline: do not darken it toward the photo values.
- The mood target is cooler (a\* −3, b\* −3). Brief the deep water between the two.

**Waterline against grass**

| bank | waterline | sources |
| --- | --- | --- |
| cut banks | abrupt: a step of 0.5–1.5 m, then the dark face, then water | is2, ge1 |
| point bars | gradual: grass, then 1–5 m of wet bare sand or silt, then 1–3 m of translucent shallow, then the pool | st5, pb3 |
| sedge and reed reaches | abrupt in plan, but frayed: tussocks and lodged straw stick 0.3–1 m into the water, with a dark wet strip 0.2–0.5 m wide right at the line | na1, cb6, river_close |

## Material notes for overcast light

| surface | albedo, colour | roughness | specular |
| --- | --- | --- | --- |
| open water | L\* 14–26 tea-brown to grey | 0.03–0.08 | yes: F0 0.02 with Fresnel, soft sky reflection, no sun glint |
| shallow over sand or silt | deep water +5–10 L\*, b\* +5 | 0.05–0.1 | yes, same as water |
| wet silt or mud at the waterline (0.2–1 m band) and the low bar | dry ×0.6–0.7 (ΔL\* −8 to −15) | 0.30–0.45 | weak and broad only; never a bright rim |
| damp cut face (soil) | L\* 22–32, a\* 4–8, b\* 10–18 | 0.65–0.8 | none visible |
| dry sand on the upper bar | L\* 45–60 after the overcast grade (75 in st5's summer sun) | 0.85–0.95 | none |
| straw, sedge and grass to the edge | L\* 30–42, b\* 15–25 | 0.9–1.0 | none |

Specular is plausible on the water and, weakly, on the wet margin band. Anything else that shows a highlight reads as plastic. The current bank glare in `art-refs/relief/banks/b4`/`top` is exactly that.

## Brief: river channel, bank height-bake and shader

```
ASSET: river channel, bank height-bake and bank/water shader
USE: macro ground and shader
COVERS: any river 1–3 tiles (8–24 m) wide
SOURCE REFS: is1/st5 (plan ratios), is6 (scale, notches, shallow colour), is2/na1 (overcast water,
  late-autumn edges), cb2/ge1 (cut face), st5/pb3 (point bar + shelf), river_close (wet strip)
VIEW: game angle 50–55° pitch, judged at the closest, default and farthest zoom
CONTENT:
  - centreline: a smooth spline through the logical tiles; bend radius ≥ 1.5 W, typically 2–3 W
  - width wanders ±15–30 % with a 1–3 W period, widest at bend apices
  - edge noise in two scales: ±0.05–0.1 W at a 1–3 W wavelength, plus notches 0.3–1 m deep
    every 1–4 m
  - outer bank: 0.5–1.5 m step, 60–90° upper face over a 30–45° toe, dark damp soil
  - inner bank: bar 0.2–0.5 W wide at 3–10°, then a shelf 0.15–0.25 W wide under the water
  - straight reaches: low banks of 0.2–0.5 m, sedge and straw right to the water
  - every waterline: a dark wet band 0.2–0.5 m wide
COLOUR: deep water = the owner-approved f875785 look (about L* 32–35 on screen), a* 0–5, b* −3 to +10; shelf +5–10 L*; wet band ΔL* −8 to −15 against
  the dry ground next to it; match is6/is2 for value and the mood target for hue
MUST NOT: axis-aligned straight edges or 90° corners from the tile grid; a uniform-width band; a
  constant-height rim around the whole river; one bank profile all the way along; bright specular
  rims on banks; water paler than the f875785 look; regularly spaced notches
TILING: n/a (procedural along the spline); bank noise must not repeat within 50 m
DELIVERABLE: shader and height-bake change; no generated images
```

**Accept if** each of the following is measurable on the screenshot set (closest, default and farthest zoom, plus one nadir debug frame):

- **No staircase.** On the nadir frame, no bank edge segment is straight and axis-aligned for more than 1 tile (8 m). The tightest bend has a centreline radius of at least 1.5 W.
- **Width varies.** Measured at 10 equally spaced cross-sections over 10 tiles, the max/min width ratio is 1.3–2.0, and the widest section lies within 1 W of a bend apex.
- **Banks are asymmetric.** At every bend sharper than about 45°:
  - The outer bank shows a dark face band of 3–9 px (0.5–1.5 m × 0.6 / px size).
  - The inner bank shows a lighter bar or shelf band at least 0.2 W wide.
  - A straight reach shows neither.
- **Edge is irregular.** A luminance profile along a 20 m bank line shows at least 5 notches or bites of 0.3–1 m depth, at irregular spacing (the coefficient of variation of the spacing is ≥ 0.3).
- **Water value.** The owner-approved water from commit f875785 sets the colour and value. Do not darken it toward the photo median of 15–25: at the game's oblique angle, Fresnel lifts it to about L\* 32–35, which matches the mood target (L\* 18–40, b\* −3 to −6). The shelf is 5–10 L\* above the adjacent pool. Water a\* lies between −4 and +6.
- **Wet margin.** Sampled across the waterline, a band 0.2–0.5 m wide (2–7 px at the closest zoom) is ΔL\* 8–15 darker than the dry bank 1 m inland.
- **No plastic.** Bank luminance does not change with view angle: compare the nadir frame with the default-zoom frame. No highlight rim follows the waterline. The bank roughness used is ≥ 0.3 everywhere above the waterline. A per-pixel L\* cap does not work as this test, because plain field texture reaches L\* 85.

## Rules learned

- Measure river shape as ratios to the local width, from nadir frames. Oblique frames give colour and edge character but foreshorten every distance.
- Kayaks, footbridges and cars in a nadir frame are the cheapest scale bar. A tandem kayak is about 4.8 m.
- Steam store screenshots of realistic RTS games show no small river at the game's angle. Do not spend time there again.
- Commons user Budgawl publishes the best Eastern-European lowland river drone set (Isloch, Stviha, Pripyat), CC BY-SA 4.0.
