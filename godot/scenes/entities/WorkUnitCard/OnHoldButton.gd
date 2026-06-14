## Copyright © 2026 Bithead LLC. All rights reserved.

## Floats top-right of a WorkUnitCard when the work unit is on hold.
## Pressing it makes an HTTP call to clear the hold.

class_name OnHoldButton extends Button

var _wu_id: int = 0


func _ready() -> void:
	pressed.connect(_on_pressed)
	Palette.style_button(self, Palette.RED)
	add_theme_font_size_override("font_size", 8)


func configure(wu_id: int) -> void:
	_wu_id = wu_id


func _on_pressed() -> void:
	disabled = true
	await BOSSBridge.post("/lean/work-unit/hold/%d" % _wu_id, {})
	BOSSBridge.poll_snapshot()
	disabled = false
