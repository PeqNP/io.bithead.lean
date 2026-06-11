## Copyright © 2026 Bithead LLC. All rights reserved.

## Singleton: HTTP communication with BOSS server + snapshot polling.
##
## Access via the BOSSBridge autoload node. All HTTP calls are async.
##
## Signals:
##   snapshot_updated(snapshot) - Emitted when a fresh FactoryFloor snapshot arrives.
##   error(message)             - Emitted on any HTTP error; FactoryFloor shows ErrorModal.
##
## Usage:
##   BOSSBridge.configure(factory_id, base_url)
##   await BOSSBridge.post("/lean/line", body)
##   await BOSSBridge.patch("/lean/line/1/locked", body)

extends Node

signal snapshot_updated(snapshot: Dictionary)
signal error(message: String)

var _factory_id: int = -1
var _base_url: String = ""

## Read-only access to the current factory id.
var factory_id: int:
	get: return _factory_id


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


## POST to a BOSS route. Returns the parsed response Dictionary, or empty on error.
func post(path: String, body: Dictionary) -> Dictionary:
	return await _request("POST", path, body)


## PATCH a BOSS route. Returns the parsed response Dictionary, or empty on error.
func patch(path: String, body: Dictionary) -> Dictionary:
	return await _request("PATCH", path, body)


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _request(method: String, path: String, body: Dictionary) -> Dictionary:
	if _base_url.is_empty():
		push_warning("BOSSBridge._request called before configure() set base_url")
		error.emit("BOSS bridge not configured.")
		return {}

	var url := _base_url + path
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body_string := JSON.stringify(body) if not body.is_empty() else ""

	var http := HTTPRequest.new()
	add_child(http)

	var http_method: int
	match method:
		"POST":  http_method = HTTPClient.METHOD_POST
		"PATCH": http_method = HTTPClient.METHOD_PATCH
		_:       http_method = HTTPClient.METHOD_GET

	var err := http.request(url, headers, http_method, body_string)
	if err != OK:
		push_error("BOSSBridge: Failed to send %s %s (err %d)" % [method, path, err])
		error.emit("Failed to reach BOSS server.")
		http.queue_free()
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	var _result_code: int       = result[0]
	var http_code: int          = result[1]
	var _headers: PackedStringArray = result[2]
	var body_bytes: PackedByteArray = result[3]

	if http_code < 200 or http_code >= 300:
		var msg := "Server returned %d for %s %s" % [http_code, method, path]
		push_error("BOSSBridge: " + msg)
		error.emit(msg)
		return {}

	if body_bytes.is_empty():
		return {}

	var json := JSON.new()
	var parse_err := json.parse(body_bytes.get_string_from_utf8())
	if parse_err != OK:
		var msg := "Failed to parse JSON response from %s %s" % [method, path]
		push_error("BOSSBridge: " + msg)
		error.emit(msg)
		return {}

	var data = json.get_data()
	if data is Dictionary:
		return data
	return {}
