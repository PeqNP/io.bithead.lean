## Copyright © 2026 Bithead LLC. All rights reserved.

## Manages the logical tile grid for the FactoryFloor.
##
## Tiles are identified by integer (x, y) coordinates. The grid grows only
## rightward and downward. A +4-tile buffer is maintained beyond the
## furthest-right and furthest-bottom occupied tile.
##
## Usage (instantiate once and keep a reference):
##   var grid := GridManager.new()
##   grid.occupy(0, 0, 12, 2, some_id)
##   grid.is_available(0, 0, 1, 1)   # → false
##   grid.get_first_available(12, 2) # → Vector2i or Vector2i(-1,-1) if none

class_name GridManager

const EDGE_BUFFER := 4

## Maps Vector2i(tile_x, tile_y) → entity id (int).
var _occupied: Dictionary = {}

## Tracks which tiles belong to each entity id for fast freeing.
## Maps entity_id → Array[Vector2i]
var _entity_tiles: Dictionary = {}

## Current floor dimensions in tiles (grows only right/bottom).
var width_tiles: int = 20
var height_tiles: int = 20


## Returns true if every tile in the w×h rectangle starting at (x, y) is free.
func is_available(x: int, y: int, w: int, h: int) -> bool:
	for tx in range(x, x + w):
		for ty in range(y, y + h):
			if _occupied.has(Vector2i(tx, ty)):
				return false
	return true


## Mark a w×h rectangle of tiles starting at (x, y) as occupied by entity_id.
## Also grows the floor if the occupied area approaches the edge.
func occupy(x: int, y: int, w: int, h: int, entity_id: int) -> void:
	var tiles: Array[Vector2i] = []
	for tx in range(x, x + w):
		for ty in range(y, y + h):
			var tile := Vector2i(tx, ty)
			_occupied[tile] = entity_id
			tiles.append(tile)
	_entity_tiles[entity_id] = tiles
	grow_if_needed(x + w - 1, y + h - 1)


## Free all tiles occupied by entity_id.
func free_entity(entity_id: int) -> void:
	if not _entity_tiles.has(entity_id):
		return
	for tile in _entity_tiles[entity_id]:
		_occupied.erase(tile)
	_entity_tiles.erase(entity_id)


## Expand the floor if the given tile is within EDGE_BUFFER tiles of the edge.
func grow_if_needed(tile_x: int, tile_y: int) -> void:
	var changed := false
	if tile_x >= width_tiles - EDGE_BUFFER:
		width_tiles = tile_x + EDGE_BUFFER + 4
		changed = true
	if tile_y >= height_tiles - EDGE_BUFFER:
		height_tiles = tile_y + EDGE_BUFFER + 4
		changed = true
	if changed:
		floor_grew.emit(width_tiles, height_tiles)


## Find the first available top-left tile where a w×h rectangle fits.
## Scans left-to-right, top-to-bottom.
## Returns Vector2i(-1, -1) if no position found within current bounds.
func get_first_available(w: int, h: int) -> Vector2i:
	for ty in range(height_tiles - h + 1):
		for tx in range(width_tiles - w + 1):
			if is_available(tx, ty, w, h):
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


## Returns the world-space bounding Rect2 of the entire floor.
## Useful for clamping the Camera2D.
func bounds_world(tile_size: int) -> Rect2:
	return Rect2(0, 0, width_tiles * tile_size, height_tiles * tile_size)


## Emitted when the floor dimensions grow. Listeners should update the camera
## clamp and redraw the background grid.
signal floor_grew(new_width_tiles: int, new_height_tiles: int)
