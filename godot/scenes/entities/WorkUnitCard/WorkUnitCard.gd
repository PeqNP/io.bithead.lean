## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single work unit row inside a StationOverlay.

extends Control

const CARD_H       := 52.0
const LABEL_COLOR  := Palette.FG_1
const MUTED_COLOR  := Palette.FG_0
const FILL_COLOR   := Palette.BG_1
const FILL_HOVER   := Palette.BG_0
const BORDER_COLOR := Palette.FG_1
const FONT_SIZE    := 10
const SMALL_FONT   := 9

var _data: Dictionary = {}
var _card_w: float = 0.0
var _hovered: bool = false

@onready var _layout:    VBoxContainer  = $Layout
@onready var _title_lbl: Label          = $Layout/Title
@onready var _eta_lbl:   Label          = $Layout/ETA
@onready var _assignees: Assignees       = $Layout/Assignees
@onready var _op_bars:   OperationBars   = $Layout/OperationBars
@onready var _open_btn:  Button         = $Layout/Buttons/OpenButton
@onready var _done_btn:  Button         = $Layout/Buttons/DoneButton
@onready var _hold_btn:  OnHoldButton   = $OnHoldButton


func _ready() -> void:
	set_process_input(true)
	_open_btn.pressed.connect(_on_open_pressed)
	_done_btn.pressed.connect(_on_done_pressed)
	Palette.style_button(_open_btn, Palette.BLUE)


func configure(data: Dictionary, card_w: float) -> void:
	_data = data
	_card_w = card_w

	var c_name := str(data.get("name", ""))
	var key    := str(data.get("key", ""))
	_title_lbl.text = "%s  %s" % [key, c_name] if not key.is_empty() else c_name
	_title_lbl.add_theme_color_override("font_color", LABEL_COLOR)
	_title_lbl.add_theme_font_size_override("font_size", FONT_SIZE)

	var eta := str(data.get("eta", ""))
	if not eta.is_empty():
		_eta_lbl.text = eta
		_eta_lbl.add_theme_color_override("font_color", MUTED_COLOR)
		_eta_lbl.add_theme_font_size_override("font_size", SMALL_FONT)
		_eta_lbl.show()
	else:
		_eta_lbl.hide()

	_assignees.configure(data.get("assignees", []))
	_op_bars.configure(int(data.get("totalOperations", 0)), int(data.get("completedOperations", 0)))

	var on_hold: bool = data.get("onHold", false)
	if on_hold:
		const BTN_W := 44.0
		const BTN_H := 14.0
		const PAD   := 3.0
		_hold_btn.position = Vector2(card_w - BTN_W - PAD, PAD)
		_hold_btn.size = Vector2(BTN_W, BTN_H)
		_hold_btn.configure(int(data.get("id", 0)))
		_hold_btn.show()
	else:
		_hold_btn.hide()

	var can_done: bool = _can_done()
	_done_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	_done_btn.disabled = not can_done
	_done_btn.tooltip_text = "Complete all operations first" if not can_done else ""
	Palette.style_button(_done_btn, Palette.GREEN if can_done else Palette.FG_0)
	_open_btn.add_theme_font_size_override("font_size", SMALL_FONT)

	# Size the layout from actual content, then report the new minimum size to the parent.
	var layout_h := maxf(_layout.get_combined_minimum_size().y, CARD_H - 8)
	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(card_w - 8, layout_h)
	custom_minimum_size = Vector2(0, layout_h + 8)
	update_minimum_size()
	queue_redraw()


func _can_done() -> bool:
	var total: int = _data.get("totalOperations", 0)
	var done: int  = _data.get("completedOperations", 0)
	return total == 0 or done >= total


func _on_open_pressed() -> void:
	BOSSBridge.open_window("StationWorkspace", [_data.get("id", 0)])


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := get_local_mouse_position()
		var inside := Rect2(Vector2.ZERO, size).has_point(local)
		if inside != _hovered:
			_hovered = inside
			queue_redraw()


func _draw() -> void:
	var fill := FILL_HOVER if _hovered else FILL_COLOR
	draw_rect(Rect2(0, 0, size.x, size.y), fill)
	draw_rect(Rect2(0, 0, size.x, size.y), BORDER_COLOR, false, 1.0)


func _on_done_pressed() -> void:
	_done_btn.disabled = true
	await BOSSBridge.post("/lean/work-unit/%d/move-to-next-station" % _data.get("id", 0), {})
	BOSSBridge.poll_snapshot()
