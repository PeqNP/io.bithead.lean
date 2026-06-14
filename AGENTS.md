# Agent Instructions — io.bithead.lean / FactoryFloor

This file is the single source of truth for AI agents working in this repository.
Read it in full at the start of every session. Treat it as both instructions and session memory.

---

## Project Overview

| Key | Value |
|---|---|
| Godot version | 4.6 |
| Project root | `~/source/io.bithead.lean/godot` |
| Export target | `~/source/boss/public/boss/app/io.bithead.lean/` |
| Export filename | `FactoryFloor.html` |
| Tile size | 64 px |
| Background | Solarized Light (`Palette.BG_0` = `#fdf6e3`) |

---

## Architecture

### BOSS Delegate pattern
- `BOSSDelegate` (base) → `WebBOSSDelegate` (browser) / `DummyBOSSDelegate` (editor)
- All JS/GDScript interop is confined to `WebBOSSDelegate.gd`
- `JavaScriptBridge` is only used inside `WebBOSSDelegate`

### BOSSBridge autoload
- Singleton at `autoload/BOSSBridge.gd`
- Signals: `snapshot_updated(snapshot: Dictionary)`, `error(message: String)`
- Methods: `configure(factory_id, base_url)`, `poll_snapshot()`, `post(path, body)`, `patch(path, body)`
- On `configure()`: stores ids, immediately calls `poll_snapshot()`
- Re-polls explicitly after every mutating GDScript call — no background timer

### Snapshot / entity rendering
- `FactoryFloor.gd` listens to `BOSSBridge.snapshot_updated` → calls `_render_entities(snapshot)`
- `_render_entities` keys entities as `"L_<id>"` (lines) and `"I_<id>"` (inventories) in `_entity_nodes` to prevent ID collisions between the two server tables
- `_find_entity(entity_id: int)` probes both `"L_<id>"` and `"I_<id>"`
- `_iq_to_line` maps intake-queue id (int) → line node; always cast JSON ids with `int()` before use as Dictionary keys

### Collision / placement
- Each entity (Line, Inventory) has a child `Area2D` with `RectangleShape2D` sized to exact pixel dimensions
  - `collision_layer = 1`, `collision_mask = 0`, `monitorable = true`, `monitoring = false`
- DragOverlay uses `PhysicsShapeQueryParameters2D` with `collide_with_areas = true`, `collide_with_bodies = false`
- GridManager is **deleted** — never re-introduce it; use Area2D physics queries for all placement checks

### Floor growth
- `FLOOR_EDGE_BUFFER = 5` tiles of empty space beyond the furthest entity
- `_process()` in FactoryFloor grows floor during drag by including ghost position via `DragOverlay.get_snap_tile()` + `get_ghost_pixel_size()`

### Conveyor belts
- Belt colors: `Palette.YELLOW_BELT` (Inventory→Station), `Palette.VIOLET_BELT` (Station↔Line), `Palette.CYAN_BELT` (Station→IntakeQueue)
- `connectsToIntakeQueue` id maps to the `id` field inside the target line's `intakeQueues` array — resolved via `_iq_to_line`
- `Conveyor.draw_static(from, to, parent)` — parent is last argument

---

## Palette (Solarized Light)

All colors live in `scripts/Palette.gd` (`class_name Palette`). No autoload needed — `class_name` makes constants globally accessible.

| Constant | Role |
|---|---|
| `BG_0` | Lightest background, floor fill, card hover |
| `BG_1` | Default card fill |
| `FG_0` | Muted / secondary text |
| `FG_1` | Primary text, borders |
| `BLUE` | Line border (focused), station border |
| `GREEN` | Inventory border (focused), output zone border |
| `BG_1_PANEL` | Semi-opaque panel background |
| `FG_1_GHOST` | Drag ghost outline |
| `GREEN_AVAIL` | Drag placement — available |
| `RED_OCCUPIED` | Drag placement — occupied |

Do not use raw `Color(r, g, b)` literals anywhere in `.gd` files. Always use `Palette.*`.

---

## GDScript Rules

### Variable shadowing — `c_` prefix
GDScript warns (error in strict mode) when a local variable shadows a Node built-in (`name`, `position`, `size`, `scale`, `rotation`, `visible`, `owner`, `type`, `data`, `id`). Prefix such locals with `c_`.

```gdscript
# Wrong
var name: String = str(data["name"])
# Correct
var c_name: String = str(data["name"])
```

### JSON ids must be cast to int
JSON parsing in Godot may return numeric values as `float`. Always cast before using as a Dictionary key or integer comparison:
```gdscript
var eid: int = int(json_dict.get("id", 0))
```

### `set_process` default is enabled
If `_process` accesses state that is only valid after an explicit `begin()`-style call, disable it in `_ready()` and re-enable in `begin()`.

### `mouse_filter` is Control-only
`Node2D` does not have `mouse_filter`. Use `input_pickable` instead.

### Hover detection on drawn Node2D
`mouse_entered`/`mouse_exited` require a physics body. Use `_input(event)` + `to_local()` + `Rect2.has_point()` instead.

### Data formatting
All dates, cycle times, and ETAs are formatted **server-side**. Godot displays strings as-is. No client-side formatting.

---

## Scene / Node Authoring Rules

### Components are scene files, not code-drawn widgets
Every reusable entity or card (Station, Hopper, IntakeQueue, Inventory, Line, etc.) must:
- Have its own `.tscn` scene file
- Use Godot node types (`Label`, `Button`, `VBoxContainer`, `HBoxContainer`, `Control`, etc.) for all visible elements
- **Never** draw labels, buttons, or text in `_draw()` or `draw_string()` calls

The only legitimate uses of `_draw()` are:
- Custom geometry (rectangles, lines, polygons) whose color comes from runtime/server data (e.g. per-station accent color)
- Conveyor belt chevrons

If you believe `draw_string` is necessary, **ask first**.

### Container layout conventions
- Name label + secondary info → `VBoxContainer`
- Action buttons side-by-side → `HBoxContainer` inside the `VBoxContainer`
- Use `size_flags_horizontal = 3` (EXPAND_FILL) on buttons to share width equally
- Use a `Control` spacer with `size_flags_vertical = 3` to push button rows to the bottom of a card

### Output zone
- The output zone border is drawn with `Palette.GREEN` at `BORDER_WIDTH` thickness — same as other entity borders
- The output zone is hidden entirely (no placeholder, no divider) when `hasOutput == false`
- `_compute_line_w()` omits `OUTPUT_W` when `hasOutput == false`

### Keyboard shortcuts
- Zoom in: `Cmd/Ctrl` + `=` or `+`
- Zoom out: `Cmd/Ctrl` + `-`
- Reset zoom (100%): `Cmd/Ctrl` + `0`
- Use `event.is_command_or_control_pressed()` — covers both macOS and Windows/Linux

### Drag position label
The `(x, y)` tile coordinate label during drag is drawn via `draw_string` in `DragOverlay._draw()`, positioned 4 px above the ghost's top-left corner. There is no `$PosLabel` node.

---

## Entity Quick Reference

| Entity | File | Area2D | Pixel size |
|---|---|---|---|
| Line | `scenes/entities/Line.tscn` | Yes | `_line_w × _line_h` (computed) |
| Inventory | `scenes/entities/Inventory.tscn` | Yes | `128 × 128` |
| Station | `scenes/entities/Station.tscn` | No (child of Line) | set by Line |
| Hopper | `scenes/entities/Hopper.tscn` | No (child of Line) | set by Line |
| IntakeQueue | `scenes/entities/IntakeQueue.tscn` | No (child of Line) | set by Line |

### Line tile width formula
```
tw = (6 if not hasOutput else 8) + n_stations * 3
```
Breakdown: intake(4) + hopper(2) + [output(2)] + each station(3)

### Line pixel height formula
```
raw_h = CONTENT_TOP + n_iq * 128 + (n_iq - 1) * 4 + 4
th = ceili(raw_h / 64.0)
```
Where `CONTENT_TOP = 60`, `n_iq = max(1, intakeQueues.size())`.

---

## File Structure

```
godot/
  autoload/
    BOSSBridge.gd              # HTTP singleton, snapshot polling
  scenes/
    FactoryFloor/
      FactoryFloor.tscn        # Main scene
      FactoryFloor.gd
      Background.gd            # Dot-grid background
    common/
      DragOverlay.tscn/.gd     # Drag-to-move ghost + placement check
      ErrorModal.tscn/.gd
      OperationPanel.tscn/.gd  # Create Line / Inventory toolbar
      ZoomSlider.tscn/.gd
    entities/
      Line.tscn/.gd
      Inventory.tscn/.gd
      Station.tscn/.gd
      Hopper.tscn/.gd
      IntakeQueue.tscn/.gd
      StationOverlay.tscn/.gd  # Scrollable WU/Ops panel
      WorkUnitCard.tscn/.gd
      InventoryStockPanel.tscn/.gd
  scripts/
    BOSSDelegate.gd
    WebBOSSDelegate.gd
    DummyBOSSDelegate.gd
    Conveyor.gd                # Animated chevron belt renderer
    Palette.gd                 # Solarized Light color constants
    Helpers.gd
  shaders/
    gray_out.gdshader          # Desaturate + 50% alpha (unfocused state)
```

---

## Fixture / Server

- Dev fixture: `server/web/Fixtures/Lean/factory-floor.json`
- Route: `GET /lean/factory-floor/:factoryId` (currently returns the fixture)
- Line and Inventory IDs are **not** globally unique — they come from separate DB tables and can collide. Always namespace them in Godot (`L_<id>` / `I_<id>`).
