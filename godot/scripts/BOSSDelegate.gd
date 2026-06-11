## Copyright © 2026 Bithead LLC. All rights reserved.

## BOSSDelegate — protocol (base class) for BOSS ↔ Godot communication.
##
## Two implementations exist:
##   WebBOSSDelegate  — production; uses JavaScriptBridge to talk to the BOSS JS layer.
##   DummyBOSSDelegate — local/editor testing; no browser required.
##
## FactoryFloor.gd holds a `_boss: BOSSDelegate` and calls only these two methods.
## No JavaScriptBridge or JavaScriptObject types appear anywhere outside WebBOSSDelegate.

class_name BOSSDelegate


## Initialize the delegate.
##
## `on_command` will be called by the delegate whenever BOSS sends a command into
## Godot. Signature: func(name: String, data: Dictionary) -> void
##
## Implementations must call `on_command` exactly as described:
##   name — the command identifier (e.g. "configure")
##   data — plain GDScript Dictionary with typed values (ints are ints, not strings)
func ready(on_command: Callable) -> void:
	pass


## Send an event from Godot to BOSS.
##
## `event_name` — e.g. "open-window"
## `data`       — plain GDScript Dictionary; Arrays and scalar values only.
##                Nested Dictionaries are not supported.
func receive(event_name: String, data: Dictionary) -> void:
	pass
