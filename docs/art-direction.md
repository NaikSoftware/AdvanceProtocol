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
- **Light and audio:** overcast northern-European daylight as the default preset, turbine and
  diesel notes, radio chatter as texture rather than language.
- **Infantry:** plate carriers, ballistic helmets, optics on rifles.

What stays forbidden, exactly as before: **no real army, nation, flag, insignia or identifiable
vehicle**, anywhere in code, data, UI or assets. The sides are fictional and stay fictional.
Era-neutrality in the *rules* also stands — nothing in `core/` encodes a period, and the unit
names in [§3.6](rules/units.md) remain role labels. The setting is an art-direction decision, not a rules one.

## Rendering and mobile budget

The camera is a fixed orthographic rig, roughly 45° yaw and 50–55° pitch. Pan and clamped zoom
only; no free rotation (90° snaps are acceptable if playtests ask for them). Because the angle is
fixed, **undersides are never seen and backs rarely are** — judge every asset from that angle.

Budget on a mid-range phone at 60 fps: under ~100 draw calls and ~150k triangles on screen.

Techniques that buy atmosphere cheaply here:

- **Bake** static terrain lighting. One directional light with shadows for units only.
- Time of day is a **per-map baked preset**, not a dynamic cycle.
- Weather = particles + a screen overlay + a wind parameter on foliage shaders + an audio bed.
- Skip volumetric fog. A depth-based fog gradient reads nearly as well and costs almost nothing.
- Wetness is a material parameter (roughness + normal blend) driven by the weather controller.
- Post-processing: a colour-grade LUT, light vignette, minimal grain. **No SSAO, no SSR.**
- **Persistent battle scars.** Wrecks stay. Smoke columns linger for several turns. Craters and
  mud ruts accumulate. This is the cheapest atmosphere in the game and it doubles as information:
  the map should tell you where the fighting has been.

Turn-based means the screen is usually static — enable low-processor mode and drop the frame rate
hard when nothing is animating. Battery life is a feature for a game passed between people.

## Effects — fire, explosions, smoke

Never one technique. A single explosion is four or five layers, each one the cheapest thing that
does its job:

| layer | technique | what it buys |
| --- | --- | --- |
| the mass of smoke and flame | `GPUParticles3D`, billboarded quads | motion, spread, lifetime |
| the look of one particle | **flipbook** sprite atlas (8×8) in the particle shader | rolling, turning smoke — without it these are blobs |
| depth | soft particles (depth fade), dissolve by a noise mask | the quad stops cutting the ground on a hard line, and dies by burning away rather than by alpha |
| the flash | an `OmniLight3D` for 3–5 frames plus emissive on the particle | the only part that actually hits the eye |
| heat haze | screen-texture refraction on one quad | cheap, and it is what reads as expensive |
| the scar | `Decal` (crater, scorching) plus debris meshes | statics, not particles — see §8 |

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
- Craters and scorching are `Decal` nodes, not quads laid over the ground — quads z-fight on slopes.

Off the table on mobile Vulkan: volumetric smoke, raymarching, GPU particle collision against the
SDF, and more than one effect sampling `screen_texture` at a time.

Build order when this comes up: the **smoke column first** — it is persistent, and persistence is
what makes it atmosphere ([§8](../CLAUDE.md), battle scars) — and the explosion after it.

3D asset generation, poly budgets and the GLB pipeline are covered by the **`asset-manager`
skill** — read it before generating anything, and do not duplicate its guidance here.
