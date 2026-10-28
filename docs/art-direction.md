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
  fibre-cement roofs, farm hangars, silos, concrete fences and poles, modern bridges.
  **Nothing medieval or old-world:** no stone-arch bridges, no slate-and-fieldstone cottages.
  Panel blocks are urban and stay off the village maps.
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
| Crossroads | late summer, sunny, dry | strong warm low sun, strong soft-edged shadows, sky-blue ambient, full leaf |
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

**Fields are nearly level** — meadow and ploughed land rise and fall by a few decimetres within a
cell, on the board and in the ring alike. Relief belongs to hills, banks and woods; a rolling
field reads as dark swells that look like shadows with no source.

## Rendering and mobile budget

The camera is a fixed perspective rig, roughly 45° yaw, with pitch easing from 55° zoomed out to
38° zoomed in (`IsoCameraRig.pitch_for`). Pan and clamped zoom
only; no free rotation (90° snaps are acceptable if playtests ask for them). Because the angle is
fixed, **undersides are never seen and backs rarely are** — judge every asset from that angle.

Budget on a mid-range phone at 60 fps: under ~100 draw calls and ~150k triangles on screen.

Techniques that buy atmosphere cheaply here:

- **Bake** static terrain lighting. One directional light casts every real shadow, set per map in
  `game/battle/look/*.tres`:
  - **Sunny maps** (Crossroads, Ridge): a 2° sun disc, so a shadow's edge softens with distance
    from its caster. Crossroads keeps full shadow opacity; Ridge's shadows are light (opacity 0.3),
    so the ground in shadow stays readable. Units and the board's buildings cast through the light;
    ruins, boulders and blocks lay a contact patch stretched along the sun, and fences, poles and
    other small props cast nothing. Units also get a contact shadow (0.6) under the hull, or they
    float.
  - **River** (overcast): shadow opacity 0.35 with a wide blur — a faint smudge, as under cloud.
    Only units cast through the light.
  - Trees never cast through the light: the forest's shadow is baked onto the ground in the map's
    sun direction, and lone trees and bushes lay a shade patch under them, stretched along the sun on
    sunny maps.
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
- **Persistent battle scars.** Wrecks block for a few turns, then their burnt scorch stays. Smoke columns linger for several turns. Mud ruts
  accumulate. There are no craters: units are the only targets, and the one battle mark on the
  ground is the scorch under a destroyed vehicle. This is the cheapest atmosphere in the game and it doubles as information:
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
  tiles, so no unit ever stands inside a neighbour's wall. Ruins stand on `RUBBLE` and are mostly
  half-destroyed: a standing wall or two reads as a ruin from above, a flat heap reads as noise.
  Small props (fences, bales, poles, trailers, blocks) sit near cell edges on passable cells; a
  vehicle that enters the cell crushes them and the debris stays as a scar, infantry passes them by.
- **Props never hide a rule.** Fences and other low props draw under the movement-zone contours,
  which always read on top (§3.13).
- **Wet maps wet the props too:** on River walls darken and roofs take on a wet sheen, or the
  buildings look dry in the rain.
- **Placed as a real village would be.** The layout of each map is authored, not scattered cell
  by cell: power lines run along roads across the board and on through the ring to its outer
  edge, so no line visibly starts or ends; a pole stands on every bend and one transformer feeds each
  settlement. Every settlement keeps a 0.4 kV line on the verge of its main street, running from
  the transformer to the last pole in front of a house. A house gets a drop under its eaves only
  where a street pole reaches it with a short straight span (≤ 16 m) that keeps off gardens and a
  neighbour's yard; a drop may cross the street only square to it (within 25°) and no longer than
  14 m, and never points straight along the view (it reads as a vertical stroke) — then it takes another
  wall facing the pole. Poles stand at least 1.6 m outside a yard's fence line, never in a gate opening or next to a
  hay bale; a 0.4 kV span keeps off yards, gardens and forest (a wire coming out from under the canopy
  reads as from nowhere) and must not read from the camera as hanging over a building (checked at the zoom-11 pitch, the lowest that keeps every settlement powered; chimneys at the lowest pitch)
  (wall, eaves, roof, chimney) — a drop only over its own wall, never its roof, and it ends clear of
  the chimney; gardens, yards and asphalt are judged on the ground, as seen from above; it hangs at least 6 m above the
  ground and over asphalt runs only square across the road, to a pole set opposite, never along the
  inside of a bend. A
  street pole carries at most three spans; a transformer pole its two 10 kV spans plus at most two
  0.4 kV. The three bare 10 kV wires are fainter each, so the trunk reads no darker than a village
  cable. No pole is added just to reach a house, and about one reachable house in three in each
  settlement is left without a drop, so neighbours are never all wired and the village does not
  turn into a web. Wires are a thin, half-transparent
  grey-olive close to the ground tone, still readable as a line at play zoom. Never a lone pole, a
  wire over a roof or a line from nowhere; a yard is a house facing the road, a garden of tilled rows
  behind it, a shed, and one fence around them with a gate to the road; bales and trailers stand
  at field edges or by a shed, never on a garden or the road; nothing hangs over a bank or stands
  within ~0.4 tile of water; bridge ends meet the banks. Every building stands on a levelled pad
  cut into the slope uphill and built up downhill, never sunk to the windows or raised on a plinth.
  Heights are real: a 0.4 kV pole 8–9 m, a single-storey house 6–7 m to the ridge.
- **Materials read in battle as in the asset preview:** textured and matte; straw, concrete and
  dry steel never shine. Ruins show floor debris inside, never grass. A few chimneys and ruins
  give off a faint smoke.
- **Forests are dense woods** a tank could hide in — canopy masses, a shrub belt at the edge, not
  a few trees with units visible between them. The wood is a calm mass of even tone: bright or
  busy foliage competes with the units and the zone contours. Two shapes per tree species, each
  tree turned and scaled on its own. Forest shadows are baked onto the ground in the map's sun
  direction (the canopy casts no real shadow); the ring beyond the board carries canopy only, and
  the understory under the canopy drops out above zoom 15 (play zoom is 12). A tank that enters a forest cell
  breaks it: no standing trees or stumps, fallen trunks lying in the dug-up soil, and the lane it
  leaves stays visible — crowns keep clear of it.
- **Loose vegetation where it really grows:** reed, cattail and willow in patches along some
  banks; fruit trees and shrubs in many yards, not all; a few lone bushes and trees on meadow,
  never on ploughed land. Every species comes in at least three shapes. A vehicle that enters the
  cell leaves a low pile of crushed branches or a flattened clump, never a flat stain. Fallen and
  broken wood keeps its bark colour: no pale fresh breaks or splintered ends anywhere, they only
  litter the picture.
- **Whatever hides a visible unit turns semi-transparent** — crowns, roofs and walls between the
  camera and a unit the current player can see fade smoothly to about 30–40 % opacity with alpha
  blending. Never a dither, stipple or hole pattern; low rubble that cannot hide a unit stays solid.
- **Scars respect the fog:** crushed props, wrecks and their scorch show only where the viewer's
  `seen` covers the tile, or they report enemy movement. A prop is crushed only on a cell the
  viewer has seen.
- **Footpaths are wear, not a laid strip.** From each house door through the gate to the road, plus
  trodden patches at gates and sheds and one or two meandering tracks from a road to the water.
  `Footpaths` bakes one RG8 mask per board (64 px per tile; R is path wear, G a trodden patch);
  `ground.gdshader` tints the ground with it, so there are no nodes, decals or draw calls. 0.4–0.8 m
  wide, wider at doors and gates, one smooth curve with a ragged, noisy edge, bare earth in patches
  with grass sprouting even in the middle, low contrast. Every path tone is the grass's own
  brightness under it times an earth hue, never a fixed colour, so the ground texture always shows
  through. On screen the middle of a path is about 0.85 of the grass beside it in rain or mud (wet
  earth) and about 1.1 on a dry map (dust); the patch at a door or gate is a little stronger, so the
  way into a yard reads at zoom 6–8. The dry earth hue and strength are set per map in its look
  (`BattleLook.path_earth_dry`, `path_trod_dry`, `path_dry_k`): on pale ochre grass a path needs a
  warmer, stronger tone with little blue, or it vanishes into the grass or turns mauve. The noise
  lives in path coordinates (along, across), never in a world texture. A path fades out on the verge
  and never reaches the carriageway or the water. No puddles or standing water on a footpath or
  trodden patch, even in rain or on marsh. Public: the fog never touches it, and it changes no rule.
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
| explosion, ground dirt, impact and muzzle flash | one camera-facing quad per layer playing a **baked flipbook atlas** (`assets/vfx/`, offline renders of CC0 sims), soft depth fade where it meets the ground or a hull, dissolving by a noise threshold rather than by alpha | rolling smoke and fire need a real fluid sim; one quad with a 64-frame atlas costs one draw |
| where the blob is born | each atlas's **blast point** (`SOURCES.md`) is pinned to the hit point — the ground for bursts, the hull for a kill, the gun tip for a muzzle flash | without it the fireball floats above the hull or sinks under the ground |
| the flash | an `OmniLight3D` for 3–5 frames plus a hot core quad | the light is what hits the eye |
| debris (ground bursts, kills) | one `GPUParticles3D` of irregular dark chunks, ballistic under real gravity, landing on a collision box and settling; shared meshes and materials | a brown cloud alone reads as smoke, not as earth thrown up |
| fire on a wreck | the Unity Labs **`Flame02` flipbook** (16×4, 64 frames, `assets/vfx/flame02.png`) on two billboards rooted on the turret roof either side of the ring, each with its own phase and rate; one warm noise-flickering light per fire (at most 4 on the board); a few sparks | a baked loop costs one quad per root; with its own phase and rate per instance, no two flicker in step and nothing moves periodically |
| smoke column | one `MultiMesh` of flipbook puffs for every column on the board, born at the flame tip | a column stands for several turns; a particle system per wreck would simulate forever |
| the scar | a stamp into the ground's **scar map** (scorch under wrecks only) | statics, not particles — see below |

The thing that is not obvious: **good fire is not simulated at runtime, it is simulated offline and
baked into a flipbook.** EmberGen or Blender's Mantaflow run the real fluid sim, render 64 frames
into an atlas, and the game plays one quad with a shader. Procedural noise in a shader looks like a
gas hob, not like an ammunition rack going up. `Flame02` is CC0 1.0 per the publisher's blog page;
see the [licence notes](art/vfx-flipbook-sources.md#licence-notes). A procedural flame with a
stable base and detaching tongues stays in `WreckLayer` behind the `USE_FLAME02` flag.

The fire burns at full size, shrinks to about half, then leaves only smoke over the wreck's life.
Fire and smoke step on one timer at 30 per second, not on `TIME`, and the timer stops when nothing
burns, so the idle frame cap can engage.

What our own constraints add on top:

- **Overdraw is the killer, not particle count.** Twenty large half-transparent quads covering half
  the screen cost more than five hundred small ones. So: fewer particles, larger atlas, better
  flipbook.
- **A smoke column standing for three turns must not be a particle system.** Every column on the
  board is one `MultiMesh` of flipbook puffs stepped by the shared timer. Otherwise five wrecks are
  five systems simulating forever, and the frame rate never drops between turns — and dropping it
  is the battery budget above.
- **An explosion is sharp, its smoke is slow.** The cloud reaches full volume in 0.1–0.2 s; then
  the flipbook crawls, the cloud rises with deceleration (1.5–2 m/s at the start), widens and
  drifts downwind, and thins evenly to zero in 3–6 s (a tank-gun hit puff 3.5 s, a 155 mm burst or
  a kill 6 s). The cloud keeps its shape for the first third of its life, then dissolves by a
  noise threshold from 35 % of its life, linearly — thin edges first, the dense core last — never
  with the last flipbook frame; the rise slows but does not stop. A cloud widens around its middle,
  not upwards from the blast point, and the rise baked into the dirt flipbook is cancelled: a
  155 mm cloud centre rises 1.5–3 m in 3 s. The player waits only for
  the flash (0.3 s), not the smoke.
- **Smoke never buries a neighbour.** Over the screen footprint of a visible unit other than the
  target, all the moment's smoke layers together are capped at 0.45 from 0.3 s, so the unit keeps
  a smoke tint rather than showing through a hole; the cap's edge is feathered over a tile.
- **Hot cores, not white stickers.** A flash core is white-yellow in the middle with an orange edge,
  alpha-blended, for two frames; sparks cool along the blackbody ramp (white → yellow → orange →
  dull red) and arc under gravity; a gun firing leaves grey-beige powder smoke along the barrel and a
  low, ragged dust sheet 1–1.5 tiles wide on the ground under and in front of the hull. A muzzle
  core is yellow-orange for three frames (~50 ms). Ground dust is one soft radial layer 0.3 m above
  the ground with a noise-eaten edge, fading softly where the relief meets it — never per-cell
  alpha or a regular grid.
- **Peaceful smoke:** 1–3 chimneys and 1–2 ruins per map breathe a barely visible plume — one
  continuous strip per source, never puffs: puffs born at a steady rate read as smoke rings fired
  in volleys. A chimney plume is 14 m tall, 0.8 m wide at the pot and a tile wide at the top; a ruin
  rises from the breach at roof level, 0.75 as tall and twice as wide at its source, and a little
  denser (density 0.65 against the chimney's 0.36), because wind lays it flat and thins it. Density
  and the ragged edge come from noise that scrolls up at the smoke's own 0.8 m/s, so nothing along
  the plume repeats; a slow edge noise bites up to ~30 % of the width so the outline is torn, not a
  cone. The strip reads as a volume without volumetrics: a smooth height field of billows gives each
  fragment a normal (finite differences, no seams; the vertical component is flipped into the
  screen basis, where y points down), lit by the map's sun on clear maps (warm lit side, cool shadow
  side) and by a sky light from above on overcast ones, **with higher contrast than the sun**
  (stronger normal, wider lit-to-shadow range) so the volume still reads without a sun. Hollows
  between billows are darker and the plume breaks into tatters towards the top. Still one strip per
  source, one draw call for all of them.
  Wet weather (`1 − sky_clear`) switches on a heavier branch: the plume is up to 2.2× wider and
  1.5× denser near the pot, the wind lean is capped at 0.16 per unit of height so it does not lie
  on the ground, and the small noise octaves are weaker so billows stay 0.9 m and larger instead of
  breaking into streaks. Clear maps keep the original values. Otherwise the plume leans with the
  wind like the wreck columns. No `sin` in the shader — game time grows all match.
  Target: the plume reads about 15–25 levels (8-bit grey, mean over its pixels) lighter than the
  ground behind it at zoom 8, never white. Measured with `tools/smoke_seq.gd` (the same frame with
  and without smoke): River 16, Crossroads 20; the brightest tenth of the pixels 36 and 39.
  Houses and ruins are public map props, so it is always on.
- **No crater after a burst:** the cloud, dust and clods play out and leave nothing on the ground.
  Debris chunks are irregular, 0.2–0.7 m, fly their whole arc, land and settle.
- Every moment is `one_shot` and frees itself with `queue_free` once its smoke is gone (≤ 6.5 s).
  Setting `emitting = false` is not enough; the particles stay in frame. A handover clears all of
  them: smoke over ground the next player never scouted would show where the target stood.
- Scorch under wrecks is stamped into a **scar map**, one texture over the board that the ground shader reads, masked by the viewer's `seen`. Not `Decal` nodes: the Mobile renderer applies at most 8 decals per mesh and the Compatibility renderer none, and the ground is one mesh. Not quads over the ground: they z-fight on slopes and cost a draw call each.

Off the table on mobile Vulkan: volumetric smoke, raymarching, GPU particle collision against the
SDF, and more than one effect sampling `screen_texture` at a time.

3D asset generation, poly budgets and the GLB pipeline are covered by the **`asset-manager`
skill** — read it before generating anything, and do not duplicate its guidance here.
