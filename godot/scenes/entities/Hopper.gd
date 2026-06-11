## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders the Hopper card inside a Line.
##
## Layer 4: shows work unit name + ETA + Start button when hopperWorkUnit present.
## configure(data, card_x, card_y, card_w, card_h) must be called after instancing.

extends Node2D

const LABEL_COLOR  := Color(1, 1, 1)
const MUTED_COLOR  := Color(0.7, 0.7, 0.7)
const FILL_COLOR   := Color(0.18, 0.28, 0.42)
const BORDER_COLOR := Color(0.35, 0.55, 0.75)
const BORDER_WIDTH := 2.0
const FONT_SIZE    := 10
const SMALL_FONT   := 9

var _data: Dictionary = {}       # Line-level data (for hopperWorkUnit)
var _card_w: float = 0.0
var _card_h: float = 0.0

@onready var _start_btn: Button = $StartButton


func _ready() -> void:
	_start_btn.pressed.connect(_on_start_pressed)
	_start_btn.hide()


func configure(data: Dictionary, card_x: float, card_y: float,
		card_w: float, card_h: float) -> void:
	_data = data
	_card_w = card_w
	_card_h = card_h
	position = Vector2(card_x, card_y)

	var wu = _data.get("hopperWorkUnit", null)
	if wu != null:
		_start_btn.show()
		_start_btn.position = Vector2(4, card_h - 26)
		_start_btn.size = Vector2(card_w - 8, 20)
		_start_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	else:
		_start_btn.hide()

	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, _card_w, _card_h), FILL_COLOR)
	draw_rect(Rect2(0, 0, _card_w, _card_h), BORDER_COLOR, false, BORDER_WIDTH)

	var wu = _data.get("hopperWorkUnit", null)
	if wu != null:
		var c_name: String = str(wu.get("name", ""))
		draw_string(ThemeDB.fallback_font, Vector2(4, 13), c_name,
			HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, FONT_SIZE, LABEL_COLOR)
		var eta: String = str(wu.get("eta", ""))
		if not eta.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(4, 26), eta,
				HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, SMALL_FONT, MUTED_COLOR)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(4, 13), "Hopper",
			HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, FONT_SIZE, MUTED_COLOR)
		draw_string(ThemeDB.fallback_font, Vector2(4, 26), "Empty",
			HORIZONTAL_ALIGNMENT_LEFT, _card_w - 8, SMALL_FONT, MUTED_COLOR)


func _on_start_pressed() -> void:
	var wu = _data.get("hopperWorkUnit", null)
	if wu == null:
		return
	_start_btn.disabled = true
	await BOSSBridge.post("/lean/start-work-unit", {"id": wu.get("id", 0)})
	_start_btn.disabled = false
	BOSSBridge.poll_snapshot()
