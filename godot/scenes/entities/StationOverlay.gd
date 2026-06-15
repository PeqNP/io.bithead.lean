## Copyright © 2026 Bithead LLC. All rights reserved.

## StationOverlay — scrollable panel that slides below a Station card.
## Line.gd creates one instance, moves it to the active station, and calls show_*/hide.
## Call show_work_units(station_data) or show_operations(station_data) to populate.
## Call hide_overlay() to collapse.

extends Node2D

const CARD_SCENE          := preload("res://scenes/entities/WorkUnitCard/WorkUnitCard.tscn")
const OPERATION_ROW_SCENE := preload("res://scenes/entities/OperationRow.tscn")
const MAX_VISIBLE     := 5        # rows before scroll arrows appear
const ROW_H           := 52.0
const PAD             :=  4.0
const OVERLAY_W       := 256.0   # matches STATION_W / num_stations; set by Line
const FILL_COLOR      := Palette.BG_1_PANEL
const BORDER_COLOR    := Palette.FG_1
const LABEL_COLOR     := Palette.FG_1
const MUTED_COLOR     := Palette.FG_0
const FONT_SIZE       := 10
const SMALL_FONT      := 9

var _overlay_type: String = ""   # "work_units" or "operations"
var _station_data: Dictionary = {}
var _scroll_offset: int = 0
var _overlay_w: float = OVERLAY_W
var _overlay_h: float = 0.0
var _rows: Array = []            # cached row data for scroll
var _compact: bool = false       # true at zoom ≤ 50%

@onready var _content:      VBoxContainer = $Content
@onready var _none_lbl:     Label         = $NoneLabel
@onready var _compact_lbl:  Label         = $CompactLabel
@onready var _up_btn:       Button        = $UpButton
@onready var _dn_btn:       Button        = $DnButton


func _ready() -> void:
	hide()
	_up_btn.pressed.connect(func(): _scroll(-1))
	_dn_btn.pressed.connect(func(): _scroll(1))


## Width is set by Line.gd to match the card width.
func set_width(w: float) -> void:
	_overlay_w = w


func set_zoom_index(zi: int) -> void:
	var was_compact := _compact
	_compact = (zi >= 2)
	if was_compact != _compact and is_visible():
		_rebuild()


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
		_content.remove_child(child)
		child.queue_free()

	_compact_lbl.hide()
	_content.show()

	_content.position = Vector2(PAD, PAD)
	_content.size = Vector2(_overlay_w - PAD * 2, 0)

	if _overlay_type == "work_units":
		_rows = _station_data.get("workUnits", [])
		_build_work_unit_rows()
	else:
		_build_operations_rows()
		_none_lbl.hide()

	var content_h := _content.get_combined_minimum_size().y
	_overlay_h = _content.position.y + maxf(content_h, ROW_H) + PAD

	_refresh_scroll_buttons()
	queue_redraw()


func _build_work_unit_rows() -> void:
	if _rows.is_empty():
		_none_lbl.position = Vector2(PAD, PAD + 4)
		_none_lbl.add_theme_color_override("font_color", MUTED_COLOR)
		_none_lbl.add_theme_font_size_override("font_size", SMALL_FONT)
		_none_lbl.show()
		return
	_none_lbl.hide()

	if _compact:
		var count := _rows.size()
		_compact_lbl.text = "%d work unit%s" % [count, "s" if count != 1 else ""]
		_compact_lbl.custom_minimum_size = Vector2(0, ROW_H)
		_compact_lbl.size_flags_horizontal = 3
		_compact_lbl.add_theme_color_override("font_color", MUTED_COLOR)
		_compact_lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		_compact_lbl.position = Vector2(PAD, PAD + 4)
		_compact_lbl.show()
		_content.hide()
		return

	var end_idx: int = min(_scroll_offset + MAX_VISIBLE, _rows.size())
	var visible_rows := _rows.slice(_scroll_offset, end_idx)
	for wu in visible_rows:
		var card := CARD_SCENE.instantiate()
		_content.add_child(card)
		card.configure(wu, _overlay_w - PAD * 2)


func _build_operations_rows() -> void:
	var work_units: Array = _station_data.get("workUnits", [])
	var end_idx: int = min(_scroll_offset + MAX_VISIBLE, work_units.size())
	for wu: Dictionary in work_units.slice(_scroll_offset, end_idx):
		_add_ops_row(str(wu.get("key", "")), str(wu.get("name", "")))
	_rows = work_units


func _add_ops_row(key: String, c_name: String) -> void:
	var row := OPERATION_ROW_SCENE.instantiate() as OperationRow
	row.configure(key, c_name)
	_content.add_child(row)


func _scroll(direction: int) -> void:
	var max_offset: int = max(0, _rows.size() - MAX_VISIBLE)
	_scroll_offset = clamp(_scroll_offset + direction, 0, max_offset)
	_rebuild()


func _refresh_scroll_buttons() -> void:
	var needs_scroll := _rows.size() > MAX_VISIBLE
	_up_btn.visible = needs_scroll and _scroll_offset > 0
	_dn_btn.visible = needs_scroll and _scroll_offset < _rows.size() - MAX_VISIBLE
	_up_btn.position = Vector2(_overlay_w - 24, 2)
	_dn_btn.position = Vector2(_overlay_w - 24, _overlay_h - 22)


func _draw() -> void:
	draw_rect(Rect2(0, 0, _overlay_w, _overlay_h), FILL_COLOR)
	draw_rect(Rect2(0, 0, _overlay_w, _overlay_h), BORDER_COLOR, false, 1.5)
