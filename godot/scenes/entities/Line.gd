## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single production Line from a LeanFragment.FactoryFloor.Line snapshot.

extends Node2D

const TILE_SIZE    := 64
## Minimum line height (no intake queues). Height grows with intake queue count.
const LINE_H_MIN   :=  3 * TILE_SIZE   # 192 px
## Y offset where hopper/stations/output content begins. Fixed regardless of line height.
const CONTENT_TOP  := TILE_SIZE - SECTION_PAD   # 60 px

const FILL_COLOR           := Palette.BG_1
const FILL_FOCUSED_COLOR   := Palette.BG_0
const BORDER_COLOR         := Palette.FG_1
const BORDER_FOCUSED_COLOR := Palette.BLUE
const BORDER_WIDTH         := 3.0
const LABEL_COLOR          := Palette.FG_1
const FONT_SIZE            := 11
const NAME_FONT_SIZE       := 22

const INTAKE_W    :=  4 * TILE_SIZE   # fixed intake zone
const HOPPER_W    :=  2 * TILE_SIZE   # fixed hopper zone
const STATION_W   :=  3 * TILE_SIZE   # fixed per-station width
const OUTPUT_W    :=  2 * TILE_SIZE   # fixed output zone
const SECTION_PAD := 4
const CARD_INSET_H := 12   ## horizontal inset of each card from its zone boundary (gap = 2 × CARD_INSET_H = 24 px)
const CARD_INSET_V := 12   ## vertical inset of each card from the zone top/bottom

## Minimum tile width when there are no stations (intake+hopper+output).
const MIN_TILE_W := (INTAKE_W + HOPPER_W + OUTPUT_W) / TILE_SIZE   # 8 tiles

## Computed at configure time from the number of stations.
var _line_w: int = (INTAKE_W + HOPPER_W + OUTPUT_W)
## Computed at configure time from the number of intake queues.
var _line_h: int = LINE_H_MIN

const INTAKE_QUEUE_SCENE := preload("res://scenes/entities/IntakeQueue.tscn")
const HOPPER_SCENE       := preload("res://scenes/entities/Hopper.tscn")
const STATION_SCENE      := preload("res://scenes/entities/Station.tscn")
const OUTPUT_SCENE       := preload("res://scenes/entities/Output.tscn")
const OVERLAY_SCENE      := preload("res://scenes/entities/StationOverlay.tscn")

## Emitted to FactoryFloor to initiate a drag-move flow.
signal move_requested(entity: Node2D, tile_w: int, tile_h: int)
## Emitted so FactoryFloor can persist focus state and apply gray-out.
signal focus_toggled(entity_id: int, focused: bool)
## Emitted so FactoryFloor can persist lock state.
signal lock_toggled(entity_id: int, locked: bool)
## Emitted when the user wants to create an intake queue on this line.
signal create_intake_queue_requested(line_id: int)
## Emitted when the user wants to create a station on this line.
signal create_station_requested(line_id: int)
## Emitted when the user taps a + button to insert a station.
## index is the array-position for the new station; null means append after last.
signal insert_station_requested(line_id: int, index)
## Emitted when the user taps a + button to insert an intake queue.
## index is the 0-based position for the new queue; null means append after last.
signal insert_intake_queue_requested(line_id: int, index)
## Emitted when the user confirms deletion of a station.
signal delete_station_requested(line_id: int, station_id: int)
## Emitted when the user confirms deletion of an intake queue.
signal delete_intake_queue_requested(line_id: int, queue_id: int)

var _data: Dictionary = {}
var _entity_id: int = 0
var _focused: bool = false
var _locked: bool = false
var _hovered: bool = false
# Placement collision — sized to exact pixel dimensions at configure time.
var _area: Area2D
var _col_shape: RectangleShape2D

var _overlays: Array[Node] = []      # StationOverlay instances, one per station
var _station_nodes: Array[Node] = [] # Station instances from last _rebuild_stations()
var _expansion_blocked_right: bool = false
var _expansion_blocked_down: bool = false
var _station_insert_blocked: bool = false
var _insert_btns: Node2D = null
var _station_toolbar: EntityToolbar = null  # toggle + Add/Delete above first station
var _add_mode: bool = false
var _delete_mode: bool = false
var _intake_toolbar: EntityToolbar = null   # toggle + Add/Delete above first intake queue
var _iq_nodes: Array[Node] = []             # IntakeQueue instances from last rebuild
var _intake_add_mode: bool = false
var _intake_delete_mode: bool = false
var _intake_insert_btns: Node2D = null

@onready var _label:            Label         = $Label
@onready var _sections:         Node2D        = $Sections
@onready var _conveyors:        Node2D        = $Conveyors
@onready var _controls:         HBoxContainer = $Controls
@onready var _move_btn:         Button        = $Controls/MoveButton
@onready var _focus_btn:        Button        = $Controls/FocusButton
@onready var _lock_btn:         Button        = $Controls/LockButton
@onready var _intake_empty_lbl: Label         = $IntakeEmptyLabel


func _ready() -> void:
	set_process_input(true)
	queue_redraw()
	# Build Area2D for pixel-accurate placement collision detection.
	var col := CollisionShape2D.new()
	_col_shape = RectangleShape2D.new()
	col.shape = _col_shape
	_area = Area2D.new()
	_area.collision_layer = 1
	_area.collision_mask  = 0
	_area.monitoring      = false
	_area.monitorable     = true
	_area.add_child(col)
	add_child(_area)

	# Wire control buttons once — _rebuild_controls only repositions them.
	for btn in [_move_btn, _focus_btn, _lock_btn]:
		Palette.style_edit_button(btn)
		btn.add_theme_font_size_override("font_size", 10)
	_move_btn.pressed.connect(_on_move_pressed)
	_focus_btn.pressed.connect(_on_focus_pressed)
	_lock_btn.pressed.connect(_on_lock_pressed)
	_controls.resized.connect(_reposition_controls)
	_insert_btns = Node2D.new()
	add_child(_insert_btns)
	_intake_insert_btns = Node2D.new()
	add_child(_intake_insert_btns)
	_station_toolbar = EntityToolbar.new()
	add_child(_station_toolbar)
	_station_toolbar.visible = false
	_station_toolbar.add_mode_changed.connect(func(on: bool):
		_set_add_mode(on)
		_rebuild_conveyors()
	)
	_station_toolbar.delete_mode_changed.connect(_set_delete_mode)
	_intake_toolbar = EntityToolbar.new()
	add_child(_intake_toolbar)
	_intake_toolbar.visible = false
	_intake_toolbar.add_mode_changed.connect(func(on: bool):
		_set_intake_add_mode(on)
		_rebuild_intake_insert_buttons()
	)
	_intake_toolbar.delete_mode_changed.connect(_set_intake_delete_mode)

	# Position intake-empty label — CONTENT_TOP is always the top value used.
	var intake_card_w := float(INTAKE_W - CARD_INSET_H * 2)
	_intake_empty_lbl.position = Vector2(CARD_INSET_H + 4, CONTENT_TOP + CARD_INSET_V + 4)
	_intake_empty_lbl.custom_minimum_size = Vector2(intake_card_w - 8, 0)
	_intake_empty_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	_intake_empty_lbl.add_theme_font_size_override("font_size", FONT_SIZE)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := to_local(get_global_mouse_position())
		var inside := Rect2(0, 0, _line_w, _line_h).has_point(local)
		if inside != _hovered:
			_set_hovered(inside)


## Populate the node from a LeanFragment.FactoryFloor.Line dictionary.
func configure(data: Dictionary) -> void:
	_data = data
	_entity_id = data.get("id", 0)
	_locked = data.get("locked", false)

	_compute_line_w()
	_compute_line_h()
	# Keep collision shape in sync with exact pixel dimensions.
	_col_shape.size = Vector2(_line_w, _line_h)
	_area.position  = Vector2(_line_w / 2.0, _line_h / 2.0)

	position = Vector2(
		data.get("gridX", 0) * TILE_SIZE,
		data.get("gridY", 0) * TILE_SIZE
	)

	_label.text = str(data.get("name", ""))
	_label.add_theme_color_override("font_color", LABEL_COLOR)
	_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_label.position = Vector2(BORDER_WIDTH + 4, BORDER_WIDTH + 2)

	_rebuild_sections()
	_rebuild_conveyors()
	_rebuild_controls()
	queue_redraw()


## Recompute _line_w from the furthest-right station column.
func _compute_line_w() -> void:
	var stations: Array = _data.get("stations", [])
	var n_cols := (_max_station_pos_x() + 1) if not stations.is_empty() else 1
	var out_w: int = OUTPUT_W if _data.get("hasOutput", true) else 0
	_line_w = INTAKE_W + HOPPER_W + n_cols * STATION_W + out_w


## How many tiles wide this Line currently is.
func tile_w() -> int:
	return _line_w / TILE_SIZE

## Recompute _line_h from intake queue count and station row count.
func _compute_line_h() -> void:
	var slot_h := 2 * TILE_SIZE
	var n_iq: int = max(1, (_data.get("intakeQueues", []) as Array).size())
	var intake_grid_h := n_iq * slot_h + (n_iq - 1) * SECTION_PAD
	var stations: Array = _data.get("stations", [])
	var n_rows := (_max_station_pos_y() + 1) if not stations.is_empty() else 1
	var station_grid_h := n_rows * slot_h + (n_rows - 1) * SECTION_PAD
	_line_h = CONTENT_TOP + max(intake_grid_h, station_grid_h)

## How many tiles tall this Line currently is (grid footprint, rounded up).
func tile_h() -> int:
	return ceili(float(_line_h) / TILE_SIZE)


func update(data: Dictionary) -> void:
	configure(data)


## Apply or remove the gray-out effect (unfocused state).
## Uses modulate so the effect propagates to all child entities.
func set_grayed(grayed: bool) -> void:
	modulate = Color(0.5, 0.5, 0.5, 0.8) if grayed else Color.WHITE


func _draw() -> void:
	var fill   := FILL_FOCUSED_COLOR   if _focused else FILL_COLOR
	var border := BORDER_FOCUSED_COLOR if _focused else BORDER_COLOR
	fill.a = 0.8 if _hovered else 0.2
	draw_rect(Rect2(0, 0, _line_w, _line_h), fill)
	draw_rect(Rect2(0, 0, _line_w, _line_h), border, false, BORDER_WIDTH)

func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_controls.visible = hovered
	queue_redraw()


func _reposition_controls() -> void:
	_controls.position = Vector2(
		_line_w - _controls.size.x - int(BORDER_WIDTH) - 2,
		int(BORDER_WIDTH) + 2
	)


func _rebuild_controls() -> void:
	_move_btn.disabled = _locked
	_focus_btn.text = "Unfocus" if _focused else "Focus"
	_lock_btn.text = "Unlock" if _locked else "Lock"
	_controls.reset_size()
	_controls.visible = _hovered
	_reposition_controls()


func _on_move_pressed() -> void:
	if _locked:
		return
	move_requested.emit(self, tile_w(), tile_h())


func _on_focus_pressed() -> void:
	_focused = !_focused
	_focus_btn.text = "Unfocus" if _focused else "Focus"
	focus_toggled.emit(_entity_id, _focused)
	queue_redraw()


func _on_lock_pressed() -> void:
	_locked = !_locked
	_lock_btn.text = "Unlock" if _locked else "Lock"
	_move_btn.disabled = _locked
	lock_toggled.emit(_entity_id, _locked)


## Returns the largest posX value across all stations (0 when none).
func _max_station_pos_x() -> int:
	var mx: int = 0
	for s: Dictionary in (_data.get("stations", []) as Array):
		mx = max(mx, s.get("posX", 0))
	return mx


## Returns the largest posY value across all stations (0 when none).
func _max_station_pos_y() -> int:
	var my: int = 0
	for s: Dictionary in (_data.get("stations", []) as Array):
		my = max(my, s.get("posY", 0))
	return my


## Pixel-space bounding rect of this line (world position + current dimensions).
func bounds() -> Rect2:
	return Rect2(position, Vector2(_line_w, _line_h))

## Width added by one additional station column (pixels).
func expansion_slot_w() -> float:
	return float(STATION_W)

## Height added by one additional station row (pixels).
func expansion_slot_h() -> float:
	return 2.0 * TILE_SIZE + SECTION_PAD


## Called by FactoryFloor after each render to mark whether growing this line
## right or down would collide with a neighbouring entity.
func set_expansion_blocked(right: bool, down: bool) -> void:
	_expansion_blocked_right = right
	_expansion_blocked_down  = down
	_refresh_station_expansion_buttons()


## Propagate current expansion-block state to each station's move buttons.
func _refresh_station_expansion_buttons() -> void:
	var max_x := _max_station_pos_x()
	var max_y := _max_station_pos_y()
	for st_node in _station_nodes:
		if not is_instance_valid(st_node):
			continue
		var pos_x: int = st_node.get("_pos_x") if st_node.get("_pos_x") != null else 0
		var pos_y: int = st_node.get("_pos_y") if st_node.get("_pos_y") != null else 0
		var block_r: bool = (pos_x == max_x) and _expansion_blocked_right
		var block_d: bool = (pos_y == max_y) and _expansion_blocked_down
		if st_node.has_method("refresh_expansion_block"):
			st_node.refresh_expansion_block(block_r, block_d)


## Returns grid position (posX, posY) of station[station_index].
func _station_pos(station_index: int) -> Vector2i:
	var stations: Array = _data.get("stations", [])
	if station_index >= stations.size():
		return Vector2i(station_index, 0)
	var s := stations[station_index] as Dictionary
	return Vector2i(s.get("posX", station_index), s.get("posY", 0))


## Returns a local-space point at the center of the requested card edge.
## edge_dir must be a unit cardinal vector: (1,0) right  (-1,0) left  (0,1) bottom  (0,-1) top.
func _station_card_edge(pos_x: int, pos_y: int, edge_dir: Vector2) -> Vector2:
	var slot_h := 2.0 * TILE_SIZE
	var zone_x := float(INTAKE_W + HOPPER_W)
	var col_x  := zone_x + pos_x * float(STATION_W)
	var row_y  := float(CONTENT_TOP) + pos_y * (slot_h + float(SECTION_PAD))
	var cx := col_x + float(STATION_W) / 2.0
	var cy := row_y + slot_h / 2.0
	if edge_dir.x > 0:
		return Vector2(col_x + float(STATION_W) - CARD_INSET_H, cy)
	elif edge_dir.x < 0:
		return Vector2(col_x + CARD_INSET_H, cy)
	elif edge_dir.y > 0:
		return Vector2(cx, row_y + slot_h - CARD_INSET_V)
	else:
		return Vector2(cx, row_y + CARD_INSET_V)


func _rebuild_sections() -> void:
	_station_nodes.clear()
	_iq_nodes.clear()
	for child in _sections.get_children():
		child.queue_free()
	for ov in _overlays:
		ov.queue_free()
	_overlays.clear()

	# Hopper/stations/output: fixed height at CONTENT_TOP. Intake queues stack vertically below.
	var h   := 2 * TILE_SIZE
	var top := float(CONTENT_TOP)

	_rebuild_intake_queues(top, h)
	_rebuild_hopper(top, h)
	_rebuild_stations(top, h)
	_rebuild_output_placeholder(top, h)
	_refresh_station_expansion_buttons()


func _rebuild_intake_queues(top: float, _h: float) -> void:
	var intake_queues: Array = _data.get("intakeQueues", [])
	var card_w := float(INTAKE_W - CARD_INSET_H * 2)
	var slot_h := 2.0 * TILE_SIZE
	var card_h := slot_h - CARD_INSET_V * 2.0

	_intake_empty_lbl.hide()
	if intake_queues.is_empty():
		_intake_toolbar.visible = false
		var btn := Button.new()
		btn.text = "Create intake queue"
		btn.position = Vector2(CARD_INSET_H, top + CARD_INSET_V)
		btn.size = Vector2(card_w, card_h)
		Palette.style_panel_button(btn)
		_sections.add_child(btn)
		btn.pressed.connect(func(): create_intake_queue_requested.emit(_entity_id))
		return

	# Show intake toolbar above first intake queue.
	var iq_toolbar_y := float(CONTENT_TOP) - EntityToolbar.BTN_H + 6.0
	_intake_toolbar.setup(float(CARD_INSET_H), iq_toolbar_y)
	_intake_toolbar.visible = true

	# Stack intake queues vertically from CONTENT_TOP downward.
	for i in intake_queues.size():
		var card_y := top + CARD_INSET_V + i * (slot_h + SECTION_PAD)
		var iq := INTAKE_QUEUE_SCENE.instantiate()
		_sections.add_child(iq)
		iq.configure(intake_queues[i], CARD_INSET_H, card_y, card_w, card_h)
		_iq_nodes.append(iq)
		if iq.has_signal("delete_requested"):
			iq.delete_requested.connect(_on_iq_delete_requested)
		iq.set_add_mode(_intake_add_mode)
		iq.set_delete_mode(_intake_delete_mode)


func _rebuild_hopper(top: float, h: float) -> void:
	var hopper := HOPPER_SCENE.instantiate()
	_sections.add_child(hopper)
	var card_x := INTAKE_W + CARD_INSET_H
	var card_w := HOPPER_W - CARD_INSET_H * 2
	hopper.configure(_data, card_x, top + CARD_INSET_V, card_w, h - CARD_INSET_V * 2.0)


func _rebuild_station_placeholder(_top: float, _h: float) -> void:
	pass


func _rebuild_stations(top: float, h: float) -> void:
	var stations: Array = _data.get("stations", [])
	var zone_x  := float(INTAKE_W + HOPPER_W)
	var card_w  := float(STATION_W) - CARD_INSET_H * 2
	var card_h  := h - CARD_INSET_V * 2.0

	if stations.is_empty():
		_station_toolbar.visible = false
		var btn := Button.new()
		btn.text = "Create station"
		btn.position = Vector2(zone_x + CARD_INSET_H, top + CARD_INSET_V)
		btn.size = Vector2(card_w, card_h)
		Palette.style_panel_button(btn)
		_sections.add_child(btn)
		btn.pressed.connect(func(): create_station_requested.emit(_entity_id))
		return

	var slot_h  := h  # 2 × TILE_SIZE

	# Build occupied set: {posX: {posY: true}} — passed to each Station so it
	# can enable/disable its directional move buttons without a server round-trip.
	var occupied: Dictionary = {}
	for s: Dictionary in stations:
		var px: int = s.get("posX", 0)
		var py: int = s.get("posY", 0)
		if not occupied.has(px):
			occupied[px] = {}
		(occupied[px] as Dictionary)[py] = true

	for i in stations.size():
		var s := stations[i] as Dictionary
		var pos_x: int = s.get("posX", i)
		var pos_y: int = s.get("posY", 0)

		var col_x  := zone_x + pos_x * float(STATION_W)
		var row_y  := top + pos_y * (slot_h + SECTION_PAD)
		var card_x := col_x + CARD_INSET_H
		var card_y := row_y + CARD_INSET_V

		var station := STATION_SCENE.instantiate()
		_sections.add_child(station)
		station.configure(s, i, card_x, card_y, card_w, card_h, occupied)
		_station_nodes.append(station)
		station.overlay_requested.connect(
				func(st: Node2D, ot: String): _on_overlay_requested(st, ot, card_x, row_y)
		)
		station.station_move_requested.connect(_on_station_move_requested)
		station.delete_requested.connect(_on_station_delete_requested)
		# Apply current add/delete mode to newly created station.
		station.set_add_mode(_add_mode)
		station.set_delete_mode(_delete_mode)

		var overlay := OVERLAY_SCENE.instantiate() as Node2D
		add_child(overlay)
		overlay.set_width(card_w)
		_overlays.append(overlay)
		station.set_meta("overlay", overlay)

		var saved: String = s.get("overlay", "none")
		if saved != "none":
			var restore_type := "work_units" if saved == "workUnits" else "operations"
			_show_station_overlay(station, restore_type, card_x, row_y)

	# Position the station toolbar above the first station card.
	var first_s := stations[0] as Dictionary
	var first_px_s: int = first_s.get("posX", 0)
	var st_card_left := float(INTAKE_W + HOPPER_W) + first_px_s * float(STATION_W) + CARD_INSET_H
	_station_toolbar.setup(st_card_left, float(CONTENT_TOP) - EntityToolbar.BTN_H + 6.0)
	_station_toolbar.visible = true


func _on_station_move_requested(station_id: int, new_pos_x: int, new_pos_y: int) -> void:
	await BOSSBridge.patch("/lean/station/%d/position" % station_id,
		{"posX": new_pos_x, "posY": new_pos_y})
	BOSSBridge.poll_snapshot()


func _on_station_delete_requested(station_id: int, _station_name: String) -> void:
	delete_station_requested.emit(_entity_id, station_id)


## Show a station's overlay without persisting — used for auto-restore during rebuild.
func _show_station_overlay(station: Node2D, overlay_type: String, card_x: float, card_top: float) -> void:
	var overlay: Node2D = station.get_meta("overlay")
	overlay.set_meta("active_type", overlay_type)
	overlay.position = Vector2(card_x, card_top + station._card_h + 2)
	if overlay_type == "work_units":
		overlay.show_work_units(station._data)
	else:
		overlay.show_operations(station._data)


func _on_overlay_requested(station: Node2D, overlay_type: String,
		card_x: float, card_top: float) -> void:
	if not station.has_meta("overlay"):
		return
	var station_id: int = (station._data as Dictionary).get("id", 0)
	var overlay: Node2D = station.get_meta("overlay")

	# Toggle: pressing the same button again closes this station's overlay.
	var current_type: String = overlay.get_meta("active_type", "")
	if current_type == overlay_type and overlay.is_visible():
		overlay.hide_overlay()
		overlay.set_meta("active_type", "")
		BOSSBridge.patch("/lean/station/view-state/%d" % station_id, {"overlay": "none"})
		return

	var api_overlay := "workUnits" if overlay_type == "work_units" else "operations"
	BOSSBridge.patch("/lean/station/view-state/%d" % station_id, {"overlay": api_overlay})
	_show_station_overlay(station, overlay_type, card_x, card_top)


func _rebuild_output_placeholder(top: float, h: float) -> void:
	if not _data.get("hasOutput", true):
		return
	var stations: Array = _data.get("stations", [])
	var n_cols: int = (_max_station_pos_x() + 1) if not stations.is_empty() else 1
	var x := INTAKE_W + HOPPER_W + n_cols * STATION_W + CARD_INSET_H
	var output := OUTPUT_SCENE.instantiate()
	_sections.add_child(output)
	output.configure(x, top + CARD_INSET_V, OUTPUT_W - CARD_INSET_H * 2, h - CARD_INSET_V * 2.0, int(_data.get("id", 0)))



## Update the blocked state for station-insert + buttons, then rebuild conveyors
## (which also rebuilds the + buttons).
func set_station_insert_blocked(blocked: bool) -> void:
	_station_insert_blocked = blocked
	_rebuild_conveyors()


## Returns the exit direction of the last station belt stub (right or left).
func _exit_direction() -> Vector2:
	var stations: Array = _data.get("stations", [])
	if stations.size() < 2:
		return Vector2(1, 0)
	var last := stations.back() as Dictionary
	var prev := stations[stations.size() - 2] as Dictionary
	var lpx: int = last.get("posX", 0)
	var ppx: int = prev.get("posX", 0)
	if ppx > lpx:
		return Vector2(-1, 0)
	return Vector2(1, 0)


## Returns the exit direction delta for the inter-station belt at index i→i+1.
func _belt_dirs(i: int) -> Array:
	var stations: Array = _data.get("stations", [])
	var curr := stations[i] as Dictionary
	var next := stations[i + 1] as Dictionary
	var dx: int = next.get("posX", i + 1) - curr.get("posX", i)
	var dy: int = next.get("posY", 0) - curr.get("posY", 0)
	var from_dir: Vector2
	var to_dir: Vector2
	if dx > 0 and dy > 0:
		from_dir = Vector2(1, 0);  to_dir = Vector2(0, -1)
	elif dx < 0 and dy > 0:
		from_dir = Vector2(0, 1);  to_dir = Vector2(1, 0)
	elif dx > 0 and dy < 0:
		from_dir = Vector2(1, 0);  to_dir = Vector2(0, 1)
	elif dx < 0 and dy < 0:
		from_dir = Vector2(0, -1); to_dir = Vector2(1, 0)
	elif dx > 0:
		from_dir = Vector2(1, 0);  to_dir = Vector2(-1, 0)
	elif dx < 0:
		from_dir = Vector2(-1, 0); to_dir = Vector2(1, 0)
	elif dy > 0:
		from_dir = Vector2(0, 1);  to_dir = Vector2(0, -1)
	else:
		from_dir = Vector2(0, -1); to_dir = Vector2(0, 1)
	return [from_dir, to_dir]


## Draw all + insert-station buttons overlaid on the station belt path.
## Called from _rebuild_conveyors — only shown when Add mode is active.
func _rebuild_station_insert_buttons() -> void:
	for child in _insert_btns.get_children():
		child.queue_free()
	if not _add_mode:
		return
	var stations: Array = _data.get("stations", [])
	if stations.is_empty():
		return

	var slot_h := 2.0 * TILE_SIZE
	var mid_y := float(CONTENT_TOP) + slot_h / 2.0
	var btn_size := Vector2(16.0, 16.0)
	var blocked: bool = _station_insert_blocked
	var tooltip_blocked := "Last station is blocked and can not move in any direction."

	# Helper: place a styled + button above the belt at center_pt.
	# Button is horizontally centered on center_pt.x; bottom edge at center_pt.y.
	var _make_btn := func(center_pt: Vector2, idx) -> void:
		var btn := ConveyorBelt.InsertButton.new()
		btn.position = Vector2(center_pt.x - btn_size.x * 0.5, center_pt.y - btn_size.y * 0.5)
		btn.setup(Palette.GREEN, blocked, tooltip_blocked if blocked else "")
		if not blocked:
			btn.pressed.connect(func(): insert_station_requested.emit(_entity_id, idx))
		_insert_btns.add_child(btn)

	# First button: on the hopper→station[0] gap belt.
	var gap_center := Vector2(float(INTAKE_W + HOPPER_W), mid_y)
	_make_btn.call(gap_center, 1)

	# Between-station buttons: midpoint of each inter-station belt segment.
	for i in range(stations.size() - 1):
		var dirs: Array = _belt_dirs(i)
		var from_dir: Vector2 = dirs[0]
		var to_dir: Vector2   = dirs[1]
		var curr := stations[i] as Dictionary
		var next := stations[i + 1] as Dictionary
		var cpx: int = curr.get("posX", i)
		var cpy: int = curr.get("posY", 0)
		var npx: int = next.get("posX", i + 1)
		var npy: int = next.get("posY", 0)
		var from_pt := _station_card_edge(cpx, cpy, from_dir)
		var to_pt   := _station_card_edge(npx, npy, to_dir)
		var belt_waypoints := ConveyorBelt._build_stub_waypoints(from_pt, from_dir, to_pt, to_dir, ConveyorBelt.STUB_LEN)
		var mid_pt  := ConveyorBelt.path_midpoint(belt_waypoints)
		_make_btn.call(mid_pt, i + 2)

	# Last button: placed 10px past exit edge (stub was drawn in _rebuild_conveyors).
	var last := stations.back() as Dictionary
	var lpx: int = last.get("posX", stations.size() - 1)
	var lpy: int = last.get("posY", 0)
	var exit_dir := _exit_direction()
	var edge_pt := _station_card_edge(lpx, lpy, exit_dir)
	# Center = edge_pt + exit_dir * (stub_len + half_btn_w)
	var last_center := Vector2(
		edge_pt.x + exit_dir.x * (10.0 + btn_size.x * 0.5) - exit_dir.x * 5.0,
		edge_pt.y
	)
	_make_btn.call(last_center, null)

func _rebuild_conveyors() -> void:
	for child in _conveyors.get_children():
		child.queue_free()

	var mid_y := float(CONTENT_TOP) + TILE_SIZE  # vertical center of row 0

	# Intake → Hopper
	ConveyorBelt.draw_animated(
		Vector2(INTAKE_W - CARD_INSET_H, mid_y),
		Vector2(INTAKE_W + CARD_INSET_H, mid_y),
		_conveyors
	)

	# Hopper → station zone (station[0] is always at posX=0, posY=0)
	ConveyorBelt.draw_animated(
		Vector2(INTAKE_W + HOPPER_W - CARD_INSET_H, mid_y),
		Vector2(INTAKE_W + HOPPER_W + CARD_INSET_H, mid_y),
		_conveyors
	)

	var stations: Array = _data.get("stations", [])

	# Station-to-station belts (array order 0→1→2…, direction from posX/posY delta).
	for i in range(stations.size() - 1):
		var curr := stations[i] as Dictionary
		var next := stations[i + 1] as Dictionary
		var cpx: int = curr.get("posX", i)
		var cpy: int = curr.get("posY", 0)
		var npx: int = next.get("posX", i + 1)
		var npy: int = next.get("posY", 0)
		var dx: int = npx - cpx
		var dy: int = npy - cpy

		var from_dir: Vector2
		var to_dir: Vector2
		if dx > 0 and dy > 0:
			# Right + down: exit right edge, enter top edge.
			from_dir = Vector2(1, 0);  to_dir = Vector2(0, -1)
		elif dx < 0 and dy > 0:
			# Left + down: exit bottom edge, enter right edge.
			from_dir = Vector2(0, 1);  to_dir = Vector2(1, 0)
		elif dx > 0 and dy < 0:
			# Right + up: exit right edge, enter bottom edge.
			from_dir = Vector2(1, 0);  to_dir = Vector2(0, 1)
		elif dx < 0 and dy < 0:
			# Left + up: exit top edge, enter right edge.
			from_dir = Vector2(0, -1); to_dir = Vector2(1, 0)
		elif dx > 0:
			from_dir = Vector2(1, 0);  to_dir = Vector2(-1, 0)
		elif dx < 0:
			from_dir = Vector2(-1, 0); to_dir = Vector2(1, 0)
		elif dy > 0:
			from_dir = Vector2(0, 1);  to_dir = Vector2(0, -1)
		else:
			from_dir = Vector2(0, -1); to_dir = Vector2(0, 1)

		var from_pt := _station_card_edge(cpx, cpy, from_dir)
		var to_pt   := _station_card_edge(npx, npy, to_dir)
		ConveyorBelt.draw_routed(
			from_pt, to_pt,
			_conveyors, ConveyorBelt.BELT_COLOR, from_dir, to_dir
		)


	# Last-station exit stub: 10px belt in exit direction (+ button follows it).
	# Only drawn when there is no Output; when hasOutput is true the gap belt
	# already starts from the same point and would cause a double-chevron blink.
	var _stub_has_output: bool = _data.get("hasOutput", true)
	if not stations.is_empty() and not _stub_has_output:
		var last_s := stations.back() as Dictionary
		var slpx: int = last_s.get("posX", stations.size() - 1)
		var slpy: int = last_s.get("posY", 0)
		var s_exit_dir := _exit_direction()
		var s_edge_pt := _station_card_edge(slpx, slpy, s_exit_dir)
		ConveyorBelt.draw_animated(
			s_edge_pt,
			s_edge_pt + s_exit_dir * 10.0,
			_conveyors
		)


	# Station zone → Output gap belt.
	var has_output: bool = _data.get("hasOutput", true)
	if has_output:
		var sx := float(INTAKE_W + HOPPER_W) + float(_max_station_pos_x() + 1) * float(STATION_W)
		ConveyorBelt.draw_animated(
			Vector2(sx - CARD_INSET_H, mid_y),
			Vector2(sx + CARD_INSET_H, mid_y),
			_conveyors
		)

	_rebuild_station_insert_buttons()
	_rebuild_intake_insert_buttons()


## Draw all + insert-intake-queue buttons above/below/between intake queues.
## Only shown when intake Add mode is active.
func _rebuild_intake_insert_buttons() -> void:
	for child in _intake_insert_btns.get_children():
		child.queue_free()
	if not _intake_add_mode:
		return
	var queues: Array = _data.get("intakeQueues", [])
	if queues.is_empty():
		return

	var slot_h := 2.0 * TILE_SIZE
	var card_h := slot_h - CARD_INSET_V * 2.0
	var card_w := float(INTAKE_W - CARD_INSET_H * 2)
	var btn_size := Vector2(16.0, 16.0)
	var btn_center_x := CARD_INSET_H + card_w / 2.0

	var _make_btn := func(btn_y: float, idx) -> void:
		var btn := ConveyorBelt.InsertButton.new()
		btn.position = Vector2(btn_center_x - btn_size.x * 0.5, btn_y)
		btn.setup(Palette.GREEN, false, "")
		btn.pressed.connect(func(): insert_intake_queue_requested.emit(_entity_id, idx))
		_intake_insert_btns.add_child(btn)

	# Above first queue: button bottom abuts card top.
	var card_y_0 := float(CONTENT_TOP) + CARD_INSET_V
	_make_btn.call(card_y_0 - btn_size.y, 0)

	# Between queues: centered in the gap.
	for i in range(queues.size() - 1):
		var card_bottom_i := float(CONTENT_TOP) + CARD_INSET_V + i * (slot_h + SECTION_PAD) + card_h
		var gap := CARD_INSET_V + SECTION_PAD + CARD_INSET_V
		_make_btn.call(card_bottom_i + (gap - btn_size.y) * 0.5, i + 1)

	# Below last queue: button top abuts card bottom.
	var last_i := queues.size() - 1
	var card_bottom_last := float(CONTENT_TOP) + CARD_INSET_V + last_i * (slot_h + SECTION_PAD) + card_h
	_make_btn.call(card_bottom_last, null)


func _set_intake_add_mode(on: bool) -> void:
	_intake_add_mode = on
	for iq in _iq_nodes:
		if iq.has_method("set_add_mode"):
			iq.set_add_mode(on)


func _set_intake_delete_mode(on: bool) -> void:
	_intake_delete_mode = on
	for iq in _iq_nodes:
		if iq.has_method("set_delete_mode"):
			iq.set_delete_mode(on)


func _on_iq_delete_requested(queue_id: int, _queue_name: String) -> void:
	delete_intake_queue_requested.emit(_entity_id, queue_id)


func _set_add_mode(on: bool) -> void:
	_add_mode = on
	for stn in _station_nodes:
		if stn.has_method("set_add_mode"):
			stn.set_add_mode(on)


func _set_delete_mode(on: bool) -> void:
	_delete_mode = on
	for stn in _station_nodes:
		if stn.has_method("set_delete_mode"):
			stn.set_delete_mode(on)


## World-space left-edge center of station[index]. Used for Inventory→Station belts.
func get_station_input_world(station_index: int) -> Vector2:
	var sp := _station_pos(station_index)
	return position + _station_card_edge(sp.x, sp.y, Vector2(-1, 0))


## World-space top-center of station[index]. Used as the subassembly forward/return anchor.
func get_station_top_world(station_index: int) -> Vector2:
	var sp := _station_pos(station_index)
	var cx := float(INTAKE_W + HOPPER_W) + sp.x * float(STATION_W) + float(STATION_W) / 2.0
	return position + Vector2(cx, 0.0)


## World-space top-center of the station card for station[index]. Used for intake-queue belt exit (top).
func get_station_card_top_world(station_index: int) -> Vector2:
	var sp := _station_pos(station_index)
	return position + _station_card_edge(sp.x, sp.y, Vector2(0, -1))


## World-space bottom-center of the station card for station[index]. Used for intake-queue belt exit (bottom).
func get_station_card_bottom_world(station_index: int) -> Vector2:
	var sp := _station_pos(station_index)
	return position + _station_card_edge(sp.x, sp.y, Vector2(0, 1))


## World-space left-center of the intake queue card identified by queue_id.
## Returns position (line origin) as a fallback if the queue is not found.
func get_intake_queue_left_world(queue_id: int) -> Vector2:
	var intake_queues: Array = _data.get("intakeQueues", [])
	var slot_h := 2.0 * TILE_SIZE
	for i in intake_queues.size():
		if (intake_queues[i] as Dictionary).get("id", -1) == queue_id:
			var center_y := float(CONTENT_TOP) + i * (slot_h + SECTION_PAD) + slot_h / 2.0
			return position + Vector2(0.0, center_y)
	return position   # fallback: queue not found on this line


## World-space left-center of the first intake queue card. Used for connectsToLine belt routing.
func get_first_intake_queue_left_world() -> Vector2:
	var slot_h := 2.0 * TILE_SIZE
	var center_y := float(CONTENT_TOP) + slot_h / 2.0
	return position + Vector2(0.0, center_y)


## World-space left-edge center of the first intake queue. Subassembly return target.
func get_first_intake_world() -> Vector2:
	var mid_y := float(CONTENT_TOP) + TILE_SIZE   # center of 2-tile content row
	return position + Vector2(0.0, mid_y)


## World-space right-edge center of the output section. Subassembly return source.
func get_output_world() -> Vector2:
	var mid_y := float(CONTENT_TOP) + TILE_SIZE   # center of 2-tile content row
	return position + Vector2(_line_w, mid_y)


## World-space bounding rect of this Line. Used by Conveyor routing to avoid drawing through the box.
func get_bounds_world() -> Rect2:
	return Rect2(position, Vector2(_line_w, _line_h))


## Returns the physics RID of this Line's Area2D, used for DragOverlay placement queries.
func get_area_rid() -> RID:
	return _area.get_rid()


## Called by FactoryFloor when camera zoom index changes.
## zi: 0=100% 1=75% 2=50% 3=25%
func set_zoom_index(zi: int) -> void:
	_label.visible = (zi < 3)
	for ov in _overlays:
		ov.set_zoom_index(zi)
