## Copyright © 2026 Bithead LLC. All rights reserved.

## Draws conveyor belts between two world-space points.
##
## Layer 1: static line stub.
## Layer 4: replaced with animated chevron belts.
##
## Usage:
##   Conveyor.draw_static(from, to, parent_node)
##   Conveyor.draw_animated(from, to, parent_node)   # Layer 4+

class_name Conveyor

const BELT_COLOR   := Color(0.3, 0.8, 0.7, 0.8)
const BELT_WIDTH   := 4.0


## Draw a plain static belt line from `from` to `to` as a child of `parent`.
## Returns the Line2D node so the caller can free it when rebuilding.
static func draw_static(from: Vector2, to: Vector2, parent: Node2D) -> Line2D:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = BELT_WIDTH
	line.default_color = BELT_COLOR
	parent.add_child(line)
	return line
