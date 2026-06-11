## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single Inventory node from a LeanFragment.FactoryFloor.Inventory snapshot.
##
## Layer 1: static rendering.
## Layer 3: hover controls (Move, Focus, Lock), focus shader.

extends Node2D

const TILE_SIZE    := 64
const INV_W        :=  2 * TILE_SIZE   # 128 px
const INV_H        :=  2 * TILE_SIZE   # 128 px

const FILL_COLOR           := Color(0.165, 0.353, 0.165)   # #2a5a2a
const FILL_FOCUSED_COLOR   := Color(0.200, 0.440, 0.200)
const BORDER_COLOR         := Color(0.353, 0.667, 0.353)   # #5aaa5a
const BORDER_FOCUSED_COLOR := Color(0.550, 1.000, 0.550)
const BORDER_WIDTH         := 3.0
const LABEL_COLOR          := Color(1, 1, 1)
const FONT_SIZE            := 11

const HEALTH_COLORS := {
	1: Color(0.086, 0.396, 0.204),
	2: Color(0.631, 0.380, 0.039),
	3: Color(0.600, 0.106, 0.106),
}

signal move_requested(entity: Node2D, tile_w: int, tile_h: int)
signal focus_toggled(entity_id: int, focused: bool)
signal lock_toggled(entity_id: int, locked: bool)

var _data: Dictionary = {}
var _entity_id: int = 0
var _focused: bool = false
var _locked: bool = false
var _hovered: bool = false

@onready var _label:        Label     = $Label
@onready var _health_strip: ColorRect = $HealthStrip
@onready var _controls:     Node2D    = $Controls


func _ready() -> void:
	set_process_input(true)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := to_local(get_global_mouse_position())
		var inside := Rect2(0, 0, INV_W, INV_H).has_point(local)
		if inside != _hovered:
			_set_hovered(inside)


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

	var health: int = data.get("health", 0)
	if HEALTH_COLORS.has(health):
		_health_strip.color = HEALTH_COLORS[health]
		_health_strip.show()
	else:
		_health_strip.hide()

	_rebuild_controls()
	queue_redraw()


func update(data: Dictionary) -> void:
	configure(data)


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
	draw_rect(Rect2(0, 0, INV_W, INV_H), fill)
	draw_rect(Rect2(0, 0, INV_W, INV_H), border, false, BORDER_WIDTH)


# ---------------------------------------------------------------------------
# Hover controls
# ---------------------------------------------------------------------------

func _set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_controls.visible = hovered


func _rebuild_controls() -> void:
	for child in _controls.get_children():
		child.queue_free()

	var move_btn := _make_ctrl_button("Move", Vector2(2, 2))
	move_btn.disabled = _locked
	move_btn.pressed.connect(_on_move_pressed)
	_controls.add_child(move_btn)

	var focus_btn := _make_ctrl_button("Unfocus" if _focused else "Focus", Vector2(2, 26))
	focus_btn.pressed.connect(_on_focus_pressed.bind(focus_btn))
	_controls.add_child(focus_btn)

	var lock_btn := _make_ctrl_button("Unlock" if _locked else "Lock", Vector2(2, 50))
	lock_btn.pressed.connect(_on_lock_pressed.bind(lock_btn, move_btn))
	_controls.add_child(lock_btn)

	_controls.visible = _hovered


func _make_ctrl_button(c_text: String, pos: Vector2) -> Button:
	var btn := Button.new()
	btn.text = c_text
	btn.position = pos
	btn.size = Vector2(INV_W - 4, 20)
	btn.add_theme_font_size_override("font_size", 9)
	return btn


func _on_move_pressed() -> void:
	if _locked:
		return
	move_requested.emit(self, 2, 2)


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
