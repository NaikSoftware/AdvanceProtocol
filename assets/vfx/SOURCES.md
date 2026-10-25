# assets/vfx — sources and licences

Every file in this folder, where it came from and what licence covers it.

## Simulations: JangaFX EmberGen free VDB animations (CC0)

Page: <https://jangafx.com/software/embergen/download/free-vdb-animations>. Wording on that page: "We have
generated numerous volumetric simulations with EmberGen and exported them as VDBs for you to use in your own
projects (Blender, Houdini, Octane, Arnold, etc). These free VDB simulations are licensed as CC0 (Public
Domain) so you are free to use them however you want!". Each archive also carries a `LICENSE.txt` that opens
"VDB SETS WERE CREATED WITH EMBERGEN BY JANGAFX LLC … Creative Commons - Public Domain - CC0:
<https://creativecommons.org/publicdomain/zero/1.0/>". What we rendered from them:

| pack (as listed on the page) | size / frames | used for |
| --- | --- | --- |
| Ground Explosion (`GroundExplosionVDB.zip`) | 661 MB, 200 frames, channels density + flames | `explosion.png` (frames 6–132 step 2), `smoke_column.png` / `smoke_column_thin.png` (smoke only, frames 66–129), `dirt_burst.png` (smoke only, brown albedo, frames 4–130 step 2), `impact_flash.png` (frames 4–34 step 2, small scale) |
| Small Camp Fire (`SmallCampfireVDB.zip`) | 59 MB, 200 frames, channels density + flames | `wreck_fire.png` (frames 0–192 at step 1.5, cross-faded into a 64-frame loop) |

Every other pack on the page (Aerial Explosion, Tornado Looping, Fire Plume, Cloud Pack, Grenade Dust Impact,
Dust Shockwave, Industrial Chimney Smoke, Building Implosion, Gasoline Explosion, High-Res Smoke Plume, Simple
Fire, Dust Devil, Mid-Air Explosion) is CC0 by the same statement. The hosting site began serving a browser
check to scripted downloads partway through, so Grenade Dust Impact, Industrial Chimney Smoke and the bigger
packs were not fetched. Simple Fire (`Fire_01`, flames + temperature) was fetched, rendered as a test and
dropped: the flame ball it holds reads wrong from above.

The atlases are renders of these sims with our own lighting (grey overcast sky plus one soft overhead light),
shader (emission ramp `#4A1204 → #B8400F → #E0702A → #FFD9A0`, smoke albedo) and camera (orthographic, 45°
pitch). The VDB files themselves are not in the repository.

## Files

| file | what | frames / grid | source |
| --- | --- | --- | --- |
| `smoke_column.png` | rolling dark smoke, plays once and ends empty (loops without a seam) | 64, 8×8 × 192 px, 4 fps, cell ≈ 22 m (the cloud fills ≈ 19 m, scale the quad) | Ground Explosion VDB |
| `smoke_column_thin.png` | the same, lighter and thinner (peak alpha 0.35) for the thinning stages | 64, 8×8 × 192 px, 4 fps | Ground Explosion VDB |
| `wreck_fire.png` | tall soft flame body rising from the cell bottom: near-white base, yellow-orange middle, orange-red fading tips, thin dark-grey smoke wisps above; shape from the sim, colour graded by height, sideways licking added as loop-period harmonics; seamless loop | 64, 16×4 × 128×256 px (2048×1024), 8 fps, cell width ≈ 3.4 m (flame ≈ 1.5 m wide, 3 m tall), base at the bottom centre, 6% above the cell bottom | Small Camp Fire VDB (vertical stretch 3.6) |
| `explosion.png` | fireball then dark smoke, one-shot | 64, 8×8 × 192 px, 48 fps, cell ≈ 22 m | Ground Explosion VDB |
| `dirt_burst.png` | brown earth and dust cloud, no fire, one-shot | 64, 8×8 × 192 px, 40 fps, cell ≈ 13.7 m | Ground Explosion VDB (density only, brown albedo) |
| `impact_flash.png` | muzzle / impact flash into a small fireball, ends empty | 16, 4×4 × 192 px, 60 fps, cell ≈ 6.7 m | Ground Explosion VDB (early frames) |
| `armour_sparks.png` | 4×2 sheet of 7 spark streaks (8th cell empty), tinted `#FFE6B0` with a white-hot core | 8 cells × 256 px | Kenney Particle Pack 1.1, `PNG (Transparent)/trace_01…trace_07.png`, resized 512→256 and tinted; <https://kenney.nl/assets/particle-pack>; CC0 1.0 (`License.txt` in the pack) |
| `smoke_puff.png` | 256², white soft puff used by the main menu | **UNKNOWN SOURCE.** Added with the menu shell (first commit `766c8f5`). It matches no file in Kenney Particle Pack or Kenney Smoke Particles, and nobody recorded where it came from. SHA-256 `0cc39934418048c69ed815a3150f1feb03a344dd30a7b90cc361bb0554068522`. Replace it, or establish the source, before release | **unknown** |

## Rebuild

`tools/blender/vfx/render_all.sh` holds the exact render arguments of every atlas (Blender 5.2 in batch mode,
never the MCP) and then packs them with `tools/blender/vfx/assemble.py`. Unpack the two packs above under one
folder (`VDB`), pick a scratch folder outside `/tmp` (`WORK`, a few GB) and an output folder (`OUT`):
`VDB=… WORK=… OUT=… tools/blender/vfx/render_all.sh`.
