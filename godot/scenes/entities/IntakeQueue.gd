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


## Place and populate this card.
## card_x/y are in Line-local pixel coordinates.
func configure(data: Dictionary, card_x: float, card_y: float,
		card_w: float, card_h: float) -> void:
	_data = data
	_card_w = card_w
	_card_h = card_h
	position = Vector2(card_x, card_y)
	queue_redraw()


func _draw() -> void:
	var color_data = _data.get("color", null)
	var fill   := _parse_color(color_data, "fill",   DEFAULT_FILL)
	var border := _parse_color(color_data, "border", DEFAULT_BORDER)

	draw_rect(Rect2(0, 0, _card_w, _card_h), fill)
	draw_rect(Rect2(0, 0, _card_w, _card_h), border, false, BORDER_WIDTH)

	# Name
	var c_name: String = str(_data.get("name", ""))
	draw_string(ThemeDB.fallback_font, Vector2(4, 13), c_name,
		HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, FONT_SIZE, LABEL_COLOR)

	# Cycle time
	var cycle: int = _data.get("cycleTime", 0)
	draw_string(ThemeDB.fallback_font, Vector2(4, 26), "Cycle: %d" % cycle,
		HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, SMALL_FONT, LABEL_COLOR)

	# Mix ratio bar at bottom
	var ratio: int = _data.get("mixRatio", 0)
	if ratio > 0:
		var bar_w := (_card_w - 8) * ratio / 100.0
		draw_rect(Rect2(4, _card_h - 6, bar_w, 4), border.lightened(0.3))


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
