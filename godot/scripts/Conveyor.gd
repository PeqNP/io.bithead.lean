## Copyright © 2026 Bithead LLC. All rights reserved.

## Draws conveyor belts between two local-space points.
##
## Layer 1: draw_static — plain Line2D stub.
## Layer 4: draw_animated — returns a ChevronBelt Node2D that animates.
##
## Usage:
##   Conveyor.draw_static(from, to, parent_node)
##   Conveyor.draw_animated(from, to, parent_node, color)  # returns ChevronBelt

class_name Conveyor

const BELT_COLOR   := Color(0.3, 0.8, 0.7, 0.8)
const BELT_WIDTH   := 4.0


## Draw a plain static belt line. Returns the Line2D.
static func draw_static(from: Vector2, to: Vector2, parent: Node2D) -> Line2D:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = BELT_WIDTH
	line.default_color = BELT_COLOR
	parent.add_child(line)
	return line


## Draw an animated chevron belt from `from` to `to` as a child of `parent`.
## Returns the ChevronBelt node.
static func draw_animated(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR) -> Node2D:
	var belt := ChevronBelt.new()
	belt.setup(from, to, color)
	parent.add_child(belt)
	return belt


# ---------------------------------------------------------------------------
# ChevronBelt — inner class, instantiated by draw_animated
# ---------------------------------------------------------------------------

class ChevronBelt extends Node2D:
	const ANIM_SPEED    := 40.0   # px/s — how fast chevrons scroll
	const CHEVRON_STEP  := 18.0   # px between chevron origins
	const CHEVRON_SIZE  :=  6.0   # half-height of the > shape
	const LINE_W        :=  2.0

	var _from: Vector2 = Vector2.ZERO
	var _to:   Vector2 = Vector2.ZERO
	var _color: Color  = Color(0.3, 0.8, 0.7, 0.8)
	var _offset: float = 0.0
	var _length: float = 0.0
	var _angle: float  = 0.0


	func setup(from: Vector2, to: Vector2, color: Color) -> void:
		_from   = from
		_to     = to
		_color  = color
		_length = from.distance_to(to)
		_angle  = from.angle_to_point(to)


	func _process(delta: float) -> void:
		_offset = fmod(_offset + ANIM_SPEED * delta, CHEVRON_STEP)
		if _is_in_viewport():
			queue_redraw()


	## Return true when any part of the belt falls within the camera viewport.
	func _is_in_viewport() -> bool:
		var vp := get_viewport()
		if vp == null:
			return true
		var cam_xform: Transform2D = vp.get_canvas_transform()
		var inv := cam_xform.affine_inverse()
		var vp_rect: Rect2 = vp.get_visible_rect()
		var world_tl := inv * vp_rect.position
		var world_br := inv * vp_rect.end
		var world_rect := Rect2(world_tl.min(world_br), (world_br - world_tl).abs())
		# Belt AABB in global (world) space.
		var gfrom := to_global(_from)
		var gto   := to_global(_to)
		var pad   := CHEVRON_SIZE + 2.0
		var belt_rect := Rect2(
			gfrom.min(gto) - Vector2(pad, pad),
			(gto - gfrom).abs() + Vector2(pad * 2.0, pad * 2.0)
		)
		return world_rect.intersects(belt_rect)


	func _draw() -> void:
		# Track line
		draw_line(_from, _to, _color * Color(1, 1, 1, 0.3), LINE_W)

		# Chevrons along the path
		var dir    := (_to - _from).normalized()
		var perp   := Vector2(-dir.y, dir.x)
		var t      := _offset
		while t < _length:
			var origin := _from + dir * t
			var tip    := origin + dir * CHEVRON_SIZE
			var top    := origin - perp * CHEVRON_SIZE
			var bot    := origin + perp * CHEVRON_SIZE
			draw_line(top, tip, _color, LINE_W)
			draw_line(tip, bot, _color, LINE_W)
			t += CHEVRON_STEP

