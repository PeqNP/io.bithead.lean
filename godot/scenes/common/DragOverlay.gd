## Copyright © 2026 Bithead LLC. All rights reserved.

## DragOverlay — drawn on top of all entities during a move operation.
##
## Shows green tiles for available positions, red for occupied.
## Follows the mouse and snaps to tile grid.
## FactoryFloor instantiates one of these and calls begin/end.

extends Node2D

const TILE_SIZE := 64

const COLOR_AVAIL    := Palette.GREEN_AVAIL
const COLOR_OCCUPIED := Palette.RED_OCCUPIED
const COLOR_GHOST    := Palette.FG_1_GHOST

var _tile_w: int = 0
var _tile_h: int = 0
var _px_w: float = 0.0   # entity's actual pixel width (for ghost drawing)
var _px_h: float = 0.0   # entity's actual pixel height (for ghost drawing)
var _exclude_area_rid: RID              # physics RID of entity being moved (excluded from query)
var _ghost_shape: RectangleShape2D      # reused each frame for placement query
var _ghost_params: PhysicsShapeQueryParameters2D  # reused each frame
var _drag_offset: Vector2 = Vector2.ZERO
var _snap_tile: Vector2i = Vector2i.ZERO
var _valid: bool = false

## Full-screen input blocker: shown during drag to prevent button/control interaction.
var _input_blocker: ColorRect = null

## Position label shown during drag.
@onready var _pos_label: Label = $PosLabel


func _ready() -> void:
	z_index = 100
	set_process(false)
	_pos_label.add_theme_color_override("font_color", Color.WHITE)
	_pos_label.add_theme_font_size_override("font_size", 11)

	# CanvasLayer at a high layer so its child Control sits above all entities.
	var blocker_layer := CanvasLayer.new()
	blocker_layer.layer = 128
	add_child(blocker_layer)

	# Transparent Control that eats all GUI input (button clicks, etc.) during drag.
	_input_blocker = ColorRect.new()
	_input_blocker.color = Color(0.0, 0.0, 0.0, 0.0)
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_blocker.hide()
	blocker_layer.add_child(_input_blocker)


## Start a drag operation for an entity of tile size w×h.
## exclude_area_rid is the physics RID of the entity's Area2D — excluded from placement queries.
## entity_pos is the entity's world-space top-left at the moment Move is pressed.
## pixel_size overrides the ghost dimensions when the entity's visual size is smaller than tile_h*TILE_SIZE.
func begin(tile_w: int, tile_h: int, exclude_area_rid: RID,
		entity_pos: Vector2, pixel_size: Vector2 = Vector2.ZERO) -> void:
	_tile_w = tile_w
	_tile_h = tile_h
	_px_w = pixel_size.x if pixel_size.x > 0.0 else tile_w * TILE_SIZE
	_px_h = pixel_size.y if pixel_size.y > 0.0 else tile_h * TILE_SIZE
	_exclude_area_rid = exclude_area_rid
	_drag_offset = get_global_mouse_position() - entity_pos
	# Clamp offset so it stays within entity bounds.
	_drag_offset.x = clamp(_drag_offset.x, 0.0, _px_w - 1.0)
	_drag_offset.y = clamp(_drag_offset.y, 0.0, _px_h - 1.0)
	# Build reusable physics query params for this drag session.
	_ghost_shape = RectangleShape2D.new()
	_ghost_shape.size = Vector2(_px_w, _px_h)
	_ghost_params = PhysicsShapeQueryParameters2D.new()
	_ghost_params.shape = _ghost_shape
	_ghost_params.collision_mask = 1
	_ghost_params.collide_with_areas = true
	_ghost_params.collide_with_bodies = false
	_ghost_params.exclude = [_exclude_area_rid]
	# Size the blocker to fill the current viewport, then show it.
	_input_blocker.size = get_viewport().get_visible_rect().size
	_input_blocker.show()
	show()
	set_process(true)


## End the drag operation. Returns the snapped tile if valid, else Vector2i(-1,-1).
func end() -> Vector2i:
	_input_blocker.hide()
	hide()
	set_process(false)
	return _snap_tile if _valid else Vector2i(-1, -1)


## Current snapped tile position of the ghost (world tile coordinates).
func get_snap_tile() -> Vector2i:
	return _snap_tile


## Pixel size of the ghost rectangle.
func get_ghost_pixel_size() -> Vector2:
	return Vector2(_px_w, _px_h)


func _process(_delta: float) -> void:
	var mouse_world := get_global_mouse_position()
	# Subtract the click offset so the entity top-left — not the mouse — snaps to a tile.
	var anchored := mouse_world - _drag_offset
	_snap_tile = Vector2i(
		int(anchored.x) / TILE_SIZE,
		int(anchored.y) / TILE_SIZE
	)
	_snap_tile.x = max(0, _snap_tile.x)
	_snap_tile.y = max(0, _snap_tile.y)

	# Check placement using Area2D physics query — pixel-accurate, no tile rounding.
	var snap_pos := Vector2(_snap_tile.x * TILE_SIZE, _snap_tile.y * TILE_SIZE)
	_ghost_params.transform = Transform2D(0.0, snap_pos + Vector2(_px_w, _px_h) * 0.5)
	_valid = get_world_2d().direct_space_state.intersect_shape(_ghost_params, 1).is_empty()

	_pos_label.text = "(%d, %d)" % [_snap_tile.x, _snap_tile.y]
	_pos_label.position = Vector2(_snap_tile.x * TILE_SIZE,
		_snap_tile.y * TILE_SIZE - 18)

	queue_redraw()


func _draw() -> void:
	if _ghost_params == null:
		return
	# Ghost of the entity being moved — sized to the entity's actual pixel dimensions.
	var ghost_rect := Rect2(
		_snap_tile.x * TILE_SIZE, _snap_tile.y * TILE_SIZE,
		_px_w, _px_h
	)
	draw_rect(ghost_rect, COLOR_GHOST)

	# Tile-by-tile availability highlight, clipped to the entity's actual pixel bounds.
	var col := COLOR_AVAIL if _valid else COLOR_OCCUPIED
	var entity_rect := Rect2(_snap_tile.x * TILE_SIZE, _snap_tile.y * TILE_SIZE, _px_w, _px_h)
	for tx in range(_snap_tile.x, _snap_tile.x + _tile_w):
		for ty in range(_snap_tile.y, _snap_tile.y + _tile_h):
			var tile_rect := Rect2(tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			var clipped := tile_rect.intersection(entity_rect)
			if clipped.size.x > 0.0 and clipped.size.y > 0.0:
				draw_rect(clipped, col, false, 2.0)
