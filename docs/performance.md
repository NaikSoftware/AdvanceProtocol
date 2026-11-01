# Performance

## Budget

On a mid-range phone at 60 fps the battle screen stays under about **100 draw calls** and
**150 000 triangles** (CLAUDE.md section 8). The count includes the sun shadow pass and the
interface canvas.

## Measuring

`tools/battle_budget.tscn` loads the real battle screen on a map, puts the camera on a cell at a
given zoom and prints one line per view:

```
BUDGET <map> <cell> z<zoom> dc=<draw calls> tris=<triangles> shadow_dc=<shadow pass> canvas_dc=<interface>
```

```bash
godot --path . --position 6000,0 res://tools/battle_budget.tscn -- <out_dir> crossroads@13,11@20
godot --path . --position 6000,0 res://tools/battle_budget.tscn -- <out_dir> --diag --only=prop_ crossroads@20,16@20
```

- It needs a window (not `--headless`); the window is placed off screen. A view is `<map>@x,y@zoom`;
  with no `@` it shoots the board centre at maximum and minimum zoom.
- The number is the **median of nine frames taken once the camera is still**, and after the
  start-up effect warm-up has removed itself (it draws about 25 extra calls for the first second).
  The fog clock is stopped so frames repeat.
- `--diag` hides each node group in turn and prints what it costs (`DIAG ... dc= tris= surfs= inst= vis=`).
  The base is re-measured before every group; differences of 2 to 3 calls are noise, so trust only
  larger ones. `--only=<substring>` limits it to matching groups.
- **Measure one launch at a time.** Two Godot windows at once shift the count by up to 10.

## Current numbers

Draw calls / triangles (thousands), view centred on cell (13, 11):

| map | z8 | z12 | z20 |
| --- | --- | --- | --- |
| crossroads | 53 / 100.6 | 57 / 100.1 | 60 / 99.1 |
| river | 52 / 135.7 | 54 / 139.9 | 66 / 138.6 |
| ridge | 49 / 104.9 | 51 / 104.8 | 63 / 110.4 |

Densest views at z20, the corner of the board with the most buildings:

| map | cell | draw calls | triangles (k) |
| --- | --- | --- | --- |
| crossroads | (20, 16) | 80 | 102.0 |
| river | (20, 16) | 73 | 137.5 |
| ridge | (20, 16) | 71 | 103.2 |

Every measured view is under the budget; the tightest margin is triangles on river (about 138k of 150k).

## Main cost groups

- Ground, water and roads: a handful of calls, but the largest share of triangles (the adaptive
  ground mesh is 12 to 22 thousand per map).
- Forest and vegetation: one merged mesh per atlas.
- Props: one call per model (a MultiMesh each), plus one for a house's second surface; houses and
  sheds that cast a sun shadow cost a second call in the shadow pass.
- Small shared layers (contact shadows, garden beds, grime, rubble floors, small boxes,
  transformers, wires): one call each.
- Effects: smoke, fire and wreck layers.
- Interface: 9 canvas calls.

## Rules that keep the frame under budget

- **Never add a MultiMesh per model for something that can share a material.** Models that share a
  texture atlas share a node; the yard fences are five kinds in one node, the kind carried in the
  instance custom data.
- **Foliage goes through `FoliageBatch`**: all instances of one atlas are merged into one mesh and
  per-instance data lives in a small texture, so a fade over a unit is a texture write, not a
  rebuild.
- **Only buildings cast sun shadows.** Props, vegetation and ruins do not; a MultiMesh casts by
  default, so switch it off.
- **A new layer must be measured**, with `--diag`, on the densest corner at z20, not only at the
  board centre.
