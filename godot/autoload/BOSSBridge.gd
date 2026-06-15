## Copyright © 2026 Bithead LLC. All rights reserved.

## Singleton: HTTP communication with BOSS server + snapshot polling.
##
## Access via the BOSSBridge autoload node. All HTTP calls are async.
##
## Snapshot is fetched:
##   - Once on configure() (triggered by BOSS web client)
##   - Explicitly after in-Godot mutations (station add, work unit move, etc.)
##   - Never on a timer.
##
## Signals:
##   snapshot_updated(snapshot) - Emitted when a fresh FactoryFloor snapshot arrives.
##   error(message)             - Emitted on any HTTP error; FactoryFloor shows ErrorModal.
##
## Usage:
##   await BOSSBridge.sign_in()                        # debug only — sets _access_token
##   BOSSBridge.configure(factory_id, base_url)
##   await BOSSBridge.post("/lean/line", body)
##   await BOSSBridge.patch("/lean/line/1/locked", body)

extends Node

signal snapshot_updated(snapshot: Dictionary)
signal error(message: String)

var _factory_id: int = -1
var _base_url: String = ""
var _access_token: String = ""   # set by sign_in(); injected as Cookie header

## Backend delegate — handles all HTTP (or in-memory equivalent).
## Assign before calling configure(). WebBOSSBridgeBackend for production;
## LocalBOSSBridgeBackend for offline testing.
var _backend: BOSSBridgeBackend = null

## Read-only access to the current factory id.
var factory_id: int:
	get: return _factory_id


## Assign the backend delegate. Adds it as a child so it can use add_child().
## Call this before configure() — typically in FactoryFloor._ready().
func set_backend(backend: BOSSBridgeBackend) -> void:
	if _backend != null:
		_backend.queue_free()
	_backend = backend
	add_child(_backend)


## Store factory_id and base_url, then immediately fetch first snapshot.
func configure(factory_id: int, base_url: String) -> void:
	_factory_id = factory_id
	_base_url = base_url
	poll_snapshot()


## Fetch a fresh FactoryFloor snapshot from BOSS.
## Emits snapshot_updated on success, error on failure.
func poll_snapshot() -> void:
	if _factory_id < 0:
		push_warning("BOSSBridge.poll_snapshot called before configure()")
		return
	var response = await _request("GET", "/lean/factory-floor/%d" % _factory_id, {})
	if response.is_empty():
		return
	snapshot_updated.emit(response)


## Open a BOSS window with the given controller and parameters array.
## Callable from any script (no _boss reference needed).
func open_window(controller: String, parameters: Array) -> void:
	if not Engine.has_singleton("JavaScriptBridge"):
		print("BOSSBridge.open_window [editor]: controller=%s params=%s" % [controller, JSON.stringify(parameters)])
		return
	var window := JavaScriptBridge.get_interface("window")
	if not (window and window.boss):
		push_warning("BOSSBridge.open_window: window.boss not available")
		return
	var data_obj: JavaScriptObject = JavaScriptBridge.create_object("Object")
	data_obj["controller"] = controller
	var arr: JavaScriptObject = JavaScriptBridge.create_object("Array")
	for i in parameters.size():
		arr[str(i)] = parameters[i]
	data_obj["parameters"] = arr
	var ev: JavaScriptObject = JavaScriptBridge.create_object("Object")
	ev["name"] = "open-window"
	ev["data"] = data_obj
	window.boss.receive(ev)


## POST to a BOSS route. Returns the parsed response Dictionary, or empty on error.
func post(path: String, body: Dictionary) -> Dictionary:
	return await _request("POST", path, body)


## PATCH a BOSS route. Returns the parsed response Dictionary, or empty on error.
func patch(path: String, body: Dictionary) -> Dictionary:
	return await _request("PATCH", path, body)


## Sign in as the super user via the debug route.
## Stores the returned accessToken for use on all subsequent requests.
## Only call this from DummyBOSSDelegate when running outside the browser.
func sign_in() -> void:
	if _base_url.is_empty():
		push_warning("BOSSBridge.sign_in called before base_url is set")
		return
	var url := _base_url + "/debug/sign-in"
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if err != OK:
		push_error("BOSSBridge.sign_in: request failed (err %d)" % err)
		http.queue_free()
		return
	var result: Array = await http.request_completed
	http.queue_free()
	var http_code: int = result[1]
	if http_code < 200 or http_code >= 300:
		push_error("BOSSBridge.sign_in: server returned %d" % http_code)
		return
	# Parse Set-Cookie header for the accessToken value.
	var resp_headers: PackedStringArray = result[2]
	for header in resp_headers:
		var h: String = header
		if h.to_lower().begins_with("set-cookie:"):
			var cookie_str := h.substr(11).strip_edges()
			for part in cookie_str.split(";"):
				var kv := part.strip_edges()
				if kv.begins_with("accessToken="):
					_access_token = kv.substr(12)
					print("BOSSBridge.sign_in: session token acquired")
					return
	push_warning("BOSSBridge.sign_in: accessToken not found in Set-Cookie header")


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _request(method: String, path: String, body: Dictionary) -> Dictionary:
	if _backend == null:
		push_warning("BOSSBridge._request: no backend set — call set_backend() before configure()")
		error.emit("BOSS bridge backend not configured.")
		return {}
	return await _backend.request(method, path, body)
