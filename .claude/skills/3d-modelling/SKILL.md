---
name: 3d-modelling
description: Use when editing an existing 3D asset in Blender for this project — fixing the scale, origin or facing of a generated GLB, decimating to a poly budget, baking textures or LODs, or diagnosing a mesh that lands in Godot floating, sunk, rotated or the wrong size. For generating a new asset from a prompt, use asset-manager instead.
---

# 3D modelling (Blender → Godot)

`asset-manager` **generates** assets (tripo → GLB). This skill covers everything *after* that:
making a mesh fit **this** game. Read that skill for generation, budgets and the GLB rule; do not
duplicate it here.

Blender 5.2 LTS. Two ways in: the `blender` binary headless, and the Blender MCP tools.

## Never work in the human's open Blender

The MCP tools without a `_for_cli` suffix execute **inside a running Blender GUI instance** — the
one the human has open, with unsaved work in it. `execute_blender_code` there will mutate their
scene. Use them to *look* (`get_objects_summary`, `get_object_detail_summary`), never to process
an asset.

Process assets in a separate headless process that cannot reach their session:

```bash
blender --background --factory-startup --python script.py
```

`--factory-startup` also stops their add-ons (including the MCP bridge) from loading, so the
headless run cannot attach to the live session. `bpy.ops.wm.read_factory_settings(use_empty=True)`
first, and never `save_mainfile` — the human's `.blend` is not yours.

## The numbers this game actually needs

An agent that does not read this section will normalise the asset to "1 metre" and ship something
three times the size of a tile. The view already encodes the truth:

- **One tile = 1.0 world unit.** `IsoCameraRig.cell_to_world(cell) → Vector3(cell.x, 0.0, cell.y)`.
- **The ground is `y = 0`.** A unit mesh must *rest* on it: origin at **bottom-centre**, lowest
  vertex at exactly `y = 0`. Anything else floats or sinks — there is no per-asset offset in the scene.
- **Units are much smaller than their tile.** Target hull dimensions, in Godot axes
  (X width, Y height, Z length), from `game/battle/unit_view.gd`:

| class | X | Y | Z |
| --- | --- | --- | --- |
| infantry | 0.40 | 0.35 | 0.40 |
| light vehicle | 0.55 | 0.30 | 0.85 |
| tank | 0.75 | 0.50 | 0.90 |
| artillery | 0.55 | 0.35 | 0.60 |
| engineer | 0.60 | 0.40 | 0.60 |

Those are the placeholder box sizes the silhouettes were tuned against (§1.5 — classes must not be
confusable from above).

**Scale uniformly to fit inside the box — never stretch per-axis to hit all three numbers.** The
tightest axis governs, and it is usually height. That rule has a consequence you must not paper
over: a source whose proportions don't match the box ends up under-filling it. A sphere fitted to
a light vehicle's 0.30 height fills only 35% of its length and reads as a ball, not a vehicle.

**Under-fill is a generation problem, not a Blender problem.** If the fitted mesh fills less than
roughly two-thirds of the box's longest axis, stop and re-roll it in `asset-manager` with a
better-proportioned prompt. Stretching to fill would distort the model and break the
silhouette-from-above rule the sizes exist to serve.

## Forward is −Z in Godot, which is +Y in Blender

`unit_view` rotates a unit by `-facing * 45°`, and facing `0` is North. At zero rotation the barrel
is built toward **−Z**. So the model must face **−Z in Godot**, and the glTF exporter maps
**Blender +Y → glTF/Godot −Z**.

Verified, not assumed — a cube corner pulled out to Blender `−Y` came back at glTF `+Z`:

```
Blender dims (1, 12, 3)  →  glTF POSITION min [-0.5, -1.5, -1] max [0.5, 1.5, 11]
Blender X → glTF X · Blender +Z (up) → glTF +Y (up) · Blender +Y → glTF −Z (forward)
```

To re-verify this yourself: the marker must be **a vertex of a face** and the shape must be
**asymmetric** along the axis under test. A loose vertex is silently dropped by the glTF exporter,
and a symmetric box proves the axis swap but not its sign.

Point the model's front along **+Y in Blender**. Getting this wrong is invisible in a front view
and only shows up as units driving backwards — the same class of bug as the facing-sign trap the
view layer already carries a warning about.

## Verify the exported file, never Blender's own numbers

Two ways Blender silently lies during a pipeline. Both were reproduced here, and both ship an
asset that is the wrong size and floats above the tile:

1. **`ob.dimensions` and `ob.bound_box` go stale after `modifier_apply`.** A decimated sphere
   reported `(0.3, 0.3, 0.3)` while the real mesh was `(0.3, 0.273, 0.230)`. `view_layer.update()`
   does **not** refresh them. Compute the bounding box from `ob.data.vertices` instead.
2. **Raw `v.co` edits may not reach the exporter.** Moving vertices directly and exporting wrote
   the *previous* geometry — `ob.data.update()` and a depsgraph update did not help. Move geometry
   with object-level operators (`origin_set`, `location`, `transform_apply`) and export with
   `export_apply=True`.

So the last step is always: **parse the written GLB and assert on it.** No Blender involved:

```python
import json, struct
d = open(path, 'rb').read(); off = 12
while off < len(d):
    clen, ctype = struct.unpack_from('<II', d, off)
    if ctype == 0x4E4F534A:
        g = json.loads(d[off+8:off+8+clen]); break
    off += 8 + clen

prims = [p for m in g['meshes'] for p in m['primitives']]
assert len(prims) == 1, f"{len(prims)} primitives — join failed; that is N draw calls"
lo = [min(g['accessors'][p['attributes']['POSITION']]['min'][i] for p in prims) for i in range(3)]
hi = [max(g['accessors'][p['attributes']['POSITION']]['max'][i] for p in prims) for i in range(3)]

assert abs(lo[1]) < 1e-4, f"asset floats/sinks: y_min={lo[1]}"
assert abs(lo[0] + hi[0]) < 1e-3 and abs(lo[2] + hi[2]) < 1e-3, "origin not centred in X/Z"
assert not [n for n in g['nodes']
            if {'translation', 'rotation', 'scale', 'matrix'} & n.keys()], \
    "node carries a transform Godot will inherit — bake it"
# and assert the hull box + tri budget you were aiming for
```

`POSITION.min[1] == 0` is the single check that catches the most common failure. Aggregate over
**all** primitives — asserting on `primitives[0]` passes while you validate a fraction of the
asset. Include `matrix` in the node check: the exporter emits one in some paths, and an unapplied
×100 scale hides there where a TRS-only check sails past it.

## Recipe

Import → strip cameras/lights → join to one object (one draw call) → decide junk-vs-authored on the
node transform, then `transform_apply` → `normals_make_consistent` (generated meshes ship inverted
faces) → weld glTF's split vertices (`remove_doubles`, ~4× vertex reduction; decimation behaves
badly without it) → `DECIMATE` to the budget → **`shade_smooth_by_angle(30°)`** → uniform scale
into the hull box → origin to bottom-centre at the world origin → export `GLB` with
`use_selection=True, export_apply=True` → parse and assert.

**Junk pose or authored pose?** Baking a node transform is only right when it is export junk. Three
signals, and generated assets usually trip all three: a scale that is a suspiciously round number
(`×100`), a rotation that is *not* a clean multiple of 90°, and a mesh-local frame that is already
upright and axis-aligned. All three → zero the transform rather than baking an arbitrary tilt into
the geometry. Any doubt → ask, because baking is irreversible once the mesh ships.

**Weld before you downscale.** `remove_doubles` takes an absolute threshold, so it must run while
the mesh is still at its imported size; the same value applied after scaling to 0.3 units welds
parts that should stay separate.

**Do not skip the shading step — triangles are not the mobile cost.** The glTF exporter splits a
vertex wherever normals aren't shared, so a flat-shaded decimate exports every triangle's corners
separately. Measured on the same 4000-triangle mesh: flat gave **11,743 verts / 400,800 bytes**,
smooth-by-angle gave **2,059 verts / 90,900 bytes** — 5.7× fewer vertices and a 4.4× smaller file
for identical geometry. Track exported vertex count and file size, not just the triangle budget.
Use `shade_smooth_by_angle`, never blanket `shade_smooth`, so hard-surface edges survive.

Poly budgets live in `asset-manager` — but note that its table is *generation* `face_limit` values
for a whole "character / vehicle" class. It does not distinguish a light vehicle from a tank, and
it is not a post-decimation triangle target. Pick within the band by silhouette need at iso
distance and say which number you chose and why.

Judge the result from **this project's camera**, not the textbook isometric one: yaw 45°, pitch
**−52°**, orthographic, `Camera3D.size` between 6 and 20 (`game/camera/iso_camera_rig.gd`). At
maximum zoom-in a tile is about a sixth of viewport height, so a 0.30-unit unit is small on
screen — detail below that reads as noise. A render from the front proves nothing.

## Common mistakes

| Mistake | What it looks like | Fix |
| --- | --- | --- |
| Normalising to "1 metre" | unit dwarfs its tile | use the hull table above |
| Trusting `ob.dimensions` after a modifier | wrong size, floats | bbox from `ob.data.vertices` |
| Leaving a transform on the glTF node | Godot re-applies ×100 | `transform_apply`, assert no TRS **or `matrix`** |
| Flat-shaded export | 5.7× the vertices, 4.4× the file | `shade_smooth_by_angle(30°)` |
| Stretching to fill the hull box | distorted model, silhouette breaks | uniform fit; re-roll if it under-fills |
| Origin at mesh centre | asset half-sunk into the ground | origin bottom-centre, `y_min == 0` |
| Model facing +Y in Godot | units drive backwards | front along **+Y in Blender** |
| Judging from a front render | reads flat or ambiguous in game | render from the iso angle |
| Working in the open GUI session | destroys the human's unsaved work | `--background --factory-startup` |

## What Blender is for here

Things tripo cannot do: retopology, decimation, scale/origin/orientation repair, texture baking,
LODs — and baking VFX flipbook atlases from a fluid sim, which is how real fire/smoke effects are
built (see the VFX notes in `docs/`). Not for authoring assets from scratch: generate with
`asset-manager`, repair here.
