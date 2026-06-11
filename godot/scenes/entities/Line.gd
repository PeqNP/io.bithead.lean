## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single production Line from a LeanFragment.FactoryFloor.Line snapshot.
##
## Layer 1: static rendering.
## Layer 3: hover controls (Move, Focus, Lock), focus shader.
## Layer 4: IntakeQueue cards, Hopper card, animated chevron conveyors.
## Layer 5: Station cards, Work Units / Operations overlays, Add Station.

extends Node2D

const TILE_SIZE   := 64
const LINE_W      := 12 * TILE_SIZE   # 768 px
const LINE_H      :=  2 * TILE_SIZE   # 128 px

const FILL_COLOR           := Color(0.165, 0.165, 0.353)   # #2a2a5a
const FILL_FOCUSED_COLOR   := Color(0.200, 0.200, 0.440)
const BORDER_COLOR         := Color(0.353, 0.353, 0.667)   # #5a5aaa
const BORDER_FOCUSED_COLOR := Color(0.550, 0.550, 1.000)
const BORDER_WIDTH         := 3.0
const LABEL_COLOR          := Color(1, 1, 1)
const FONT_SIZE            := 11

const INTAKE_W  :=  4 * TILE_SIZE
const HOPPER_W  :=  2 * TILE_SIZE
const STATION_W :=  4 * TILE_SIZE
const OUTPUT_W  :=  2 * TILE_SIZE
const SECTION_PAD := 4

const INTAKE_QUEUE_SCENE := preload("res://scenes/entities/IntakeQueue.tscn")
const HOPPER_SCENE       := preload("res://scenes/entities/Hopper.tscn")
const STATION_SCENE      := preload("res://scenes/entities/Station.tscn")
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

# Layer 5: overlay state (at most one overlay open per Line).
var _active_overlay: Node2D = null   # the StationOverlay instance
var _active_station_id: int = -1
var _active_overlay_type: String = ""

@onready var _label:     Label  = $Label
@onready var _sections:  Node2D = $Sections
@onready var _conveyors: Node2D = $Conveyors
@onready var _controls:  Node2D = $Controls


func _ready() -> void:
	set_process_input(true)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := to_local(get_global_mouse_position())
		var inside := Rect2(0, 0, LINE_W, LINE_H).has_point(local)
		if inside != _hovered:
			_set_hovered(inside)


## Populate the node from a LeanFragment.FactoryFloor.Line dictionary.
func configure(data: Dictionary) -> void:
	_data = data
	_entity_id = data.get("id", 0)
	_locked = data.get("locked", false)

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
	draw_rect(Rect2(0, 0, LINE_W, LINE_H), fill)
	draw_rect(Rect2(0, 0, LINE_W, LINE_H), border, false, BORDER_WIDTH)

	# Section dividers
	for x in [INTAKE_W, INTAKE_W + HOPPER_W, INTAKE_W + HOPPER_W + STATION_W]:
		draw_line(Vector2(x, BORDER_WIDTH), Vector2(x, LINE_H - BORDER_WIDTH),
			border * Color(1, 1, 1, 0.4), 1.0)


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

	var move_btn := _make_ctrl_button("Move", Vector2(LINE_W - 190, btn_y))
	move_btn.disabled = _locked
	move_btn.pressed.connect(_on_move_pressed)
	_controls.add_child(move_btn)

	var focus_btn := _make_ctrl_button("Unfocus" if _focused else "Focus",
		Vector2(LINE_W - 136, btn_y))
	focus_btn.pressed.connect(_on_focus_pressed.bind(focus_btn))
	_controls.add_child(focus_btn)

	var lock_btn := _make_ctrl_button("Unlock" if _locked else "Lock",
		Vector2(LINE_W - 78, btn_y))
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
	move_requested.emit(self, 12, 2)


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


# ---------------------------------------------------------------------------
# Sections — Layer 4: intake queue cards + hopper card
# ---------------------------------------------------------------------------

func _rebuild_sections() -> void:
	for child in _sections.get_children():
		child.queue_free()

	var top  := 20 + SECTION_PAD
	var h    := LINE_H - top - SECTION_PAD

	_rebuild_intake_queues(top, h)
	_rebuild_hopper(top, h)
	_rebuild_stations(top, h)
	_rebuild_output_placeholder(top, h)


func _rebuild_intake_queues(top: float, h: float) -> void:
	var intake_queues: Array = _data.get("intakeQueues", [])

	if intake_queues.is_empty():
		# Empty placeholder with section label.
		_add_placeholder(_sections, SECTION_PAD, top, INTAKE_W - SECTION_PAD * 2, h,
			Color(0.15, 0.15, 0.40), "Intake\n(empty)")
		return

	# Divide the intake zone evenly among queues.
	var zone_w := INTAKE_W - SECTION_PAD * 2
	var card_w := zone_w / float(intake_queues.size())
	for i in intake_queues.size():
		var card_x := SECTION_PAD + i * card_w
		var iq := INTAKE_QUEUE_SCENE.instantiate()
		_sections.add_child(iq)
		iq.configure(intake_queues[i], card_x, top, card_w - SECTION_PAD, h)


func _rebuild_hopper(top: float, h: float) -> void:
	var hopper := HOPPER_SCENE.instantiate()
	_sections.add_child(hopper)
	var card_x := INTAKE_W + SECTION_PAD
	var card_w := HOPPER_W - SECTION_PAD * 2
	hopper.configure(_data, card_x, top, card_w, h)


func _rebuild_station_placeholder(_top: float, _h: float) -> void:
	# Replaced in Layer 5 — this stub kept to avoid breaking _rebuild_sections call order.
	pass


# ---------------------------------------------------------------------------
# Sections — Layer 5: Station cards + overlay
# ---------------------------------------------------------------------------

func _rebuild_stations(top: float, h: float) -> void:
	var stations: Array = _data.get("stations", [])
	var zone_x   := float(INTAKE_W + HOPPER_W)
	var zone_w   := float(STATION_W)

	if stations.is_empty():
		_add_placeholder(_sections, zone_x + SECTION_PAD, top,
			zone_w - SECTION_PAD * 2, h, Color(0.12, 0.12, 0.30), "Stations\n(none)")
		_add_station_button(zone_x + SECTION_PAD, top, h, -1, 0)
		return

	var card_w := (zone_w - SECTION_PAD * 2) / float(stations.size())

	for i in stations.size():
		var card_x := zone_x + SECTION_PAD + i * card_w
		var station := STATION_SCENE.instantiate()
		_sections.add_child(station)
		station.configure(stations[i], i, card_x, top, card_w - SECTION_PAD, h)
		station.overlay_requested.connect(
			func(s: Node2D, ot: String): _on_overlay_requested(s, ot, card_x, top)
		)

		# Add "+" before first and between each pair.
		if i == 0:
			_add_station_button(zone_x + SECTION_PAD - 14, top, h, _data.get("id", 0), 0)
		_add_station_button(card_x + card_w, top, h, _data.get("id", 0), i + 1)

	# Create (or reuse) the shared overlay instance.
	if _active_overlay == null:
		_active_overlay = OVERLAY_SCENE.instantiate()
		add_child(_active_overlay)   # child of Line so it renders above sections


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


func _on_overlay_requested(station: Node2D, overlay_type: String,
		card_x: float, card_top: float) -> void:
	var station_id: int = -1
	if "_data" in station:
		station_id = (station._data as Dictionary).get("id", -1)

	# Toggle: pressing the same button again closes the overlay.
	if _active_station_id == station_id and _active_overlay_type == overlay_type:
		_active_overlay.hide_overlay()
		_active_station_id = -1
		_active_overlay_type = ""
		return

	_active_station_id = station_id
	_active_overlay_type = overlay_type

	# Position overlay just below the station card.
	_active_overlay.position = Vector2(card_x, card_top + station._card_h + 2)
	_active_overlay.set_width(station._card_w)

	if overlay_type == "work_units":
		_active_overlay.show_work_units(station._data)
	else:
		_active_overlay.show_operations(station._data)


func _rebuild_output_placeholder(top: float, h: float) -> void:
	var has_output: bool = _data.get("hasOutput", true)
	if not has_output:
		return
	var x := INTAKE_W + HOPPER_W + STATION_W + SECTION_PAD
	_add_placeholder(_sections, x, top, OUTPUT_W - SECTION_PAD * 2, h,
		Color(0.12, 0.30, 0.12), "Output")


func _add_placeholder(parent: Node2D, x: float, y: float, w: float, h: float,
		color: Color, c_text: String) -> void:
	var r := ColorRect.new()
	r.position = Vector2(x, y)
	r.size = Vector2(w, h)
	r.color = color
	parent.add_child(r)

	var lbl := Label.new()
	lbl.position = Vector2(x + 4, y + 4)
	lbl.size = Vector2(w - 8, h - 8)
	lbl.text = c_text
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(lbl)


# ---------------------------------------------------------------------------
# Conveyors — Layer 4: animated chevron belts
# ---------------------------------------------------------------------------

func _rebuild_conveyors() -> void:
	for child in _conveyors.get_children():
		child.queue_free()

	var top   := 20 + SECTION_PAD
	var mid_y := top + (LINE_H - 20 - SECTION_PAD * 2) / 2.0

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
	if has_output:
		Conveyor.draw_animated(
			Vector2(INTAKE_W + HOPPER_W + STATION_W - SECTION_PAD, mid_y),
			Vector2(INTAKE_W + HOPPER_W + STATION_W + SECTION_PAD, mid_y),
			_conveyors
		)
