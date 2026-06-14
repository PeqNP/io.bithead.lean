## Copyright © 2026 Bithead LLC. All rights reserved.

## Renders per-operation progress segments as colored rects.
## Width is determined by the parent VBoxContainer (EXPAND_FILL).

class_name OperationBars extends Control

const BAR_H := 4.0
const GAP   := 2.0

var _total: int = 0
var _done:  int = 0


func configure(total: int, done: int) -> void:
	_total = total
	_done  = done
	queue_redraw()


func _draw() -> void:
	if _total <= 0:
		return
	var w := size.x
	var seg_w := (w - GAP * (_total - 1)) / float(_total)
	for i in _total:
		var x := i * (seg_w + GAP)
		draw_rect(Rect2(x, 0, seg_w, BAR_H), Palette.GREEN if i < _done else Palette.FG_0)
