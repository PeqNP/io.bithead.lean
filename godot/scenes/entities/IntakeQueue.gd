## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single IntakeQueue card inside a Line.
## configure(data, card_x, card_y, card_w, card_h) must be called after instancing.

extends Node2D

const LABEL_COLOR   := Palette.FG_1
const FONT_SIZE     := 10
const SMALL_FONT    := 9
const BORDER_WIDTH  := 2.0
const DEFAULT_FILL  := Palette.BG_1
const DEFAULT_BORDER := Palette.BLUE

signal delete_requested(queue_id: int, queue_name: String)

var _data: Dictionary = {}
var _card_w: float = 0.0
var _card_h: float = 0.0
var _hovered: bool = false
var _delete_btn: Button = null

@onready var _layout:       VBoxContainer = $Layout
@onready var _name_label:   Label         = $Layout/Name
@onready var _cycle_label:  Label         = $Layout/CycleTime
@onready var _dist_label:   Label         = $Layout/Distribution
@onready var _wu_btn:       Button        = $Layout/WUButton
@onready var _controls:     HBoxContainer = $Controls
@onready var _edit_btn:     Button        = $Controls/EditButton


func _ready() -> void:
	set_process_input(true)
	Palette.style_edit_button(_edit_btn)
	_edit_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	_edit_btn.pressed.connect(_on_edit_pressed)
	_controls.resized.connect(_reposition_controls)
	_controls.hide()
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	_delete_btn.custom_minimum_size = Vector2(0.0, 18.0)
	Palette.style_button(_delete_btn, Palette.RED)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_delete_btn.hide()
	add_child(_delete_btn)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := get_local_mouse_position()
		var inside := Rect2(0, 0, _card_w, _card_h).has_point(local)
		if inside != _hovered:
			_hovered = inside
			_controls.visible = _hovered
			queue_redraw()


## Place and populate this card.
## card_x/y are in Line-local pixel coordinates.
func configure(data: Dictionary, card_x: float, card_y: float,
		card_w: float, card_h: float) -> void:
	_data = data
	_card_w = card_w
	_card_h = card_h
	position = Vector2(card_x, card_y)
	_delete_btn.position = Vector2(4.0, 4.0)
	_delete_btn.custom_minimum_size = Vector2(_card_w - 8.0, 0.0)

	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(card_w - 8, card_h - 8)

	_controls.reset_size()
	_name_label.text = str(data.get("name", ""))
	_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)

	var _cycle_v = data.get("cycleTime")
	var cycle: int = _cycle_v if _cycle_v != null else 0
	_cycle_label.text = "Cycle: %d" % cycle
	_cycle_label.add_theme_color_override("font_color", LABEL_COLOR)
	_cycle_label.add_theme_font_size_override("font_size", SMALL_FONT)

	var _ratio_v = data.get("mixRatio")
	var ratio: int = _ratio_v if _ratio_v != null else 0
	if ratio > 0:
		_dist_label.text = "Distribution: %d%%" % ratio
		_dist_label.add_theme_color_override("font_color", LABEL_COLOR)
		_dist_label.add_theme_font_size_override("font_size", SMALL_FONT)
		_dist_label.show()
	else:
		_dist_label.hide()

	var _nwu_v = data.get("numWorkUnits")
	var num_wu: int = _nwu_v if _nwu_v != null else 0
	_wu_btn.text = "Work Units (%d)" % num_wu
	_wu_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	var accent := _parse_color(data.get("color", null), "border", DEFAULT_BORDER)
	Palette.style_button(_wu_btn, accent)
	var _id_v = data.get("id")
	var iq_id: int = _id_v if _id_v != null else 0
	if not _wu_btn.pressed.is_connected(_on_wu_pressed):
		_wu_btn.pressed.connect(_on_wu_pressed.bind(iq_id))

	queue_redraw()


func _draw() -> void:
	var color_data = _data.get("color", null)
	var fill   := _parse_color(color_data, "fill",   DEFAULT_FILL)
	var border := _parse_color(color_data, "border", DEFAULT_BORDER)
	if _hovered:
		fill = fill.lightened(0.3)
	draw_rect(Rect2(0, 0, _card_w, _card_h), fill)
	draw_rect(Rect2(0, 0, _card_w, _card_h), border, false, BORDER_WIDTH)




func _on_wu_pressed(iq_id: int) -> void:
	BOSSBridge.open_window("WorkUnits", [iq_id])


func set_add_mode(_on: bool) -> void:
	pass  # Intake queues have no move buttons to suppress.


func set_delete_mode(on: bool) -> void:
	if on:
		_delete_btn.show()
	else:
		_delete_btn.hide()


func _on_delete_pressed() -> void:
	var iq_name := str(_data.get("name", ""))
	var iq_id: int = int(_data.get("id", 0))
	BOSSBridge.show_delete_modal(
		"Delete intake queue '%s'?" % iq_name,
		func(): delete_requested.emit(iq_id, iq_name)
	)


func _on_edit_pressed() -> void:
	BOSSBridge.open_window("EditIntakeQueue", [int(_data.get("id", 0))])


func _reposition_controls() -> void:
	if _card_w <= 0:
		return
	_controls.position = Vector2(_card_w - _controls.size.x - 4.0, 4.0)


func _parse_color(color_data, key: String, fallback: Color) -> Color:
	if color_data == null:
		return fallback
	var hex: String = str(color_data.get(key, ""))
	if hex.is_empty():
		return fallback
	# Strip leading # if present.
	if hex.begins_with("#"):
		hex = hex.substr(1)
	return Color.from_string(hex, fallback)
