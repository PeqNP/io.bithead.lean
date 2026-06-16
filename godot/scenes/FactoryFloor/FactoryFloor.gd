## Copyright © 2026 Bithead LLC. All rights reserved.

## FactoryFloor — main scene root.

extends Node2D

const TILE_SIZE := 64
const PAN_SPEED  := 4.0   # pan multiplier — increase for faster scrolling
## Tiles of empty space kept beyond the furthest entity (and beyond the drag ghost during a move).
const FLOOR_EDGE_BUFFER := 5
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

# Inertia for mouse-wheel panning — decays each frame.
var _scroll_velocity: Vector2 = Vector2.ZERO

var _drag_overlay: Node2D = null
var _drag_entity: Node2D = null       # entity currently being dragged
var _drag_entity_id: int = 0
var _drag_tile_w: int = 0
var _drag_tile_h: int = 0
var _focus_active: bool = false       # true when any entity is focused
var _zoom_slider: CanvasLayer = null

var _snapshot: Dictionary = {}
var _iq_to_line: Dictionary = {}

var _entity_nodes: Dictionary = {}

# BOSS delegate — WebBOSSDelegate in browser, DummyBOSSDelegate in editor.
var _boss: BOSSDelegate
var _minimap: MiniMap = null

@onready var _camera:      Camera2D    = $Camera2D
@onready var _error_modal: CanvasLayer  = $ErrorModal/ErrorModal
@onready var _bg:          Node2D      = $Background
@onready var _panel:       CanvasLayer = $OperationPanel
@onready var _belt_layer:  Node2D      = $BeltLayer

func is_web() -> bool:
	return OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge")

func _process(delta: float) -> void:
	# Decay mouse-wheel scroll inertia every frame.
	if _scroll_velocity.length_squared() > 0.01:
		_pan(_camera.position + _scroll_velocity * delta)
		_scroll_velocity *= 0.82
	else:
		_scroll_velocity = Vector2.ZERO

	if _drag_entity == null:
		return
	# Expand floor bounds live while dragging so the camera and background grow
	# as the ghost moves toward or past the current edge.
	var bounds := _compute_floor_bounds()
	var new_w := ceili(bounds.size.x / float(TILE_SIZE))
	var new_h := ceili(bounds.size.y / float(TILE_SIZE))
	if new_w != _bg.floor_width_tiles or new_h != _bg.floor_height_tiles:
		_bg.floor_width_tiles  = new_w
		_bg.floor_height_tiles = new_h
		_update_camera_limits()
		_bg.queue_redraw()

func _ready() -> void:
	BOSSBridge.snapshot_updated.connect(_on_snapshot_updated)
	BOSSBridge.error.connect(_on_boss_error)
	get_viewport().size_changed.connect(_on_viewport_resized)

	_update_camera_limits()

	# Ensure stretch settings are applied at runtime (canvas_items + expand).
	# This makes the viewport size grow to match the containing window/canvas size
	# when resized (revealing more of the floor), and makes project settings changes
	# take effect even if the editor UI / project.godot write is having issues.
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

	# Apply camera/background updates for whatever the *current* viewport size is
	# (after forcing the scale mode). This is important on web where the canvas
	# may have already been sized by the container before _ready finishes.
	_on_viewport_resized()

	if OS.is_debug_build():
		print("FactoryFloor: effective viewport size at ready: ", get_viewport_rect().size)
		print("FactoryFloor: content_scale_mode=", root.content_scale_mode, " aspect=", root.content_scale_aspect)

	_panel.create_line_pressed.connect(_on_create_line)
	_panel.create_inventory_pressed.connect(_on_create_inventory)

	_drag_overlay = DRAG_OVERLAY_SCENE.instantiate()
	$Entities.add_child(_drag_overlay)

	_zoom_slider = ZOOM_SLIDER_SCENE.instantiate()
	add_child(_zoom_slider)
	_zoom_slider.zoom_changed.connect(_on_zoom_slider_changed)

	var _minimap_layer := CanvasLayer.new()
	_minimap_layer.layer = 10
	add_child(_minimap_layer)
	_minimap = MiniMap.new()
	_minimap_layer.add_child(_minimap)
	_minimap.reposition(get_viewport_rect().size)
	_minimap.tapped.connect(_on_minimap_tapped)

	if is_web():
		_boss = WebBOSSDelegate.new()
		BOSSBridge.set_backend(WebBOSSBridgeBackend.new())
	else:
		_boss = LocalBOSSDelegate.new()
		BOSSBridge.set_backend(LocalBOSSBridgeBackend.new())
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

	# Build incoming map: entity_id → {data, is_line}.
	# Tile width for Lines is computed from station count (each station = 2 tiles).
	var incoming: Dictionary = {}
	for line_data: Dictionary in (snapshot.get("lines", []) as Array):
		var n_st: int = (line_data.get("stations", []) as Array).size()
		var has_out: bool = line_data.get("hasOutput", true)
		# tw: mirrors Line._compute_line_w(). Uses max posX across stations.
		var max_pos_x: int = 0
		for s: Dictionary in (line_data.get("stations", []) as Array):
			max_pos_x = max(max_pos_x, s.get("posX", 0))
		var n_cols := (max_pos_x + 1) if n_st > 0 else 0
		var tw: int = (6 if not has_out else 8) + n_cols * 3   # intake(4)+hopper(2)+[output(2)]+n_cols*station(3)
		# th: mirrors Line._compute_line_h(). CONTENT_TOP=60, slot_h=128, gap=4.
		var n_iq: int = max(1, (line_data.get("intakeQueues", []) as Array).size())
		var intake_h := n_iq * 128 + (n_iq - 1) * 4
		var max_pos_y: int = 0
		for s: Dictionary in (line_data.get("stations", []) as Array):
			max_pos_y = max(max_pos_y, s.get("posY", 0))
		var n_rows := (max_pos_y + 1) if n_st > 0 else 1
		var station_h := n_rows * 128 + (n_rows - 1) * 4
		var raw_h: int = 60 + max(intake_h, station_h)
		var th: int = ceili(float(raw_h) / 64.0)
		incoming["L_%d" % line_data.get("id", 0)] = {"data": line_data, "tw": tw, "th": th, "is_line": true}
	for inv_data: Dictionary in (snapshot.get("inventories", []) as Array):
		incoming["I_%d" % inv_data.get("id", 0)] = {"data": inv_data, "tw": 2, "th": 2, "is_line": false}

	# Remove entities no longer in the snapshot.
	var stale: Array = []
	for eid in _entity_nodes:
		if not incoming.has(eid):
			stale.append(eid)
	for eid in stale:
		_entity_nodes[eid].queue_free()
		_entity_nodes.erase(eid)

	# Add new entities and update existing ones.
	for eid in incoming:
		var info: Dictionary = incoming[eid]
		var c_data: Dictionary = info["data"]
		var tw: int = info["tw"]
		var th: int = info["th"]
		var c_is_line: bool = info["is_line"]
		var gx: int = c_data.get("gridX", 0)
		var gy: int = c_data.get("gridY", 0)

		if _entity_nodes.has(eid):
			var node: Node2D = _entity_nodes[eid]
			node.set_meta("tile_w", tw)
			node.set_meta("tile_h", th)
			node.update(c_data)
		else:
			# Create new node.
			var node: Node2D
			if c_is_line:
				node = LINE_SCENE.instantiate()
			else:
				node = INVENTORY_SCENE.instantiate()
			entities.add_child(node)
			node.configure(c_data)
			node.set_zoom_index(_zoom_index)
			node.set_meta("is_line", c_is_line)
			_wire_entity_signals(node, tw, th)
			_entity_nodes[eid] = node

	_update_camera_limits()
	var bg_bounds := _compute_floor_bounds()
	_bg.floor_width_tiles  = ceili(bg_bounds.size.x / float(TILE_SIZE))
	_bg.floor_height_tiles = ceili(bg_bounds.size.y / float(TILE_SIZE))
	_bg.queue_redraw()
	_render_belts()
	_update_all_expansion_blocking()
	_update_minimap()


func _update_minimap() -> void:
	if _minimap == null:
		return
	var entries: Array = []
	for eid in _entity_nodes:
		var node: Node2D = _entity_nodes[eid]
		var is_line: bool = node.get_meta("is_line", false)
		var w: float = float(node._line_w) if is_line else float(node.get_meta("tile_w", 2) * TILE_SIZE)
		var h: float = float(node._line_h) if is_line else float(node.get_meta("tile_h", 2) * TILE_SIZE)
		var color_data = node._data.get("color", null)
		var fallback: Color = Palette.BLUE if is_line else Palette.GREEN
		var accent: Color = _minimap_color(color_data, fallback)
		entries.append({"rect": Rect2(node.position, Vector2(w, h)), "color": accent})
	_minimap.refresh(entries, _compute_floor_bounds())


func _on_minimap_tapped(world_pos: Vector2) -> void:
	_pan(world_pos)


func _minimap_color(color_data, fallback: Color) -> Color:
	if color_data == null:
		return fallback
	var hex: String = str((color_data as Dictionary).get("border", ""))
	if hex.is_empty():
		return fallback
	if hex.begins_with("#"):
		hex = hex.substr(1)
	return Color.from_string(hex, fallback)


func _update_all_expansion_blocking() -> void:
	for eid in _entity_nodes:
		var node: Node2D = _entity_nodes[eid]
		if not node.get_meta("is_line", false):
			continue
		var block_right: bool = _is_line_expansion_blocked(node, true)
		var block_down: bool = _is_line_expansion_blocked(node, false)
		node.set_expansion_blocked(block_right, block_down)
		node.set_station_insert_blocked(_is_station_insert_blocked(node))


## Returns true if growing `line_node` by one station column (check_right=true)
## or one station row (check_right=false) would intersect a neighbouring entity.
func _is_line_expansion_blocked(line_node: Node2D, check_right: bool) -> bool:
	var lw: float = line_node._line_w
	var lh: float = line_node._line_h
	var extra_w: float = line_node.expansion_slot_w() if check_right else 0.0
	var extra_h: float = line_node.expansion_slot_h() if not check_right else 0.0
	var expanded: Rect2 = Rect2(line_node.position, Vector2(lw + extra_w, lh + extra_h))
	for eid in _entity_nodes:
		var other: Node2D = _entity_nodes[eid]
		if other == line_node:
			continue
		var other_rect: Rect2
		if other.get_meta("is_line", false):
			other_rect = Rect2(other.position, Vector2(other._line_w, other._line_h))
		else:
			other_rect = Rect2(other.position, Vector2(
				other.get_meta("tile_w", 2) * TILE_SIZE,
				other.get_meta("tile_h", 2) * TILE_SIZE
			))
		if expanded.intersects(other_rect):
			return true
	return false


## Returns true when no candidate position exists for the last station to move
## after a new station is inserted anywhere on the line.
func _is_station_insert_blocked(line_node: Node2D) -> bool:
	var stations: Array = (line_node._data.get("stations", []) as Array)
	if stations.is_empty():
		return false
	var last := stations.back() as Dictionary
	var lpx: int = int(last.get("posX", 0))
	var lpy: int = int(last.get("posY", 0))
	var exit_x: int = 1
	if stations.size() >= 2:
		var prev := stations[stations.size() - 2] as Dictionary
		if int(prev.get("posX", 0)) > lpx:
			exit_x = -1
	var primary := Vector2i(lpx + exit_x, lpy)
	var candidates: Array = []
	if exit_x < 0 and primary.x < 0:
		candidates.append(Vector2i(lpx, lpy + 1))
		candidates.append(Vector2i(lpx, lpy - 1))
	else:
		candidates.append(primary)
	var max_px: int = 0
	var max_py: int = 0
	for s: Dictionary in stations:
		max_px = max(max_px, int(s.get("posX", 0)))
		max_py = max(max_py, int(s.get("posY", 0)))
	for cand in candidates:
		var cx: int = cand.x
		var cy: int = cand.y
		if cx < 0 or cy < 0:
			continue
		var occupied := false
		for s: Dictionary in stations:
			if int(s.get("posX", 0)) == cx and int(s.get("posY", 0)) == cy:
				occupied = true
				break
		if occupied:
			continue
		if cx > max_px and _is_line_expansion_blocked(line_node, true):
			continue
		if cy > max_py and _is_line_expansion_blocked(line_node, false):
			continue
		return false
	return true


func _on_boss_error(message: String) -> void:
	_error_modal.show_error("Error", message)


func _on_floor_grew(_new_w: int, _new_h: int) -> void:
	_update_camera_limits()
	_bg.queue_redraw()


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


func _on_create_intake_queue(line_id: int) -> void:
	if not is_web():
		await BOSSBridge.post("/lean/line/%d/intake-queue" % line_id, {})
		BOSSBridge.poll_snapshot()
		return
	_boss.receive("open-window", {
		"controller": "CreateFactoryModel",
		"parameters": ["intake-queue", line_id],
	})


func _on_create_station(line_id: int) -> void:
	if not is_web():
		await BOSSBridge.post("/lean/line/%d/station" % line_id, {})
		BOSSBridge.poll_snapshot()
		return
	_boss.receive("open-window", {
		"controller": "CreateFactoryModel",
		"parameters": ["station", line_id],
	})


func _on_insert_station(line_id: int, index) -> void:
	var body: Dictionary = {}
	if index != null:
		body["index"] = index
	await BOSSBridge.post("/lean/line/%d/station" % line_id, body)
	BOSSBridge.poll_snapshot()


func _on_delete_station(line_id: int, station_id: int) -> void:
	await BOSSBridge.delete("/lean/line/%d/station/%d" % [line_id, station_id])
	BOSSBridge.poll_snapshot()


func _on_insert_intake_queue(line_id: int, index) -> void:
	var body: Dictionary = {}
	if index != null:
		body["index"] = index
	await BOSSBridge.post("/lean/line/%d/intake-queue" % line_id, body)
	BOSSBridge.poll_snapshot()


func _on_delete_intake_queue(line_id: int, queue_id: int) -> void:
	await BOSSBridge.delete("/lean/line/%d/intake-queue/%d" % [line_id, queue_id])
	BOSSBridge.poll_snapshot()


## Add a temporary placeholder Line at the first available grid position.
## Uses a negative id so it won't collide with server-assigned ids.
var _next_placeholder_id: int = -1

func _add_placeholder_line() -> void:
	var px_pos := _first_available_pos(11.0 * TILE_SIZE, 3.0 * TILE_SIZE)
	if px_pos == Vector2(-1.0, -1.0):
		return
	var tile_x := int(px_pos.x) / TILE_SIZE
	var tile_y := int(px_pos.y) / TILE_SIZE
	var data := {
		"id": _next_placeholder_id,
		"gridX": tile_x,
		"gridY": tile_y,
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
	node.set_meta("is_line", true)
	_wire_entity_signals(node, 11, 3)
	_entity_nodes[data["id"]] = node
	_update_camera_limits()
	_pan(px_pos + Vector2(11.0 * TILE_SIZE, 3.0 * TILE_SIZE) * 0.5)
func _add_placeholder_inventory() -> void:
	var px_pos := _first_available_pos(4.0 * TILE_SIZE, 2.0 * TILE_SIZE)
	if px_pos == Vector2(-1.0, -1.0):
		return
	var tile_x := int(px_pos.x) / TILE_SIZE
	var tile_y := int(px_pos.y) / TILE_SIZE
	var data := {
		"id": _next_placeholder_id,
		"gridX": tile_x,
		"gridY": tile_y,
		"name": "New Inventory",
		"locked": false,
		"health": 0
	}
	_next_placeholder_id -= 1
	var node: Node2D = INVENTORY_SCENE.instantiate()
	$Entities.add_child(node)
	node.configure(data)
	node.set_zoom_index(_zoom_index)
	node.set_meta("is_line", false)
	_wire_entity_signals(node, 4, 2)
	_entity_nodes[data["id"]] = node
	_update_camera_limits()
	_pan(px_pos + Vector2(4.0 * TILE_SIZE, 2.0 * TILE_SIZE) * 0.5)
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
	var bounds: Rect2 = _compute_floor_bounds()
	_camera.limit_left   = int(bounds.position.x)
	_camera.limit_top    = int(bounds.position.y)
	_camera.limit_right  = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)


func _on_viewport_resized() -> void:
	_update_camera_limits()
	# Re-clamp the camera so that growing the window reveals more floor
	# (instead of leaving the view stuck at the old edges), and shrinking
	# pulls the view back inside bounds.
	var bounds := _compute_floor_bounds()
	var half_view := get_viewport_rect().size * 0.5 / _camera.zoom
	_camera.position = _camera.position.clamp(
		bounds.position + half_view,
		bounds.end - half_view
	)
	_bg.queue_redraw()
	if _minimap != null:
		_minimap.reposition(get_viewport_rect().size)

	if OS.is_debug_build():
		print("FactoryFloor: viewport resized to ", get_viewport_rect().size)


func set_zoom(index: int) -> void:
	var clamped_index: int = clamp(index, 0, ZOOM_LEVELS.size() - 1)
	# Do not zoom out past the point where the floor no longer fills the viewport.
	var viewport_size := get_viewport_rect().size
	var bounds := _compute_floor_bounds()
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


func _input(event: InputEvent) -> void:
	# Confirm or cancel drag on left/right click.
	# Handled in _input (before GUI) so the input blocker in DragOverlay
	# doesn't swallow the placement click.
	if _drag_entity and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_drag()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Pan with middle mouse drag or left mouse drag on empty floor.
	if event is InputEventMouseMotion and (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or
		(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _drag_entity)
	):
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

	# Scroll wheel pans with inertia (no zoom — use the zoom slider or keyboard).
	# event.factor is fractional on smooth-scroll devices, 1.0 per detent on
	# physical wheels — this gives proportional impulse for free.
	# Horizontal direction is inverted on web to match Godot editor feel.
	if event is InputEventMouseButton:
		const IMPULSE := 320.0   # pixels/sec added per detent
		var h_sign := -1.0 if OS.get_name() == "Web" else 1.0
		var factor := maxf(event.factor, 1.0)   # physical mouse always 1.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_velocity.y -= IMPULSE * factor
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_velocity.y += IMPULSE * factor
		elif event.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_scroll_velocity.x -= IMPULSE * factor * h_sign
		elif event.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_scroll_velocity.x += IMPULSE * factor * h_sign

	# Keyboard zoom: Cmd+=/- (macOS) or Ctrl+=/- (Windows/Linux), Cmd/Ctrl+0 resets to 100%.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_command_or_control_pressed():
			if event.keycode in [KEY_EQUAL, KEY_PLUS]:
				zoom_in()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_MINUS:
				zoom_out()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_0:
				set_zoom(0)
				_zoom_slider.set_index(_zoom_index)
				get_viewport().set_input_as_handled()

	# Confirm or cancel drag — now handled in _input above; kept as dead-code guard.
	if _drag_entity and event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_drag()
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()
			get_viewport().set_input_as_handled()


## Move the camera to `target`, clamped to floor bounds, then persist.
func _pan(target: Vector2) -> void:
	var bounds := _compute_floor_bounds()
	var half_view := get_viewport_rect().size * 0.5 / _camera.zoom
	_camera.position = target.clamp(
		bounds.position + half_view,
		bounds.end - half_view
	)
	_save_viewport()


func _wire_entity_signals(entity: Node2D, tile_w: int, tile_h: int) -> void:
	# Store tile dimensions on the entity for use during move.
	entity.set_meta("tile_w", tile_w)
	entity.set_meta("tile_h", tile_h)
	entity.move_requested.connect(_on_move_requested)
	entity.focus_toggled.connect(_on_focus_toggled)
	entity.lock_toggled.connect(_on_lock_toggled)
	if entity.get_meta("is_line", false):
		entity.create_intake_queue_requested.connect(_on_create_intake_queue)
		entity.create_station_requested.connect(_on_create_station)
		entity.insert_station_requested.connect(_on_insert_station)
		entity.delete_station_requested.connect(_on_delete_station)
		entity.insert_intake_queue_requested.connect(_on_insert_intake_queue)
		entity.delete_intake_queue_requested.connect(_on_delete_intake_queue)


func _on_move_requested(entity: Node2D, tile_w: int, tile_h: int) -> void:
	if _drag_entity:
		return   # already dragging
	_drag_entity = entity
	_drag_entity_id = entity._entity_id
	_drag_tile_w = tile_w
	_drag_tile_h = tile_h
	# Pass the entity's actual pixel size so the ghost exactly matches the visual box.
	var px_size := Vector2.ZERO
	if entity.get_meta("is_line", false):
		px_size = Vector2(entity._line_w, entity._line_h)
	_drag_overlay.begin(tile_w, tile_h, entity.get_area_rid(), entity.position, px_size)
	_panel.set_busy(true)


func _confirm_drag() -> void:
	var tile: Vector2i = _drag_overlay.end()
	if tile == Vector2i(-1, -1):
		_cancel_drag()
		return
	# Move entity to the confirmed position — Area2D moves with it automatically.
	_drag_entity.position = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

	# Persist via BOSS.
	var path: String
	if _drag_entity.get_meta("is_line", false):
		path = "/lean/line/%d/position" % _drag_entity_id
	else:
		path = "/lean/inventory/%d/position" % _drag_entity_id
	BOSSBridge.patch(path, {"x": tile.x, "y": tile.y})

	_drag_entity = null
	_panel.set_busy(false)
	_update_camera_limits()
	var bg_bounds := _compute_floor_bounds()
	_bg.floor_width_tiles  = ceili(bg_bounds.size.x / float(TILE_SIZE))
	_bg.floor_height_tiles = ceili(bg_bounds.size.y / float(TILE_SIZE))
	_bg.queue_redraw()
	_render_belts()
	_update_all_expansion_blocking()


func _cancel_drag() -> void:
	_drag_overlay.end()
	# Entity position is unchanged — Area2D is already at the correct position.
	_drag_entity = null
	_panel.set_busy(false)


func _on_focus_toggled(entity_id: int, focused: bool) -> void:
	# Persist.
	var entity := _find_entity(entity_id)
	if entity == null:
		return
	var is_line: bool = entity.get_meta("is_line", false)
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
	# A focused entity keeps itself and all entities it connects to.
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
		if child.get_meta("is_line", false):
			line_nodes[child._entity_id] = child
		elif tile_w == 2:
			inv_nodes[child._entity_id] = child

	# Build intake-queue-id → line_node lookup for connectsToIntakeQueue belt routing.
	_iq_to_line.clear()
	for ld: Dictionary in (_snapshot.get("lines", []) as Array):
		var ln = line_nodes.get(int(ld.get("id", 0)))
		if ln == null:
			continue
		for iq: Dictionary in (ld.get("intakeQueues", []) as Array):
			_iq_to_line[int(iq.get("id", 0))] = ln

	for line_data in _snapshot.get("lines", []):
		var c_line_id: int = line_data.get("id", 0)
		var line_node = line_nodes.get(c_line_id)
		if line_node == null:
			continue
		var stations: Array = line_data.get("stations", [])
		for i in stations.size():
			var st: Dictionary = stations[i]

			# Inventory → Station belt (amber).
			# Connect vertical edges: bottom of inv→top of station when inv is above, and vice versa.
			var inv_raw = st.get("connectsToInventory")
			if inv_raw != null:
				var inv_node = inv_nodes.get(int(inv_raw))
				if inv_node != null:
					var station_world: Vector2
					var inv_world: Vector2
					var inv_dir: Vector2
					var station_dir: Vector2
					if inv_node.position.y < line_node.position.y:
						# Inventory is above the line — exit bottom of inv, enter top of station.
						inv_world    = inv_node.get_center_bottom_world()
						station_world = line_node.get_station_card_top_world(i)
						inv_dir      = Vector2(0,  1)
						station_dir  = Vector2(0, -1)
					else:
						# Inventory is below the line — exit top of inv, enter bottom of station.
						inv_world    = inv_node.get_center_top_world()
						station_world = line_node.get_station_card_bottom_world(i)
						inv_dir      = Vector2(0, -1)
						station_dir  = Vector2(0,  1)
					ConveyorBelt.draw_routed(
							inv_world, station_world,
							_belt_layer,
							Palette.YELLOW_BELT,
							inv_dir, station_dir
					)
			var sub_raw = st.get("connectsToLine")
			if sub_raw != null:
				var sub_node = line_nodes.get(int(sub_raw))
				if sub_node != null:
					var station_world: Vector2
					var sub_from_dir: Vector2
					if sub_node.position.y < line_node.position.y:
						station_world = line_node.get_station_card_top_world(i)
						sub_from_dir = Vector2(0, -1)   # exit upward
					else:
						station_world = line_node.get_station_card_bottom_world(i)
						sub_from_dir = Vector2(0, 1)    # exit downward
					ConveyorBelt.draw_routed_bidirectional(
						station_world, sub_from_dir,
						sub_node.get_first_intake_queue_left_world(), Vector2(-1, 0),
						_belt_layer,
						Palette.VIOLET_BELT,
						sub_node.get_bounds_world()
					)

			# Station → IntakeQueue bidirectional belt (teal).
			# Two side-by-side lanes: one flowing into the queue, one flowing back toward the station.
			var iq_raw = st.get("connectsToIntakeQueue")
			if iq_raw != null:
				var iq_id: int = int(iq_raw)
				var target_line = _iq_to_line.get(iq_id)
				if target_line != null:
					var station_world: Vector2
					var iq_from_dir: Vector2
					if target_line.position.y < line_node.position.y:
						station_world = line_node.get_station_card_top_world(i)
						iq_from_dir = Vector2(0, -1)   # exit upward
					else:
						station_world = line_node.get_station_card_bottom_world(i)
						iq_from_dir = Vector2(0, 1)    # exit downward
					ConveyorBelt.draw_routed_bidirectional(
						station_world, iq_from_dir,
						target_line.get_intake_queue_left_world(iq_id), Vector2(-1, 0),
						_belt_layer,
						Palette.CYAN_BELT,
						target_line.get_bounds_world()
					)


func _on_lock_toggled(entity_id: int, locked: bool) -> void:
	var entity := _find_entity(entity_id)
	if entity == null:
		return
	var is_line: bool = entity.get_meta("is_line", false)
	var path: String = "/lean/line/%d/locked" % entity_id if is_line \
		else "/lean/inventory/%d/locked" % entity_id
	BOSSBridge.patch(path, {"locked": locked})


func _on_zoom_slider_changed(index: int) -> void:
	set_zoom(index)
	# Keep slider in sync after clamping.
	_zoom_slider.set_index(_zoom_index)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_entity(entity_id: int) -> Node2D:
	var node = _entity_nodes.get("L_%d" % entity_id)
	if node:
		return node
	return _entity_nodes.get("I_%d" % entity_id)


## Compute the world-space bounding rect of all entities plus FLOOR_EDGE_BUFFER.
## Used for camera limits and background grid dimensions.
## When a drag is active, also accounts for the ghost position.
func _compute_floor_bounds() -> Rect2:
	var buffer := FLOOR_EDGE_BUFFER * TILE_SIZE
	var max_x := 20.0 * TILE_SIZE
	var max_y := 20.0 * TILE_SIZE
	for child in $Entities.get_children():
		if child == _drag_overlay:
			continue
		if child.get_meta("is_line", false):
			max_x = max(max_x, child.position.x + float(child._line_w))
			max_y = max(max_y, child.position.y + float(child._line_h))
		elif child.has_meta("tile_w"):
			max_x = max(max_x, child.position.x + float(child.get_meta("tile_w", 2) * TILE_SIZE))
			max_y = max(max_y, child.position.y + float(child.get_meta("tile_h", 2) * TILE_SIZE))
	# If a drag is in progress, include the ghost's projected far edge.
	if _drag_overlay != null and _drag_overlay.visible:
		var ghost_snap: Vector2i = _drag_overlay.get_snap_tile()
		var ghost_px  : Vector2  = _drag_overlay.get_ghost_pixel_size()
		max_x = max(max_x, ghost_snap.x * TILE_SIZE + ghost_px.x)
		max_y = max(max_y, ghost_snap.y * TILE_SIZE + ghost_px.y)
	return Rect2(0, 0, max_x + buffer, max_y + buffer)


## Find the first tile-aligned world-space position where (px_w × px_h) fits
## without overlapping any entity Area2D. Scans up to a 20×20-tile area.
## Returns Vector2(-1, -1) if no free spot found.
func _first_available_pos(px_w: float, px_h: float) -> Vector2:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(px_w, px_h)
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.collision_mask = 1
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for ty in range(20):
		for tx in range(20):
			var pos := Vector2(tx * TILE_SIZE, ty * TILE_SIZE)
			params.transform = Transform2D(0.0, pos + Vector2(px_w, px_h) * 0.5)
			if get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty():
				return pos
	return Vector2(-1.0, -1.0)


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
