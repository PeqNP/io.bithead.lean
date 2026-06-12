## Copyright © 2026 Bithead LLC. All rights reserved.

## Draws conveyor belts between two local-space points.
##
## Layer 1: draw_static  — plain Line2D stub.
## Layer 4: draw_animated — straight ChevronBelt (two waypoints).
##           draw_routed   — L-shaped ChevronBelt (three waypoints, horizontal-first).
##
## Usage:
##   Conveyor.draw_static(from, to, parent_node)
##   Conveyor.draw_animated(from, to, parent_node, color)   # straight
##   Conveyor.draw_routed(from, to, parent_node, color)     # L-shaped, always axis-aligned

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
## Draws a straight two-point belt. For cross-entity belts use draw_routed.
## Returns the ChevronBelt node.
static func draw_animated(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR) -> Node2D:
	var belt := ChevronBelt.new()
	belt.setup([from, to], color)
	parent.add_child(belt)
	return belt


## Draw an L-shaped routed belt: horizontal to target x, then vertical to target y.
## Keeps belts axis-aligned so they never cut diagonally through other entities.
## Falls back to straight if already axis-aligned in either axis.
static func draw_routed(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR) -> Node2D:
	var waypoints: Array[Vector2]
	if absf(from.x - to.x) < 1.0 or absf(from.y - to.y) < 1.0:
		# Already axis-aligned — straight segment.
		waypoints = [from, to]
	else:
		# Horizontal first, then vertical.
		waypoints = [from, Vector2(to.x, from.y), to]
	var belt := ChevronBelt.new()
	belt.setup(waypoints, color)
	parent.add_child(belt)
	return belt


# ---------------------------------------------------------------------------
# ChevronBelt — inner class, instantiated by draw_animated
# ---------------------------------------------------------------------------

class ChevronBelt extends Node2D:
	const ANIM_SPEED    := 40.0   # px/s
	const CHEVRON_STEP  := 18.0   # px between chevron origins
	const CHEVRON_SIZE  :=  6.0   # half-height of the > shape
	const LINE_W        :=  2.0

	var _waypoints: Array[Vector2] = []
	var _color: Color = Color(0.3, 0.8, 0.7, 0.8)
	var _offset: float = 0.0


	func setup(waypoints: Array[Vector2], color: Color) -> void:
		_waypoints = waypoints
		_color = color


	func _process(delta: float) -> void:
		_offset = fmod(_offset + ANIM_SPEED * delta, CHEVRON_STEP)
		if _is_in_viewport():
			queue_redraw()


	## Return true when any part of the belt's AABB is inside the camera viewport.
	func _is_in_viewport() -> bool:
		var vp := get_viewport()
		if vp == null or _waypoints.is_empty():
			return true
		var cam_xform: Transform2D = vp.get_canvas_transform()
		var inv := cam_xform.affine_inverse()
		var vp_rect: Rect2 = vp.get_visible_rect()
		var world_tl := inv * vp_rect.position
		var world_br := inv * vp_rect.end
		var world_rect := Rect2(world_tl.min(world_br), (world_br - world_tl).abs())
		# Compute AABB over all waypoints in world space.
		var gmin := to_global(_waypoints[0])
		var gmax := gmin
		for pt in _waypoints:
			var gpt := to_global(pt)
			gmin = gmin.min(gpt)
			gmax = gmax.max(gpt)
		var pad := CHEVRON_SIZE + 2.0
		var belt_rect := Rect2(gmin - Vector2(pad, pad), gmax - gmin + Vector2(pad * 2.0, pad * 2.0))
		return world_rect.intersects(belt_rect)


	func _draw() -> void:
		if _waypoints.size() < 2:
			return
		# Chevrons animate continuously across all segments.
		# `accumulated` tracks total path distance so far, used to phase-shift
		# each segment's chevron start so they flow seamlessly around bends.
		var accumulated: float = 0.0
		for i in range(_waypoints.size() - 1):
			var seg_from := _waypoints[i]
			var seg_to   := _waypoints[i + 1]
			var seg_len  := seg_from.distance_to(seg_to)
			if seg_len < 0.1:
				accumulated += seg_len
				continue
			var dir  := (seg_to - seg_from).normalized()
			var perp := Vector2(-dir.y, dir.x)
			# Track line.
			draw_line(seg_from, seg_to, _color * Color(1, 1, 1, 0.3), LINE_W)
			# Start chevrons at the phase-shifted offset for this segment.
			var t := fmod(accumulated + _offset, CHEVRON_STEP)
			while t < seg_len:
				var origin := seg_from + dir * t
				var tip    := origin + dir * CHEVRON_SIZE
				var top    := origin - perp * CHEVRON_SIZE
				var bot    := origin + perp * CHEVRON_SIZE
				draw_line(top, tip, _color, LINE_W)
				draw_line(tip, bot, _color, LINE_W)
				t += CHEVRON_STEP
			accumulated += seg_len

