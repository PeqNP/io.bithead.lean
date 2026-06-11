## Copyright © 2026 Bithead LLC. All rights reserved.

## WebBOSSDelegate — production BOSS ↔ Godot bridge via JavaScriptBridge.
##
## All JavaScriptBridge and JavaScriptObject usage is confined to this file.
## FactoryFloor.gd passes and receives plain GDScript types only.

class_name WebBOSSDelegate extends BOSSDelegate

var _js_delegate: JavaScriptObject
var _js_send_callback: JavaScriptObject
var _on_command: Callable


## Wire window.boss and signal readiness to BOSS.
func ready(on_command: Callable) -> void:
	_on_command = on_command
	var window := JavaScriptBridge.get_interface("window")
	if not (window and window.boss):
		push_warning("WebBOSSDelegate: window.boss not available")
		return
	_js_delegate = window.boss
	_js_send_callback = JavaScriptBridge.create_callback(_on_js_send)
	_js_delegate.send = _js_send_callback
	_js_delegate.ready()


## Send an event from Godot to BOSS. Converts GDScript types to JavaScriptObjects.
##
## Array values in `data` are converted to JS Arrays (keys are string indices per
## the JavaScriptBridge limitation). All other values are set directly.
func receive(event_name: String, data: Dictionary) -> void:
	if not _js_delegate:
		push_warning("WebBOSSDelegate.receive: bridge not connected")
		return
	var data_obj: JavaScriptObject = JavaScriptBridge.create_object("Object")
	for key in data:
		var value = data[key]
		if value is Array:
			var arr: JavaScriptObject = JavaScriptBridge.create_object("Array")
			for i in value.size():
				arr[str(i)] = value[i]
			data_obj[str(key)] = arr
		else:
			data_obj[str(key)] = value
	var ev: JavaScriptObject = JavaScriptBridge.create_object("Object")
	ev["name"] = event_name
	ev["data"] = data_obj
	_js_delegate.receive(ev)


## Called by BOSS JS via the registered send callback.
## Converts the JavaScriptObject command into GDScript types and calls _on_command.
func _on_js_send(args: Array) -> void:
	if args.is_empty():
		return
	var cmd: JavaScriptObject = args[0]
	var c_name: String = str(cmd["name"])
	var js_data: JavaScriptObject = cmd["data"]
	var data := _convert_command_data(c_name, js_data)
	_on_command.call(c_name, data)


## Convert the JS data object for a known command into a plain GDScript Dictionary.
## JS values arrive as strings; this function casts them to their intended types.
func _convert_command_data(c_name: String, js_data: JavaScriptObject) -> Dictionary:
	match c_name:
		"configure":
			return {
				"factoryId": int(str(js_data["factoryId"])),
				"baseUrl":   str(js_data["baseUrl"]),
			}
	push_warning("WebBOSSDelegate: unknown command '%s' — data not converted" % c_name)
	return {}
