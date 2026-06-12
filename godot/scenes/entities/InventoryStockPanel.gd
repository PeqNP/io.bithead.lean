## Copyright © 2026 Bithead LLC. All rights reserved.

## InventoryStockPanel — stock level table that slides out below an Inventory card.
## estimatedReorderDate, and health color.
## Created dynamically by Inventory._ready(); shown/hidden by the Stock toggle button.

extends Node2D

const PANEL_W      := 128.0
const ROW_H        := 16.0
const PAD          :=  5.0
const FILL_COLOR   := Color(0.08, 0.18, 0.08, 0.96)
const BORDER_COLOR := Color(0.25, 0.55, 0.25)
const LABEL_COLOR  := Color(1, 1, 1)
const MUTED_COLOR  := Color(0.65, 0.75, 0.65)
const FONT_SIZE    := 9

const HEALTH_COLORS := {
	1: Color(0.086, 0.396, 0.204),
	2: Color(0.631, 0.380, 0.039),
	3: Color(0.600, 0.106, 0.106),
}

var _rows: Array = []      # Array of {label: String, value: String}
var _health_color: Color = Color(0, 0, 0, 0)
var _panel_h: float = 0.0


## Populate from a LeanFragment.FactoryFloor.Inventory dictionary.
func configure(data: Dictionary) -> void:
	_rows.clear()
	_health_color = Color(0, 0, 0, 0)

	_add_row("Cycle Stock",   data.get("cycleStock"))
	_add_row("Buffer Stock",  data.get("bufferStockLevel"))
	_add_row("Safety Stock",  data.get("safetyStockLevel"))
	_add_row("Reorder Point", data.get("reorderPoint"))
	_add_row("Reorder Date",  data.get("estimatedReorderDate"))

	var health_idx = data.get("health")
	if health_idx != null and HEALTH_COLORS.has(int(health_idx)):
		_health_color = HEALTH_COLORS[int(health_idx)]

	_panel_h = PAD + _rows.size() * ROW_H + PAD + (4.0 if _health_color.a > 0 else 0.0)
	queue_redraw()


func _add_row(label: String, value) -> void:
	if value == null:
		return
	_rows.append({"label": label, "value": str(value)})


func _draw() -> void:
	if _rows.is_empty() and _health_color.a == 0:
		return

	var font := ThemeDB.fallback_font
	var actual_h := PAD + _rows.size() * ROW_H + PAD + (4.0 if _health_color.a > 0 else 0.0)

	# Panel background + border.
	draw_rect(Rect2(0, 0, PANEL_W, actual_h), FILL_COLOR)
	draw_rect(Rect2(0, 0, PANEL_W, actual_h), BORDER_COLOR, false, 1.5)

	# Health color strip at top.
	if _health_color.a > 0:
		draw_rect(Rect2(0, 0, PANEL_W, 4.0), _health_color)

	var y_start := PAD + (4.0 if _health_color.a > 0 else 0.0)
	for i in _rows.size():
		var y := y_start + i * ROW_H + ROW_H - 4.0   # baseline
		var label: String = _rows[i]["label"]
		var value: String = _rows[i]["value"]
		draw_string(font, Vector2(PAD, y), label + ":", HORIZONTAL_ALIGNMENT_LEFT,
			PANEL_W / 2.0 - PAD, FONT_SIZE, MUTED_COLOR)
		draw_string(font, Vector2(PANEL_W / 2.0, y), value, HORIZONTAL_ALIGNMENT_LEFT,
			PANEL_W / 2.0 - PAD, FONT_SIZE, LABEL_COLOR)
