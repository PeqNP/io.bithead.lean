## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single production Line from a LeanFragment.FactoryFloor.Line snapshot.
##
## Layer 1: static rendering.
## Layer 3: hover controls (Move, Focus, Lock), focus shader.

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
const SECTION_PAD := 6

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
# Sections
# ---------------------------------------------------------------------------

func _rebuild_sections() -> void:
	for child in _sections.get_children():
		child.queue_free()

	var x := SECTION_PAD
	var top := 20 + SECTION_PAD
	var h   := LINE_H - top - SECTION_PAD

	var intake_queues: Array = _data.get("intakeQueues", [])
	_add_section(_sections, x, top, INTAKE_W - SECTION_PAD * 2, h,
		Color(0.2, 0.2, 0.5), "Intake\n(%d)" % intake_queues.size())
	x += INTAKE_W

	var hopper_wu = _data.get("hopperWorkUnit", null)
	var hopper_label := "Hopper\n%s" % (str(hopper_wu.get("name", "")) if hopper_wu else "—")
	_add_section(_sections, x, top, HOPPER_W - SECTION_PAD * 2, h,
		Color(0.2, 0.3, 0.5), hopper_label)
	x += HOPPER_W

	var stations: Array = _data.get("stations", [])
	_add_section(_sections, x, top, STATION_W - SECTION_PAD * 2, h,
		Color(0.2, 0.2, 0.4), "Stations\n(%d)" % stations.size())
	x += STATION_W

	var has_output: bool = _data.get("hasOutput", true)
	if has_output:
		_add_section(_sections, x, top, OUTPUT_W - SECTION_PAD * 2, h,
			Color(0.15, 0.4, 0.15), "Output")


func _add_section(parent: Node2D, x: int, y: int, w: int, h: int,
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
# Conveyors (static stub — animated in Layer 4)
# ---------------------------------------------------------------------------

func _rebuild_conveyors() -> void:
	for child in _conveyors.get_children():
		child.queue_free()

	var top := 20 + SECTION_PAD
	var mid_y := top + (LINE_H - 20 - SECTION_PAD * 2) / 2.0

	var points := [
		Vector2(INTAKE_W,                          mid_y),
		Vector2(INTAKE_W + HOPPER_W,               mid_y),
		Vector2(INTAKE_W + HOPPER_W + STATION_W,   mid_y),
	]

	for i in range(points.size() - 1):
		Conveyor.draw_static(points[i], points[i + 1], _conveyors)
