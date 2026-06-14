## Copyright © 2026 Bithead LLC. All rights reserved.

## InventoryStockPanel — stock level table that slides out below an Inventory card.
## estimatedReorderDate, and health color.
## Created dynamically by Inventory._ready(); shown/hidden by the Stock toggle button.

extends Node2D

const PANEL_W      := 128.0
const ROW_H        := 16.0
const PAD          :=  5.0
const FILL_COLOR   := Palette.BG_1_PANEL
const BORDER_COLOR := Palette.GREEN
const LABEL_COLOR  := Palette.FG_1
const MUTED_COLOR  := Palette.FG_0
const FONT_SIZE    := 9

const HEALTH_COLORS := {
	1: Palette.GREEN,
	2: Palette.ORANGE,
	3: Palette.RED,
}

var _health_color: Color = Color(0, 0, 0, 0)
var _panel_h: float = 0.0

@onready var _rows_container:   VBoxContainer = $Rows
@onready var _cycle_row:        HBoxContainer = $Rows/CycleStockRow
@onready var _cycle_val:        Label         = $Rows/CycleStockRow/ValueLabel
@onready var _buffer_row:       HBoxContainer = $Rows/BufferStockRow
@onready var _buffer_val:       Label         = $Rows/BufferStockRow/ValueLabel
@onready var _safety_row:       HBoxContainer = $Rows/SafetyStockRow
@onready var _safety_val:       Label         = $Rows/SafetyStockRow/ValueLabel
@onready var _reorder_pt_row:   HBoxContainer = $Rows/ReorderPointRow
@onready var _reorder_pt_val:   Label         = $Rows/ReorderPointRow/ValueLabel
@onready var _reorder_date_row: HBoxContainer = $Rows/ReorderDateRow
@onready var _reorder_date_val: Label         = $Rows/ReorderDateRow/ValueLabel


func _ready() -> void:
	_rows_container.size = Vector2(PANEL_W - PAD * 2, ROW_H * 5)

	var all_rows := [_cycle_row, _buffer_row, _safety_row, _reorder_pt_row, _reorder_date_row]
	var name_labels: Array[Label] = [
		$Rows/CycleStockRow/NameLabel,
		$Rows/BufferStockRow/NameLabel,
		$Rows/SafetyStockRow/NameLabel,
		$Rows/ReorderPointRow/NameLabel,
		$Rows/ReorderDateRow/NameLabel,
	]
	var val_labels: Array[Label] = [_cycle_val, _buffer_val, _safety_val, _reorder_pt_val, _reorder_date_val]

	for row in all_rows:
		row.hide()
		row.custom_minimum_size = Vector2(0, ROW_H)
	for lbl in name_labels:
		lbl.size_flags_horizontal = 3
		lbl.add_theme_color_override("font_color", MUTED_COLOR)
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	for lbl in val_labels:
		lbl.size_flags_horizontal = 3
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)


## Populate from a LeanFragment.FactoryFloor.Inventory dictionary.
func configure(data: Dictionary) -> void:
	_health_color = Color(0, 0, 0, 0)
	var health_idx = data.get("health")
	if health_idx != null and HEALTH_COLORS.has(int(health_idx)):
		_health_color = HEALTH_COLORS[int(health_idx)]

	var health_h := 4.0 if _health_color.a > 0 else 0.0
	_rows_container.position = Vector2(PAD, PAD + health_h)

	_panel_h = PAD + health_h
	_panel_h += _configure_row(_cycle_row, _cycle_val, data.get("cycleStock"))
	_panel_h += _configure_row(_buffer_row, _buffer_val, data.get("bufferStockLevel"))
	_panel_h += _configure_row(_safety_row, _safety_val, data.get("safetyStockLevel"))
	_panel_h += _configure_row(_reorder_pt_row, _reorder_pt_val, data.get("reorderPoint"))
	_panel_h += _configure_row(_reorder_date_row, _reorder_date_val, data.get("estimatedReorderDate"))
	_panel_h += PAD

	queue_redraw()


func _configure_row(row: HBoxContainer, val_lbl: Label, value) -> float:
	if value == null:
		row.hide()
		return 0.0
	val_lbl.text = str(value)
	row.show()
	return ROW_H


func _draw() -> void:
	if _panel_h <= PAD * 2:
		return
	draw_rect(Rect2(0, 0, PANEL_W, _panel_h), FILL_COLOR)
	draw_rect(Rect2(0, 0, PANEL_W, _panel_h), BORDER_COLOR, false, 1.5)
	if _health_color.a > 0:
		draw_rect(Rect2(0, 0, PANEL_W, 4.0), _health_color)
