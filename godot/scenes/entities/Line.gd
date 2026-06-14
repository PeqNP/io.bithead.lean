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

const INTAKE_W    :=  4 * TILE_SIZE   # fixed intake zone
const HOPPER_W    :=  2 * TILE_SIZE   # fixed hopper zone
const STATION_W   :=  3 * TILE_SIZE   # fixed per-station width
const OUTPUT_W    :=  2 * TILE_SIZE   # fixed output zone
const SECTION_PAD := 4

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

var _data: Dictionary = {}
var _entity_id: int = 0
var _focused: bool = false
var _locked: bool = false
var _hovered: bool = false
# Placement collision — sized to exact pixel dimensions at configure time.
var _area: Area2D
var _col_shape: RectangleShape2D

var _overlays: Array[Node] = []  # StationOverlay instances, one per station

@onready var _label:     Label  = $Label
@onready var _sections:  Node2D = $Sections
@onready var _conveyors: Node2D = $Conveyors
@onready var _controls:  Node2D = $Controls


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
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.position = Vector2(BORDER_WIDTH + 4, BORDER_WIDTH + 2)

	_rebuild_sections()
	_rebuild_conveyors()
	_rebuild_controls()
	queue_redraw()


## Recompute _line_w from the current station count.
func _compute_line_w() -> void:
	var n: int = (_data.get("stations", []) as Array).size()
	var stations_w: int = max(0, n) * STATION_W
	var out_w: int = OUTPUT_W if _data.get("hasOutput", true) else 0
	_line_w = INTAKE_W + HOPPER_W + stations_w + out_w


## How many tiles wide this Line currently is.
func tile_w() -> int:
	return _line_w / TILE_SIZE

## Recompute _line_h from the current intake queue count.
func _compute_line_h() -> void:
	var n: int = max(1, (_data.get("intakeQueues", []) as Array).size())
	var card_h := 2 * TILE_SIZE
	_line_h = CONTENT_TOP + n * card_h + (n - 1) * SECTION_PAD + SECTION_PAD

## How many tiles tall this Line currently is (grid footprint, rounded up).
func tile_h() -> int:
	return ceili(float(_line_h) / TILE_SIZE)


func update(data: Dictionary) -> void:
	configure(data)


## Apply or remove the gray-out shader (unfocused state).
func set_grayed(grayed: bool) -> void:
	if grayed:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/gray_out.gdshader")
		material = mat
	else:
		material = null


func _draw() -> void:
	var fill   := FILL_FOCUSED_COLOR   if _focused else FILL_COLOR
	var border := BORDER_FOCUSED_COLOR if _focused else BORDER_COLOR
	draw_rect(Rect2(0, 0, _line_w, _line_h), fill)
	draw_rect(Rect2(0, 0, _line_w, _line_h), border, false, BORDER_WIDTH)

	# Section dividers
	var stations_zone_w := (_data.get("stations", []) as Array).size() * STATION_W
	var dividers := [INTAKE_W, INTAKE_W + HOPPER_W]
	if _data.get("hasOutput", true):
		dividers.append(INTAKE_W + HOPPER_W + stations_zone_w)
	for x in dividers:
		draw_line(Vector2(x, BORDER_WIDTH), Vector2(x, _line_h - BORDER_WIDTH),
			border * Color(1, 1, 1, 0.4), 1.0)

	# Output zone border
	if _data.get("hasOutput", true):
		var ox := float(INTAKE_W + HOPPER_W + stations_zone_w + SECTION_PAD)
		draw_rect(Rect2(ox, float(CONTENT_TOP), float(OUTPUT_W - SECTION_PAD * 2), 2.0 * TILE_SIZE),
			Palette.GREEN, false, BORDER_WIDTH)


# ---------------------------------------------------------------------------
# Hover controls
# ---------------------------------------------------------------------------

func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_controls.visible = hovered


func _rebuild_controls() -> void:
	for child in _controls.get_children():
		child.queue_free()

	var btn_y := int(BORDER_WIDTH) + 2

	var move_btn := _make_ctrl_button("Move", Vector2(_line_w - 190, btn_y))
	move_btn.disabled = _locked
	move_btn.pressed.connect(_on_move_pressed)
	_controls.add_child(move_btn)

	var focus_btn := _make_ctrl_button("Unfocus" if _focused else "Focus",
		Vector2(_line_w - 136, btn_y))
	focus_btn.pressed.connect(_on_focus_pressed.bind(focus_btn))
	_controls.add_child(focus_btn)

	var lock_btn := _make_ctrl_button("Unlock" if _locked else "Lock",
		Vector2(_line_w - 78, btn_y))
	lock_btn.pressed.connect(_on_lock_pressed.bind(lock_btn, move_btn))
	_controls.add_child(lock_btn)

	_controls.visible = _hovered


func _make_ctrl_button(c_text: String, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.text = c_text
	btn.position = pos
	btn.size = Vector2(54, 20)
	btn.add_theme_font_size_override("font_size", 10)
	return btn


func _on_move_pressed() -> void:
	if _locked:
		return
	move_requested.emit(self, tile_w(), tile_h())


func _on_focus_pressed(btn: Button) -> void:
	_focused = !_focused
	btn.text = "Unfocus" if _focused else "Focus"
	focus_toggled.emit(_entity_id, _focused)
	queue_redraw()


func _on_lock_pressed(lock_btn: Button, move_btn: Button) -> void:
	_locked = !_locked
	lock_btn.text = "Unlock" if _locked else "Lock"
	move_btn.disabled = _locked
	lock_toggled.emit(_entity_id, _locked)


func _rebuild_sections() -> void:
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


func _rebuild_intake_queues(top: float, _h: float) -> void:
	var intake_queues: Array = _data.get("intakeQueues", [])
	var card_w := float(INTAKE_W - SECTION_PAD * 2)
	var card_h := 2.0 * TILE_SIZE

	if intake_queues.is_empty():
		# Empty placeholder — a plain label-only node.
		var lbl := Label.new()
		lbl.position = Vector2(SECTION_PAD + 4, top + 4)
		lbl.size = Vector2(card_w - 8, card_h - 8)
		lbl.text = "Intake\n(empty)"
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sections.add_child(lbl)
		return

	# Stack intake queues vertically from CONTENT_TOP downward.
	for i in intake_queues.size():
		var card_y := top + i * (card_h + SECTION_PAD)
		var iq := INTAKE_QUEUE_SCENE.instantiate()
		_sections.add_child(iq)
		iq.configure(intake_queues[i], SECTION_PAD, card_y, card_w, card_h)


func _rebuild_hopper(top: float, h: float) -> void:
	var hopper := HOPPER_SCENE.instantiate()
	_sections.add_child(hopper)
	var card_x := INTAKE_W + SECTION_PAD
	var card_w := HOPPER_W - SECTION_PAD * 2
	hopper.configure(_data, card_x, top, card_w, h)


func _rebuild_station_placeholder(_top: float, _h: float) -> void:
	pass


func _rebuild_stations(top: float, h: float) -> void:
	var stations: Array = _data.get("stations", [])
	var zone_x   := float(INTAKE_W + HOPPER_W)
	var stations_zone_w := float(stations.size() * STATION_W)

	if stations.is_empty():
		# No stations: no zone to show (output follows immediately).
		_add_station_button(zone_x + SECTION_PAD, top, h, _data.get("id", 0), 0)
		return

	var card_w := float(STATION_W) - SECTION_PAD   # fixed per-station width

	for i in stations.size():
		var card_x := zone_x + SECTION_PAD + i * float(STATION_W)
		var station := STATION_SCENE.instantiate()
		_sections.add_child(station)
		station.configure(stations[i], i, card_x, top, card_w, h)
		station.overlay_requested.connect(
			func(s: Node2D, ot: String): _on_overlay_requested(s, ot, card_x, top)
		)

		var overlay := OVERLAY_SCENE.instantiate() as Node2D
		add_child(overlay)
		overlay.set_width(card_w)
		_overlays.append(overlay)
		station.set_meta("overlay", overlay)

		# Restore saved overlay state without making an HTTP call.
		var saved: String = (stations[i] as Dictionary).get("overlay", "none")
		if saved != "none":
			var restore_type := "work_units" if saved == "workUnits" else "operations"
			_show_station_overlay(station, restore_type, card_x, top)

		# "+" before first and between/after stations.
		if i == 0:
			_add_station_button(zone_x + SECTION_PAD - 14, top, h, _data.get("id", 0), 0)
		_add_station_button(zone_x + SECTION_PAD + (i + 1) * float(STATION_W), top, h,
			_data.get("id", 0), i + 1)


## Small "+" button to add a station at a given position.
func _add_station_button(x: float, top: float, h: float,
		line_id: int, position_index: int) -> void:
	var btn := Button.new()
	btn.text = "+"
	btn.position = Vector2(x - 7, top + h / 2.0 - 10)
	btn.size = Vector2(14, 20)
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(_on_add_station.bind(line_id, position_index))
	_sections.add_child(btn)


func _on_add_station(line_id: int, position_index: int) -> void:
	await BOSSBridge.post("/lean/station", {"lineId": line_id, "position": position_index})
	BOSSBridge.poll_snapshot()


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
	var n: int = (_data.get("stations", []) as Array).size()
	var x := INTAKE_W + HOPPER_W + n * STATION_W + SECTION_PAD
	var output := OUTPUT_SCENE.instantiate()
	_sections.add_child(output)
	output.configure(x, top, OUTPUT_W - SECTION_PAD * 2, h, int(_data.get("id", 0)))


func _rebuild_conveyors() -> void:
	for child in _conveyors.get_children():
		child.queue_free()

	# mid_y: center of the 2-tile content row (hopper/stations/output), which is fixed at CONTENT_TOP.
	var mid_y := float(CONTENT_TOP) + TILE_SIZE

	# Intake → Hopper
	Conveyor.draw_animated(
		Vector2(INTAKE_W - SECTION_PAD, mid_y),
		Vector2(INTAKE_W + SECTION_PAD, mid_y),
		_conveyors
	)

	# Hopper → Stations
	Conveyor.draw_animated(
		Vector2(INTAKE_W + HOPPER_W - SECTION_PAD, mid_y),
		Vector2(INTAKE_W + HOPPER_W + SECTION_PAD, mid_y),
		_conveyors
	)

	# Stations → Output
	var has_output: bool = _data.get("hasOutput", true)
	var n_stations: int = (_data.get("stations", []) as Array).size()
	if has_output:
		var sx := INTAKE_W + HOPPER_W + n_stations * STATION_W
		Conveyor.draw_animated(
			Vector2(sx - SECTION_PAD, mid_y),
			Vector2(sx + SECTION_PAD, mid_y),
			_conveyors
		)


## World-space left-edge center of station[index]. Used for Inventory→Station belts.
func get_station_input_world(station_index: int) -> Vector2:
	var card_x := float(INTAKE_W + HOPPER_W + SECTION_PAD + station_index * STATION_W)
	var mid_y := float(CONTENT_TOP) + TILE_SIZE   # center of 2-tile content row
	return position + Vector2(card_x, mid_y)


## World-space top-center of station[index]. Used as the subassembly forward/return anchor.
func get_station_top_world(station_index: int) -> Vector2:
	var card_x := float(INTAKE_W + HOPPER_W + SECTION_PAD + station_index * STATION_W)
	return position + Vector2(card_x + float(STATION_W - SECTION_PAD) / 2.0, 0.0)


## World-space top-center of the station card for station[index]. Used for intake-queue belt exit (top).
func get_station_card_top_world(station_index: int) -> Vector2:
	var card_x := float(INTAKE_W + HOPPER_W + SECTION_PAD + station_index * STATION_W)
	var card_cx := card_x + float(STATION_W - SECTION_PAD) / 2.0
	return position + Vector2(card_cx, float(CONTENT_TOP))


## World-space bottom-center of the station card for station[index]. Used for intake-queue belt exit (bottom).
func get_station_card_bottom_world(station_index: int) -> Vector2:
	var card_x := float(INTAKE_W + HOPPER_W + SECTION_PAD + station_index * STATION_W)
	var card_cx := card_x + float(STATION_W - SECTION_PAD) / 2.0
	return position + Vector2(card_cx, float(CONTENT_TOP) + 2.0 * TILE_SIZE)


## World-space left-center of the intake queue card identified by queue_id.
## Returns position (line origin) as a fallback if the queue is not found.
func get_intake_queue_left_world(queue_id: int) -> Vector2:
	var intake_queues: Array = _data.get("intakeQueues", [])
	var card_h := 2.0 * TILE_SIZE
	for i in intake_queues.size():
		if (intake_queues[i] as Dictionary).get("id", -1) == queue_id:
			var center_y := float(CONTENT_TOP) + i * (card_h + SECTION_PAD) + card_h / 2.0
			return position + Vector2(0.0, center_y)
	return position   # fallback: queue not found on this line


## World-space left-center of the first intake queue card. Used for connectsToLine belt routing.
func get_first_intake_queue_left_world() -> Vector2:
	var card_h := 2.0 * TILE_SIZE
	var center_y := float(CONTENT_TOP) + card_h / 2.0
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
