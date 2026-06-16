# Copyright © 2026 Bithead LLC. All rights reserved.
#
# ConveyorBelt — drop-in replacement for Conveyor.
#
# Uses Line2D + a tiled chevron texture + a UV-scrolling shader instead of
# custom-drawn BeltLane nodes.  Because the shader runs on the GPU and derives
# its offset from the built-in TIME uniform, every belt in every frame reads the
# same clock value.  There is no per-node phase accumulation and therefore no
# junction gap artefacts.
#
# Public API is identical to Conveyor so callers only need to change the class
# name.  InsertButton is preserved unchanged.
#
# Requires:
#   res://shaders/conveyor_belt.gdshader  — the UV-scroll shader
#   res://scripts/Palette.gd              — colour constants
class_name ConveyorBelt
extends Node

# ---------------------------------------------------------------------------
# Constants (same values as Conveyor so callers that reference them still work)
# ---------------------------------------------------------------------------

const BELT_COLOR  := Palette.BLUE_BELT
const BELT_HALF_W := 6.0
const BORDER_W    := 1.5
const STUB_LEN    := 12.0

# ---------------------------------------------------------------------------
# Belt drawing — each returns the Line2D added to `parent`
# ---------------------------------------------------------------------------

## Draw a straight animated belt from `from` to `to`.
static func draw_animated(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR, half_w: float = BELT_HALF_W) -> Line2D:
	return _make_belt([from, to], color, half_w, parent)


## Draw an L-shaped routed belt between two points with optional entry/exit
## directions.  Routing matches the Conveyor stub-waypoint algorithm.
static func draw_routed(from: Vector2, to: Vector2, parent: Node2D,
		color: Color = BELT_COLOR,
		from_dir: Vector2 = Vector2.ZERO, to_dir: Vector2 = Vector2.ZERO,
		avoid_rect: Rect2 = Rect2()) -> Line2D:
	if from_dir == Vector2.ZERO:
		var dx := to.x - from.x
		from_dir = Vector2(1.0 if dx >= 0.0 else -1.0, 0.0)
	if to_dir == Vector2.ZERO:
		to_dir = -from_dir
	var waypoints := _build_stub_waypoints(from, from_dir, to, to_dir, STUB_LEN, avoid_rect)
	return _make_belt(waypoints, color, BELT_HALF_W, parent)


## Draw a bidirectional routed belt (two parallel lanes, one each direction).
static func draw_routed_bidirectional(from: Vector2, from_dir: Vector2,
		to: Vector2, to_dir: Vector2, parent: Node2D,
		color: Color = BELT_COLOR, avoid_rect: Rect2 = Rect2()) -> void:
	var center := _build_stub_waypoints(from, from_dir, to, to_dir, STUB_LEN, avoid_rect)
	# Lane A: forward (from → to), offset CCW by BELT_HALF_W.
	var lane_a: Array[Vector2] = _offset_lane(center, BELT_HALF_W)
	_make_belt(lane_a, color, BELT_HALF_W, parent)
	# Lane B: reverse (to → from), offset the other way.
	var center_rev: Array[Vector2] = center.duplicate()
	center_rev.reverse()
	var lane_b: Array[Vector2] = _offset_lane(center_rev, BELT_HALF_W)
	_make_belt(lane_b, color, BELT_HALF_W, parent)


## Draw a plain non-animated belt (static, no shader).
static func draw_static(from: Vector2, to: Vector2, parent: Node2D) -> Line2D:
	var line := Line2D.new()
	line.add_point(from)
	line.add_point(to)
	line.width = BELT_HALF_W * 2.0
	line.default_color = BELT_COLOR
	parent.add_child(line)
	return line


## Draw a short stub in `dir` from `from_pt` (used to show exit direction).
static func draw_stub_terminal(from_pt: Vector2, dir: Vector2, parent: Node2D,
		color: Color = BELT_COLOR) -> void:
	var to_pt := from_pt + dir * (STUB_LEN * 1.5)
	_make_belt([from_pt, to_pt], color, BELT_HALF_W, parent)


# ---------------------------------------------------------------------------
# Path geometry helpers (identical logic to Conveyor)
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
# Internal belt factory
# ---------------------------------------------------------------------------

static func _make_belt(waypoints: Array[Vector2], color: Color,
		half_w: float, parent: Node2D) -> Line2D:
	var line := Line2D.new()
	for pt in waypoints:
		line.add_point(pt)
	line.width = half_w * 2.0
	line.default_color = color

	var tex := _chevron_texture(color)
	line.texture = tex
	line.texture_mode = Line2D.LINE_TEXTURE_TILE

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/conveyor_belt.gdshader")
	line.material = mat

	parent.add_child(line)
	return line


## Generates a 64×12 px Image with repeating ›-chevrons baked in, then wraps it
## in an ImageTexture.  Called once per belt; cheap enough at construction time.
static func _chevron_texture(color: Color, width: int = 64, height: int = 16) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	
	# Background
	var bg := Color(color.r, color.g, color.b, 0.35)
	img.fill(bg)
	
	var fg := Color(color.r, color.g, color.b, 1.0)
	
	var half_h := height / 2
	var arm := int(half_h * 0.9)   # Much longer arms → better looking chevrons
	
	# Draw two chevrons per tile
	for cx in [width / 4, width * 3 / 4]:
		for y in range(height):
			if y <= half_h:
				# Upper arm
				var t := float(y) / float(half_h)
				var x: int = cx - arm + int(t * float(arm))
				_draw_thick_pixel(img, x, y, fg, 2)   # thickness = 2
			else:
				# Lower arm
				var t := float(y - half_h) / float(half_h)
				var x: int = cx - int(t * float(arm))
				_draw_thick_pixel(img, x, y, fg, 2)

	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _draw_thick_pixel(img: Image, x: int, y: int, color: Color, thickness: int = 2):
	for dx in range(-thickness / 2, thickness / 2 + 1):
		for dy in range(-thickness / 2, thickness / 2 + 1):
			var px := x + dx
			var py := y + dy
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, color)


static func _draw_thick(img: Image, x: int, y: int, color: Color) -> void:
	for dx: int in [-1, 0, 1]:
		var px: int = clampi(x + dx, 0, img.get_width() - 1)
		img.set_pixel(px, y, color)


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
