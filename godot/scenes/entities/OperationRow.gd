## Copyright © 2026 Bithead LLC. All rights reserved.

## Single row inside a StationOverlay operations list.

class_name OperationRow extends Label


func configure(key: String, c_name: String) -> void:
	text = "%s  %s" % [key, c_name] if not key.is_empty() else c_name
	custom_minimum_size = Vector2(0, 24)
	size_flags_horizontal = 3
	add_theme_color_override("font_color", Palette.FG_1)
	add_theme_font_size_override("font_size", 10)
