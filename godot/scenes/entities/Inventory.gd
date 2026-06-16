## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders a single Inventory node from a LeanFragment.FactoryFloor.Inventory snapshot.

extends Node2D

const TILE_SIZE    := 64
const INV_W        :=  4 * TILE_SIZE   # 256 px
const INV_H        :=  2 * TILE_SIZE   # 128 px

const FILL_COLOR           := Palette.BG_1
const FILL_FOCUSED_COLOR   := Palette.BG_0
const BORDER_COLOR         := Palette.FG_1
const BORDER_FOCUSED_COLOR := Palette.GREEN
const BORDER_WIDTH         := 3.0
const LABEL_COLOR          := Palette.FG_1
const FONT_SIZE            := 11

const HEALTH_COLORS := {
	1: Palette.GREEN,
	2: Palette.ORANGE,
	3: Palette.RED,
}

const STOCK_PANEL_SCENE := preload("res://scenes/entities/InventoryStockPanel.tscn")

signal move_requested(entity: Node2D, tile_w: int, tile_h: int)
signal focus_toggled(entity_id: int, focused: bool)
signal lock_toggled(entity_id: int, locked: bool)

var _data: Dictionary = {}
var _entity_id: int = 0
var _focused: bool = false
var _locked: bool = false
var _hovered: bool = false
# Placement collision — fixed 128×128 px.
var _area: Area2D
var _col_shape: RectangleShape2D

var _stock_panel: Node2D = null
var _stock_open: bool = false
var _stock_triangle: Control = null

@onready var _layout:        VBoxContainer = $Layout
@onready var _name_label:    Label         = $Layout/Name
@onready var _health_label:  Label         = $Layout/HealthLabel
@onready var _order_label:   Label         = $Layout/OrderRequestLabel
@onready var _stock_btn:     Button        = $Layout/StockButton
@onready var _controls:      HBoxContainer = $Controls
@onready var _move_btn:      Button        = $Controls/MoveButton
@onready var _focus_btn:     Button        = $Controls/FocusButton
@onready var _lock_btn:      Button        = $Controls/LockButton


func _ready() -> void:
	set_process_input(true)
	queue_redraw()
	# Build Area2D for pixel-accurate placement collision detection.
	var col := CollisionShape2D.new()
	_col_shape = RectangleShape2D.new()
	_col_shape.size = Vector2(INV_W, INV_H)
	col.shape = _col_shape
	_area = Area2D.new()
	_area.collision_layer = 1
	_area.collision_mask  = 0
	_area.monitoring      = false
	_area.monitorable     = true
	_area.position        = Vector2(INV_W / 2.0, INV_H / 2.0)
	_area.add_child(col)
	add_child(_area)

	_stock_panel = STOCK_PANEL_SCENE.instantiate()
	_stock_panel.position = Vector2(0, INV_H + 2)
	_stock_panel.hide()
	add_child(_stock_panel)

	_stock_btn.add_theme_font_size_override("font_size", 8)
	_stock_btn.pressed.connect(_on_stock_pressed)

	for btn in [_move_btn, _focus_btn, _lock_btn]:
		Palette.style_edit_button(btn)
		btn.add_theme_font_size_override("font_size", 9)
	_move_btn.pressed.connect(_on_move_pressed)
	_focus_btn.pressed.connect(_on_focus_pressed)
	_lock_btn.pressed.connect(_on_lock_pressed)
	_controls.resized.connect(_reposition_controls)

	Palette.style_button(_stock_btn, Palette.GREEN)
	# Build HBox content inside the button: "Stock" label + triangle indicator.
	_stock_btn.text = ""
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.set_anchors_preset(Control.PRESET_CENTER)
	hbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hbox.grow_vertical   = Control.GROW_DIRECTION_BOTH
	var lbl := Label.new()
	lbl.text = "Stock"
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stock_triangle = DrawShape.triangle(hbox, false)
	_stock_btn.add_child(hbox)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var local := to_local(get_global_mouse_position())
		var inside := Rect2(0, 0, INV_W, INV_H).has_point(local)
		if inside != _hovered:
			_hovered = inside
			_controls.visible = _hovered


func _on_lock_toggled_update() -> void:
	_lock_btn.text = "Unlock" if _locked else "Lock"
	_move_btn.disabled = _locked


func configure(data: Dictionary) -> void:
	_data = data
	_entity_id = data.get("id", 0)
	_locked = data.get("locked", false)

	position = Vector2(
		data.get("gridX", 0) * TILE_SIZE,
		data.get("gridY", 0) * TILE_SIZE
	)

	_layout.position = Vector2(4, 4)
	_layout.size = Vector2(INV_W - 8, INV_H - 8)

	_name_label.text = str(data.get("name", ""))
	_name_label.add_theme_color_override("font_color", LABEL_COLOR)
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)

	var health_str: String = str(data.get("health", ""))
	if health_str.is_empty():
		_health_label.hide()
	else:
		_health_label.text = health_str
		_health_label.add_theme_font_size_override("font_size", FONT_SIZE)
		match health_str:
			"Healthy":  _health_label.add_theme_color_override("font_color", Palette.GREEN)
			"Low":      _health_label.add_theme_color_override("font_color", Palette.ORANGE)
			"Critical": _health_label.add_theme_color_override("font_color", Palette.RED)
			_:          _health_label.add_theme_color_override("font_color", LABEL_COLOR)
		_health_label.show()

	var order: Dictionary = data.get("orderRequest", {}) as Dictionary
	if order.is_empty():
		_order_label.hide()
	else:
		var arrive: String = str(order.get("arriveDate", ""))
		if not arrive.is_empty():
			_order_label.text = "Arrived %s" % arrive
		else:
			var tracking: String = str(order.get("tracking", ""))
			if not tracking.is_empty():
				_order_label.text = "Shipped – %s" % tracking
			else:
				var eta: String = str(order.get("estimatedDeliveryDate", ""))
				_order_label.text = "Order pending – ETA %s" % eta
		_order_label.add_theme_font_size_override("font_size", FONT_SIZE)
		_order_label.add_theme_color_override("font_color", Palette.CYAN)
		_order_label.show()

	if _stock_panel != null:
		_stock_panel.configure(data)
	_update_controls()
	queue_redraw()


func update(data: Dictionary) -> void:
	configure(data)


func set_grayed(grayed: bool) -> void:
	if grayed:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/gray_out.gdshader")
		material = mat
	else:
		material = null


## Called by FactoryFloor when camera zoom index changes.
## zi: 0=100% 1=75% 2=50% 3=25%
func set_zoom_index(zi: int) -> void:
	_name_label.visible = (zi < 3)


## Returns the physics RID of this Inventory's Area2D, used for DragOverlay placement queries.
func get_area_rid() -> RID:
	return _area.get_rid()


## World-space point at the center-right edge — used as the belt source for
## Inventory→Station connections.
func get_center_right_world() -> Vector2:
	return position + Vector2(INV_W, INV_H / 2.0)


## World-space point at the top-center edge.
func get_center_top_world() -> Vector2:
	return position + Vector2(INV_W / 2.0, 0.0)


## World-space point at the bottom-center edge.
func get_center_bottom_world() -> Vector2:
	return position + Vector2(INV_W / 2.0, INV_H)


func _draw() -> void:
	var fill   := FILL_FOCUSED_COLOR   if _focused else FILL_COLOR
	var border := BORDER_FOCUSED_COLOR if _focused else BORDER_COLOR
	draw_rect(Rect2(0, 0, INV_W, INV_H), fill)
	draw_rect(Rect2(0, 0, INV_W, INV_H), border, false, BORDER_WIDTH)


func _update_controls() -> void:
	_move_btn.disabled = _locked
	_focus_btn.text = "Unfocus" if _focused else "Focus"
	_lock_btn.text = "Unlock" if _locked else "Lock"
	_controls.reset_size()
	_controls.visible = _hovered


func _reposition_controls() -> void:
	_controls.position = Vector2(
		INV_W - _controls.size.x - int(BORDER_WIDTH) - 2,
		int(BORDER_WIDTH) + 2
	)


func _on_move_pressed() -> void:
	if _locked:
		return
	move_requested.emit(self, INV_W / TILE_SIZE, INV_H / TILE_SIZE)


func _on_focus_pressed() -> void:
	_focused = !_focused
	_focus_btn.text = "Unfocus" if _focused else "Focus"
	focus_toggled.emit(_entity_id, _focused)
	queue_redraw()


func _on_lock_pressed() -> void:
	_locked = !_locked
	_lock_btn.text = "Unlock" if _locked else "Lock"
	_move_btn.disabled = _locked
	lock_toggled.emit(_entity_id, _locked)


func _on_stock_pressed() -> void:
	_stock_open = !_stock_open
	_stock_panel.visible = _stock_open
	# Swap triangle direction: down when closed, up when open.
	_stock_triangle.get_parent().remove_child(_stock_triangle)
	_stock_triangle.queue_free()
	var hbox := _stock_btn.get_child(0) as HBoxContainer
	_stock_triangle = DrawShape.triangle(hbox, _stock_open)
