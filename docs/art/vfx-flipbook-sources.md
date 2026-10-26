# VFX flipbook sources

Ready-made, offline-simulated flipbook atlases for five effects: (1) burning-wreck fire loop,
(2) rising dark smoke, (3) shell/drone fireball, (4) dirt/dust impact burst, (5) metal sparks.
Every image below was opened and looked at, both as a whole atlas and as 1:1 frames composited
over the wet-field ground colour. The contact sheet (local only, not in the repo) is at
`~/.cache/ap-scratch/vfx-research/vfx_flipbook_sheet.jpg`.

## What the camera needs

At 7 cm/px (closest zoom) a 6 m fireball covers about 86 px, a 2–3 m wreck flame 30–40 px and a
4 m smoke puff about 57 px. At 22 cm/px these numbers are a third as large. **A 128 px frame is
already more than enough. A 204 px frame is twice the need.** Nobody needs to chase 2K-per-effect
atlases or the `HD` variants. An 8×8 atlas of 128 px frames is 1024².

## Verdict per effect

| effect | top pick | ready-made? |
| --- | --- | --- |
| 1 wreck fire loop | **U-Flame02** (U-Flame03 as the small variant, U-FireBall02 additive as the hot core) | yes |
| 2 rising dark smoke | **U-WispySmoke01** (puffs), **U-DiscSmoke01** (column segment); tint both dark | yes, needs a tint |
| 3 shell/drone fireball | **U-Explosion00** (U-Explosion02 as the variant) | yes |
| 4 dirt/dust burst | **none realistic and ready-made.** Stopgap: U-Explosion01-nofire tinted brown. Real route: render the JangaFX CC0 VDBs (below) | **no** |
| 5 metal sparks | **none as a flipbook, and none is needed**: point particles with a stretched streak sprite, Kenney `trace_01`/`trace_07` | not a flipbook |

## Shortlist

Licence "CC0\*" = the Unity Labs caveat, see the licence notes below.

| id | source | licence (where read) | layout · resolution | effects | loop (measured) | quality notes | ship? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **U-Explosion00** ★ | [Unity Labs flipbooks](https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks), T. Iché 2016 | CC0\* (blog text) | 5×5, 1024², 204 px/frame, RGBA straight alpha; EXR also | 3 | one-shot (last→first diff 17 vs 4.7 between frames) | Houdini sim. Irregular, lumpy fireball that turns to black smoke with a brown fringe. The most realistic of the set; reads like an HE burst | ship |
| U-Explosion02 | same | CC0\* | 5×5, 1024², RGBA | 3 | one-shot | Same sim family, rounder; the first 3 frames are a blown-out white ball. Use as a variant, cut frames 0–1 | ship |
| U-Explosion01 | same | CC0\* | 5×5, 1024², RGBA | 3 | one-shot | Between 00 and 02; not needed | spare |
| **U-Explosion01-nofire** | same | CC0\* | 5×5, 1024², RGBA, grey max 230 | 2, 4 (stopgap) | one-shot | Dark, cauliflower-shaped billowing burst, no flame. Tinted brown it passes for a dust burst from a distance, but it is a *smoke* burst: it has no low, wide dome and no ejecta | ship (stopgap) |
| **U-Flame02** ★ | same | CC0\* | 16×4 = 64 frames, 2048×1024, 128×256 px/frame, RGBA | 1 | **loops** (seam 5.6 vs 5.1 between frames) | Real fluid flame tongue with a sooty tip. In straight alpha it carries a dark brown halo; drawn here with plain alpha blending (`blend_mix`), which looks right with the shipped gain. **Shipped** as `assets/vfx/flame02.png` (PNG, 2048×1024, VRAM compressed with mipmaps ≈ 2.8 MB), played by `game/battle/shaders/fire.gdshader`. Provenance: the publisher's page (Unity Labs blog, T. Iché, 2016) releases the sequence under CC0 1.0 | ship |
| U-Flame03 | same | CC0\* | 16×4, 1024×512, 64×128 px/frame, RGBA (+ a temperature map in the EXR) | 1 | **loops** (5.8 / 5.9) | Thinner, more ragged flame; good for small secondary fires on a wreck. Half the memory of Flame02 | ship |
| U-FireBall02 | same | CC0\* | 8×8, 1024², **RGB only, no alpha** (additive) | 1 (core glow) | **loops** (5.6 / 5.0) | A rolling ball of fire; as an additive core under Flame02 it gives the engine-deck glow. Alone it looks like a sun, not a fire | ship |
| **U-WispySmoke01** ★ | same | CC0\* | 8×8, 1024², 128 px/frame, RGBA, grey max 183 | 2 | **loops** (5.9 / 5.3) | Lit, wispy, self-shadowed smoke puff. Too light for the target (L\* 12–27): multiply it to a dark grey-brown in the shader | ship |
| U-WispySmoke02 / 03 | same | CC0\* | 8×8, 1024², RGBA | 2 | **loop** (6.6/5.9, 4.7/4.6) | Variants of 01; 03 is the densest. Use one as a second puff variant if repetition shows | ship |
| **U-DiscSmoke01** | same | CC0\* | 16×4, 2048×1024, 128×256 px/frame, RGBA | 2 (column) | **loops** (5.7 / 4.8) | The only tall rising-column shape. Pale (steam-like) as shipped; tint dark. Fits the puff stack of the wreck column | ship |
| U-Cloud02 | same | CC0\* | 8×8, 1024², RGBA | — | loops | Frames barely change: a static soft blob. **Reject** | no |
| **Kenney PP trace_01 / trace_07** ★ | [Kenney Particle Pack 1.1](https://kenney.nl/assets/particle-pack) | CC0 1.0 (`License.txt` in the zip: "You may use these assets in personal and commercial projects. Credit … not mandatory") | single sprites, 512², greyscale | 5 | n/a | Soft streaks; stretched along velocity they make spark trails. Keep them short and few; no starbursts (`spark_*`, `star_*` rejected) | ship |
| Kenney PP dirt_01–03 | same | CC0 1.0 | single sprites, 512² | 4 (chunks) | n/a | Flat chunk sprays; only usable tiny, as flying clods inside a dust burst | ship (minor) |
| JangaFX CC0 VDBs | [Free VDB volumes](https://jangafx.com/software/embergen/download/free-vdb-animations) | "These free VDB simulations are licensed as CC0 (Public Domain) so you are free to use them however you want!" (page text) | **VDB volumes, not flipbooks.** Grenade Dust Impact 200 fr 3.45 GB, Ground Explosion 200 fr 661 MB, Dust Shockwave 155 fr 5.0 GB, Small Camp Fire 200 fr 59 MB, Simple Fire 101 fr 65 MB, Industrial Chimney Smoke 250 fr 1.2 GB; MediaFire-hosted | 4 (and 1–3) | — | EmberGen sims, not looked at (nothing downloaded: GB-sized). The only CC0 realistic **dust** source found. Rendering them to an 8×8 atlas needs Blender (VDB import, top-down-ish camera), not an EmberGen licence | pipeline source |
| Fab Realistic Starter VFX Pack Vol 2 | [Fab listing](https://www.fab.com/listings/ac2818b3-7d35-4cf5-a1af-cbf8ff5c61c1), FX Cat UA | Fab Standard License; Personal tier price 0, `isCc0: false` (listing JSON via web.archive.org; fab.com returns 403 here). Only the **non-binding summary** was read: "Use the assets with any compatible tools (usage is not limited to Unreal Engine)… You may not: Resell or redistribute the asset … on a standalone basis" | Unreal Engine format only; texture layouts unknown | 1, 2, 3, 5 | — | Previews: game-grade, semi-realistic; explosion blown out to white, sparks are a bright starburst spray. Textures only reachable through a UE install | reference only (full EULA and Personal-tier eligibility unverified) |
| OGA boom3 | [Explosion Sheet](https://opengameart.org/content/explosion-sheet), StumpyStrust | CC0 badge on the page | 8×8, 1024² | 3 | one-shot | Particle-engine render, white for half the frames, no smoke. **Reject** | no |
| OGA smoke_sheet | [Smoke Sprite Sheet](https://opengameart.org/content/smoke-sprite-sheet), ohyhei | CC0 badge | 1280² sheet | 2 | — | Soft round blob, no structure. **Reject** | no |
| OGA others | [explosion atlas](https://opengameart.org/content/explosion-particles-sprite-atlas) (TheJosh), [Explosion](https://opengameart.org/content/explosion-7) (BenHickling), [2D Explosion Animations #2](https://opengameart.org/content/2d-explosion-animations-2-frame-by-frame) (Sinestesia), [Fire FX](https://opengameart.org/content/fire-fx-burning-fire-animation) (Mikodrak) | CC0 badges | various | 1, 3 | — | Painterly puffs, a starburst, cartoon frame-by-frame, a pixel-era fire. **Reject on sight** | no |
| Brackeys VFX Bundle | [itch.io](https://brackeysgames.itch.io/brackeys-vfx-bundle) | page: "released under a Creative Commons Zero (CC0)… Attribution is not required" | — | — | — | A repack of Iché (Unity Labs) flipbooks and Kenney textures plus CodeManu sprites. Adds nothing over the originals. Not downloaded | no |

## Licence notes

- **Unity Labs (the asterisk).** The blog page (posted 2016-11-28, Thomas Iché) says: "Here are some
  image sequences we want to share with you under CC0 license" and "Today, we release some of these
  sequences under CC0 license so you can use them in your projects", linking CC0 1.0. All 28
  downloads sit on that page and no item is marked otherwise. **The zips contain no licence
  file.** Record the blog URL as provenance. Whether that is enough is open decision #5 in
  [damage-fx-research.md](damage-fx-research.md). All links still resolve
  (`unity3d.com/files/labs/downloads/vfx/assets01/<Name>/<Name>-flipbooks.zip`, 2.5–8.8 MB each).
- **Alpha.** The Unity TGAs are straight (non-premultiplied) RGBA. The smoke maps are lit greyscale (no
  colour), so tint in the shader. FireBall02 is RGB only and meant for additive blending. No atlas
  bleeds alpha onto a cell border (measured: max border alpha 0–4 of 255).
- **Unreal Starter Content / Epic samples: rejected.** The UE EULA counts Starter Content as
  Licensed Technology. Its royalty-free "Non-Engine Products" are those that "do not include
  Starter Content in source format", and it adds "certain assets that we make available under
  separate agreements are available for use only with Unreal Engine" (read from the archived EULA
  at unrealengine.com/eula/unreal).
- **Unity Asset Store: not pursued.** Unity's support article says Asset Store assets are "not
  restricted to Unity projects", but forbids letting users "access or extract the raw asset files".
  An unencrypted Godot `.pck` lets anyone extract them, so the clause is a trap. Some
  Unity-published packs also carry Unity-only terms.
- **JangaFX EmberGen** itself has no free tier (Indie licence ~$300). The only free JangaFX
  output is the CC0 VDB set above. There is no free JangaFX flipbook pack.
- **ambientCG and Poly Haven**: no smoke/fire/explosion/spark assets (API queries for those terms
  return only lava materials and HDRIs).

## Gaps

- **Dust/dirt impact (4):** no ready-made realistic CC0 flipbook exists in any source checked.
  The honest options are (a) U-Explosion01-nofire tinted brown plus Kenney dirt chunks as a
  stopgap, or (b) render JangaFX "Ground Explosion" (661 MB) or "Grenade Dust Impact" (3.45 GB) VDBs in
  Blender into an 8×8, 1024², 128 px/frame atlas.
- **Sparks (5):** none as a flipbook anywhere, realistic or not. This does not matter: sparks are
  short-lived point particles, and a stretched streak sprite (Kenney trace) is the standard technique.
