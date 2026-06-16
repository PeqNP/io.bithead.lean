## Copyright © 2026 Bithead LLC. All rights reserved.

## EntityToolbar — reusable toggle / Add / Delete toolbar for line entities.
##
## Toggle button: circle icon when closed, right-pointing triangle when open.
## Add and Delete buttons appear when the toolbar is open.
##
## Usage:
##   var toolbar := EntityToolbar.new()
##   add_child(toolbar)
##   toolbar.add_mode_changed.connect(_on_add_mode)
##   toolbar.delete_mode_changed.connect(_on_delete_mode)
##   toolbar.setup(card_left, toolbar_y)

class_name EntityToolbar
extends Node2D

## Emitted when the user toggles Add mode on or off.
signal add_mode_changed(on: bool)
## Emitted when the user toggles Delete mode on or off.
signal delete_mode_changed(on: bool)

const BTN_H   := 24.0
const BTN_GAP := 4.0

var _open: bool = false
var _add_mode: bool = false
var _delete_mode: bool = false

var _toggle_btn: Button = null
var _add_btn: Button = null
var _delete_btn: Button = null
var _center_wrap: CenterContainer = null


## (Re)build toolbar buttons at the given position.
## Preserves _open / _add_mode / _delete_mode across rebuilds (e.g. snapshot updates).
func setup(card_left: float, toolbar_y: float) -> void:
	for child in get_children():
		child.queue_free()
	_toggle_btn = null
	_add_btn = null
	_delete_btn = null
	_center_wrap = null
	_build(card_left, toolbar_y)


## Sync Add button pressed state from outside (e.g. after mode restored from snapshot).
func set_add_mode(on: bool) -> void:
	_add_mode = on
	if _add_btn and is_instance_valid(_add_btn):
		_add_btn.button_pressed = on


## Sync Delete button pressed state from outside.
func set_delete_mode(on: bool) -> void:
	_delete_mode = on
	if _delete_btn and is_instance_valid(_delete_btn):
		_delete_btn.button_pressed = on


func _build(card_left: float, toolbar_y: float) -> void:
	# Toggle button.
	var toggle_btn := Button.new()
	toggle_btn.toggle_mode = true
	toggle_btn.button_pressed = _open
	toggle_btn.custom_minimum_size = Vector2(BTN_H, BTN_H)
	toggle_btn.position = Vector2(card_left, toolbar_y)
	Palette.style_edit_button(toggle_btn)
	toggle_btn.text = ""
	_toggle_btn = toggle_btn

	_center_wrap = CenterContainer.new()
	_center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _open:
		DrawShape.triangle(_center_wrap, false, Vector2(8.0, 8.0), Color.WHITE, true)
	else:
		DrawShape.circle(_center_wrap, Vector2(8.0, 8.0))
	toggle_btn.add_child(_center_wrap)
	toggle_btn.pressed.connect(_on_toggle_pressed)
	add_child(toggle_btn)

	# Add button (visible only when open).
	var btn_x := card_left + BTN_H + BTN_GAP
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.toggle_mode = true
	add_btn.button_pressed = _add_mode
	add_btn.position = Vector2(btn_x, toolbar_y)
	add_btn.add_theme_font_size_override("font_size", 9)
	Palette.style_button(add_btn, Palette.GREEN)
	add_btn.pressed.connect(_on_add_pressed)
	add_btn.visible = _open
	add_child(add_btn)
	_add_btn = add_btn

	# Delete button (visible only when open).
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.toggle_mode = true
	del_btn.button_pressed = _delete_mode
	del_btn.position = Vector2(btn_x + add_btn.get_minimum_size().x + BTN_GAP, toolbar_y)
	del_btn.add_theme_font_size_override("font_size", 9)
	Palette.style_button(del_btn, Palette.RED)
	del_btn.pressed.connect(_on_delete_pressed)
	del_btn.visible = _open
	add_child(del_btn)
	_delete_btn = del_btn


func _on_toggle_pressed() -> void:
	_open = !_open
	if not _open:
		if _add_mode:
			_add_mode = false
			if _add_btn:
				_add_btn.button_pressed = false
			add_mode_changed.emit(false)
		if _delete_mode:
			_delete_mode = false
			if _delete_btn:
				_delete_btn.button_pressed = false
			delete_mode_changed.emit(false)
	# Swap shape in toggle button.
	if _center_wrap:
		for child in _center_wrap.get_children():
			child.queue_free()
		if _open:
			DrawShape.triangle(_center_wrap, false, Vector2(8.0, 8.0), Color.WHITE, true)
		else:
			DrawShape.circle(_center_wrap, Vector2(8.0, 8.0))
	if _add_btn:
		_add_btn.visible = _open
	if _delete_btn:
		_delete_btn.visible = _open
	_toggle_btn.button_pressed = _open


func _on_add_pressed() -> void:
	_add_mode = !_add_mode
	add_mode_changed.emit(_add_mode)


func _on_delete_pressed() -> void:
	_delete_mode = !_delete_mode
	delete_mode_changed.emit(_delete_mode)
