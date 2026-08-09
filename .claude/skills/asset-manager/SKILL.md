---
name: asset-manager
description: Use when creating 3D assets for this project from a text prompt or reference image, choosing poly/texture budgets for an asset, re-rolling an asset that came out wrong, or diagnosing a failing tripo command.
---

# Asset Manager (Tripo → Godot)

Generate 3D assets with the `tripo` CLI. This skill covers only *generation* and the things the
CLI's own docs can't know: how to invoke it here, and what this game needs.

**Project shape that drives every choice below: mobile-first, 3D rendered in a top-down
isometric view.** Assets are small on screen, seen from a fixed high angle, on a phone GPU.

**The CLI ships its own agent-facing reference — authoritative and versioned with the binary.
Read it instead of guessing flags:**

```bash
tripo docs                              # agent skill map
tripo docs --topic commands/make        # every flag for a command
tripo docs --topic examples/game-asset  # copy-paste recipes
tripo docs --topic common-errors        # exit code → fix table
```

## Invocation on this machine

`tripo` needs Node >= 20, but system Node is v18 and nvm loads only in interactive shells.
**Non-interactive commands must load nvm first or they fail on the wrong Node:**

```bash
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh" >/dev/null; tripo make ...
```

Auth lives in `~/.tripo` (mode 0600) from `tripo login`. Never write a key into a project
`.env`. `tripo login` needs a real terminal — it exits 2 in non-interactive shells.

## Stay in GLB

Godot 4 imports GLB natively; FBX needs an external FBX2glTF binary. Tripo's native output is
already GLB, so **the correct action is to add no conversion step.**

Two traps that silently leave GLB: `--then convert:fbx` and `-p quad=true` (quads can't be
stored in GLB, so it forces FBX). `--for game-mobile` sounds right for this project but chains
a convert-to-FBX — don't use it; set the budget flags explicitly instead.

## Budgets: mobile + isometric

Use `--model tripo-p1` (the low-poly model) as the default. Starting points to tune against
real frame timings, not fixed law:

| asset | faces | note |
| --- | --- | --- |
| small prop (crate, barrel, rock) | 500–1500 | dozens on screen at once |
| large prop / structure | 2000–5000 | |
| character / vehicle | 4000–8000 | reads at ~100px tall; detail is wasted below that |

```bash
tripo make "a rusted cargo crate, stylized" --model tripo-p1 -p face_limit=1200 --json --yes
```

`tripo-p1` accepts face_limit 50–20000. For a high-fidelity source you want to reuse, generate
with `--for game-pc` and `--then decimate:N` (500–20000, bakes normals onto the low-poly by
default) — that keeps one authored source with cheap variants.

**The camera never sees the underside and rarely sees the back.** Detail budget belongs on the
top and upper sides. Judge every asset from a high angle, not head-on — a model that looks
right in a front view can read as flat or ambiguous from above, which is the only view that
ships. Silhouette-from-above is what distinguishes props at iso distance.

**Placement flags matter more here than in a free-camera game.** A `convert` step exposes
`--pivot-to-center-bottom` (assets sit on the ground plane without a per-asset offset in Godot)
and `--export-orientation`. If a batch of assets lands floating or rotated in Godot, fix it at
export rather than nudging transforms per scene.

Texture size is a `convert` argument, not a generation one; converting with `format=GLTF` is the
GLB-family path, but **confirm the emitted file extension on first use** before adopting it for
a batch. Prefer 512–1024 textures on mobile — 2K on a crate seen at 100px is wasted memory.

## Behavior that trips agents up

- **`tripo make` blocks** — it submits, polls, downloads, exits. Don't re-implement polling,
  don't set a timeout under 15 min, don't stop at the first `task_id` in the logs.
- **stdout is the contract**, stderr is commentary. With `--json` (auto-on when piped), stdout
  is exactly one final JSON line: `output_dir`, `model_file`, `preview`, `credits_consumed`.
- **Judge the result by reading `preview.png`.** Bad geometry → `tripo redo` for a new seed
  rather than re-writing the prompt.
- **Branch on exit codes**: 0 ok · 2 params · 3 auth · 4 credits · 5 content policy · 6 task
  failed (credits auto-refund) · 7 network · 9 rate limit.
- **Never invent parameters.** Unknown `-p key=value` pairs pass straight through to the API.
- **Don't pin `--model`** beyond the p1/v3.1 choice above; the CLI's default is current.

## Costs

Generation spends real credits. Check `tripo balance` before batch work. Exit 4 means the human
must run `tripo topup` — not something to retry around.
