## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders the Hopper card inside a Line.
## configure(data, card_x, card_y, card_w, card_h) must be called after instancing.

extends Node2D

const LABEL_COLOR  := Palette.FG_1
const MUTED_COLOR  := Palette.FG_0
const FILL_COLOR   := Palette.BG_1
const BORDER_COLOR := Palette.BLUE
const BORDER_WIDTH := 2.0
const FONT_SIZE    := 10
const SMALL_FONT   := 9

var _data: Dictionary = {}       # Line-level data (for hopperWorkUnit)
var _card_w: float = 0.0
var _card_h: float = 0.0

@onready var _layout:     VBoxContainer = $Layout
@onready var _name_label: Label         = $Layout/Name
@onready var _eta_label:  Label         = $Layout/ETA
@onready var _start_btn:  Button        = $Layout/StartButton


func _ready() -> void:
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.hide()
	Palette.style_button(_start_btn, BORDER_COLOR)


func configure(data: Dictionary, card_x: float, card_y: float,
		card_w: float, card_h: float) -> void:
	_data = data
	_card_w = card_w
	_card_h = card_h
	position = Vector2(card_x, card_y)

	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(card_w - 8, card_h - 8)

	var wu = _data.get("hopperWorkUnit", null)
	if wu != null:
		_name_label.text = str(wu.get("name", ""))
		_name_label.add_theme_color_override("font_color", LABEL_COLOR)
		_eta_label.text = str(wu.get("eta", ""))
		_eta_label.visible = not _eta_label.text.is_empty()
		_eta_label.add_theme_color_override("font_color", MUTED_COLOR)
		_start_btn.show()
		_start_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	else:
		_name_label.text = "Hopper"
		_name_label.add_theme_color_override("font_color", MUTED_COLOR)
		_eta_label.text = "Empty"
		_eta_label.visible = true
		_eta_label.add_theme_color_override("font_color", MUTED_COLOR)
		_start_btn.hide()

	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_eta_label.add_theme_font_size_override("font_size", SMALL_FONT)

	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, _card_w, _card_h), FILL_COLOR)
	draw_rect(Rect2(0, 0, _card_w, _card_h), BORDER_COLOR, false, BORDER_WIDTH)


func _on_start_pressed() -> void:
	var wu = _data.get("hopperWorkUnit", null)
	if wu == null:
		return
	_start_btn.disabled = true
	await BOSSBridge.post("/lean/start-work-unit", {"id": wu.get("id", 0)})
	_start_btn.disabled = false
	BOSSBridge.poll_snapshot()
