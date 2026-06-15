## Copyright © 2026 Bithead LLC. All rights reserved.

## Operation Panel — fixed top-left toolbox for creating entities.
##
## Lives on a CanvasLayer so it is unaffected by Camera2D zoom/pan.
## Buttons are disabled while an HTTP request is in-flight to prevent
## duplicate submissions.
##
## Signals:
##   create_line_pressed      — FactoryFloor should handle the create flow.
##   create_inventory_pressed — FactoryFloor should handle the create flow.

extends CanvasLayer

signal create_line_pressed
signal create_inventory_pressed

@onready var _create_line_btn:      Button = $Panel/VBox/CreateLineButton
@onready var _create_inventory_btn: Button = $Panel/VBox/CreateInventoryButton


func _ready() -> void:
	_style_panel()
	Palette.style_panel_button(_create_line_btn)
	Palette.style_panel_button(_create_inventory_btn)
	_create_line_btn.pressed.connect(func(): create_line_pressed.emit())
	_create_inventory_btn.pressed.connect(func(): create_inventory_pressed.emit())


func _style_panel() -> void:
	var panel := $Panel as PanelContainer
	var sb := StyleBoxFlat.new()
	sb.bg_color     = Palette.BASE_02
	sb.border_color = Palette.BASE_03
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left   = 8.0
	sb.content_margin_right  = 8.0
	sb.content_margin_top    = 8.0
	sb.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", sb)


## Disable all action buttons while a request is in-flight.
func set_busy(busy: bool) -> void:
	_create_line_btn.disabled      = busy
	_create_inventory_btn.disabled = busy
