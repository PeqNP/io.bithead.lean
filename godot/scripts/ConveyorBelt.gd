# Copyright © 2026 Bithead LLC. All rights reserved.
#
# ConveyorBelt — draws animated conveyor belts using a Node2D that manually
# stamps oriented chevrons along the path every frame via _draw().  No shader
# required.
#
# Each _BeltDrawer reads Time.get_ticks_msec() for its scroll phase, so every
# belt in the scene shares the same clock and junctions are seamless.
#
# Public API matches the original Conveyor so callers only need to change the
# class name.  InsertButton is preserved unchanged.
#
# Requires:
#   res://scripts/Palette.gd  — colour constants
class_name ConveyorBelt
extends Node

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BELT_COLOR  := Palette.BLUE_BELT
const BELT_HALF_W := 6.0
const BORDER_W    := 1.5
const STUB_LEN    := 12.0

# ---------------------------------------------------------------------------
# Belt drawing
# ---------------------------------------------------------------------------

## Draw a straight animated belt from `from` to `to`.
static func draw_animated(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR, half_w: float = BELT_HALF_W) -> Node2D:
	return _make_belt([from, to], color, half_w, parent, true)


## Draw an L-shaped routed belt between two points with optional entry/exit
## directions.  Routing matches the Conveyor stub-waypoint algorithm.
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
	return _make_belt(waypoints, color, BELT_HALF_W, parent, true)


## Draw a bidirectional routed belt (two parallel lanes, one each direction).
static func draw_routed_bidirectional(from: Vector2, from_dir: Vector2,
		to: Vector2, to_dir: Vector2, parent: Node2D,
		color: Color = BELT_COLOR, avoid_rect: Rect2 = Rect2()) -> void:
	var center := _build_stub_waypoints(from, from_dir, to, to_dir, STUB_LEN, avoid_rect)
	var lane_a: Array[Vector2] = _offset_lane(center, BELT_HALF_W)
	_make_belt(lane_a, color, BELT_HALF_W, parent, true)
	var center_rev: Array[Vector2] = center.duplicate()
	center_rev.reverse()
	var lane_b: Array[Vector2] = _offset_lane(center_rev, BELT_HALF_W)
	_make_belt(lane_b, color, BELT_HALF_W, parent, true)


## Draw a plain non-animated belt (no chevrons).
static func draw_static(from: Vector2, to: Vector2, parent: Node2D) -> Node2D:
	return _make_belt([from, to], BELT_COLOR, BELT_HALF_W, parent, false)


## Draw a short stub in `dir` from `from_pt` (used to show exit direction).
static func draw_stub_terminal(from_pt: Vector2, dir: Vector2, parent: Node2D,
		color: Color = BELT_COLOR) -> void:
	var to_pt := from_pt + dir * (STUB_LEN * 1.5)
	_make_belt([from_pt, to_pt], color, BELT_HALF_W, parent, true)


# ---------------------------------------------------------------------------
# Path geometry helpers
# ---------------------------------------------------------------------------

## Returns the world-space midpoint of a multi-segment path by arc length.
static func path_midpoint(waypoints: Array[Vector2]) -> Vector2:
	if waypoints.size() <= 1:
		return waypoints[0] if waypoints.size() == 1 else Vector2.ZERO
	var total: float = 0.0
	for i in range(waypoints.size() - 1):
		total += waypoints[i].distance_to(waypoints[i + 1])
	var half: float = total * 0.5
	var acc: float = 0.0
	for i in range(waypoints.size() - 1):
		var seg_len: float = waypoints[i].distance_to(waypoints[i + 1])
		if acc + seg_len >= half:
			var t: float = (half - acc) / seg_len
			return waypoints[i].lerp(waypoints[i + 1], t)
		acc += seg_len
	return waypoints.back()


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
		Vector2(p1.x,     bypass_y),
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
				var bisector := avg.normalized()
				var dot_val  := bisector.dot(n0)
				var miter_len := dist / maxf(absf(dot_val), 0.25)
				result.append(pts[i] + bisector * miter_len)
			else:
				result.append(pts[i] + n0 * dist)
			continue
		result.append(pts[i] + perp * dist)
	return result


# ---------------------------------------------------------------------------
# Internal factory
# ---------------------------------------------------------------------------

static func _make_belt(waypoints: Array[Vector2], color: Color,
		half_w: float, parent: Node2D, animated: bool) -> Node2D:
	var drawer := _BeltDrawer.new()
	drawer.setup(waypoints, color, half_w, animated)
	parent.add_child(drawer)
	return drawer


# ---------------------------------------------------------------------------
# _BeltDrawer — Node2D that draws belt fill, chevrons, and rails each frame
# ---------------------------------------------------------------------------

class _BeltDrawer extends Node2D:
	const CHEVRON_SPACING := 18.0   # pixels between chevron centres along path
	const CHEVRON_SPEED   := 40.0   # pixels per second (shared global clock)

	var _waypoints : PackedVector2Array
	var _color     : Color
	var _half_w    : float
	var _animated  : bool

	func setup(waypoints: Array[Vector2], color: Color,
			half_w: float, animated: bool) -> void:
		_waypoints = PackedVector2Array(waypoints)
		_color     = color
		_half_w    = half_w
		_animated  = animated

	func _process(_delta: float) -> void:
		if _animated:
			queue_redraw()

	func _draw() -> void:
		if _waypoints.size() < 2:
			return
		_draw_fill()
		if _animated:
			_draw_chevrons()
		_draw_rails()

	# -------------------------------------------------------------------------
	# Belt fill — single miter-joined polygon covering the whole path
	# -------------------------------------------------------------------------

	func _draw_fill() -> void:
		var fill := Color(_color.r, _color.g, _color.b, 0.45)
		var left  := _offset_polyline(_half_w)
		var right := _offset_polyline(-_half_w)
		# Polygon: left edge forward, right edge backward.
		var poly := PackedVector2Array()
		for p: Vector2 in left:
			poly.append(p)
		for i in range(right.size() - 1, -1, -1):
			poly.append(right[i])
		draw_colored_polygon(poly, fill)

	# -------------------------------------------------------------------------
	# Chevrons — ">" stamps, oriented along path, driven by global clock
	# -------------------------------------------------------------------------

	func _draw_chevrons() -> void:
		var total_len := _path_length()
		if total_len < 0.001:
			return
		# Global clock: all belts share the same phase so junctions are seamless.
		var t_sec := Time.get_ticks_msec() * 0.001
		var phase := fmod(t_sec * CHEVRON_SPEED, CHEVRON_SPACING)
		var fg := Color(
			minf(_color.r * 1.8, 1.0),
			minf(_color.g * 1.8, 1.0),
			minf(_color.b * 1.8, 1.0),
			0.95)
		var tip_x  :=  _half_w * 0.35
		var back_x := -_half_w * 0.35
		var arm_y  :=  _half_w * 0.75
		var dist   := phase
		while dist < total_len:
			var info  := _point_at_dist(dist)
			var pos   : Vector2 = info[0]
			var angle : float   = info[1]
			draw_set_transform(pos, angle, Vector2.ONE)
			draw_line(Vector2(back_x, -arm_y), Vector2(tip_x, 0.0), fg, 2.0, true)
			draw_line(Vector2(back_x,  arm_y), Vector2(tip_x, 0.0), fg, 2.0, true)
			dist += CHEVRON_SPACING
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# -------------------------------------------------------------------------
	# Side rails — miter-joined polylines along both edges
	# -------------------------------------------------------------------------

	func _draw_rails() -> void:
		var rail := Color(
			minf(_color.r * 1.3, 1.0),
			minf(_color.g * 1.3, 1.0),
			minf(_color.b * 1.3, 1.0),
			1.0)
		draw_polyline(_offset_polyline(_half_w),  rail, 1.5, true)
		draw_polyline(_offset_polyline(-_half_w), rail, 1.5, true)

	# -------------------------------------------------------------------------
	# Path helpers
	# -------------------------------------------------------------------------

	# Returns a PackedVector2Array offset from _waypoints by `dist` pixels,
	# with miter joins at interior corners so edges are contiguous.
	func _offset_polyline(dist: float) -> PackedVector2Array:
		var pts := _waypoints
		var result := PackedVector2Array()
		for i in pts.size():
			if i == 0:
				var d := (pts[1] - pts[0]).normalized()
				result.append(pts[0] + Vector2(-d.y, d.x) * dist)
			elif i == pts.size() - 1:
				var d := (pts[i] - pts[i - 1]).normalized()
				result.append(pts[i] + Vector2(-d.y, d.x) * dist)
			else:
				var d0 := (pts[i]     - pts[i - 1]).normalized()
				var d1 := (pts[i + 1] - pts[i]).normalized()
				var n0 := Vector2(-d0.y, d0.x)
				var n1 := Vector2(-d1.y, d1.x)
				var avg := n0 + n1
				if avg.length_squared() > 0.001:
					var bisector  := avg.normalized()
					var miter_len := dist / maxf(absf(bisector.dot(n0)), 0.25)
					result.append(pts[i] + bisector * miter_len)
				else:
					result.append(pts[i] + n0 * dist)
		return result

	func _path_length() -> float:
		var total := 0.0
		for i in range(_waypoints.size() - 1):
			total += _waypoints[i].distance_to(_waypoints[i + 1])
		return total

	# Returns [pos: Vector2, angle: float] at `dist` pixels along the path.
	func _point_at_dist(dist: float) -> Array:
		var acc := 0.0
		for i in range(_waypoints.size() - 1):
			var a       : Vector2 = _waypoints[i]
			var b       : Vector2 = _waypoints[i + 1]
			var seg_len := a.distance_to(b)
			if acc + seg_len >= dist:
				var t   := (dist - acc) / seg_len
				var pos := a.lerp(b, t)
				return [pos, (b - a).angle()]
			acc += seg_len
		var last : Vector2 = _waypoints[_waypoints.size() - 1]
		var prev : Vector2 = _waypoints[_waypoints.size() - 2]
		return [last, (last - prev).angle()]


# ---------------------------------------------------------------------------
# InsertButton — 16×16 custom Control for + insert buttons on belts.
# ---------------------------------------------------------------------------

class InsertButton extends Control:
	const SIZE := 16.0
	const FONT_SIZE := 12
	const BORDER_W_BTN := 1.0

	var _color: Color = Palette.BLUE_BELT
	var _disabled: bool = false
	signal pressed

	func setup(color: Color, disabled: bool, tooltip: String) -> void:
		_color = color
		_disabled = disabled
		custom_minimum_size = Vector2(SIZE, SIZE)
		size = Vector2(SIZE, SIZE)
		mouse_filter = MOUSE_FILTER_STOP
		tooltip_text = tooltip
		queue_redraw()

	func _draw() -> void:
		var alpha: float = 0.4 if _disabled else 1.0
		var fill := Color(_color.r, _color.g, _color.b, alpha)
		var border_color := Color(
			minf(_color.r * 1.4, 1.0),
			minf(_color.g * 1.4, 1.0),
			minf(_color.b * 1.4, 1.0),
			alpha)
		draw_rect(Rect2(0.0, 0.0, SIZE, SIZE), fill)
		draw_rect(Rect2(0.0, 0.0, SIZE, SIZE), border_color, false, BORDER_W_BTN)
		var font := ThemeDB.fallback_font
		var lbl := "+"
		var fs := FONT_SIZE
		var tw := font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var th := font.get_height(fs)
		var tx := (SIZE - tw) * 0.5
		var ty := (SIZE + th) * 0.5 - font.get_descent(fs)
		draw_string(font, Vector2(tx, ty), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 1.0, alpha))

	func _gui_input(event: InputEvent) -> void:
		if _disabled:
			return
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			pressed.emit()
			accept_event()
