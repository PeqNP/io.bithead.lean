## Copyright © 2026 Bithead LLC. All rights reserved.

## MiniMap — fixed-size overlay showing all Line and Inventory entities as
## solid accent-colored blocks. Hosted on a CanvasLayer so it stays fixed in
## screen space while the camera moves.
##
## Usage:
##   var mm := MiniMap.new()
##   canvas_layer.add_child(mm)
##   mm.refresh(entries, floor_bounds)   # call after every _render_entities()
##
## entries: Array of { rect: Rect2, color: Color }
## floor_bounds: full pixel-space bounding rect of the floor (from _compute_floor_bounds)

class_name MiniMap extends Control

## Fixed screen-space size: 2 × TILE_SIZE (64 px) per axis.
const SIZE     := 128.0
## Gap from the viewport bottom-left corner.
const PAD      :=  12.0
## Background fill — Solarized BASE_03 at 75 % opacity.
const BG_COLOR := Color(0.000, 0.169, 0.212, 0.75)
## Minimum pixel size for any entity block so tiny items remain visible.
const MIN_BLOCK := 2.0

## Emitted when the user taps the minimap.
## world_pos is the corresponding world-space position on the factory floor.
signal tapped(world_pos: Vector2)

var _entries: Array       = []
var _floor_bounds: Rect2  = Rect2(0.0, 0.0, 1.0, 1.0)


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Update the minimap contents. Call this after every snapshot render.
## entries  — Array of { "rect": Rect2, "color": Color }
## floor_bounds — full floor extent in world-space pixels
func refresh(entries: Array, floor_bounds: Rect2) -> void:
	_entries      = entries
	_floor_bounds = floor_bounds
	queue_redraw()


## Reposition to the bottom-left of the current viewport.
func reposition(viewport_size: Vector2) -> void:
	position = Vector2(PAD, viewport_size.y - SIZE - PAD)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var scale: float = min(
				SIZE / _floor_bounds.size.x,
				SIZE / _floor_bounds.size.y
			)
			if scale <= 0.0:
				return
			# mb.position is in local Control space (0..SIZE) because
			# custom_minimum_size is set. Invert the _draw() transform:
			# mapped = (world - floor_origin) * scale  →  world = floor_origin + mapped / scale
			var local: Vector2 = mb.position
			var world_pos: Vector2 = Vector2(
				_floor_bounds.position.x + clamp(local.x, 0.0, SIZE) / scale,
				_floor_bounds.position.y + clamp(local.y, 0.0, SIZE) / scale
			)
			tapped.emit(world_pos)
			accept_event()


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, SIZE, SIZE), BG_COLOR)

	if _floor_bounds.size.x <= 0.0 or _floor_bounds.size.y <= 0.0:
		return

	var scale: float = min(
		SIZE / _floor_bounds.size.x,
		SIZE / _floor_bounds.size.y
	)

	for entry: Dictionary in _entries:
		var r: Rect2  = entry["rect"]
		var c: Color  = entry["color"]
		var mapped: Rect2 = Rect2(
			(r.position.x - _floor_bounds.position.x) * scale,
			(r.position.y - _floor_bounds.position.y) * scale,
			max(r.size.x * scale, MIN_BLOCK),
			max(r.size.y * scale, MIN_BLOCK)
		)
		draw_rect(mapped, c)
