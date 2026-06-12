## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single Station card inside a Line's station zone.
## configure(data, index, card_x, card_y, card_w, card_h) must be called after instancing.
## Overlay exclusivity is managed by Line.gd, which calls close_overlay() on all
## siblings before opening a new one.

extends Node2D

const LABEL_COLOR   := Color(1, 1, 1)
const MUTED_COLOR   := Color(0.65, 0.65, 0.65)
const FILL_COLOR    := Color(0.15, 0.15, 0.32)
const BORDER_COLOR  := Color(0.35, 0.35, 0.65)
const BORDER_WIDTH  := 2.0
const FONT_SIZE     := 10
const SMALL_FONT    := 9

## Emitted when the Work Units or Operations button is pressed.
## Line.gd listens to close overlays on other stations first.
signal overlay_requested(station: Node2D, overlay_type: String)

var _data: Dictionary = {}
var _station_index: int = 0
var _card_w: float = 0.0
var _card_h: float = 0.0

@onready var _wu_btn:  Button = $WUButton
@onready var _ops_btn: Button = $OpsButton


func _ready() -> void:
	_wu_btn.pressed.connect(func(): overlay_requested.emit(self, "work_units"))
	_ops_btn.pressed.connect(func(): overlay_requested.emit(self, "operations"))


func configure(data: Dictionary, station_index: int,
		card_x: float, card_y: float, card_w: float, card_h: float) -> void:
	_data = data
	_station_index = station_index
	_card_w = card_w
	_card_h = card_h
	position = Vector2(card_x, card_y)

	# Position buttons at the bottom of the card.
	var btn_w := (card_w - 8) / 2.0
	_wu_btn.position  = Vector2(4, card_h - 26)
	_wu_btn.size      = Vector2(btn_w, 20)
	_wu_btn.add_theme_font_size_override("font_size", SMALL_FONT)

	_ops_btn.position = Vector2(4 + btn_w + 2, card_h - 26)
	_ops_btn.size     = Vector2(btn_w, 20)
	_ops_btn.add_theme_font_size_override("font_size", SMALL_FONT)

	queue_redraw()


func close_overlay() -> void:
	pass  # StationOverlay is managed by Line.gd; signal to close is issued there.


func _draw() -> void:
	var color_data = _data.get("color", null)
	var fill   := _parse_color(color_data, "fill",   FILL_COLOR)
	var border := _parse_color(color_data, "border", BORDER_COLOR)

	draw_rect(Rect2(0, 0, _card_w, _card_h), fill)
	draw_rect(Rect2(0, 0, _card_w, _card_h), border, false, BORDER_WIDTH)

	var c_name: String = str(_data.get("name", "Station"))
	draw_string(ThemeDB.fallback_font, Vector2(4, 13), c_name,
		HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, FONT_SIZE, LABEL_COLOR)

	var cycle = _data.get("cycleTime", null)
	if cycle != null:
		draw_string(ThemeDB.fallback_font, Vector2(4, 26), "Cycle: %d" % int(cycle),
			HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, SMALL_FONT, MUTED_COLOR)

	var wu_count: int = (_data.get("workUnits", []) as Array).size()
	if wu_count > 0:
		draw_string(ThemeDB.fallback_font, Vector2(4, 38), "%d WU" % wu_count,
			HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, SMALL_FONT, LABEL_COLOR)


func _parse_color(color_data, key: String, fallback: Color) -> Color:
	if color_data == null:
		return fallback
	var hex: String = str(color_data.get(key, ""))
	if hex.is_empty():
		return fallback
	if hex.begins_with("#"):
		hex = hex.substr(1)
	return Color.from_string(hex, fallback)
