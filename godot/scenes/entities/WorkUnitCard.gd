## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single work unit row inside a StationOverlay.

extends Node2D

const CARD_H       := 52.0
const LABEL_COLOR  := Palette.FG_1
const MUTED_COLOR  := Palette.FG_0
const FILL_COLOR   := Palette.BG_1
const FILL_HOVER   := Palette.BG_0
const BORDER_COLOR := Palette.FG_1
const DONE_COLOR   := Palette.GREEN
const HOLD_COLOR   := Palette.ORANGE
const FONT_SIZE    := 10
const SMALL_FONT   := 9

var _data: Dictionary = {}
var _card_w: float = 0.0
var _hovered: bool = false

@onready var _buttons:  HBoxContainer = $Buttons
@onready var _open_btn: Button        = $Buttons/OpenButton
@onready var _done_btn: Button        = $Buttons/DoneButton


func _ready() -> void:
	set_process_input(true)
	_open_btn.pressed.connect(_on_open_pressed)
	_done_btn.pressed.connect(_on_done_pressed)
	Palette.style_button(_open_btn, Palette.BLUE)


func configure(data: Dictionary, card_w: float, card_y: float) -> void:
	_data = data
	_card_w = card_w
	position = Vector2(0, card_y)

	const BTN_H := 20.0
	const BTN_Y := CARD_H - BTN_H - 4.0
	_buttons.position = Vector2(4, BTN_Y)
	_buttons.size = Vector2(card_w - 8, BTN_H)

	var can_done: bool = _can_done()
	_done_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	_done_btn.disabled = not can_done
	if not can_done:
		_done_btn.tooltip_text = "Complete all operations first"
	Palette.style_button(_done_btn, Palette.GREEN if can_done else Palette.FG_0)
	_open_btn.add_theme_font_size_override("font_size", SMALL_FONT)

	queue_redraw()


func _can_done() -> bool:
	var total: int = _data.get("totalOperations", 0)
	var done: int  = _data.get("completedOperations", 0)
	return total == 0 or done >= total


func _on_open_pressed() -> void:
	BOSSBridge.open_window("StationWorkspace", [_data.get("id", 0)])


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := to_local(get_global_mouse_position())
		var inside := Rect2(0, 0, _card_w, CARD_H).has_point(local)
		if inside != _hovered:
			_hovered = inside
			queue_redraw()


func _draw() -> void:
	var fill := FILL_HOVER if _hovered else FILL_COLOR
	draw_rect(Rect2(0, 0, _card_w, CARD_H), fill)
	draw_rect(Rect2(0, 0, _card_w, CARD_H), BORDER_COLOR, false, 1.0)

	# On-hold tint
	if _data.get("onHold", false):
		draw_rect(Rect2(0, 0, 3, CARD_H), HOLD_COLOR)

	# Name + key
	var c_name := str(_data.get("name", ""))
	var key    := str(_data.get("key", ""))
	var title  := "%s  %s" % [key, c_name] if not key.is_empty() else c_name
	draw_string(ThemeDB.fallback_font, Vector2(8, 13), title,
		HORIZONTAL_ALIGNMENT_LEFT, _card_w - 70, FONT_SIZE, LABEL_COLOR)

	# ETA
	var eta := str(_data.get("eta", ""))
	if not eta.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(8, 26), eta,
			HORIZONTAL_ALIGNMENT_LEFT, _card_w - 70, SMALL_FONT, MUTED_COLOR)

	# Assignee initials
	var assignees: Array = _data.get("assignees", [])
	var ax := 8.0
	for a in assignees.slice(0, 3):
		var avatar: String = str(a.get("avatar", ""))
		var initials := _make_initials(str(a.get("name", "?"))) if avatar.is_empty() else avatar
		draw_circle(Vector2(ax + 8, 38), 8, Palette.BLUE)
		draw_string(ThemeDB.fallback_font, Vector2(ax + 3, 41), initials,
			HORIZONTAL_ALIGNMENT_LEFT, 16, 8, LABEL_COLOR)
		ax += 20

	# Per-operation progress bars (each operation = one segment, 2 px gap between).
	var total: int = _data.get("totalOperations", 0)
	var done: int  = _data.get("completedOperations", 0)
	if total > 0:
		var bar_x    := 8.0
		var bar_y    := CARD_H - 6.0
		var bar_h    := 4.0
		var gap      := 2.0
		var bar_total_w := _card_w - 70.0
		var seg_w   := (bar_total_w - gap * (total - 1)) / float(total)
		for i in total:
			var x := bar_x + i * (seg_w + gap)
			var color := DONE_COLOR if i < done else Palette.FG_0
			draw_rect(Rect2(x, bar_y, seg_w, bar_h), color)


func _make_initials(full_name: String) -> String:
	var parts := full_name.split(" ")
	if parts.size() >= 2:
		return (parts[0].substr(0, 1) + parts[1].substr(0, 1)).to_upper()
	return full_name.substr(0, 2).to_upper()


func _on_done_pressed() -> void:
	_done_btn.disabled = true
	await BOSSBridge.post("/lean/work-unit/%d/move-to-next-station" % _data.get("id", 0), {})
	BOSSBridge.poll_snapshot()
