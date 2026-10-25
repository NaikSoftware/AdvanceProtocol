# assets/vfx — sources and licences

Every file in this folder, where it came from and what licence covers it.

| file | what | source | licence |
| --- | --- | --- | --- |
| `smoke_column.png` | 8×8 flipbook, rolling dark smoke puff, 64 frames, 4 fps, plays once and ends empty (loops without a seam) | rendered here: Blender 5.2 Mantaflow + Cycles, `tools/blender/vfx/bake_flipbook.py` preset `smoke_puff`, packed by `assemble.py` | own work, no third-party input |
| `smoke_column_thin.png` | the same sim, lighter and thinner (peak alpha 0.35) for the thinning stages | same preset, graded by `assemble.py` | own work |
| `wreck_fire.png` | 8×8 flipbook, low flames 1–2 m with dark smoke at the tips, 64-frame seamless loop, 8 fps | Blender Mantaflow + Cycles, preset `wreck_fire` | own work |
| `explosion.png` | 8×8 flipbook, fireball then dark smoke, one-shot, 64 frames | Blender Mantaflow + Cycles, preset `explosion` | own work |
| `dirt_burst.png` | 8×8 flipbook, brown earth and dust, no fire, one-shot, 64 frames | Blender Mantaflow + Cycles, preset `dirt_burst` | own work |
| `impact_flash.png` | 4×4 flipbook, muzzle / impact flash into a small fireball, 16 frames | Blender Mantaflow + Cycles, preset `flash` | own work |
| `armour_sparks.png` | 4×2 sheet of 7 spark streaks (8th cell empty), tinted `#FFE6B0` with a white-hot core | Kenney Particle Pack 1.1, `PNG (Transparent)/trace_01…trace_07.png`, resized 512→256 and tinted; <https://kenney.nl/assets/particle-pack> | CC0 1.0 (`License.txt` in the pack) |
| `smoke_puff.png` | 256², white soft puff used by the main menu | **UNKNOWN SOURCE.** Added with the menu shell (first commit `766c8f5`). It matches no file in Kenney Particle Pack or Kenney Smoke Particles, and nobody recorded where it came from. SHA-256 `0cc39934418048c69ed815a3150f1feb03a344dd30a7b90cc361bb0554068522`. Replace it, or establish the source, before release | **unknown** |

Rebuild the rendered atlases: `tools/blender/vfx/bake_flipbook.py` (bake + render per preset, run with
`blender -b --factory-startup -P … -- <preset> <work dir>`), then `tools/blender/vfx/assemble.py`
(`python3 -I assemble.py <work dir> <out dir> all`). Keep the work dir out of `/tmp`: the sim caches run
to gigabytes.
