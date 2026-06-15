## Copyright © 2026 Bithead LLC. All rights reserved.

## Draws conveyor belts between two local-space points.
## Belts are rendered with side rails, a filled surface, and animated chevrons.
##
## Usage:
##   Conveyor.draw_static(from, to, parent)
##   Conveyor.draw_animated(from, to, parent, color)            # straight, animated
##   Conveyor.draw_routed(from, to, parent, color, ...)         # L-shaped, single direction
##   Conveyor.draw_routed_bidirectional(from, dir, to, dir, …)  # L-shaped, two lanes

class_name Conveyor

const BELT_COLOR  := Palette.BLUE_BELT
## Half-width of one belt lane in pixels (total lane width = 2 × BELT_HALF_W).
const BELT_HALF_W := 6.0
## Side-rail line width in pixels.
const BORDER_W    := 1.5
## Minimum straight run at each endpoint before the first bend.
const STUB_LEN    := 12.0


## Draw a plain static (non-animated) belt. Returns the Line2D.
static func draw_static(from: Vector2, to: Vector2, parent: Node2D) -> Line2D:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = BELT_HALF_W * 2.0
	line.default_color = BELT_COLOR
	parent.add_child(line)
	return line


## Draw an animated single-lane belt between two points. Returns the BeltLane node.
static func draw_animated(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR, half_w: float = BELT_HALF_W) -> Node2D:
	var belt := BeltLane.new()
	belt.setup([from, to], color, half_w, true, true)
	parent.add_child(belt)
	return belt


## Draw an L-shaped routed single-direction belt with side rails on both sides.
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
	var belt := BeltLane.new()
	belt.setup(waypoints, color, BELT_HALF_W, true, true)
	parent.add_child(belt)
	return belt


## Draw a short belt stub from 'from_pt' in 'dir' with a filled arrowhead cap.
## Used to show the exit direction of the last station in a chain.
static func draw_stub_terminal(from_pt: Vector2, dir: Vector2, parent: Node2D,
		color: Color = BELT_COLOR) -> void:
	var stub_len := STUB_LEN * 1.5
	var to_pt := from_pt + dir * stub_len

	var belt := BeltLane.new()
	belt.setup([from_pt, to_pt], color, BELT_HALF_W, true, true)
	parent.add_child(belt)

	# Filled arrowhead triangle just beyond the stub end.
	var perp := Vector2(-dir.y, dir.x)
	var tip  := to_pt + dir * BELT_HALF_W
	var bl   := to_pt + perp * BELT_HALF_W
	var br   := to_pt - perp * BELT_HALF_W
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([tip, bl, br])
	arrow.color = color
	parent.add_child(arrow)


## Draw two parallel bidirectional lanes sharing a center rail.
## Lane A carries chevrons from → to. Lane B carries chevrons to → from.
## The two outer rails are drawn by each lane; the shared center rail is drawn once.
static func draw_routed_bidirectional(from: Vector2, from_dir: Vector2,
		to: Vector2, to_dir: Vector2, parent: Node2D,
		color: Color = BELT_COLOR, avoid_rect: Rect2 = Rect2()) -> void:
	var center := _build_stub_waypoints(from, from_dir, to, to_dir, STUB_LEN, avoid_rect)

	# Lane A: forward (from → to). Offset CCW by BELT_HALF_W.
	# Draws outer rail (left of travel) only — inner rail is shared with Lane B.
	var lane_a_pts := _offset_lane(center, BELT_HALF_W)
	var belt_a := BeltLane.new()
	belt_a.setup(lane_a_pts, color, BELT_HALF_W, true, false)
	parent.add_child(belt_a)

	# Lane B: reverse (to → from). In the reversed direction CCW lands on the
	# opposite side of the original path, giving the other outer rail.
	var center_rev: Array[Vector2] = center.duplicate()
	center_rev.reverse()
	var lane_b_pts := _offset_lane(center_rev, BELT_HALF_W)
	var belt_b := BeltLane.new()
	belt_b.setup(lane_b_pts, color, BELT_HALF_W, true, false)
	parent.add_child(belt_b)

	# Shared center rail — drawn once along the original centerline.
	var rail := Line2D.new()
	rail.width = BORDER_W
	rail.default_color = color
	for pt in center:
		rail.add_point(pt)
	parent.add_child(rail)


# ---------------------------------------------------------------------------
# Waypoint helpers (unchanged from original)
# ---------------------------------------------------------------------------

static func _build_stub_waypoints(from: Vector2, from_dir: Vector2,
		to: Vector2, to_dir: Vector2, stub_len: float,
		avoid_rect: Rect2 = Rect2()) -> Array[Vector2]:
	var p1 := from + from_dir * stub_len
	var p4 := to   + to_dir   * stub_len

	var pts: Array[Vector2] = [from, p1]
	if absf(p1.x - p4.x) < 1.0 and absf(p1.y - p4.y) < 1.0:
		pass
	elif absf(p1.x - p4.x) < 1.0 or absf(p1.y - p4.y) < 1.0:
		pts.append(p4)
	else:
		var detour := _detour_around_rect(p1, from_dir, p4, avoid_rect, stub_len)
		if not detour.is_empty():
			pts.append_array(detour)
		elif absf(from_dir.x) > 0.5:
			pts.append(Vector2(p4.x, p1.y))
		else:
			pts.append(Vector2(p1.x, p4.y))
		pts.append(p4)
	pts.append(to)
	return pts


static func _detour_around_rect(p1: Vector2, from_dir: Vector2,
		p4: Vector2, avoid_rect: Rect2, stub_len: float) -> Array[Vector2]:
	if absf(from_dir.x) > 0.5 or not avoid_rect.has_area():
		return []

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

	var bypass_y: float
	if p1.y <= box_top:
		bypass_y = box_top - stub_len
	else:
		bypass_y = box_bot + stub_len

	var bypass_x := box_left - stub_len
	return [
		Vector2(p1.x,    bypass_y),
		Vector2(bypass_x, bypass_y),
	]


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
			if avg.length_squared() > 0.001:
				var bisector  := avg.normalized()
				var dot_val   := bisector.dot(n0)
				# True miter length keeps perpendicular distance exactly |dist|
				# from both adjacent segments. Cap at 4× to avoid spikes on
				# very acute angles.
				var miter_len := dist / maxf(absf(dot_val), 0.25)
				result.append(pts[i] + bisector * miter_len)
			else:
				result.append(pts[i] + n0 * dist)
			continue
		result.append(pts[i] + perp * dist)
	return result


# ---------------------------------------------------------------------------
# BeltLane — animated belt lane with fill, rails, and chevrons.
# ---------------------------------------------------------------------------

class BeltLane extends Node2D:
	const ANIM_SPEED     := 40.0   # px/s
	const CHEVRON_STEP   := 16.0   # px between chevron origins along the path
	const CHEVRON_SIZE   :=  4.5   # half-span of the > shape (must be < _half_w)
	const CHEVRON_LINE_W :=  1.5

	var _waypoints: Array[Vector2] = []
	var _color: Color = Palette.BLUE_BELT
	var _half_w: float = 6.0
	var _draw_left_border: bool = true
	var _draw_right_border: bool = true
	var _offset: float = 0.0


	func setup(waypoints: Array[Vector2], color: Color,
			half_w: float = 6.0,
			draw_left: bool = true, draw_right: bool = true) -> void:
		_waypoints = waypoints
		_color = color
		_half_w = half_w
		_draw_left_border = draw_left
		_draw_right_border = draw_right


	func _process(delta: float) -> void:
		_offset = fmod(_offset + ANIM_SPEED * delta, CHEVRON_STEP)
		if _is_in_viewport():
			queue_redraw()


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
		var gmin := to_global(_waypoints[0])
		var gmax := gmin
		for pt in _waypoints:
			var gpt := to_global(pt)
			gmin = gmin.min(gpt)
			gmax = gmax.max(gpt)
		var pad := _half_w + 2.0
		var belt_rect := Rect2(gmin - Vector2(pad, pad), gmax - gmin + Vector2(pad * 2.0, pad * 2.0))
		return world_rect.intersects(belt_rect)


	func _draw() -> void:
		if _waypoints.size() < 2:
			return

		# Offset polylines for the two rails.
		var left_pts  := Conveyor._offset_lane(_waypoints,  _half_w)
		var right_pts := Conveyor._offset_lane(_waypoints, -_half_w)

		# --- Fill polygon (left rail path + reversed right rail path) ---
		var fill_poly := PackedVector2Array()
		for pt in left_pts:
			fill_poly.append(pt)
		for i in range(right_pts.size() - 1, -1, -1):
			fill_poly.append(right_pts[i])
		var fill_color := Color(_color.r, _color.g, _color.b, _color.a * 0.35)
		draw_colored_polygon(fill_poly, fill_color)

		# --- Side rails ---
		if _draw_left_border:
			draw_polyline(PackedVector2Array(left_pts), _color, Conveyor.BORDER_W)
		if _draw_right_border:
			draw_polyline(PackedVector2Array(right_pts), _color, Conveyor.BORDER_W)

		# --- Animated chevrons (>-shapes along the centerline) ---
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

			var t := fmod(accumulated + _offset, CHEVRON_STEP)
			while t < seg_len:
				var origin := seg_from + dir * t
				var tip    := origin + dir * CHEVRON_SIZE
				var top    := origin + perp * CHEVRON_SIZE
				var bot    := origin - perp * CHEVRON_SIZE
				draw_line(top, tip, _color, CHEVRON_LINE_W)
				draw_line(tip, bot, _color, CHEVRON_LINE_W)
				t += CHEVRON_STEP
			accumulated += seg_len
