## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single Station card inside a Line's station zone.
## configure(data, index, card_x, card_y, card_w, card_h) must be called after instancing.
## Overlay exclusivity is managed by Line.gd, which calls close_overlay() on all
## siblings before opening a new one.

extends Node2D

const LABEL_COLOR   := Palette.FG_1
const MUTED_COLOR   := Palette.FG_0
const FILL_COLOR    := Palette.BG_1
const BORDER_COLOR  := Palette.BLUE
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

@onready var _layout:      VBoxContainer = $Layout
@onready var _name_label:  Label         = $Layout/Name
@onready var _cycle_label: Label         = $Layout/CycleTime
@onready var _wu_btn:      Button        = $Layout/Buttons/WUButton
@onready var _ops_btn:     Button        = $Layout/Buttons/OpsButton


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

	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(card_w - 8, card_h - 8)

	_name_label.text = str(data.get("name", "Station"))
	_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)

	var cycle = data.get("cycleTime", null)
	_cycle_label.visible = cycle != null
	_cycle_label.text = "Cycle: %d" % int(cycle) if cycle != null else ""
	_cycle_label.add_theme_color_override("font_color", MUTED_COLOR)
	_cycle_label.add_theme_font_size_override("font_size", SMALL_FONT)

	var wu_count: int = (data.get("workUnits", []) as Array).size()
	_wu_btn.text = "WUs (%d)" % wu_count
	_wu_btn.add_theme_font_size_override("font_size", SMALL_FONT)
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


func _parse_color(color_data, key: String, fallback: Color) -> Color:
	if color_data == null:
		return fallback
	var hex: String = str(color_data.get(key, ""))
	if hex.is_empty():
		return fallback
	if hex.begins_with("#"):
		hex = hex.substr(1)
	return Color.from_string(hex, fallback)
