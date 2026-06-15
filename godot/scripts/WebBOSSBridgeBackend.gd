## Copyright © 2026 Bithead LLC. All rights reserved.

## WebBOSSBridgeBackend — production backend that makes real HTTP calls.
##
## Reads BOSSBridge._base_url and BOSSBridge._access_token at request time so
## it always uses the current session state without needing its own copies.
## Emits BOSSBridge.error on any HTTP or parse failure.

class_name WebBOSSBridgeBackend extends BOSSBridgeBackend


func request(method: String, path: String, body: Dictionary) -> Dictionary:
	var url: String = BOSSBridge._base_url + path
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not BOSSBridge._access_token.is_empty():
		headers.append("Cookie: accessToken=%s" % BOSSBridge._access_token)
	var body_string: String = JSON.stringify(body) if not body.is_empty() else ""

	var http := HTTPRequest.new()
	add_child(http)

	var http_method: int
	match method:
		"POST":  http_method = HTTPClient.METHOD_POST
		"PATCH": http_method = HTTPClient.METHOD_PATCH
		_:       http_method = HTTPClient.METHOD_GET

	var err: int = http.request(url, headers, http_method, body_string)
	if err != OK:
		push_error("WebBOSSBridgeBackend: failed to send %s %s (err %d)" % [method, path, err])
		BOSSBridge.error.emit("Failed to reach BOSS server.")
		http.queue_free()
		return {}

	var result: Array = await http.request_completed
	http.queue_free()

	var http_code: int = result[1]
	var body_bytes: PackedByteArray = result[3]

	if http_code < 200 or http_code >= 300:
		var msg: String = "Server returned %d for %s %s" % [http_code, method, path]
		push_error("WebBOSSBridgeBackend: " + msg)
		BOSSBridge.error.emit(msg)
		return {}

	if body_bytes.is_empty():
		return {}

	var json := JSON.new()
	var parse_err: int = json.parse(body_bytes.get_string_from_utf8())
	if parse_err != OK:
		var msg: String = "Failed to parse JSON response from %s %s" % [method, path]
		push_error("WebBOSSBridgeBackend: " + msg)
		BOSSBridge.error.emit(msg)
		return {}

	var data = json.get_data()
	if data is Dictionary:
		return data
	return {}
