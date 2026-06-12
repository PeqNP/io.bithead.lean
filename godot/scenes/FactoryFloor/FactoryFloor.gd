## Copyright © 2026 Bithead LLC. All rights reserved.

## FactoryFloor — main scene root.
##
## Layer 0: BOSS JS bridge, camera, error modal.
## Layer 1: Render Line and Inventory entities from snapshot.
## Layer 2: OperationPanel — Create Line / Create Inventory flows.
## Layer 3: Hover controls, drag-to-move, focus/gray-out, lock, zoom slider.
## Layer 6: Cross-entity belts (Inventory→Station amber, subassembly purple), focus propagation.

extends Node2D

const TILE_SIZE := 64
const PAN_SPEED  := 2.0   # pan multiplier — increase for faster scrolling
const ZOOM_LEVELS: Array[Vector2] = [
	Vector2(1.0,  1.0),
	Vector2(0.75, 0.75),
	Vector2(0.5,  0.5),
	Vector2(0.25, 0.25),
]

const LINE_SCENE         := preload("res://scenes/entities/Line.tscn")
const INVENTORY_SCENE    := preload("res://scenes/entities/Inventory.tscn")
const DRAG_OVERLAY_SCENE := preload("res://scenes/common/DragOverlay.tscn")
const ZOOM_SLIDER_SCENE  := preload("res://scenes/common/ZoomSlider.tscn")

var _zoom_index: int = 0

# Layer 3 state.
var _drag_overlay: Node2D = null
var _drag_entity: Node2D = null       # entity currently being dragged
var _drag_entity_id: int = 0
var _drag_tile_w: int = 0
var _drag_tile_h: int = 0
var _focus_active: bool = false       # true when any entity is focused
var _zoom_slider: CanvasLayer = null

# Layer 6: last received snapshot (used by belt rendering and focus propagation).
var _snapshot: Dictionary = {}

# Layer 7: live map of entity_id → Node2D for O(1) lookup and reconciliation.
var _entity_nodes: Dictionary = {}

# Grid manager — owns tile occupation state.
var grid: GridManager = GridManager.new()

# BOSS delegate — WebBOSSDelegate in browser, DummyBOSSDelegate in editor.
var _boss: BOSSDelegate

@onready var _camera:      Camera2D    = $Camera2D
@onready var _error_modal: CanvasLayer  = $ErrorModal/ErrorModal
@onready var _bg:          Node2D      = $Background
@onready var _panel:       CanvasLayer = $OperationPanel
@onready var _belt_layer:  Node2D      = $BeltLayer

func is_web() -> bool:
	return OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")

func _ready() -> void:
	BOSSBridge.snapshot_updated.connect(_on_snapshot_updated)
	BOSSBridge.error.connect(_on_boss_error)
	grid.floor_grew.connect(_on_floor_grew)

	_update_camera_limits()

	_panel.create_line_pressed.connect(_on_create_line)
	_panel.create_inventory_pressed.connect(_on_create_inventory)

	# Layer 3: drag overlay (added to Entities so it tracks world space).
	_drag_overlay = DRAG_OVERLAY_SCENE.instantiate()
	$Entities.add_child(_drag_overlay)

	# Layer 3: zoom slider fixed top-right.
	_zoom_slider = ZOOM_SLIDER_SCENE.instantiate()
	add_child(_zoom_slider)
	_zoom_slider.zoom_changed.connect(_on_zoom_slider_changed)

	if is_web():
		_boss = WebBOSSDelegate.new()
	else:
		_boss = DummyBOSSDelegate.new()
	await _boss.ready(_on_boss_command)


# ---------------------------------------------------------------------------
# BOSS delegate command handler
# ---------------------------------------------------------------------------

func _on_boss_command(c_name: String, data: Dictionary) -> void:
	match c_name:
		"configure":
			BOSSBridge.configure(data.get("factoryId", 0), data.get("baseUrl", ""))
			_restore_viewport()
		_:
			push_warning("FactoryFloor: unknown BOSS command '%s'" % c_name)


# ---------------------------------------------------------------------------
# BOSSBridge signals
# ---------------------------------------------------------------------------

func _on_snapshot_updated(snapshot: Dictionary) -> void:
	_render_entities(snapshot)


func _render_entities(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	var entities := $Entities

	# Build incoming map: entity_id → {data, tile_w, tile_h}.
	var incoming: Dictionary = {}
	for line_data: Dictionary in (snapshot.get("lines", []) as Array):
		incoming[line_data.get("id", 0)] = {"data": line_data, "tw": 12, "th": 2}
	for inv_data: Dictionary in (snapshot.get("inventories", []) as Array):
		incoming[inv_data.get("id", 0)] = {"data": inv_data, "tw": 2, "th": 2}

	# Remove entities no longer in the snapshot.
	var stale: Array = []
	for eid in _entity_nodes:
		if not incoming.has(eid):
			stale.append(eid)
	for eid in stale:
		grid.free_entity(eid)
		_entity_nodes[eid].queue_free()
		_entity_nodes.erase(eid)

	# Add new entities and update existing ones.
	for eid in incoming:
		var info: Dictionary = incoming[eid]
		var c_data: Dictionary = info["data"]
		var tw: int = info["tw"]
		var th: int = info["th"]
		var gx: int = c_data.get("gridX", 0)
		var gy: int = c_data.get("gridY", 0)

		if _entity_nodes.has(eid):
			# Update existing — re-occupy grid only if position changed.
			var node: Node2D = _entity_nodes[eid]
			var old_x := int(node.position.x) / TILE_SIZE
			var old_y := int(node.position.y) / TILE_SIZE
			if old_x != gx or old_y != gy:
				grid.free_entity(eid)
				grid.occupy(gx, gy, tw, th, eid)
			node.update(c_data)
		else:
			# Create new node.
			var node: Node2D
			if tw == 12:
				node = LINE_SCENE.instantiate()
			else:
				node = INVENTORY_SCENE.instantiate()
			entities.add_child(node)
			node.configure(c_data)
			node.set_zoom_index(_zoom_index)
			_wire_entity_signals(node, tw, th)
			grid.occupy(gx, gy, tw, th, eid)
			_entity_nodes[eid] = node

	_update_camera_limits()
	_bg.floor_width_tiles  = grid.width_tiles
	_bg.floor_height_tiles = grid.height_tiles
	_bg.queue_redraw()
	_render_belts()


func _on_boss_error(message: String) -> void:
	_error_modal.show_error("Error", message)


func _on_floor_grew(_new_w: int, _new_h: int) -> void:
	_update_camera_limits()
	_bg.queue_redraw()


# ---------------------------------------------------------------------------
# Layer 2: Create flows
# ---------------------------------------------------------------------------

func _on_create_line() -> void:
	# Tell BOSS to open the CreateFactoryModel window for a new line.
	_boss.receive("open-window", {
		"controller": "CreateFactoryModel",
		"parameters": ["line", BOSSBridge.factory_id],
	})
	# Temporarily add a placeholder line to the floor while BOSS processes the request.
	# This will be replaced when the snapshot is next updated.
	_add_placeholder_line()


func _on_create_inventory() -> void:
	# Tell BOSS to open the CreateFactoryModel window for a new inventory.
	_boss.receive("open-window", {
		"controller": "CreateFactoryModel",
		"parameters": ["inventory", BOSSBridge.factory_id],
	})
	# Temporarily add a placeholder inventory to the floor.
	_add_placeholder_inventory()


## Add a temporary placeholder Line at the first available grid position.
## Uses a negative id so it won't collide with server-assigned ids.
var _next_placeholder_id: int = -1

func _add_placeholder_line() -> void:
	var pos: Vector2i = grid.get_first_available(12, 2)
	if pos == Vector2i(-1, -1):
		return
	var data := {
		"id": _next_placeholder_id,
		"gridX": pos.x,
		"gridY": pos.y,
		"name": "New Line",
		"locked": false,
		"hasOutput": true,
		"subAssemblyLine": false,
		"intakeQueues": [],
		"stations": [],
		"hopperWorkUnit": null
	}
	_next_placeholder_id -= 1
	var node: Node2D = LINE_SCENE.instantiate()
	$Entities.add_child(node)
	node.configure(data)
	node.set_zoom_index(_zoom_index)
	_wire_entity_signals(node, 12, 2)
	grid.occupy(pos.x, pos.y, 12, 2, data["id"])
	_entity_nodes[data["id"]] = node
	_scroll_camera_to_tile(pos)


func _add_placeholder_inventory() -> void:
	var pos: Vector2i = grid.get_first_available(2, 2)
	if pos == Vector2i(-1, -1):
		return
	var data := {
		"id": _next_placeholder_id,
		"gridX": pos.x,
		"gridY": pos.y,
		"name": "New Inventory",
		"locked": false,
		"health": 0
	}
	_next_placeholder_id -= 1
	var node: Node2D = INVENTORY_SCENE.instantiate()
	$Entities.add_child(node)
	node.configure(data)
	node.set_zoom_index(_zoom_index)
	_wire_entity_signals(node, 2, 2)
	grid.occupy(pos.x, pos.y, 2, 2, data["id"])
	_entity_nodes[data["id"]] = node
	_scroll_camera_to_tile(pos)


## Smoothly move the camera so the given tile position is visible.
func _scroll_camera_to_tile(tile: Vector2i) -> void:
	var target := Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)
	var half_view := get_viewport_rect().size / 2.0 / _camera.zoom
	var clamped := target.clamp(
		Vector2(_camera.limit_left, _camera.limit_top) + half_view,
		Vector2(_camera.limit_right, _camera.limit_bottom) - half_view
	)
	_camera.position = clamped


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _update_camera_limits() -> void:
	var bounds: Rect2 = grid.bounds_world(TILE_SIZE)
	_camera.limit_left   = int(bounds.position.x)
	_camera.limit_top    = int(bounds.position.y)
	_camera.limit_right  = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)


func set_zoom(index: int) -> void:
	var clamped_index: int = clamp(index, 0, ZOOM_LEVELS.size() - 1)
	# Do not zoom out past the point where the floor no longer fills the viewport.
	var viewport_size := get_viewport_rect().size
	var bounds := grid.bounds_world(TILE_SIZE)
	while clamped_index < ZOOM_LEVELS.size() - 1:
		var z := ZOOM_LEVELS[clamped_index]
		if bounds.size.x * z.x >= viewport_size.x and bounds.size.y * z.y >= viewport_size.y:
			break
		clamped_index += 1
	_zoom_index = clamped_index
	_camera.zoom = ZOOM_LEVELS[_zoom_index]
	_notify_entities_zoom()
	_save_viewport()


func zoom_in() -> void:
	set_zoom(_zoom_index - 1)


func zoom_out() -> void:
	set_zoom(_zoom_index + 1)


func _unhandled_input(event: InputEvent) -> void:
	# Pan with middle mouse drag.
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_pan(_camera.position - event.relative * PAN_SPEED / _camera.zoom)
		return

	# Two-finger trackpad / touchpad pan gesture.
	if event is InputEventPanGesture:
		_pan(_camera.position + event.delta * PAN_SPEED / _camera.zoom)
		return

	# Touch drag (single finger on touchscreen).
	if event is InputEventScreenDrag and event.index == 0:
		_pan(_camera.position - event.relative * PAN_SPEED / _camera.zoom)
		return

	# Zoom with scroll wheel.
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()

	# Confirm or cancel drag on left/right click.
	if _drag_entity and event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_drag()
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()
			get_viewport().set_input_as_handled()


## Move the camera to `target`, clamped to floor bounds, then persist.
func _pan(target: Vector2) -> void:
	var bounds := grid.bounds_world(TILE_SIZE)
	var half_view := get_viewport_rect().size * 0.5 / _camera.zoom
	_camera.position = target.clamp(
		bounds.position + half_view,
		bounds.end - half_view
	)
	_save_viewport()


# ---------------------------------------------------------------------------
# Layer 3: entity signal wiring
# ---------------------------------------------------------------------------

func _wire_entity_signals(entity: Node2D, tile_w: int, tile_h: int) -> void:
	# Store tile dimensions on the entity for use during move.
	entity.set_meta("tile_w", tile_w)
	entity.set_meta("tile_h", tile_h)
	entity.move_requested.connect(_on_move_requested)
	entity.focus_toggled.connect(_on_focus_toggled)
	entity.lock_toggled.connect(_on_lock_toggled)


# ---------------------------------------------------------------------------
# Layer 3: drag-to-move
# ---------------------------------------------------------------------------

func _on_move_requested(entity: Node2D, tile_w: int, tile_h: int) -> void:
	if _drag_entity:
		return   # already dragging
	_drag_entity = entity
	_drag_entity_id = entity._entity_id
	_drag_tile_w = tile_w
	_drag_tile_h = tile_h
	_drag_overlay.begin(grid, tile_w, tile_h, _drag_entity_id, entity.position)
	_panel.set_busy(true)


func _confirm_drag() -> void:
	var tile: Vector2i = _drag_overlay.end()
	if tile == Vector2i(-1, -1):
		_cancel_drag()
		return
	# Update grid and entity position.
	grid.free_entity(_drag_entity_id)
	grid.occupy(tile.x, tile.y, _drag_tile_w, _drag_tile_h, _drag_entity_id)
	_drag_entity.position = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

	# Persist via BOSS.
	var path: String
	if _drag_tile_w == 12:
		path = "/lean/line/%d/position" % _drag_entity_id
	else:
		path = "/lean/inventory/%d/position" % _drag_entity_id
	BOSSBridge.patch(path, {"x": tile.x, "y": tile.y})

	_drag_entity = null
	_panel.set_busy(false)
	_update_camera_limits()
	_bg.floor_width_tiles  = grid.width_tiles
	_bg.floor_height_tiles = grid.height_tiles
	_bg.queue_redraw()
	_render_belts()


func _cancel_drag() -> void:
	_drag_overlay.end()
	# Restore grid occupation to original entity position.
	var orig_tile := Vector2i(
		int(_drag_entity.position.x) / TILE_SIZE,
		int(_drag_entity.position.y) / TILE_SIZE
	)
	grid.free_entity(_drag_entity_id)
	grid.occupy(orig_tile.x, orig_tile.y, _drag_tile_w, _drag_tile_h, _drag_entity_id)
	_drag_entity = null
	_panel.set_busy(false)


# ---------------------------------------------------------------------------
# Layer 3: focus / gray-out
# ---------------------------------------------------------------------------

func _on_focus_toggled(entity_id: int, focused: bool) -> void:
	# Persist.
	var entity := _find_entity(entity_id)
	if entity == null:
		return
	var is_line: bool = entity.get_meta("tile_w", 2) == 12
	var path: String = "/lean/line/%d/focused" % entity_id if is_line \
		else "/lean/inventory/%d/focused" % entity_id
	BOSSBridge.patch(path, {"focused": focused})

	# Track whether any entity is focused.
	_focus_active = false
	for child in $Entities.get_children():
		if child == _drag_overlay:
			continue
		if child.has_method("set_grayed") and child._focused:
			_focus_active = true
			break

	# Apply gray-out to all non-focused entities.
	_apply_focus_shader()


func _apply_focus_shader() -> void:
	# Build the set of entity IDs that should stay full opacity when focus is active.
	# A focused entity keeps itself and all entities it connects to (Layer 6).
	var visible_ids: Dictionary = {}
	if _focus_active:
		for child in $Entities.get_children():
			if child == _drag_overlay or not child.has_method("set_grayed"):
				continue
			if child._focused:
				visible_ids[child._entity_id] = true
				_collect_connected_ids(child._entity_id, visible_ids)

	for child in $Entities.get_children():
		if child == _drag_overlay:
			continue
		if not child.has_method("set_grayed"):
			continue
		if _focus_active:
			child.set_grayed(!visible_ids.has(child._entity_id))
		else:
			child.set_grayed(false)


## Collect all entity IDs connected (directly) to entity_id via station links.
func _collect_connected_ids(entity_id: int, result: Dictionary) -> void:
	for line_data in _snapshot.get("lines", []):
		var c_line_id: int = line_data.get("id", 0)
		for st in (line_data.get("stations", []) as Array):
			var inv_raw = st.get("connectsToInventory")
			var sub_raw = st.get("connectsToLine")
			var inv_id: int = int(inv_raw) if inv_raw != null else 0
			var sub_id: int = int(sub_raw) if sub_raw != null else 0
			# Focused line → mark its connected inventory and sub-line.
			if c_line_id == entity_id:
				if inv_id != 0: result[inv_id] = true
				if sub_id != 0: result[sub_id] = true
			# Focused inventory or sub-line → mark the line that references it.
			if inv_id == entity_id or sub_id == entity_id:
				result[c_line_id] = true


# ---------------------------------------------------------------------------
# Layer 6: cross-entity belt rendering
# ---------------------------------------------------------------------------

## Rebuild all cross-entity conveyor belts from the last snapshot.
## Amber: Inventory → Station. Purple: Station ↔ sub-assembly Line.
func _render_belts() -> void:
	for child in _belt_layer.get_children():
		child.queue_free()

	if _snapshot.is_empty():
		return

	# Build entity lookup by id.
	var line_nodes: Dictionary = {}
	var inv_nodes: Dictionary = {}
	for child in $Entities.get_children():
		if child == _drag_overlay:
			continue
		var tile_w: int = child.get_meta("tile_w", 0)
		if tile_w == 12:
			line_nodes[child._entity_id] = child
		elif tile_w == 2:
			inv_nodes[child._entity_id] = child

	for line_data in _snapshot.get("lines", []):
		var c_line_id: int = line_data.get("id", 0)
		var line_node = line_nodes.get(c_line_id)
		if line_node == null:
			continue
		var stations: Array = line_data.get("stations", [])
		for i in stations.size():
			var st: Dictionary = stations[i]

			# Inventory → Station belt (amber).
			var inv_raw = st.get("connectsToInventory")
			if inv_raw != null:
				var inv_node = inv_nodes.get(int(inv_raw))
				if inv_node != null:
					Conveyor.draw_routed(
						inv_node.get_center_right_world(),
						line_node.get_station_input_world(i),
						_belt_layer,
						Color(1.0, 0.65, 0.1, 0.9)   # amber
					)

			# Sub-assembly belts (purple).
			var sub_raw = st.get("connectsToLine")
			if sub_raw != null:
				var sub_node = line_nodes.get(int(sub_raw))
				if sub_node != null:
					# Forward: station top → sub-line first intake.
					Conveyor.draw_routed(
						line_node.get_station_top_world(i),
						sub_node.get_first_intake_world(),
						_belt_layer,
						Color(0.65, 0.2, 0.9, 0.9)   # purple
					)
					# Return: sub-line output → station top.
					Conveyor.draw_routed(
						sub_node.get_output_world(),
						line_node.get_station_top_world(i),
						_belt_layer,
						Color(0.65, 0.2, 0.9, 0.9)
					)


# ---------------------------------------------------------------------------
# Layer 3: lock
# ---------------------------------------------------------------------------

func _on_lock_toggled(entity_id: int, locked: bool) -> void:
	var entity := _find_entity(entity_id)
	if entity == null:
		return
	var is_line: bool = entity.get_meta("tile_w", 2) == 12
	var path: String = "/lean/line/%d/locked" % entity_id if is_line \
		else "/lean/inventory/%d/locked" % entity_id
	BOSSBridge.patch(path, {"locked": locked})


# ---------------------------------------------------------------------------
# Layer 3: zoom slider
# ---------------------------------------------------------------------------

func _on_zoom_slider_changed(index: int) -> void:
	set_zoom(index)
	# Keep slider in sync after clamping.
	_zoom_slider.set_index(_zoom_index)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_entity(entity_id: int) -> Node2D:
	return _entity_nodes.get(entity_id)


# ---------------------------------------------------------------------------
# Layer 7: zoom notification + viewport persistence
# ---------------------------------------------------------------------------

func _notify_entities_zoom() -> void:
	for child in $Entities.get_children():
		if child == _drag_overlay:
			continue
		if child.has_method("set_zoom_index"):
			child.set_zoom_index(_zoom_index)


func _save_viewport() -> void:
	if not is_web() or BOSSBridge.factory_id < 0:
		return
	var val := JSON.stringify({
		"x": _camera.position.x,
		"y": _camera.position.y,
		"zoom": _zoom_index
	})
	# Single quotes around the value are safe because JSON uses double quotes internally.
	JavaScriptBridge.eval("localStorage.setItem('ff_%d_vp', '%s')" % [BOSSBridge.factory_id, val])


func _restore_viewport() -> void:
	if not is_web() or BOSSBridge.factory_id < 0:
		return
	var raw = JavaScriptBridge.eval("localStorage.getItem('ff_%d_vp')" % BOSSBridge.factory_id)
	if raw == null or typeof(raw) != TYPE_STRING or (raw as String).is_empty() or raw == "null":
		return
	var json := JSON.new()
	if json.parse(raw as String) != OK:
		return
	var vp = json.get_data()
	if not (vp is Dictionary):
		return
	_camera.position = Vector2(float((vp as Dictionary).get("x", 640)),
		float((vp as Dictionary).get("y", 360)))
	set_zoom(int((vp as Dictionary).get("zoom", 0)))
	_zoom_slider.set_index(_zoom_index)
