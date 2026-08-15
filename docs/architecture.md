# Architecture

The detail behind §6 of CLAUDE.md — the core/game split, the command flow and the repository layout.

[back to CLAUDE.md](../CLAUDE.md)

The single most important structural rule:

> **`core/` contains the entire game. It does not import Godot node types and does not know a
> renderer exists.**

Everything under `core/` is plain data and functions: the board, the units, the rules, the turn
order. It can be run headless in a test with no scene tree. Everything under `game/` is Godot
scenes that *display* what `core/` decided.

This buys four things that are hard to retrofit: hot-seat fog correctness (visibility is a pure
function of state and active player, not of what happens to be on screen), a testable damage
model, replays, and — if online ever happens — a state model that is already deterministic and
serialisable.

**The flow of a player action:**

```
input → intent → Command → Rules.validate() → Rules.apply() → [BattleEvent] → view animates
```

- A `Command` is a value object (`MoveCommand`, `FireCommand`, `EngineerCommand`, `EndTurn`).
- `apply()` mutates `BattleState` and returns an ordered list of `BattleEvent`s
  (`UnitMoved`, `ShotFired`, `DamageDealt`, `UnitDestroyed`, `TileRevealed`, `MineTriggered`…).
- The view consumes events and plays them back over time. **The view never computes an outcome.**
  If a shell is in flight for 400 ms, the damage was already decided before it left the barrel.

**Events are not filtered per player, and that is a debt online would call in.** `apply()` returns
one ordered list describing everything that happened. In hot-seat this is harmless: one screen,
one active player, and the board is blanked at the handover. But some events carry information
their subject should not have — `MineTriggered` reveals that a mine existed to anyone replaying
the list, and the same will be true of anything that fires on an opponent's turn. If online ever
happens, the transport cannot broadcast this list as-is; it needs a per-observer filter, and the
place to build it is here in `core/`, not in the view. Keep that in mind when adding event types:
an event that only the acting player may see should be recognisable as such.

**Facing is a second leak, and a per-observer event filter will not close it.** An attack now turns
a unit whose owner is not playing, and the turn is still on the board afterwards — the leak is in
the state, not in the event. Three-player case: A fires on B's tank from ground C has never scouted;
B's tank turns to answer, and on C's turn that bearing points straight at a unit of A's that C
cannot see. Accepted for hot-seat v1. Online must filter facing as **state**, and not in the view —
the view cannot know whose turn a given facing came from.

**Determinism.** One `RandomNumberGenerator`, seeded per match and stored in `BattleState`. Every
roll goes through a single `Rules.roll()` helper. Never call the global `randi()` / `randf()`
anywhere in `core/`.

### Layout

```
project.godot
core/                    # pure rules — no Node, no scene tree, no rendering
  battle_state.gd
  board.gd
  unit.gd
  unit_types.gd          # the stat table — source of truth
  terrain.gd
  rules.gd               # damage, terrain cost, armour sector, the two distance metrics
  pathing.gd             # Dijkstra flood fill for the two movement zones
  vision.gd              # per-player visible/seen grids
  targeting.gd           # read-only queries behind the board overlays (§3.13)
  mines.gd
  objectives.gd
  experience.gd
  battle_serializer.gd
  commands/
  events.gd
game/                    # Godot scenes and nodes
  battle/                # board view, unit views, selection, zone overlay
  ui/                    # HUD, unit inspector, handover gate
  camera/                # fixed-angle rig: pan, clamped zoom
  fx/                    # weather, smoke, wrecks, impacts
  audio/
maps/
assets/
  models/ materials/ textures/ audio/
tests/                   # GUT specs against core/
tools/                   # map editor
docs/
```
