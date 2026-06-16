## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single Station card inside a Line's station zone.
## configure(data, index, card_x, card_y, card_w, card_h) must be called after instancing.
## Overlay exclusivity is managed by Line.gd, which calls close_overlay() on all
## siblings before opening a new one.

extends Node2D

const LABEL_COLOR   := Palette.FG_1
const MUTED_COLOR   := Palette.FG_0
const FILL_COLOR    := Palette.BG_1
const BORDER_COLOR  := Palette.BLUE
const BORDER_WIDTH  := 2.0
const FONT_SIZE     := 10
const SMALL_FONT    := 9

## Emitted when the Work Units or Operations button is pressed.
## Line.gd listens to close overlays on other stations first.
signal overlay_requested(station: Node2D, overlay_type: String)
## Emitted when a directional move button is tapped.
## Line.gd handles persistence and rebuild.
signal station_move_requested(station_id: int, new_pos_x: int, new_pos_y: int)
## Emitted when the delete button inside this card is tapped.
signal delete_requested(station_id: int, station_name: String)

const BTN_SIZE := 14   ## px — size of each directional move button

var _data: Dictionary = {}
var _occupied: Dictionary = {}
var _station_index: int = 0
var _card_w: float = 0.0
var _card_h: float = 0.0
var _hovered: bool = false
var _pos_x: int = 0
var _pos_y: int = 0
var _station_id: int = 0
var _is_first_station: bool = false
var _add_mode: bool = false     # when true, move buttons are suppressed
var _delete_btn: Button = null  # red delete button shown in delete mode

@onready var _layout:      VBoxContainer = $Layout
@onready var _name_label:  Label         = $Layout/Name
@onready var _cycle_label: Label         = $Layout/CycleTime
@onready var _wu_btn:      Button        = $Layout/Buttons/WUButton
@onready var _ops_btn:     Button        = $Layout/Buttons/OpsButton
@onready var _controls:    HBoxContainer = $Controls
@onready var _edit_btn:    Button        = $Controls/EditButton
@onready var _btn_up:      Button        = $MoveUp
@onready var _btn_down:    Button        = $MoveDown
@onready var _btn_left:    Button        = $MoveLeft
@onready var _btn_right:   Button        = $MoveRight


func _ready() -> void:
	set_process_input(true)
	_wu_btn.pressed.connect(func(): overlay_requested.emit(self, "work_units"))
	_ops_btn.pressed.connect(func(): overlay_requested.emit(self, "operations"))
	Palette.style_edit_button(_edit_btn)
	_edit_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	_edit_btn.pressed.connect(_on_edit_pressed)
	_controls.resized.connect(_reposition_controls)
	_controls.hide()
	_btn_up.pressed.connect(func(): _on_move_dir(0, -1))
	_btn_down.pressed.connect(func(): _on_move_dir(0, 1))
	_btn_left.pressed.connect(func(): _on_move_dir(-1, 0))
	_btn_right.pressed.connect(func(): _on_move_dir(1, 0))
	for b in [_btn_up, _btn_down, _btn_left, _btn_right]:
		b.hide()
	# Delete button — hidden until delete mode is active.
	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	_delete_btn.custom_minimum_size = Vector2(0.0, 18.0)
	Palette.style_button(_delete_btn, Palette.RED)
	_delete_btn.pressed.connect(_on_delete_pressed)
	_delete_btn.hide()
	add_child(_delete_btn)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := get_local_mouse_position()
		# Expand hit area to include the hanging move buttons outside the card.
		var pad := float(BTN_SIZE)
		var inside := Rect2(-pad, -pad, _card_w + pad * 2.0, _card_h + pad * 2.0).has_point(local)
		if inside != _hovered:
			_hovered = inside
			_controls.visible = _hovered
			if not _is_first_station and not _add_mode:
				for b in [_btn_up, _btn_down, _btn_left, _btn_right]:
					b.visible = _hovered


func configure(data: Dictionary, station_index: int,
		card_x: float, card_y: float, card_w: float, card_h: float,
		occupied: Dictionary = {}) -> void:
	_data = data
	_occupied = occupied
	_station_index = station_index
	_station_id = data.get("id", 0)
	_pos_x = data.get("posX", station_index)
	_pos_y = data.get("posY", 0)
	_is_first_station = (station_index == 0)
	_card_w = card_w
	_card_h = card_h
	position = Vector2(card_x, card_y)

	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(card_w - 8, card_h - 8)

	_name_label.text = str(data.get("name", "Station"))
	_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)

	_controls.reset_size()

	var cycle = data.get("cycleTime", null)
	_cycle_label.visible = cycle != null
	_cycle_label.text = "Cycle: %d" % int(cycle) if cycle != null else ""
	_cycle_label.add_theme_color_override("font_color", MUTED_COLOR)
	_cycle_label.add_theme_font_size_override("font_size", SMALL_FONT)

	var wu_count: int = (data.get("workUnits", []) as Array).size()
	_wu_btn.text = "WUs (%d)" % wu_count
	_wu_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	_ops_btn.add_theme_font_size_override("font_size", SMALL_FONT)
	var accent := _parse_color(data.get("color", null), "border", BORDER_COLOR)
	Palette.style_button(_wu_btn, accent)
	Palette.style_button(_ops_btn, accent)

	_update_move_buttons(accent, occupied)
	queue_redraw()


## Style and enable/disable the four directional move buttons.
func _update_move_buttons(accent: Color, occupied: Dictionary) -> void:
	# First station is immovable — buttons are never shown.
	if _is_first_station:
		return

	for b: Button in [_btn_up, _btn_down, _btn_left, _btn_right]:
		_style_move_button(b, accent)

	_btn_up.disabled    = (_pos_y <= 0) or _is_pos_occupied(_pos_x, _pos_y - 1, occupied)
	_btn_down.disabled  = _is_pos_occupied(_pos_x, _pos_y + 1, occupied)
	_btn_left.disabled  = (_pos_x <= 0) or _is_pos_occupied(_pos_x - 1, _pos_y, occupied)
	_btn_right.disabled = _is_pos_occupied(_pos_x + 1, _pos_y, occupied)

	# Top/bottom buttons: 3× wide, 1× tall — centered horizontally on the edge.
	var wide: float = BTN_SIZE * 3.0
	_btn_up.custom_minimum_size   = Vector2(wide, BTN_SIZE)
	_btn_down.custom_minimum_size = Vector2(wide, BTN_SIZE)
	_btn_up.position   = Vector2(_card_w / 2.0 - wide / 2.0, -BTN_SIZE)
	_btn_down.position = Vector2(_card_w / 2.0 - wide / 2.0, _card_h)

	# Left/right buttons: 1× wide, 3× tall — centered vertically on the edge.
	var tall: float = BTN_SIZE * 3.0
	_btn_left.custom_minimum_size  = Vector2(BTN_SIZE, tall)
	_btn_right.custom_minimum_size = Vector2(BTN_SIZE, tall)
	_btn_left.position  = Vector2(-BTN_SIZE, _card_h / 2.0 - tall / 2.0)
	_btn_right.position = Vector2(_card_w,   _card_h / 2.0 - tall / 2.0)


func _style_move_button(btn: Button, accent: Color) -> void:
	btn.add_theme_font_size_override("font_size", 7)
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = accent.lightened(0.2)
	var sb_pressed := sb.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = accent.darkened(0.2)
	var sb_disabled := sb.duplicate() as StyleBoxFlat
	sb_disabled.bg_color = Color(accent.r, accent.g, accent.b, 0.25)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))


func _is_pos_occupied(px: int, py: int, occupied: Dictionary) -> bool:
	if not occupied.has(px):
		return false
	return (occupied[px] as Dictionary).has(py)


func _on_move_dir(dx: int, dy: int) -> void:
	if _is_first_station:
		return
	station_move_requested.emit(_station_id, _pos_x + dx, _pos_y + dy)


## Update right/down button state to reflect whether a line-expanding move
## would collide with a neighbouring entity. Called by Line.gd after layout.
func refresh_expansion_block(block_right: bool, block_down: bool) -> void:
	if _is_first_station:
		return
	if block_right:
		_btn_right.text = "!"
		_btn_right.tooltip_text = "A node is preventing the line from growing."
		_btn_right.disabled = true
	else:
		_btn_right.text = ""
		_btn_right.tooltip_text = ""
		_btn_right.disabled = _is_pos_occupied(_pos_x + 1, _pos_y, _occupied)
	if block_down:
		_btn_down.text = "!"
		_btn_down.tooltip_text = "A node is preventing the line from growing."
		_btn_down.disabled = true
	else:
		_btn_down.text = ""
		_btn_down.tooltip_text = ""
		_btn_down.disabled = _is_pos_occupied(_pos_x, _pos_y + 1, _occupied)


func close_overlay() -> void:
	pass  # StationOverlay is managed by Line.gd; signal to close is issued there.


## Called by Line.gd when Add mode is toggled on/off.
## Hides move buttons entirely while Add mode is active to avoid mis-taps.
func set_add_mode(on: bool) -> void:
	_add_mode = on
	if on or not _hovered:
		for b in [_btn_up, _btn_down, _btn_left, _btn_right]:
			b.hide()


## Called by Line.gd when Delete mode is toggled on/off.
## Shows/hides the red Delete button inside each station card.
func set_delete_mode(on: bool) -> void:
	_delete_btn.visible = on
	if on:
		var btn_w := _card_w - 8.0
		_delete_btn.custom_minimum_size = Vector2(btn_w, 18.0)
		_delete_btn.position = Vector2(4.0, 4.0)


func _on_delete_pressed() -> void:
	var name: String = str(_data.get("name", "this station"))
	BOSSBridge.show_delete_modal(
		"Delete station '%s'?" % name,
		func(): delete_requested.emit(_station_id, name)
	)


func _on_edit_pressed() -> void:
	BOSSBridge.open_window("EditStation", [int(_data.get("id", 0))])


func _reposition_controls() -> void:
	if _card_w <= 0:
		return
	_controls.position = Vector2(_card_w - _controls.size.x - 4.0, 4.0)


func _draw() -> void:
	var color_data = _data.get("color", null)
	var fill   := _parse_color(color_data, "fill",   FILL_COLOR)
	var border := _parse_color(color_data, "border", BORDER_COLOR)
	draw_rect(Rect2(0, 0, _card_w, _card_h), fill)
	draw_rect(Rect2(0, 0, _card_w, _card_h), border, false, BORDER_WIDTH)


func _parse_color(color_data, key: String, fallback: Color) -> Color:
	if color_data == null:
		return fallback
	var hex: String = str(color_data.get(key, ""))
	if hex.is_empty():
		return fallback
	if hex.begins_with("#"):
		hex = hex.substr(1)
	return Color.from_string(hex, fallback)
