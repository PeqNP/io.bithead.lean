## Copyright © 2026 Bithead LLC. All rights reserved.

## FactoryFloor — main scene root.
##
## Responsibilities (Layer 0):
##   - Wire BOSS JS bridge: read window.boss, register _send_callback,
##     handle "configure" command to start BOSSBridge.
##   - Connect BOSSBridge signals for snapshot and error.
##   - Handle Camera2D pan/zoom.
##   - Show ErrorModal on any BOSSBridge error.
##
## Entities are rendered in Layer 1+.

extends Node2D

const TILE_SIZE := 64
const ZOOM_LEVELS: Array[Vector2] = [
	Vector2(1.0,  1.0),
	Vector2(0.75, 0.75),
	Vector2(0.5,  0.5),
	Vector2(0.25, 0.25),
]

var _zoom_index: int = 0

# Grid manager — owns tile occupation state.
var grid: GridManager = GridManager.new()

# BOSS JS bridge references.
var _delegate: JavaScriptObject
var _send_callback: JavaScriptObject

@onready var _camera:      Camera2D   = $Camera2D
@onready var _error_modal: CanvasLayer = $ErrorModal/ErrorModal
@onready var _bg:          Node2D     = $Background


func _ready() -> void:
	BOSSBridge.snapshot_updated.connect(_on_snapshot_updated)
	BOSSBridge.error.connect(_on_boss_error)
	grid.floor_grew.connect(_on_floor_grew)

	_update_camera_limits()

	if Engine.has_singleton("JavaScriptBridge"):
		var window := JavaScriptBridge.get_interface("window")
		if window.boss:
			_delegate = window.boss
			_send_callback = JavaScriptBridge.create_callback(_on_boss_send)
			_delegate.send = _send_callback
		else:
			push_warning("FactoryFloor: window.boss not set — running outside BOSS?")


# ---------------------------------------------------------------------------
# BOSS bridge
# ---------------------------------------------------------------------------

func _on_boss_send(args: Array) -> void:
	if args.is_empty():
		return
	var cmd: JavaScriptObject = args[0]
	var c_name: String = str(cmd["name"])
	match c_name:
		"configure":
			var data: JavaScriptObject = cmd["data"]
			var factory_id: int = int(str(data["factoryId"]))
			var base_url: String = str(data["baseUrl"])
			BOSSBridge.configure(factory_id, base_url)
		_:
			push_warning("FactoryFloor: unknown BOSS command '%s'" % c_name)


# ---------------------------------------------------------------------------
# BOSSBridge signals
# ---------------------------------------------------------------------------

func _on_snapshot_updated(snapshot: Dictionary) -> void:
	# Layer 1+ renders entities. Nothing to do in Layer 0.
	pass


func _on_boss_error(message: String) -> void:
	_error_modal.show_error("Error", message)


func _on_floor_grew(_new_w: int, _new_h: int) -> void:
	_update_camera_limits()
	_bg.queue_redraw()


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------

func _update_camera_limits() -> void:
	var bounds: Rect2 = grid.bounds_world(TILE_SIZE)
	_camera.limit_left   = int(bounds.position.x)
	_camera.limit_top    = int(bounds.position.y)
	_camera.limit_right  = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)


func set_zoom(index: int) -> void:
	_zoom_index = clamp(index, 0, ZOOM_LEVELS.size() - 1)
	_camera.zoom = ZOOM_LEVELS[_zoom_index]


func zoom_in() -> void:
	set_zoom(_zoom_index - 1)


func zoom_out() -> void:
	set_zoom(_zoom_index + 1)


func _unhandled_input(event: InputEvent) -> void:
	# Pan with middle mouse drag.
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_camera.position -= event.relative / _camera.zoom

	# Zoom with scroll wheel.
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()
