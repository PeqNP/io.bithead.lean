## Copyright © 2026 Bithead LLC. All rights reserved.
##
## DrawShape — utility that creates small Control nodes that draw primitive
## shapes via _draw().  All returned nodes have mouse_filter = IGNORE so
## they do not consume input events.
##
## Usage:
##   var tri := DrawShape.triangle(parent, false)   # pointing down
##   var tri := DrawShape.triangle(parent, true)    # pointing up
##   var dot := DrawShape.circle(parent)

class_name DrawShape
extends RefCounted


## Creates and adds a _TriangleControl child to `parent`.
## `flipped` false → pointing down (▼); true → pointing up (▲).
## `pointing_right` true overrides flipped and draws a right-pointing (▶) triangle.
## Returns the Control so the caller can adjust size / position.
static func triangle(parent: Node, flipped: bool, size: Vector2 = Vector2(8.0, 5.0),
		color: Color = Color.WHITE, pointing_right: bool = false) -> Control:
	var t := _TriangleControl.new()
	t.flipped        = flipped
	t.pointing_right = pointing_right
	t.draw_color     = color
	t.custom_minimum_size = size
	t.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(t)
	return t


## Creates and adds a _CircleControl child to `parent`.
## Returns the Control so the caller can adjust size / position.
static func circle(parent: Node, size: Vector2 = Vector2(8.0, 8.0),
		color: Color = Color.WHITE) -> Control:
	var c := _CircleControl.new()
	c.draw_color   = color
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(c)
	return c


# ---------------------------------------------------------------------------
# Inner Control classes
# ---------------------------------------------------------------------------

class _TriangleControl extends Control:
	var flipped:        bool  = false
	var pointing_right: bool  = false
	var draw_color:     Color = Color.WHITE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts: PackedVector2Array
		if pointing_right:
			# pointing right (▶)
			pts = PackedVector2Array([
				Vector2(0.0, 0.0),
				Vector2(w,   h * 0.5),
				Vector2(0.0, h),
			])
		elif flipped:
			# pointing up (▲)
			pts = PackedVector2Array([
				Vector2(w * 0.5, 0.0),
				Vector2(w,       h),
				Vector2(0.0,     h),
			])
		else:
			# pointing down (▼)
			pts = PackedVector2Array([
				Vector2(0.0,     0.0),
				Vector2(w,       0.0),
				Vector2(w * 0.5, h),
			])
		draw_colored_polygon(pts, draw_color)


class _CircleControl extends Control:
	var draw_color: Color = Color.WHITE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(Vector2(size.x * 0.5, size.y * 0.5), r, draw_color)
