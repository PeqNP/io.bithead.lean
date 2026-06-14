## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders up to 3 assignee avatar circles with initials.
## Sized by the parent VBoxContainer via custom_minimum_size.

class_name Assignees extends Control

const AVATAR_R  := 7.0
const AVATAR_GAP := 3.0
const FONT_SIZE := 7

var _assignees: Array = []


func configure(assignees: Array) -> void:
	_assignees = assignees
	queue_redraw()


func _draw() -> void:
	var ax := 0.0
	for a in _assignees.slice(0, 3):
		draw_circle(Vector2(ax + AVATAR_R, AVATAR_R), AVATAR_R, Palette.BLUE)
		var initials := _make_initials(str(a.get("name", "?")))
		draw_string(ThemeDB.fallback_font, Vector2(ax + 2, AVATAR_R + 3), initials,
			HORIZONTAL_ALIGNMENT_LEFT, AVATAR_R * 2.0, FONT_SIZE, Color.WHITE)
		ax += AVATAR_R * 2.0 + AVATAR_GAP


func _make_initials(full_name: String) -> String:
	var parts := full_name.split(" ")
	if parts.size() >= 2:
		return (parts[0].substr(0, 1) + parts[1].substr(0, 1)).to_upper()
	return full_name.substr(0, 2).to_upper()
