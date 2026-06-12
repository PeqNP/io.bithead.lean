## Copyright © 2026 Bithead LLC. All rights reserved.

## DragOverlay — drawn on top of all entities during a move operation.
##
## Shows green tiles for available positions, red for occupied.
## Follows the mouse and snaps to tile grid.
## FactoryFloor instantiates one of these and calls begin/end.

extends Node2D

const TILE_SIZE := 64

const COLOR_AVAIL    := Color(0.2, 1.0, 0.3, 0.35)
const COLOR_OCCUPIED := Color(1.0, 0.2, 0.2, 0.35)
const COLOR_GHOST    := Color(1.0, 1.0, 1.0, 0.15)

var _grid: GridManager = null
var _tile_w: int = 0
var _tile_h: int = 0
var _exclude_id: int = 0   # id of entity being moved (treated as available)
var _drag_offset: Vector2 = Vector2.ZERO   # mouse-to-entity-top-left offset at drag start
var _original_tile: Vector2i = Vector2i.ZERO  # entity's tile position when Move was pressed
var _snap_tile: Vector2i = Vector2i.ZERO
var _valid: bool = false

## Position label shown during drag.
@onready var _pos_label: Label = $PosLabel


func _ready() -> void:
	z_index = 100
	set_process(false)
	_pos_label.add_theme_color_override("font_color", Color.WHITE)
	_pos_label.add_theme_font_size_override("font_size", 11)


## Start a drag operation for an entity of tile size w×h with given id.
## entity_pos is the entity's world-space top-left at the moment Move is pressed;
## it is used to keep the mouse anchored at the same relative point within the entity.
func begin(grid: GridManager, tile_w: int, tile_h: int, exclude_id: int,
		entity_pos: Vector2) -> void:
	_grid = grid
	_tile_w = tile_w
	_tile_h = tile_h
	_exclude_id = exclude_id
	_drag_offset = get_global_mouse_position() - entity_pos
	# Clamp offset so it stays within entity bounds.
	_drag_offset.x = clamp(_drag_offset.x, 0.0, tile_w * TILE_SIZE - 1.0)
	_drag_offset.y = clamp(_drag_offset.y, 0.0, tile_h * TILE_SIZE - 1.0)
	_original_tile = Vector2i(int(entity_pos.x) / TILE_SIZE, int(entity_pos.y) / TILE_SIZE)
	show()
	set_process(true)


## End the drag operation. Returns the snapped tile if valid, else Vector2i(-1,-1).
func end() -> Vector2i:
	hide()
	set_process(false)
	return _snap_tile if _valid else Vector2i(-1, -1)


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

	# Temporarily free dragged entity to check availability at new tile.
	# If valid: re-occupy at the preview tile so other entities' availability
	# checks remain correct next frame.
	# If invalid: re-occupy at the original tile so we never overwrite another
	# entity's grid entries (GridManager.occupy silently overwrites).
	_grid.free_entity(_exclude_id)
	_valid = _grid.is_available(_snap_tile.x, _snap_tile.y, _tile_w, _tile_h)
	if _valid:
		_grid.occupy(_snap_tile.x, _snap_tile.y, _tile_w, _tile_h, _exclude_id)
	else:
		_grid.occupy(_original_tile.x, _original_tile.y, _tile_w, _tile_h, _exclude_id)

	_pos_label.text = "(%d, %d)" % [_snap_tile.x, _snap_tile.y]
	_pos_label.position = Vector2(_snap_tile.x * TILE_SIZE,
		_snap_tile.y * TILE_SIZE - 18)

	queue_redraw()


func _draw() -> void:
	if _grid == null:
		return
	# Ghost of the entity being moved.
	var ghost_rect := Rect2(
		_snap_tile.x * TILE_SIZE, _snap_tile.y * TILE_SIZE,
		_tile_w * TILE_SIZE, _tile_h * TILE_SIZE
	)
	draw_rect(ghost_rect, COLOR_GHOST)

	# Tile-by-tile availability highlight.
	for tx in range(_snap_tile.x, _snap_tile.x + _tile_w):
		for ty in range(_snap_tile.y, _snap_tile.y + _tile_h):
			var col := COLOR_AVAIL if _valid else COLOR_OCCUPIED
			draw_rect(Rect2(tx * TILE_SIZE, ty * TILE_SIZE, TILE_SIZE, TILE_SIZE),
				col, false, 2.0)
