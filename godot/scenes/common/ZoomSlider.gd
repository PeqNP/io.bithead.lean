## Copyright © 2026 Bithead LLC. All rights reserved.

## ZoomSlider — fixed top-right CanvasLayer, 4 discrete zoom steps.
##
## Emits zoom_changed(index) where 0=100%, 1=75%, 2=50%, 3=25%.

extends CanvasLayer

signal zoom_changed(index: int)

const LABELS := ["100%", "75%", "50%", "25%"]

var _current: int = 0

@onready var _buttons: HBoxContainer = $Panel/HBox


func _ready() -> void:
	layer = 15
	_rebuild()


func set_index(index: int) -> void:
	_current = clamp(index, 0, LABELS.size() - 1)
	_refresh_buttons()


func _rebuild() -> void:
	for i in range(LABELS.size()):
		var btn := Button.new()
		btn.text = LABELS[i]
		btn.toggle_mode = true
		btn.button_pressed = (i == _current)
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(44, 24)
		btn.pressed.connect(_on_btn_pressed.bind(i, btn))
		_buttons.add_child(btn)


func _refresh_buttons() -> void:
	for i in range(_buttons.get_child_count()):
		var btn := _buttons.get_child(i) as Button
		btn.button_pressed = (i == _current)


func _on_btn_pressed(index: int, btn: Button) -> void:
	# Force-update toggle state before re-checking others.
	_current = index
	_refresh_buttons()
	zoom_changed.emit(index)
