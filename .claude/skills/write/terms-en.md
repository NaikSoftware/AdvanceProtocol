# English technical terms

Precise usage for docs, skills, `CLAUDE.md` and English identifiers. Sources: Google developer
style word list, Microsoft Style Guide, Godot docs and class reference, RFC 2119/8174, Fowler,
ISTQB. *[usage]* marks a project decision.

## Confused pairs

| pair | rule |
| --- | --- |
| parameter / argument | parameter = name in the declaration; argument = value at the call |
| method / function | every `func` in a script is a **method**; "function" for built-ins (`abs()`) and lambdas |
| property / member variable | Godot: **property** for engine and `@export` vars, **member variable** for script `var`s; avoid "field", "attribute" |
| annotation | `@export`, `@onready` are annotations, not attributes or decorators |
| deprecated / obsolete / removed | deprecated = still works, scheduled to go; never "deprecated" for something already removed |
| invalid / illegal | **invalid** move, **rejected** command; "illegal" implies a law |
| error / exception / failure | error = wrong state; failure = observed (a test fails); GDScript has no exceptions — never "throws" |
| validate / verify / check | validate = input satisfies the rules (`Rules.validate()`); verify = confirm a claim is true |
| deterministic / reproducible / idempotent | same seed + input → same output / someone else gets it again / applying twice = once. `Rules.apply()` is deterministic, not idempotent |
| constant / read-only / immutable | `const` / no setter / never changes after creation (GDScript can't guarantee it) |
| instance / instantiate | `PackedScene.instantiate()`; "instance" is never a verb (Godot 3 `instance()` is gone) |
| signal / event / callback / handler | signal = Godot observer (`emit`, `connect`); `BattleEvent` = project data; callback = a `Callable`; handler = the connected method |
| render / draw / display | renderer renders a frame; geometry is drawn (draw call); the player sees what is displayed |
| frame / tick / turn / step | `_process` iteration / physics tick / a player's turn / one tile of a walked move *[usage]* |
| frame time / FPS | budget in ms of frame time — it is linear; FPS = 1000 / frame time |
| edge case / corner case | one parameter at its limit / several at once |
| bug / regression | regression = worked before, broken now |
| refactor / rewrite / cleanup | refactor preserves behaviour; if behaviour changes, it is not a refactor |
| test / assertion | a test contains assertions (`assert_eq`) |
| stub / mock / fake / fixture | canned answers / verifies calls / working light implementation / fixed setup state |
| unit / integration / e2e | `core/` in isolation / modules together / through the real UI (`tests/e2e/`) |
| default / fallback | value when unspecified / what runs when the preferred option fails (`gl_compatibility`) |
| flag / option / setting | boolean or CLI switch / user choice / persisted configuration |
| asset / resource | asset = source file (GLB, PNG); `Resource` = Godot class (`.tres`, imported) |
| node / scene / packed scene | one object / a saved tree (`.tscn`) / the `PackedScene` you instantiate |
| autoload / singleton | write **autoload** — Godot does not make it a true singleton; "singleton" for `Engine`, `OS` |
| orthographic / isometric | the rig is an **orthographic camera with an isometric-style view** — 50–55° pitch is not true isometric (≈35.26°); enum `PROJECTION_ORTHOGONAL` |
| tile / cell | **tile** in rules and prose; "cell" only when quoting an API (`GridMap`) |
| seed / state | seed initialises the RNG; `state` is where it is now — saves store both (`core/battle_serializer.gd`) |

## Requirement words

Don't adopt RFC 2119 capitals in the rules docs — they read as shouting and drift. Instead:

- **Invariant:** a declarative present-tense statement, plus the test that enforces it —
  "`front >= side >= rear` for every unit." Bold **must** / **never** in lowercase, as `CLAUDE.md` does.
- **Recommendation:** "prefer", "should" + the reason.
- **Permission:** "may".
- Never "should" when you mean "must".

## Godot names, exactly

- API in code font with Godot's capitalisation: `Node3D`, `SceneTree`, `PackedScene`, `Resource`,
  `Tween`, `AnimationPlayer`, `MeshInstance3D`, `Camera3D`, `Viewport`, `LightmapGI`,
  `RandomNumberGenerator`, `Callable`.
- Concepts lowercase in prose: scene tree, viewport, autoload, lightmap baking, draw calls, LOD
  (level of detail), low-processor mode (`application/run/low_processor_mode`).
- `_process(delta)` runs every frame, `_physics_process(delta)` every physics tick. There is no
  "idle frame" in Godot 4 — that is Godot 3 vocabulary.
- "emit a signal", "connect a signal to a method"; code `pressed.emit()`, `pressed.connect(...)`.
- "Typed GDScript" or "static typing"; `class_name`, `@export`.
- **GUT** (Godot Unit Test), always uppercase.

## Wargame vocabulary

| term | meaning here |
| --- | --- |
| hot-seat | players share one device (the project's word; "pass-and-play" is the synonym) |
| fog of war | hidden enemy units and mines (§3.5) |
| vision range / vision diamond | how far a unit sees — **not** "line of sight": nothing blocks sight here |
| field of view | not used — there is no view cone |
| zone of control | not used — the game has none |
| facing | the direction a unit points (8 directions) |
| flanking | hitting the side or rear sector |
| armour sector | front / side / rear; no "hull" vs "turret" — the whole unit turns |
| retaliation | automatic return fire within the same exchange (§3.3.1); not "counterattack" |
| scouted / in sight | `seen` (permanent) / `visible` (now) |
| damage roll | the random part of damage, through `Rules.roll()` |
| seeded match | one RNG per match, seeded at start |

## Words to replace

utilize → use · leverage → use · functionality → feature, behaviour · in order to → to ·
performant → fast, or the number · via → through, by · once (= after) → after ·
since (= because) → because · execute → run · abort, kill → stop, cancel ·
sanity check → quick check · e.g. / i.e. → for example / that is · etc. (in a spec) → the full list ·
whitelist / blacklist → allowlist / denylist · "handle", "manage", "process" with no object →
name the action: rejects, retries, logs.
