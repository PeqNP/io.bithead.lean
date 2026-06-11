## Copyright © 2026 Bithead LLC. All rights reserved.

## StationOverlay — scrollable panel that slides below a Station card.
##
## Layer 5: shows Work Units list or Operations list for one station at a time.
## Line.gd creates one instance, moves it to the active station, and calls show_*/hide.
##
## Call show_work_units(station_data) or show_operations(station_data) to populate.
## Call hide_overlay() to collapse.

extends Node2D

const CARD_SCENE      := preload("res://scenes/entities/WorkUnitCard.tscn")
const MAX_VISIBLE     := 5        # rows before scroll arrows appear
const ROW_H           := 52.0
const PAD             :=  4.0
const OVERLAY_W       := 256.0   # matches STATION_W / num_stations; set by Line
const FILL_COLOR      := Color(0.10, 0.10, 0.22, 0.96)
const BORDER_COLOR    := Color(0.30, 0.30, 0.60)
const LABEL_COLOR     := Color(1, 1, 1)
const MUTED_COLOR     := Color(0.65, 0.65, 0.65)
const FONT_SIZE       := 10
const SMALL_FONT      := 9

var _overlay_type: String = ""   # "work_units" or "operations"
var _station_data: Dictionary = {}
var _scroll_offset: int = 0
var _overlay_w: float = OVERLAY_W
var _rows: Array = []            # cached row data for scroll

@onready var _content: Node2D = $Content
@onready var _up_btn:   Button = $UpButton
@onready var _dn_btn:   Button = $DnButton


func _ready() -> void:
	hide()
	_up_btn.pressed.connect(func(): _scroll(-1))
	_dn_btn.pressed.connect(func(): _scroll(1))


## Width is set by Line.gd to match the card width.
func set_width(w: float) -> void:
	_overlay_w = w


func show_work_units(station_data: Dictionary) -> void:
	_station_data = station_data
	_overlay_type = "work_units"
	_scroll_offset = 0
	_rebuild()
	show()


func show_operations(station_data: Dictionary) -> void:
	_station_data = station_data
	_overlay_type = "operations"
	_scroll_offset = 0
	_rebuild()
	show()


func hide_overlay() -> void:
	hide()
	_overlay_type = ""


func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()

	if _overlay_type == "work_units":
		_rows = _station_data.get("workUnits", [])
		_build_work_unit_rows()
	else:
		_build_operations_rows()

	_refresh_scroll_buttons()
	queue_redraw()


func _build_work_unit_rows() -> void:
	var visible_rows := _rows.slice(_scroll_offset,
		min(_scroll_offset + MAX_VISIBLE, _rows.size()))
	var y := PAD
	for wu in visible_rows:
		var card := CARD_SCENE.instantiate()
		_content.add_child(card)
		card.configure(wu, _overlay_w - PAD * 2, y)
		y += ROW_H + PAD

	if _rows.is_empty():
		queue_redraw()   # will draw "No work units" in _draw


func _build_operations_rows() -> void:
	# Operations come from the station's work unit data (unique operations).
	# Build a deduplicated summary: {name, count, cycleTime}.
	var ops: Dictionary = {}
	for wu: Dictionary in (_station_data.get("workUnits", []) as Array):
		# StationWorkUnit doesn't carry operation list directly in the snapshot.
		# Placeholder: show work unit count per station for now.
		pass

	# Stub: show each work unit's key + name as an operation row.
	var work_units: Array = _station_data.get("workUnits", [])
	var y := PAD
	for wu: Dictionary in work_units.slice(_scroll_offset,
			min(_scroll_offset + MAX_VISIBLE, work_units.size())):
		_add_ops_row(str(wu.get("key", "")), str(wu.get("name", "")), y)
		y += 28 + PAD

	_rows = work_units


func _add_ops_row(key: String, c_name: String, y: float) -> void:
	var lbl := Label.new()
	lbl.text = "%s  %s" % [key, c_name] if not key.is_empty() else c_name
	lbl.position = Vector2(PAD, y)
	lbl.size = Vector2(_overlay_w - PAD * 2, 24)
	lbl.add_theme_color_override("font_color", LABEL_COLOR)
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	_content.add_child(lbl)


func _scroll(direction: int) -> void:
	_scroll_offset = clamp(_scroll_offset + direction, 0,
		max(0, _rows.size() - MAX_VISIBLE))
	_rebuild()


func _refresh_scroll_buttons() -> void:
	var needs_scroll := _rows.size() > MAX_VISIBLE
	_up_btn.visible = needs_scroll and _scroll_offset > 0
	_dn_btn.visible = needs_scroll and _scroll_offset < _rows.size() - MAX_VISIBLE
	_up_btn.position = Vector2(_overlay_w - 24, 2)
	_dn_btn.position = Vector2(_overlay_w - 24, _visible_height() - 22)


func _visible_height() -> float:
	var visible_count: int = min(_rows.size(), MAX_VISIBLE)
	if visible_count == 0:
		return ROW_H + PAD * 2
	return visible_count * (ROW_H + PAD) + PAD


func _draw() -> void:
	var h := _visible_height()
	draw_rect(Rect2(0, 0, _overlay_w, h), FILL_COLOR)
	draw_rect(Rect2(0, 0, _overlay_w, h), BORDER_COLOR, false, 1.5)

	# Header label
	var header := "Work Units" if _overlay_type == "work_units" else "Operations"
	draw_string(ThemeDB.fallback_font, Vector2(PAD, 13), header,
		HORIZONTAL_ALIGNMENT_LEFT, _overlay_w - 30, FONT_SIZE, LABEL_COLOR)

	if _rows.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(PAD, 32), "None",
			HORIZONTAL_ALIGNMENT_LEFT, _overlay_w - PAD * 2, SMALL_FONT, MUTED_COLOR)
