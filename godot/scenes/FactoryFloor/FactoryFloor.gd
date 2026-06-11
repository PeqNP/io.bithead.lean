## Copyright © 2026 Bithead LLC. All rights reserved.

## FactoryFloor — main scene root.
##
## Layer 0: BOSS JS bridge, camera, error modal.
## Layer 1: Render Line and Inventory entities from snapshot.
## Layer 2: OperationPanel — Create Line / Create Inventory flows.
## Layer 3: Hover controls, drag-to-move, focus/gray-out, lock, zoom slider.

extends Node2D

const TILE_SIZE := 64
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

# Grid manager — owns tile occupation state.
var grid: GridManager = GridManager.new()

# BOSS JS bridge references.
var _delegate: JavaScriptObject
var _send_callback: JavaScriptObject

@onready var _camera:      Camera2D    = $Camera2D
@onready var _error_modal: CanvasLayer  = $ErrorModal/ErrorModal
@onready var _bg:          Node2D      = $Background
@onready var _panel:       CanvasLayer = $OperationPanel


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

	if Engine.has_singleton("JavaScriptBridge"):
		var window := JavaScriptBridge.get_interface("window")
		if window and window.boss:
			_delegate = window.boss
			_send_callback = JavaScriptBridge.create_callback(_on_boss_send)
			_delegate.send = _send_callback
			_delegate.ready()
		else:
			push_warning("FactoryFloor: window.boss not set — running outside BOSS?")


# ---------------------------------------------------------------------------
# BOSS bridge
# ---------------------------------------------------------------------------

func _on_boss_send(args: Array) -> void:
	if args.is_empty():
		return
	var cmd: JavaScriptObject = args[0]
	var c_name: String = str(cmd["name"])
	match c_name:
		"configure":
			var data: JavaScriptObject = cmd["data"]
			var factory_id: int = int(str(data["factoryId"]))
			var base_url: String = str(data["baseUrl"])
			BOSSBridge.configure(factory_id, base_url)
		_:
			push_warning("FactoryFloor: unknown BOSS command '%s'" % c_name)


# ---------------------------------------------------------------------------
# BOSSBridge signals
# ---------------------------------------------------------------------------

func _on_snapshot_updated(snapshot: Dictionary) -> void:
	_render_entities(snapshot)


func _render_entities(snapshot: Dictionary) -> void:
	# Clear all existing entity children.
	var entities := $Entities
	for child in entities.get_children():
		child.queue_free()

	# Reset grid occupation.
	grid = GridManager.new()
	grid.floor_grew.connect(_on_floor_grew)

	# Render Lines.
	var lines: Array = snapshot.get("lines", [])
	for line_data in lines:
		var node: Node2D = LINE_SCENE.instantiate()
		entities.add_child(node)
		node.configure(line_data)
		_wire_entity_signals(node, 12, 2)
		grid.occupy(
			line_data.get("gridX", 0),
			line_data.get("gridY", 0),
			12, 2,
			line_data.get("id", 0)
		)

	# Render Inventories.
	var inventories: Array = snapshot.get("inventories", [])
	for inv_data in inventories:
		var node: Node2D = INVENTORY_SCENE.instantiate()
		entities.add_child(node)
		node.configure(inv_data)
		_wire_entity_signals(node, 2, 2)
		grid.occupy(
			inv_data.get("gridX", 0),
			inv_data.get("gridY", 0),
			2, 2,
			inv_data.get("id", 0)
		)

	_update_camera_limits()
	_bg.floor_width_tiles  = grid.width_tiles
	_bg.floor_height_tiles = grid.height_tiles
	_bg.queue_redraw()


func _on_boss_error(message: String) -> void:
	_error_modal.show_error("Error", message)


func _on_floor_grew(_new_w: int, _new_h: int) -> void:
	_update_camera_limits()
	_bg.queue_redraw()


# ---------------------------------------------------------------------------
# Layer 2: Create flows
# ---------------------------------------------------------------------------

func _on_create_line() -> void:
	if not _delegate:
		_error_modal.show_error("Not connected", "BOSS controller is not available.")
		return
	# Tell BOSS to open the CreateFactoryModel window for a new line.
	_send_open_window("CreateFactoryModel", ["line", BOSSBridge.factory_id])
	# Temporarily add a placeholder line to the floor while BOSS processes the request.
	# This will be replaced when the snapshot is next updated.
	_add_placeholder_line()


func _on_create_inventory() -> void:
	if not _delegate:
		_error_modal.show_error("Not connected", "BOSS controller is not available.")
		return
	# Tell BOSS to open the CreateFactoryModel window for a new inventory.
	_send_open_window("CreateFactoryModel", ["inventory", BOSSBridge.factory_id])
	# Temporarily add a placeholder inventory to the floor.
	_add_placeholder_inventory()


## Send an open-window event to the BOSS GodotController.
## BOSS will load the named controller and pass parameters to its configure().
func _send_open_window(controller_name: String, parameters: Array) -> void:
	var params_obj: JavaScriptObject = JavaScriptBridge.create_object("Array")
	for i in parameters.size():
		params_obj[str(i)] = parameters[i]
	var data_obj: JavaScriptObject = JavaScriptBridge.create_object("Object")
	data_obj["controller"] = controller_name
	data_obj["parameters"] = params_obj
	var ev: JavaScriptObject = JavaScriptBridge.create_object("Object")
	ev["name"] = "open-window"
	ev["data"] = data_obj
	_delegate.receive(ev)


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
	_wire_entity_signals(node, 12, 2)
	grid.occupy(pos.x, pos.y, 12, 2, data["id"])
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
	_wire_entity_signals(node, 2, 2)
	grid.occupy(pos.x, pos.y, 2, 2, data["id"])
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


func zoom_in() -> void:
	set_zoom(_zoom_index - 1)


func zoom_out() -> void:
	set_zoom(_zoom_index + 1)


func _unhandled_input(event: InputEvent) -> void:
	# Pan with middle mouse drag.
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_camera.position -= event.relative / _camera.zoom

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
	_drag_overlay.begin(grid, tile_w, tile_h, _drag_entity_id)
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
	for child in $Entities.get_children():
		if child == _drag_overlay:
			continue
		if not child.has_method("set_grayed"):
			continue
		if _focus_active:
			child.set_grayed(!child._focused)
		else:
			child.set_grayed(false)


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
	for child in $Entities.get_children():
		if child == _drag_overlay:
			continue
		if "_entity_id" in child and child._entity_id == entity_id:
			return child
	return null
