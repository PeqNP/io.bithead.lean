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

const BELT_COLOR     := Color(0.3, 0.8, 0.7, 0.8)
const BELT_WIDTH     := 4.0
## Minimum straight run (px) from each endpoint before the first bend.
const STUB_LEN       := 10.0
## Half-gap between the two lanes of a bidirectional belt (px).
const LANE_HALF_GAP  :=  3.5


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


## Build axis-aligned waypoints with a STUB_LEN straight run at each endpoint before the first bend.
## from_dir / to_dir: unit vectors pointing AWAY from each endpoint.
## avoid_rect: world-space Rect2 the path must route around. Only the vertical-first case is handled.
static func _build_stub_waypoints(from: Vector2, from_dir: Vector2,
		to: Vector2, to_dir: Vector2, stub_len: float,
		avoid_rect: Rect2 = Rect2()) -> Array[Vector2]:
	var p1 := from + from_dir * stub_len   # end of start stub
	var p4 := to   + to_dir   * stub_len   # end of end stub

	var pts: Array[Vector2] = [from, p1]
	if absf(p1.x - p4.x) < 1.0 and absf(p1.y - p4.y) < 1.0:
		pass   # p1 and p4 coincide — no elbow needed
	elif absf(p1.x - p4.x) < 1.0 or absf(p1.y - p4.y) < 1.0:
		pts.append(p4)   # stubs are already axis-aligned — no elbow
	else:
		# One elbow (or box-avoidance detour). Axis order determined by from_dir.
		var detour := _detour_around_rect(p1, from_dir, p4, avoid_rect, stub_len)
		if not detour.is_empty():
			pts.append_array(detour)
		elif absf(from_dir.x) > 0.5:
			pts.append(Vector2(p4.x, p1.y))   # horizontal-first
		else:
			pts.append(Vector2(p1.x, p4.y))   # vertical-first
		pts.append(p4)
	pts.append(to)
	return pts


## Returns detour waypoints to route around avoid_rect for a vertical-exit / horizontal-entry path.
## Handles the case where the horizontal segment p1→p4 would pass through avoid_rect.
## Returns [] when no detour is needed (or the case isn't handled).
static func _detour_around_rect(p1: Vector2, from_dir: Vector2,
		p4: Vector2, avoid_rect: Rect2, stub_len: float) -> Array[Vector2]:
	# Only handle vertical exit (from_dir is ±Y) entering horizontally (to_dir is ±X).
	if absf(from_dir.x) > 0.5 or not avoid_rect.has_area():
		return []

	# The horizontal segment of the standard L-shape runs at y=p4.y from x=p1.x to x=p4.x.
	# Check if it intersects avoid_rect.
	var seg_y    := p4.y
	var seg_x_lo := minf(p1.x, p4.x)
	var seg_x_hi := maxf(p1.x, p4.x)
	var box_top  := avoid_rect.position.y
	var box_bot  := avoid_rect.end.y
	var box_left := avoid_rect.position.x
	var box_right := avoid_rect.end.x

	var crosses := seg_y > box_top and seg_y < box_bot \
		and seg_x_hi > box_left and seg_x_lo < box_right

	if not crosses:
		return []

	# Route around the box.  The bypass Y is outside the box on the side closest to p1.
	var bypass_y: float
	if p1.y <= box_top:
		bypass_y = box_top - stub_len   # approach from above
	else:
		bypass_y = box_bot + stub_len   # approach from below

	# bypass_x == p4.x when to is at the box's left edge (the normal case).
	var bypass_x := box_left - stub_len

	return [
		Vector2(p1.x,    bypass_y),
		Vector2(bypass_x, bypass_y),
	]


## Offset a polyline laterally by dist (perpendicular CCW to travel direction).
## Interior vertices use the bisector of adjacent segment normals.
static func _offset_lane(pts: Array[Vector2], dist: float) -> Array[Vector2]:
	if pts.size() < 2:
		return pts
	var result: Array[Vector2] = []
	for i in pts.size():
		var perp: Vector2
		if i == 0:
			var dir := (pts[1] - pts[0]).normalized()
			perp = Vector2(-dir.y, dir.x)
		elif i == pts.size() - 1:
			var dir := (pts[i] - pts[i - 1]).normalized()
			perp = Vector2(-dir.y, dir.x)
		else:
			var d0 := (pts[i]     - pts[i - 1]).normalized()
			var d1 := (pts[i + 1] - pts[i]).normalized()
			var n0 := Vector2(-d0.y, d0.x)
			var n1 := Vector2(-d1.y, d1.x)
			var avg := n0 + n1
			perp = avg.normalized() if avg.length_squared() > 0.001 else n0
		result.append(pts[i] + perp * dist)
	return result


## Draw an L-shaped routed belt with a STUB_LEN straight run at each endpoint before the first bend.
## from_dir / to_dir: unit vectors pointing AWAY from each endpoint.
## If zero, direction is inferred as horizontal toward the other endpoint.
static func draw_routed(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR,
		from_dir: Vector2 = Vector2.ZERO, to_dir: Vector2 = Vector2.ZERO,
		avoid_rect: Rect2 = Rect2()) -> Node2D:
	if from_dir == Vector2.ZERO:
		var dx := to.x - from.x
		from_dir = Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)
	if to_dir == Vector2.ZERO:
		to_dir = -from_dir
	var waypoints := _build_stub_waypoints(from, from_dir, to, to_dir, STUB_LEN, avoid_rect)
	var belt := ChevronBelt.new()
	belt.setup(waypoints, color)
	parent.add_child(belt)
	return belt


## Draw two side-by-side parallel lanes (two-lane road), chevrons in opposite directions.
## from_dir / to_dir: unit vectors pointing AWAY from each endpoint.
## Lane A: chevrons from → to. Lane B: chevrons to → from.
## Both lanes use STUB_LEN straight runs before each bend.
static func draw_routed_bidirectional(from: Vector2, from_dir: Vector2,
		to: Vector2, to_dir: Vector2, parent: Node2D,
		color: Color = BELT_COLOR, avoid_rect: Rect2 = Rect2()) -> void:
	var center := _build_stub_waypoints(from, from_dir, to, to_dir, STUB_LEN, avoid_rect)

	# Lane A: forward (from → to), offset +LANE_HALF_GAP to the left of travel.
	var belt_fwd := ChevronBelt.new()
	belt_fwd.setup(_offset_lane(center, LANE_HALF_GAP), color)
	parent.add_child(belt_fwd)

	# Lane B: reverse (to → from), same offset applied to the reversed path.
	var center_rev: Array[Vector2] = center.duplicate()
	center_rev.reverse()
	var belt_rev := ChevronBelt.new()
	belt_rev.setup(_offset_lane(center_rev, LANE_HALF_GAP), color)
	parent.add_child(belt_rev)


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

