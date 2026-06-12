# Lean FactoryFloor — Godot Implementation Plan

## Decisions Log

| Decision | Value |
|---|---|
| Godot version | 4.6 |
| Project root | `~/source/io.bithead.lean/godot` |
| Export target | `~/source/boss/public/boss/app/io.bithead.lean/` |
| Export main filename | `FactoryFloor.html` |
| BOSS controller key | `FactoryFloor` with `godot.main: "FactoryFloor.html"` |
| Tile size | 64 px |
| Default Line footprint | 12 tiles wide × 2 tiles tall |
| Default Line tile breakdown | Intake queue: 4 tiles, Hopper: 2 tiles, Station: 4 tiles, Output: 2 tiles |
| Floor growth trigger | Any item within 4 tiles of right/bottom edge → add 4 tile buffer |
| Snapshot delivery | Godot polls `GET /lean/factory-floor/:factoryId` (also re-polls after every mutating command) |
| Mutating commands | GDScript `HTTPClient` → BOSS HTTP routes directly |
| Configure handoff | BOSS JS calls `controller.send({name: "configure", data: {factoryId, baseUrl}})` after iframe `onload` |
| Overlay exclusivity | Per-line: at most one overlay (Work Units or Operations) open across all stations within a given Line |
| Gray-out style | Shader: desaturate + 50% alpha |
| Background | `#1a1a2e` dark with subtle dot-grid overlay |
| Conveyors | Animated chevron belts from Layer 1 |
| Node outlines | Thick (3–4 px) solid outline on all Line and Inventory nodes |
| Data formatting | All dates, cycle times, and ETAs are formatted **server-side**. Godot displays strings as-is from the snapshot. No client-side formatting logic. |

---

## GDScript Coding Conventions

### Variable shadowing — `c_` prefix

GDScript raises a warning (treated as error in strict mode) when a local variable shadows a built-in property of a base class (e.g. `name` shadows `Node.name`, `position` shadows `Node2D.position`).

**Rule:** Any local variable whose identifier would shadow a GDScript or Node built-in must be prefixed with `c_` (short for "custom").

```gdscript
# Wrong — shadows Node.name
var name: String = str(cmd["name"])

# Correct
var c_name: String = str(cmd["name"])
```

Common built-ins to watch for: `name`, `position`, `size`, `scale`, `rotation`, `visible`, `owner`, `type`, `data`, `id`.

### `mouse_filter` is a `Control`-only property

`Node2D` does not have `mouse_filter`. Do not set it. `Node2D` input pickable state is controlled by `input_pickable` (default `true`).

### `mouse_entered` / `mouse_exited` signals on `Node2D`

These signals on `Node2D` require a physics body or collision shape to fire. For drawn nodes (pure `_draw()` rendering), use `_input(event: InputEvent)` instead:

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        var local := to_local(get_viewport().get_mouse_position())
        var inside := Rect2(0, 0, WIDTH, HEIGHT).has_point(local)
        if inside != _hovered:
            _set_hovered(inside)
```

### `set_process` default is enabled

All `Node` subclasses have `_process` enabled by default. If a node's `_process` accesses state that is only valid after an explicit `begin()`-style setup call, disable processing in `_ready()` and re-enable in `begin()`:

```gdscript
func _ready() -> void:
    set_process(false)

func begin(...) -> void:
    # set up state
    set_process(true)
```

### `Conveyor.draw_static` argument order

Signature is `draw_static(from: Vector2, to: Vector2, parent: Node2D)`. The parent node is the **last** argument, not the first.

---

## Project File Structure

```
godot/
  project.godot
  export_presets.cfg
  autoload/
    BOSSBridge.gd            # Singleton: HTTP, snapshot polling, configure handler
  scenes/
    FactoryFloor/
      FactoryFloor.tscn      # Main scene root
      FactoryFloor.gd
    common/
      ErrorModal.tscn
      ErrorModal.gd
      OperationPanel.tscn    # Toolbox (Layer 2+)
      OperationPanel.gd
      DragOverlay.tscn       # Layer 3: drag-to-move tile highlight
      DragOverlay.gd
      ZoomSlider.tscn        # Layer 3: fixed top-right zoom buttons
      ZoomSlider.gd
    entities/
      Line.tscn
      Line.gd
      Inventory.tscn
      Inventory.gd
      IntakeQueue.tscn       # Layer 4+
      IntakeQueue.gd
      Hopper.tscn            # Layer 4+
      Hopper.gd
      Station.tscn           # Layer 5+
      Station.gd
  shaders/
    gray_out.gdshader        # Desaturate + alpha
  scripts/
    GridManager.gd           # Logical grid, occupation, growth
    Conveyor.gd              # Animated chevron belt drawing
```

---

## Layer 0 — Foundation & Infrastructure

**Goal:** A bootable, empty scene that communicates with BOSS and handles configuration. No entities rendered.

### Files to create

| File | Purpose |
|---|---|
| `project.godot` | Project config; sets `BOSSBridge` as autoload; main scene = `FactoryFloor.tscn` |
| `autoload/BOSSBridge.gd` | Singleton: HTTPClient wrapper, polling loop, signal `snapshot_updated(data)`, `error(msg)` signal, `configure(factoryId, baseUrl)` method |
| `scenes/FactoryFloor/FactoryFloor.tscn` | Root `Node2D`; `Camera2D` child; `CanvasLayer` for UI (ErrorModal) |
| `scenes/FactoryFloor/FactoryFloor.gd` | Listens to `BOSSBridge.snapshot_updated`; listens to `BOSSBridge.error`; wires `window.boss` on `_ready` |
| `scenes/common/ErrorModal.tscn` | Popup with title label, description label, OK button; hidden by default |
| `scenes/common/ErrorModal.gd` | `show(title, description)` method; OK closes it |
| `scripts/GridManager.gd` | Dictionary of occupied `(x, y)` → entity id; `is_available(x, y, w, h)`, `occupy(x, y, w, h, id)`, `free(id)`, `get_first_available(w, h)`, `grow_if_needed(x, y)` |
| `shaders/gray_out.gdshader` | Fragment shader: desaturate (luminance) + multiply alpha by 0.5 |

### BOSSBridge detail

```
Signals:
  snapshot_updated(snapshot: Dictionary)
  error(message: String)

Methods:
  configure(factory_id: int, base_url: String)
  poll_snapshot()       # GET /lean/factory-floor/:factory_id → emits snapshot_updated
  post(path, body)      # Returns response dict or emits error
  patch(path, body)
```

- On `configure()`: store `factory_id` and `base_url`, immediately call `poll_snapshot()`.
- On HTTP error: emit `error(message)` → FactoryFloor shows ErrorModal.
- Polling: after `configure`, re-poll on a timer only if no command is in-flight (keep it simple — no timer in early layers; poll explicitly after each mutating call).

### BOSS bridge wiring (FactoryFloor.gd `_ready`)

```
1. JavaScriptBridge: get window.boss
2. If present: store as _delegate; create _send_callback; assign _delegate.send = _send_callback
3. _on_boss_send handles {name: "configure", data: {factoryId, baseUrl}}
4. On configure: call BOSSBridge.configure(factory_id, base_url)
```

### Camera2D

- 4 discrete zoom levels: `[Vector2(1,1), Vector2(0.75,0.75), Vector2(0.5,0.5), Vector2(0.25,0.25)]`
- Default: `Vector2(1,1)`
- Clamp camera position to current floor bounds (`GridManager.bounds_world()`)
- Pan: middle-mouse drag or two-finger scroll
- Zoom: scroll wheel or discrete UI buttons (added Layer 3)

### Verification checklist

- [ ] Project opens in Godot editor without errors
- [ ] Run in browser → dark `#1a1a2e` background visible
- [ ] `BOSSBridge.configure(1, "http://localhost:8080")` called from GDScript console → HTTP request fires (check browser network tab)
- [ ] Simulated HTTP error → ErrorModal appears with message, OK closes it
- [ ] `GridManager.get_first_available(12, 2)` returns `(0, 0)` on empty grid
- [ ] `GridManager.occupy(0, 0, 12, 2, 1)` then `is_available(0, 0, 1, 1)` returns `false`

---

## Layer 1 — Static Factory Floor + Entities

**Goal:** Receive a real (or fixture) snapshot and render Line and Inventory nodes at their grid positions. No interaction. Full Shapez 2 aesthetic.

**Depends on:** Layer 0.

### New files

| File | Purpose |
|---|---|
| `scenes/entities/Line.tscn` | `Node2D` with `Sprite2D`/`NinePatchRect` body, name `Label`, thick outline; children: IntakeQueuesContainer, HopperContainer, StationsContainer, OutputContainer |
| `scenes/entities/Line.gd` | `configure(data: Dictionary)` populates labels; `update(data)` for reconciliation |
| `scenes/entities/Inventory.tscn` | `Node2D` body; name `Label`; health color strip |
| `scenes/entities/Inventory.gd` | `configure(data: Dictionary)` |
| `scripts/Conveyor.gd` | `draw_chevron(from: Vector2, to: Vector2, container: Node2D)` — creates animated belt; autoloaded or instanced |

### Rendering rules

- `FactoryFloor.gd` on `snapshot_updated`: clear all Line/Inventory children; instance fresh from snapshot. (Reconciliation by id comes in Layer 7.)
- Line world position: `Vector2(gridX * 64, gridY * 64)`
- Line size: `12 * 64` px wide, `2 * 64` px tall (constant until stations are added in Layer 5)
- Inventory world position: `Vector2(gridX * 64, gridY * 64)`
- Inventory size: `2 * 64` wide, `2 * 64` tall

### Shapez 2 aesthetic (mandatory from this layer)

- Background: `ColorRect` covering floor, color `#1a1a2e`
- Dot-grid: `CanvasItem._draw()` on a background `Node2D`; draw circles radius 1 px at every 64 px intersection, color `#2a2a4a`
- Line node: fill `#2a2a5a`, border `#5a5aaa`, stroke width 3 px
- Inventory node: fill `#2a5a2a`, border `#5aaa5a`, stroke width 3 px
- Labels: white, `font_size` 11 px

### Internal conveyor (stub — static line only)

Draw a static line from the center-right of each internal component to the center-left of the next (IntakeQueue → Hopper → Station → Output). Animated chevrons come after the static version is verified.

### Verification checklist

- [ ] Load fixture `factory-floor.json` → correct number of Line and Inventory nodes appear
- [ ] Lines positioned at correct grid coordinates
- [ ] No two items overlap (grid correctly reports occupied tiles)
- [ ] Line with 0 stations/intake queues renders without crash
- [ ] `subAssemblyLine: true` lines render (no output section)
- [ ] Dark background + dot-grid visible
- [ ] Thick outlines on all nodes

---

## Layer 2 — Operation Panel + Create Flows

**Goal:** Add new Lines and Inventories from within Godot. Floor grows as needed.

**Depends on:** Layer 1.

### New files

| File | Purpose |
|---|---|
| `scenes/common/OperationPanel.tscn` | Fixed-position `CanvasLayer` (not affected by camera zoom); vertical button column top-left |
| `scenes/common/OperationPanel.gd` | Emits `create_line_pressed`, `create_inventory_pressed`; Operator submenu (stubs) |

### Flows

**Create Line:**
1. Button pressed → `BOSSBridge.post("/lean/line", {factoryId})` → returns `Fragment.Option` (id + name)
2. Find `GridManager.get_first_available(12, 2)` — if none, show ErrorModal "No space available"
3. Occupy tiles, instance `Line.tscn` at position
4. Re-poll snapshot to get full line data
5. Camera scrolls to new line if off-screen

**Create Inventory:**
1. Same flow, size `2 × 2` tiles, route `POST /lean/inventory`

**Disable buttons while in-flight:**
- Disable both Create buttons while any HTTP request is pending; re-enable on response

### Verification checklist

- [ ] Click Create Line → Line appears at first available position
- [ ] Floor grows if line would land near edge
- [ ] Click Create Inventory → Inventory appears
- [ ] Rapid double-click does not send two requests
- [ ] BOSS error on create → ErrorModal with message from server
- [ ] Operator submenu appears (stubs — no crash)

---

## Layer 3 — Core Interaction: Move, Focus, Lock, Zoom

**Goal:** Primary manipulation of top-level items.

**Depends on:** Layer 2.

### Hover controls (shown on mouse-enter, hidden on mouse-exit)

Each Line/Inventory node shows a control bar on hover containing:
- **Move** button — initiates drag flow (disabled when locked)
- **Focus/Unfocus** toggle button
- **Lock/Unlock** toggle button

Hover detection: `Node2D` does not have `mouse_entered`/`mouse_exited`. Instead, `_input(event)` checks `InputEventMouseMotion`, converts viewport mouse position to local space with `to_local()`, and tests against the entity's bounding rect.

### Move

- Drag initiated via Move button; `move_requested(entity, tile_w, tile_h)` signal emitted to `FactoryFloor`
- `DragOverlay` scene handles visual feedback (world-space `Node2D`, `z_index = 100`):
  - Ghost rect + per-tile green (available) / red (occupied) highlight
  - Live `(X, Y)` position label
  - `_process` disabled by default; enabled in `begin()`, disabled in `end()`
  - Each frame: temporarily `free_entity` + re-`occupy` at preview tile to keep grid state consistent for availability checks
- Left-click confirms; right-click cancels
- On confirm: `BOSSBridge.patch("/lean/line/:id/position", {x, y})` (or `/lean/inventory/:id/position`)
- On cancel: grid restored to original entity position

### Focus

- Toggle `_focused` state locally; entity's border/fill color changes immediately
- `focus_toggled(entity_id, focused)` signal emitted to `FactoryFloor`
- `FactoryFloor._on_focus_toggled`: persists via `BOSSBridge.patch("…/focused", {focused})`; scans all entities for any `_focused == true`; applies `gray_out` shader to all non-focused entities via `set_grayed(true/false)`
- Connected items (Layer 6): for now, gray everything not directly focused

### Lock

- Toggle `_locked` locally; Move button disabled immediately
- `lock_toggled(entity_id, locked)` signal emitted to `FactoryFloor`
- `FactoryFloor._on_lock_toggled`: persists via `BOSSBridge.patch("…/locked", {locked})`

### Zoom slider

- `ZoomSlider` is a `CanvasLayer` (layer 15), anchored top-right, 4 toggle buttons
- On press: emits `zoom_changed(index)` → `FactoryFloor.set_zoom(index)`
- After clamping: slider synced back with `set_index(_zoom_index)` to reflect actual applied zoom

### Verification checklist

- [x] Hover → controls appear; mouse-exit → controls hide
- [ ] Move line to valid position → confirmed on re-poll
- [ ] Move to occupied position → reverts (right-click cancel)
- [ ] Lock prevents move (Move button disabled)
- [ ] Focus grays unfocused items via shader
- [x] Zoom slider changes Camera2D zoom
- [x] Camera clamps to floor bounds at all zoom levels

---

## Layer 4 — Line Internals: Intake Queues, Hopper, Conveyors

**Goal:** Render intake queues and hopper work unit inside a Line. Draw animated conveyors.

**Depends on:** Layer 3.

### New files

| File | Purpose |
|---|---|
| `scenes/entities/IntakeQueue.tscn` | 4×2-tile card: name label, `Cycle: X` label, color strip |
| `scenes/entities/IntakeQueue.gd` | `configure(data)` |
| `scenes/entities/Hopper.tscn` | 2×2-tile card; work unit card if `hopperWorkUnit` present |
| `scenes/entities/Hopper.gd` | `configure(data, intake_queue_colors)` |

### Inside Line

- `Line.gd.configure()` instances IntakeQueue nodes + Hopper node from snapshot data
- Color map: each IntakeQueue gets a unique color (same palette logic as FactoryFloor.html)
- Hopper: if `hopperWorkUnit` present → show name, ETA (`format_eta`), Start button
  - Start button → `BOSSBridge.post("/lean/start-work-unit", {id})` → re-poll
- Add intake queue: `+` button at end of intake group → JB stub for now

### Animated chevron conveyors

Replace static lines with `Conveyor.gd` animated belts:
- Each belt is a series of chevron shapes moving from source → destination at `ANIM_SPEED` px/s
- Colors: internal conveyor = muted teal; inventory belt = different color (Layer 6)
- Route: IntakeQueue center-right → Hopper center-left; Hopper center-right → first Station center-left (Layer 5); last Station center-right → Output center-left

### Verification checklist

- [ ] Line with 2 intake queues shows 2 IntakeQueue nodes, correctly colored
- [ ] Hopper with work unit shows name + ETA + Start button
- [ ] Start button → work unit disappears from hopper, re-poll confirms move
- [ ] 0 intake queues → IntakeQueues container visible with add button, no crash
- [ ] Animated conveyors run at consistent speed
- [ ] Conveyor redraws after adding intake queue

---

## Layer 5 — Stations + Work Unit / Operations Overlays

**Goal:** Render stations inside a Line; open Work Units and Operations overlays.

**Depends on:** Layer 4.

### New files

| File | Purpose |
|---|---|
| `scenes/entities/Station.tscn` | 4×2-tile card: name, `Cycle: X`, two toggle buttons (Work Units / Operations), optional subassembly color strip |
| `scenes/entities/Station.gd` | `configure(data, index)`, overlay toggle logic, per-line exclusivity |

### Overlay rules

- Each Line tracks `active_overlay_station_id` and `active_overlay_type` (`:work_units` or `:operations`)
- Opening an overlay on station A closes any existing overlay within the same Line
- Different Lines are fully independent

### Work Units overlay

- Slides down below Station node
- Scrollable list; show scroll arrows when >5 items
- Per work unit card: name, avatar initials, `format_cycle_time(cycleTime)`, `format_eta(eta)`, progress bar (`completedOperations / totalOperations`)
- Hover → Edit (JB stub), Done button
  - Done → `BOSSBridge.post("/lean/work-unit/:id/move-to-next-station")` → re-poll
  - Prevent Done if operations incomplete (check `completedOperations < totalOperations`)

### Operations overlay

- Same slide-down behavior
- Per operation card: name, work unit count, cycle time
- Hover → Edit (JB stub)

### Station drag / reorder

- First station is locked in position (move handle grayed)
- Other stations: drag left/right within the line's station container
  - Drop position calculated from center-x of drag target
  - `BOSSBridge.patch("/lean/station/:id/position", {position: newIndex})` → re-poll
- Conveyors update on any station add/remove/reorder

### Add station

- `+` buttons: before first, between each pair, after last
- → `BOSSBridge.post("/lean/station", {lineId, position})` → re-poll

### Verification checklist

- [ ] Station cards render with correct names and cycle times
- [ ] Work Units overlay opens; Done moves work unit (confirmed via re-poll)
- [ ] Operations overlay opens on same station; Work Units closes
- [ ] Overlays on two different Lines can be open simultaneously
- [ ] Cannot Done a work unit with incomplete operations
- [ ] First station move handle is disabled
- [ ] Reordering stations updates conveyor routing
- [ ] Add station at position 2 → server shifts others, re-poll shows correct order

---

## Layer 6 — Inventory Connections + Subassembly Belts

**Goal:** Draw cross-entity conveyors; complete focus propagation.

**Depends on:** Layer 5.

### Inventory → Station belts

- For each `station.connectsToInventory`: draw a belt from `Inventory` node's center-right to `Station` node's center-left
- Belt style: distinct color (e.g. amber) to differentiate from internal belts
- `Inventory` expand button: slides open table (cycleStock, bufferStock, safetyStock, reorderPoint, estimatedReorderDate, health color)

### Subassembly belts

- For each `station.connectsToLine`:
  - Forward belt: from source Station top-left → target Line's first IntakeQueue center-left
  - Return belt: from target Line's output center-right → source Station top-right
  - Distinct style (e.g. purple, wider)

### Focus propagation update

- When a Line is focused: also keep full opacity on:
  - All Inventory nodes that supply any station in that line (`connectsToInventory`)
  - All Lines connected via `connectsToLine` in either direction

### Verification checklist

- [ ] Inventory → Station belt appears when `connectsToInventory` is set
- [ ] Inventory expand shows stock table
- [ ] Subassembly forward + return belts drawn correctly
- [ ] Focus on a line keeps its connected subassembly and inventory full opacity
- [ ] Inventory supplying two stations → two belts

---

## Layer 7 — Production Polish & Real-time Sync

**Goal:** Production-ready: per-node reconciliation, performance, all stubs wired.

**Depends on:** All prior.

### Snapshot reconciliation

- On `snapshot_updated`: diff by `id` instead of clear + rebuild
  - New id → instance and add
  - Removed id → remove and free
  - Existing id → call `update(data)` on node (only re-render changed fields)
- Prevents camera/overlay state loss on re-poll

### HTTP polling timer

- After initial configure: poll every N seconds (configurable; start at 5 s)
- Suppress timer-triggered poll if a command is in-flight (re-poll on command completion instead)

### Performance

- Cull conveyor segments outside camera viewport
- At zoom ≤ 0.5: hide per-work-unit cards (show counts only)
- At zoom ≤ 0.25: hide station/intake-queue labels

### Remaining stubs to wire

- Edit Line → load BOSS controller `Line`
- Edit Station → load BOSS controller (TBD)
- Edit Work Unit → load BOSS controller (TBD)
- Add Work Unit to Intake Queue → `POST /lean/work-unit`
- Operator Add / Operator List → `POST /lean/operator` / `GET /lean/operators`
- Work Unit on-hold toggle

### Viewport persistence

- On camera move/zoom: save `{position, zoom}` to `window.localStorage` keyed by `factoryId`
- On `_ready`: restore if present

### Verification checklist

- [ ] Rapid re-polls do not cause flicker or entity duplication
- [ ] Open Work Units overlay → re-poll → overlay remains open, data refreshes
- [ ] 50+ stations/lines render at 60 fps (browser performance tab)
- [ ] Zoom to 25% → labels hidden, performance stable
- [ ] Camera position/zoom restored after page refresh

---

## BOSS App Bundle Changes (in `io.bithead.lean`)

These changes are made in the BOSS project, not the Godot project.

### `application.json` — add FactoryFloor controller entry

```json
"FactoryFloor": {
    "godot": {
        "title": "Factory Floor",
        "main": "FactoryFloor.html"
    }
}
```

### `controller/FactoryFloor.html` — replace current Pixi implementation

- Follows `io.bithead.boss/controller/Godot.html` pattern exactly
- `configure(factoryId)` stored; on iframe `onload`: `container.contentWindow.boss = controller`
- Controller's `send()` method called after configure with `{name: "configure", data: {factoryId, baseUrl: window.location.origin}}`
- Controller's `receive(ev)` handles events from Godot (e.g. future deep-link navigation)

### `controller/Godot.js` — app-side GodotController

```
GodotController.receive(ev):
  if ev.name == "navigate": load appropriate BOSS controller
  else: log unknown event
```

### Export workflow

```
1. In Godot: Project → Export → Web → Export to:
   ~/source/boss/public/boss/app/io.bithead.lean/FactoryFloor.html
2. BOSS serves the file at /boss/app/io.bithead.lean/FactoryFloor.html
```

---

## Layer Execution Order

```
Layer 0 → verify → Layer 1 → verify → Layer 2 → verify →
Layer 3 → verify → Layer 4 → verify → Layer 5 → verify →
Layer 6 → verify → Layer 7
```

Do not advance to the next layer until all verification checkboxes for the current layer are checked.

## Implementation Principles

- **Prefer built-in Godot node types** before building custom logic. Use `Area2D + CollisionShape2D` for collision/overlap detection, `PhysicsShapeQueryParameters2D` for placement queries, `CharacterBody2D`/`StaticBody2D` for physics bodies, `AnimationPlayer` for sequenced animations, etc. Only write custom code when no Godot built-in adequately covers the requirement.
