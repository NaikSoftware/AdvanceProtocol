# Art direction

The detail behind the setting note in §2 and all of §8 of CLAUDE.md — what the game looks like, and what it may cost to draw.

[back to CLAUDE.md](../CLAUDE.md)

## Setting — fixed

**Near-future conventional war, roughly the 2030s, between fictional states.** Decided ahead of
asset generation, which is the deadline that mattered: the setting drives every model prompt,
every material, and the whole lighting and audio brief.

It follows the rules rather than leading them. The drone strike ([§3.9](rules/units.md)) is already load-bearing —
it is one corner of the matchup triangle — and a contemporary setting simply *has* drones. The
alternative was a mid-century setting with a weapon that does not belong to it, which is a rule
bent to fit a mood; here the mood fits the rules.

What this fixes, concretely:

- **Materials:** modern composite and appliqué armour, slat cages, rubber-padded tracks, thermal
  optics, antenna clusters. Not riveted plate.
- **Palette:** contemporary digital-pattern camouflage, low-saturation greys, greens and tans.
  Dust, rain and mud are the only things that dirty a vehicle.
- **Light and audio:** per-map daylight (see below), turbine and diesel notes, radio chatter as
  texture rather than language.
- **Countryside:** contemporary Eastern-European — brick and plaster houses under metal or
  fibre-cement roofs, panel blocks, farm hangars, silos, concrete fences and poles, modern bridges.
  **Nothing medieval or old-world:** no stone-arch bridges, no slate-and-fieldstone cottages.
- **Infantry:** plate carriers, ballistic helmets, optics on rifles.

What stays forbidden, exactly as before: **no real army, nation, flag, insignia or identifiable
vehicle**, anywhere in code, data, UI or assets. The sides are fictional and stay fictional.
Era-neutrality in the *rules* also stands — nothing in `core/` encodes a period, and the unit
names in [§3.6](rules/units.md) remain role labels. The setting is an art-direction decision, not a rules one.

## Maps: season, sky and two characters

Each map has its own season and sky, and the sky decides the light:

| map | season and sky | light and shadows |
| --- | --- | --- |
| River | late autumn, overcast, rain | soft diffuse light, weak soft shadows, high cool ambient, bare broadleaf |
| Crossroads | late summer, sunny, dry | strong warm low sun, crisp shadows, sky-blue ambient, full leaf |
| Ridge | early autumn, clear | bright sun higher up, crisp shadows, yellow-orange birch and oak |

The season never contradicts the map's ground state (§3.12): snow needs `FROZEN`, rain needs a
wet ground state. Deciduous trees and grass come in three seasonal variants; pine serves every map.

**The two halves of a map differ in character and are fair only by numbers.** Rules-relevant
layout is balanced by the pace and terrain-count tests in `tests/game/test_maps.gd`; the scenery
(field and forest sub-types, props, bridge designs, the ring beyond the board) differs per half.
A 180° copy reads like a chessboard.

**Land use follows how the country is really farmed**, never noise. Ploughed land is a man-made
rectangle reached by a road or track; it keeps at least one cell of meadow from water, marsh and
houses and never lies on a hill. Floodplains and riverbanks are meadow and reed, hamlets sit on
roads with gardens and orchards around them, woods take hills, poor ground and field edges. Format and examples: [`tools/maps/README.md`](../tools/maps/README.md).

## Rendering and mobile budget

The camera is a fixed perspective rig, roughly 45° yaw, with pitch easing from 55° zoomed out to
38° zoomed in (`IsoCameraRig.pitch_for`). Pan and clamped zoom
only; no free rotation (90° snaps are acceptable if playtests ask for them). Because the angle is
fixed, **undersides are never seen and backs rarely are** — judge every asset from that angle.

Budget on a mid-range phone at 60 fps: under ~100 draw calls and ~150k triangles on screen.

Techniques that buy atmosphere cheaply here:

- **Bake** static terrain lighting. One directional light with shadows for units only. On sunny
  maps props carry baked or contact shadows cast along that map's sun, or they float.
- Time of day is a **per-map baked preset**, not a dynamic cycle.
- Weather = particles + a screen overlay + a wind parameter on foliage shaders + an audio bed.
- Skip volumetric fog. A depth-based fog gradient reads nearly as well and costs almost nothing.
- Wetness is a material parameter (roughness + normal blend) driven by the weather controller.
- Post-processing: a colour-grade LUT, light vignette, minimal grain. **No SSAO, no SSR.**
- **Persistent battle scars.** Wrecks block for a few turns, then their burnt scorch stays. Smoke columns linger for several turns. Craters and
  mud ruts accumulate. This is the cheapest atmosphere in the game and it doubles as information:
  the map should tell you where the fighting has been.

Turn-based means the screen is usually static — enable low-processor mode and drop the frame rate
hard when nothing is animating. Battery life is a feature for a game passed between people.

## Props

- **Realistic, never cartoon or toy-like:** real proportions and materials, weathering. Flat
  faces, blob trees and boxes with painted windows fail.
- **Detail matches the screen**, 7 cm/px at the closest zoom and 22 cm/px at the farthest: a
  feature under ~15 cm is texture or nothing; a feature of ~0.5 m or more that changes the
  silhouette from above is geometry. Textures sit at 1.5–3 cm per texel. Check every asset at both
  zooms: no blur close, no shimmer far.
- **Props add no rule.** A structure stands only on `BUILDING` cells and fits a whole number of
  tiles, so no unit ever stands inside a neighbour's wall. Small props (fences, bales, poles,
  trailers, blocks) sit near cell edges on passable cells; a vehicle that enters the cell crushes
  them and the debris stays as a scar, infantry passes them by.
- **Forests are dense woods** a tank could hide in — canopy masses, a shrub belt at the edge, not
  a few trees with units visible between them. The canopy dithers over cells holding a unit the
  current player can see, including the cells between the unit and the camera.
- **Scars respect the fog:** crushed props, wrecks and craters show only where the viewer's
  `seen` covers the tile, or they report enemy movement.
- Briefs, sizes and routes per prop (Blender, Tripo or CC0): [`art/props-research.md`](art/props-research.md).

## Effects — fire, explosions, smoke

**What a hit shows.** A vehicle that survives a hit shows only the hit itself — sparks and
ricochets for small arms, a flash with a dust and debris burst for shells and drones — and no
lasting damage. A destroyed vehicle burns, then smokes, and leaves a burnt-out wreck that blocks
vehicles for a few turns ([§3.14](../CLAUDE.md)). A squad loses figures as its HP drops — one of
four per quarter lost — and the fallen lie beside it; a destroyed squad leaves them and a scorch,
restrained, and no obstacle. Effects attach only to units the current player can see, the attacker's muzzle flash included.
Sizes, durations, colours and sources: [`art/damage-fx-research.md`](art/damage-fx-research.md).


Never one technique. A single explosion is four or five layers, each one the cheapest thing that
does its job:

| layer | technique | what it buys |
| --- | --- | --- |
| the mass of smoke and flame | `GPUParticles3D`, billboarded quads | motion, spread, lifetime |
| the look of one particle | **flipbook** sprite atlas (8×8) in the particle shader | rolling, turning smoke — without it these are blobs |
| depth | soft particles (depth fade), dissolve by a noise mask | the quad stops cutting the ground on a hard line, and dies by burning away rather than by alpha |
| the flash | an `OmniLight3D` for 3–5 frames plus emissive on the particle | the only part that actually hits the eye |
| heat haze | screen-texture refraction on one quad | cheap, and it is what reads as expensive |
| the scar | a stamp into the ground's scar map (crater, scorching) plus debris meshes | statics, not particles — see §8 |

The thing that is not obvious: **good fire is not simulated at runtime, it is simulated offline and
baked into a flipbook.** EmberGen or Blender's Mantaflow run the real fluid sim, render 64 frames
into an atlas, and the game plays one quad with a shader. This is what AAA does too. Procedural
noise in a shader looks like a gas hob, not like an ammunition rack going up.

What our own constraints add on top:

- **Overdraw is the killer, not particle count.** Twenty large half-transparent quads covering half
  the screen cost more than five hundred small ones. So: fewer particles, larger atlas, better
  flipbook.
- **A smoke column standing for three turns must not be a particle system.** It is a mesh (cone or
  ribbon) with a shader — scrolling noise on the UV plus a vertex wobble. Otherwise five wrecks are
  five systems simulating forever, and the frame rate never drops between turns — and dropping it
  is the battery budget above.
- The explosion itself is `one_shot`, lives ~1.5 s, then `queue_free`. Setting `emitting = false`
  is not enough; the particles stay in frame.
- Craters, scorching and crushed-prop debris are stamped into a **scar map**, one texture over the board that the ground shader reads. Not `Decal` nodes: the Mobile renderer applies at most 8 decals per mesh and the Compatibility renderer none, and the ground is one mesh. Not quads over the ground: they z-fight on slopes and cost a draw call each.

Off the table on mobile Vulkan: volumetric smoke, raymarching, GPU particle collision against the
SDF, and more than one effect sampling `screen_texture` at a time.

Build order when this comes up: the **smoke column first** — it is persistent, and persistence is
what makes it atmosphere ([§8](../CLAUDE.md), battle scars) — and the explosion after it.

3D asset generation, poly budgets and the GLB pipeline are covered by the **`asset-manager`
skill** — read it before generating anything, and do not duplicate its guidance here.
