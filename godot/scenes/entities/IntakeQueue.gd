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

var _data: Dictionary = {}
var _card_w: float = 0.0
var _card_h: float = 0.0
var _hovered: bool = false

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
	_controls.hide()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := get_local_mouse_position()
		var inside := Rect2(0, 0, _card_w, _card_h).has_point(local)
		if inside != _hovered:
			_hovered = inside
			_controls.visible = _hovered


## Place and populate this card.
## card_x/y are in Line-local pixel coordinates.
func configure(data: Dictionary, card_x: float, card_y: float,
		card_w: float, card_h: float) -> void:
	_data = data
	_card_w = card_w
	_card_h = card_h
	position = Vector2(card_x, card_y)

	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(card_w - 8, card_h - 8)

	_controls.position = Vector2(4, card_h - 28)
	_controls.size = Vector2(card_w - 8, 24)
	_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)

	var cycle: int = int(data.get("cycleTime", 0))
	_cycle_label.text = "Cycle: %d" % cycle
	_cycle_label.add_theme_color_override("font_color", LABEL_COLOR)
	_cycle_label.add_theme_font_size_override("font_size", SMALL_FONT)

	var ratio: int = int(data.get("mixRatio", 0))
	if ratio > 0:
		_dist_label.text = "Distribution: %d%%" % ratio
		_dist_label.add_theme_color_override("font_color", LABEL_COLOR)
		_dist_label.add_theme_font_size_override("font_size", SMALL_FONT)
		_dist_label.show()
	else:
		_dist_label.hide()

	var num_wu: int = int(data.get("numWorkUnits", 0))
	_wu_btn.text = "Work Units (%d)" % num_wu
	_wu_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	var accent := _parse_color(data.get("color", null), "border", DEFAULT_BORDER)
	Palette.style_button(_wu_btn, accent)
	var iq_id: int = int(data.get("id", 0))
	if not _wu_btn.pressed.is_connected(_on_wu_pressed):
		_wu_btn.pressed.connect(_on_wu_pressed.bind(iq_id))

	queue_redraw()


func _draw() -> void:
	var color_data = _data.get("color", null)
	var fill   := _parse_color(color_data, "fill",   DEFAULT_FILL)
	var border := _parse_color(color_data, "border", DEFAULT_BORDER)

	draw_rect(Rect2(0, 0, _card_w, _card_h), fill)
	draw_rect(Rect2(0, 0, _card_w, _card_h), border, false, BORDER_WIDTH)




func _on_wu_pressed(iq_id: int) -> void:
	BOSSBridge.open_window("WorkUnits", [iq_id])


func _on_edit_pressed() -> void:
	BOSSBridge.open_window("EditIntakeQueue", [int(_data.get("id", 0))])


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
