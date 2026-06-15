## Copyright © 2026 Bithead LLC. All rights reserved.

## InventoryStockPanel — stock level table shown below an Inventory card.
## Shows stock levels (cycle / buffer / safety) and the reorder algorithm + properties.

extends Node2D

const PANEL_W  := 256.0
const ROW_H    := 16.0
const PAD      :=  5.0
const FILL_COLOR   := Palette.BG_1_PANEL
const BORDER_COLOR := Palette.GREEN
const LABEL_COLOR  := Palette.FG_1
const MUTED_COLOR  := Palette.FG_0
const FONT_SIZE    := 9

var _panel_h: float = 0.0

@onready var _rows_container:    VBoxContainer = $Rows
@onready var _cycle_row:         HBoxContainer = $Rows/CycleStockRow
@onready var _cycle_val:         Label         = $Rows/CycleStockRow/ValueLabel
@onready var _buffer_row:        HBoxContainer = $Rows/BufferStockRow
@onready var _buffer_val:        Label         = $Rows/BufferStockRow/ValueLabel
@onready var _safety_row:        HBoxContainer = $Rows/SafetyStockRow
@onready var _safety_val:        Label         = $Rows/SafetyStockRow/ValueLabel
@onready var _algo_row:          HBoxContainer = $Rows/AlgorithmRow
@onready var _algo_val:          Label         = $Rows/AlgorithmRow/ValueLabel
@onready var _min_stock_row:     HBoxContainer = $Rows/MinStockRow
@onready var _min_stock_val:     Label         = $Rows/MinStockRow/ValueLabel
@onready var _max_stock_row:     HBoxContainer = $Rows/MaxStockRow
@onready var _max_stock_val:     Label         = $Rows/MaxStockRow/ValueLabel
@onready var _est_date_row:      HBoxContainer = $Rows/EstDateRow
@onready var _est_date_val:      Label         = $Rows/EstDateRow/ValueLabel
@onready var _last_computed_row: HBoxContainer = $Rows/LastComputedRow
@onready var _last_computed_val: Label         = $Rows/LastComputedRow/ValueLabel
@onready var _buffer_row2:       HBoxContainer = $Rows/BufferRow
@onready var _buffer_val2:       Label         = $Rows/BufferRow/ValueLabel


func _ready() -> void:
	_rows_container.position = Vector2(PAD, PAD)

	var all_rows := [
		_cycle_row, _buffer_row, _safety_row,
		_algo_row, _min_stock_row, _max_stock_row,
		_est_date_row, _last_computed_row, _buffer_row2,
	]
	var name_labels: Array[Label] = [
		$Rows/CycleStockRow/NameLabel,
		$Rows/BufferStockRow/NameLabel,
		$Rows/SafetyStockRow/NameLabel,
		$Rows/AlgorithmRow/NameLabel,
		$Rows/MinStockRow/NameLabel,
		$Rows/MaxStockRow/NameLabel,
		$Rows/EstDateRow/NameLabel,
		$Rows/LastComputedRow/NameLabel,
		$Rows/BufferRow/NameLabel,
	]
	var val_labels: Array[Label] = [
		_cycle_val, _buffer_val, _safety_val,
		_algo_val, _min_stock_val, _max_stock_val,
		_est_date_val, _last_computed_val, _buffer_val2,
	]

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
	_panel_h = PAD
	_panel_h += _configure_row(_cycle_row, _cycle_val, data.get("cycleStock"))
	_panel_h += _configure_row(_buffer_row, _buffer_val, data.get("bufferStockLevel"))
	_panel_h += _configure_row(_safety_row, _safety_val, data.get("safetyStockLevel"))

	var algo: Dictionary = data.get("reorderAlgorithm", {}) as Dictionary
	_configure_algorithm(algo)

	_panel_h += PAD
	queue_redraw()


func _configure_row(row: HBoxContainer, val_lbl: Label, value) -> float:
	if value == null:
		row.hide()
		return 0.0
	val_lbl.text = str(value)
	row.show()
	return ROW_H


func _configure_algorithm(algo: Dictionary) -> void:
	var algo_type: String = str(algo.get("type", ""))
	if algo_type.is_empty():
		for row in [_algo_row, _min_stock_row, _max_stock_row, _est_date_row, _last_computed_row, _buffer_row2]:
			row.hide()
		return

	var display_name := ""
	match algo_type:
		"reorderPoint": display_name = "Reorder Point"
		"minMax":       display_name = "Min / Max"
		"oneTime":      display_name = "One Time"
		_:              display_name = algo_type

	_panel_h += _configure_row(_algo_row, _algo_val, display_name)
	_panel_h += _configure_row(_min_stock_row, _min_stock_val, algo.get("minStock"))
	_panel_h += _configure_row(_max_stock_row, _max_stock_val, algo.get("maxStock"))
	_panel_h += _configure_row(_est_date_row, _est_date_val, algo.get("estimatedDate"))
	_panel_h += _configure_row(_last_computed_row, _last_computed_val, algo.get("lastComputed"))
	_panel_h += _configure_row(_buffer_row2, _buffer_val2, algo.get("buffer"))


func _draw() -> void:
	if _panel_h <= PAD * 2:
		return
	draw_rect(Rect2(0, 0, PANEL_W, _panel_h), FILL_COLOR)
	draw_rect(Rect2(0, 0, PANEL_W, _panel_h), BORDER_COLOR, false, 1.5)
