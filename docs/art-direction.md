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

**Vehicles follow real contemporary designs under altered names**: a player recognises the
family, but no model carries its real designation. **No real army, flag or insignia** anywhere in
code, data, UI or assets. Each player's set comes from one country's family — never a mix — and
wheels and tracks turn when a vehicle moves.
Era-neutrality in the *rules* also stands — nothing in `core/` encodes a period, and the unit
class names in [§3.6](rules/units.md) remain role labels. The setting is an art-direction decision, not a rules one.

## Maps: season, sky and two characters

Each map has its own season and sky, and the sky decides the light:

| map | season and sky | light and shadows |
| --- | --- | --- |
| River | late autumn, overcast, rain | soft diffuse light, faint blurred shadows, high cool ambient, bare broadleaf |
| Crossroads | late summer, sunny, dry | strong warm low sun, soft light shadows, sky-blue ambient, full leaf |
| Ridge | early autumn, clear | bright sun higher up, soft light shadows, yellow-orange birch and oak |

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

- **Bake** static terrain lighting. One directional light casts every dynamic shadow
  (`game/battle/look/*.tres`):
  - **Sunny maps** (Crossroads, Ridge): shadow opacity 0.3 and a 2° sun disc, so shadows are soft
    and light — the ground in shadow stays readable, because a unit standing in it must still be
    read. Units, buildings and small props cast through the light; trees cast through cheap
    shadow-only proxies, never through the canopy cards. Units also get a contact shadow (0.6)
    under the hull, or they float.
  - **River** (overcast): shadow opacity 0.35 with a wide blur — a faint smudge, as under cloud.
- Time of day is a **per-map baked preset**, not a dynamic cycle.
- Weather = particles + a screen overlay + a wind parameter on foliage shaders + an audio bed.
- Skip volumetric fog. A depth-based fog gradient reads nearly as well and costs almost nothing.
- Wetness is a material parameter (roughness + normal blend) driven by the weather controller.
  Puddles collect only where water would stand: on dirt tracks, in hollows and on flat ground,
  never on a hill slope and never on a riverbank, where they read as a mistake, not as rain.
  Smoke drifts with the same wind that slants the rain, so a column never leans against it.
  Wave size on open water follows the map's weather: River's rain and wind give the full ripple,
  the calm sunny maps a fraction of it.
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
- **Props add no rule.** A structure stands only on `BUILDING` cells and fills whole tiles, so no
  unit ever stands inside a neighbour's wall. Ruins stand on `RUBBLE` and are mostly
  half-destroyed: a standing wall or two reads as a ruin from above, a flat heap reads as noise.
  Small props (fences, bales, poles, trailers, blocks) sit near cell edges on passable cells; a
  vehicle that enters the cell crushes them and the debris stays as a scar, infantry passes them by.
- **Props never hide a rule.** A roof fades over a unit the current player is shown, so the unit
  and its marks stay readable. Fences and other low props draw under the movement-zone contours,
  which must always read on top (§3.13).
- **Wet maps wet the props too:** on River walls darken and roofs take on a wet sheen, or the
  buildings look dry in the rain.
- **Forests are dense woods** a tank could hide in — canopy masses, a shrub belt at the edge, not
  a few trees with units visible between them. Trees are 9–14 m tall. The wood is a calm, dark mass:
  bright or busy foliage competes with the units and the zone contours. A lane through the wood
  stays visible. The canopy dithers over cells holding a unit the current player can see,
  including the cells between the unit and the camera.
- **Scars respect the fog:** crushed props, wrecks and craters show only where the viewer's
  `seen` covers the tile, or they report enemy movement. A prop is crushed only on a cell the
  viewer has seen.
- Briefs, sizes and routes per prop (Blender, Tripo or CC0): [`art/props-research.md`](art/props-research.md).

## Effects — fire, explosions, smoke

**What a hit shows.** A vehicle that survives a hit shows only the hit itself — sparks and
ricochets for small arms, a flash with a dust and debris burst for shells and drones — and no
lasting damage. A destroyed vehicle burns, then smokes, and leaves a burnt-out wreck that blocks
vehicles for a few turns ([§3.14](../CLAUDE.md)). A squad loses figures as its HP drops — one of
four per quarter lost — and the fallen lie beside it; a destroyed squad leaves them and a scorch,
restrained, and no obstacle. Effects attach only to units the current player can see, the attacker's muzzle flash included.
Sizes, durations, colours and sources: [`art/damage-fx-research.md`](art/damage-fx-research.md).


Each effect is the cheapest technique that reads at both zooms, in `game/battle/`:

| effect | technique | why |
| --- | --- | --- |
| explosion, ground dirt, impact and muzzle flash | one camera-facing quad per layer playing a **baked flipbook atlas** (`assets/vfx/`, offline renders of CC0 sims), soft depth fade where it meets the ground or a hull | rolling smoke and fire need a real fluid sim; one quad with a 64-frame atlas costs one draw |
| where the blob is born | each atlas's **blast point** (`SOURCES.md`) is pinned to the hit point — the ground for bursts, the hull for a kill, the gun tip for a muzzle flash | without it the fireball floats above the hull or sinks under the ground |
| the flash | an `OmniLight3D` for a few frames; the flash sprite starts dimmer and cools to deep orange at its edge | the light is what hits the eye; a pure-white blob reads as a UI glitch |
| ground-burst debris (shell, tank gun on a soft target) | one `GPUParticles3D` of 10–20 dark clods and one of 2–4 streaks, ballistic under real gravity, ≤ 1.2 s, shared materials | a brown cloud alone reads as smoke, not as earth thrown up |
| fire on a wreck | **procedural** shader flame on two billboards rooted at the turret ring, leaning together into one fire; one warm noise-flickering light per fire (at most 4 on the board); a few sparks | baked fire atlases read as torn filaments or cut-outs at this size; the shader keeps a solid hot base, red tips and loose tongues, with no periodic motion |
| smoke column | one `MultiMesh` of flipbook puffs for every column on the board, born at the flame tip | a column stands for several turns; a particle system per wreck would simulate forever |
| the scar | a stamp into the ground's **scar map** (scorch under wrecks, craters from shells and tank guns on soft targets) | statics, not particles — see below |

The fire burns, shrinks, then leaves only smoke over the wreck's life, and its height never drops
below 0.8 of its peak — a flat crown reads as a rug on the hull. Fire and smoke step on one timer
at 30 per second, not on `TIME`, and the timer stops when nothing burns, so the idle frame cap can
engage.

What our own constraints add on top:

- **Overdraw is the killer, not particle count.** Twenty large half-transparent quads covering half
  the screen cost more than five hundred small ones.
- A hit is `one_shot`, lives ~1.5 s, then `queue_free`. Setting `emitting = false` is not enough;
  the particles stay in frame.
- Craters, scorching and crushed-prop debris are stamped into a **scar map**, one texture over the board that the ground shader reads, masked by the viewer's `seen`. Not `Decal` nodes: the Mobile renderer applies at most 8 decals per mesh and the Compatibility renderer none, and the ground is one mesh. Not quads over the ground: they z-fight on slopes and cost a draw call each.

Off the table on mobile Vulkan: volumetric smoke, raymarching, GPU particle collision against the
SDF, and more than one effect sampling `screen_texture` at a time.

3D asset generation, poly budgets and the GLB pipeline are covered by the **`asset-manager`
skill** — read it before generating anything, and do not duplicate its guidance here.
