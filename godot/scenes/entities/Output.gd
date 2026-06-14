## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders the Output zone card inside a Line.
## configure(card_x, card_y, card_w, card_h) must be called after instancing.

extends Node2D

const FILL_COLOR   := Palette.GREEN_FILL
const BORDER_COLOR := Palette.GREEN
const BORDER_WIDTH := 2.0
const FONT_SIZE    := 10
const LABEL_COLOR  := Palette.FG_1

var _card_w: float = 0.0
var _card_h: float = 0.0
var _line_id: int = 0

@onready var _layout:     VBoxContainer = $Layout
@onready var _name_label: Label         = $Layout/Name
@onready var _wu_btn:     Button        = $Layout/WUButton


func _ready() -> void:
	_wu_btn.pressed.connect(_on_wu_pressed)
	Palette.style_button(_wu_btn, BORDER_COLOR)


func configure(card_x: float, card_y: float, card_w: float, card_h: float, line_id: int = 0) -> void:
	_card_w = card_w
	_card_h = card_h
	_line_id = line_id
	position = Vector2(card_x, card_y)

	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(card_w - 8, card_h - 8)

	_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_wu_btn.add_theme_font_size_override("font_size", 9)

	queue_redraw()


func _on_wu_pressed() -> void:
	BOSSBridge.open_window("OutputWorkUnits", [_line_id])


func _draw() -> void:
	draw_rect(Rect2(0, 0, _card_w, _card_h), FILL_COLOR)
	draw_rect(Rect2(0, 0, _card_w, _card_h), BORDER_COLOR, false, BORDER_WIDTH)
