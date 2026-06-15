## Copyright © 2026 Bithead LLC. All rights reserved.

## Background node — draws the dark floor and dot-grid.
## Attached to the Background Node2D child of FactoryFloor.

extends Node2D

const BG_COLOR   := Palette.BG_0
const DOT_COLOR  := Palette.FG_0
const DOT_RADIUS := 1.0
const TILE_SIZE  := 64

## Set by FactoryFloor when the grid grows.
var floor_width_tiles:  int = 20
var floor_height_tiles: int = 20


func _draw() -> void:
	var w := floor_width_tiles  * TILE_SIZE
	var h := floor_height_tiles * TILE_SIZE

	# Fill background.
	draw_rect(Rect2(0, 0, w, h), BG_COLOR)

	# Dot at every tile intersection.
	for tx in range(floor_width_tiles + 1):
		for ty in range(floor_height_tiles + 1):
			draw_circle(Vector2(tx * TILE_SIZE, ty * TILE_SIZE), DOT_RADIUS, DOT_COLOR)
