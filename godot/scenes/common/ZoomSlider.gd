## Copyright © 2026 Bithead LLC. All rights reserved.

## ZoomSlider — fixed top-right CanvasLayer, 4 discrete zoom steps.
##
## Emits zoom_changed(index) where 0=100%, 1=75%, 2=50%, 3=25%.

extends CanvasLayer

signal zoom_changed(index: int)

## Fill fraction of the button area for each zoom level (100% → 75% → 50% → 25%).
const SCALE_FRACTIONS := [0.8, 0.6, 0.4, 0.2]

var _current: int = 0

@onready var _buttons: HBoxContainer = $Panel/HBox


func _ready() -> void:
	layer = 15
	_style_panel()
	_rebuild()


func _style_panel() -> void:
	var panel := $Panel as PanelContainer
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Palette.BASE_03
	sb.border_color = Palette.BASE_02
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left   = 6.0
	sb.content_margin_right  = 6.0
	sb.content_margin_top    = 4.0
	sb.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", sb)


func set_index(index: int) -> void:
	_current = clamp(index, 0, SCALE_FRACTIONS.size() - 1)
	_refresh_buttons()


func _rebuild() -> void:
	# "Zoom" label at the left of the panel.
	var lbl := Label.new()
	lbl.text = "Zoom"
	lbl.add_theme_color_override("font_color", Palette.FG_0)
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_buttons.add_child(lbl)

	for i in range(SCALE_FRACTIONS.size()):
		var btn := Button.new()
		btn.text = ""
		btn.toggle_mode = true
		btn.button_pressed = (i == _current)
		btn.custom_minimum_size = Vector2(44, 24)
		Palette.style_nav_button(btn)

		var rect_ctrl := _ZoomRect.new()
		rect_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect_ctrl.fraction = SCALE_FRACTIONS[i]
		rect_ctrl.active = (i == _current)
		btn.add_child(rect_ctrl)

		btn.pressed.connect(_on_btn_pressed.bind(i, btn))
		_buttons.add_child(btn)


func _refresh_buttons() -> void:
	# Skip index 0 which is the "Zoom" label.
	for i in range(SCALE_FRACTIONS.size()):
		var btn := _buttons.get_child(i + 1) as Button
		btn.button_pressed = (i == _current)
		var rect_ctrl := btn.get_child(0) as _ZoomRect
		if rect_ctrl:
			rect_ctrl.active = (i == _current)
			rect_ctrl.queue_redraw()


func _on_btn_pressed(index: int, _btn: Button) -> void:
	_current = index
	_refresh_buttons()
	zoom_changed.emit(index)


## Inner control that draws a centered filled rectangle scaled by `fraction`.
class _ZoomRect extends Control:
	var fraction: float = 0.8
	var active: bool = false

	func _draw() -> void:
		var rw := size.x * fraction
		var rh := size.y * fraction
		var rx := (size.x - rw) * 0.5
		var ry := (size.y - rh) * 0.5
		var color := Color.WHITE if active else Palette.FG_0
		draw_rect(Rect2(rx, ry, rw, rh), color)
