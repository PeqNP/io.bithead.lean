## Copyright © 2026 Bithead LLC. All rights reserved.

## LocalBOSSBridgeBackend — offline backend for editor / no-server testing.
##
## Loads res://fixtures/factory-floor.json on _ready() and holds it as an
## in-memory Dictionary. All BOSSBridge.post() / .patch() calls are handled
## here and applied to that snapshot immediately, simulating successful server
## responses. poll_snapshot() re-emits the updated snapshot so FactoryFloor
## re-renders exactly as it would with a real server.

class_name LocalBOSSBridgeBackend extends BOSSBridgeBackend

const FIXTURE_PATH := "res://fixtures/factory-floor.json"

var _snapshot: Dictionary = {}


func _ready() -> void:
	_load_fixture()


func request(method: String, path: String, body: Dictionary) -> Dictionary:
	# GET /lean/factory-floor/{id} — used by BOSSBridge.poll_snapshot()
	if method == "GET" and path.begins_with("/lean/factory-floor/"):
		return _snapshot

	if method == "PATCH":
		return _handle_patch(path, body)

	if method == "POST":
		return _handle_post(path, body)

	print("LocalBOSSBridgeBackend: unhandled %s %s" % [method, path])
	return {}


# ---------------------------------------------------------------------------
# Fixture loading
# ---------------------------------------------------------------------------

func _load_fixture() -> void:
	if not FileAccess.file_exists(FIXTURE_PATH):
		push_error("LocalBOSSBridgeBackend: fixture not found at %s" % FIXTURE_PATH)
		return
	var text: String = FileAccess.get_file_as_string(FIXTURE_PATH)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("LocalBOSSBridgeBackend: failed to parse fixture: %s" % json.get_error_message())
		return
	var parsed = json.get_data()
	if parsed is Dictionary:
		_snapshot = parsed
		print("LocalBOSSBridgeBackend: loaded fixture (%d lines, %d inventories)" % [
			(_snapshot.get("lines", []) as Array).size(),
			(_snapshot.get("inventories", []) as Array).size(),
		])
	else:
		push_error("LocalBOSSBridgeBackend: fixture root must be a Dictionary")


# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------

func _handle_patch(path: String, body: Dictionary) -> Dictionary:
	var re := RegEx.new()

	# PATCH /lean/station/{id}/position  {posX, posY}
	re.compile("^/lean/station/(\\d+)/position$")
	var m := re.search(path)
	if m:
		_update_station(int(m.get_string(1)), {"posX": body.get("posX", 0), "posY": body.get("posY", 0)})
		return {}

	# PATCH /lean/station/view-state/{id}  {overlay}
	re.compile("^/lean/station/view-state/(\\d+)$")
	m = re.search(path)
	if m:
		_update_station(int(m.get_string(1)), {"overlay": body.get("overlay", "none")})
		return {}

	# PATCH /lean/line/{id}/position  {x, y}
	re.compile("^/lean/line/(\\d+)/position$")
	m = re.search(path)
	if m:
		_update_entity("lines", int(m.get_string(1)), {"gridX": body.get("x", 0), "gridY": body.get("y", 0)})
		return {}

	# PATCH /lean/inventory/{id}/position  {x, y}
	re.compile("^/lean/inventory/(\\d+)/position$")
	m = re.search(path)
	if m:
		_update_entity("inventories", int(m.get_string(1)), {"gridX": body.get("x", 0), "gridY": body.get("y", 0)})
		return {}

	# PATCH /lean/line/{id}/focused  {focused}
	re.compile("^/lean/line/(\\d+)/focused$")
	m = re.search(path)
	if m:
		_update_entity("lines", int(m.get_string(1)), {"focused": body.get("focused", false)})
		return {}

	# PATCH /lean/inventory/{id}/focused  {focused}
	re.compile("^/lean/inventory/(\\d+)/focused$")
	m = re.search(path)
	if m:
		_update_entity("inventories", int(m.get_string(1)), {"focused": body.get("focused", false)})
		return {}

	# PATCH /lean/line/{id}/locked  {locked}
	re.compile("^/lean/line/(\\d+)/locked$")
	m = re.search(path)
	if m:
		_update_entity("lines", int(m.get_string(1)), {"locked": body.get("locked", false)})
		return {}

	# PATCH /lean/inventory/{id}/locked  {locked}
	re.compile("^/lean/inventory/(\\d+)/locked$")
	m = re.search(path)
	if m:
		_update_entity("inventories", int(m.get_string(1)), {"locked": body.get("locked", false)})
		return {}

	print("LocalBOSSBridgeBackend: unhandled PATCH %s" % path)
	return {}


func _handle_post(path: String, body: Dictionary) -> Dictionary:
	print("LocalBOSSBridgeBackend: stub POST %s %s" % [path, str(body)])
	return {}


# ---------------------------------------------------------------------------
# In-memory mutation helpers
# ---------------------------------------------------------------------------

func _update_station(station_id: int, fields: Dictionary) -> void:
	for line: Dictionary in (_snapshot.get("lines", []) as Array):
		for station: Dictionary in (line.get("stations", []) as Array):
			if station.get("id", -1) == station_id:
				for key in fields:
					station[key] = fields[key]
				return
	push_warning("LocalBOSSBridgeBackend: station %d not found" % station_id)


func _update_entity(collection: String, entity_id: int, fields: Dictionary) -> void:
	for entity: Dictionary in (_snapshot.get(collection, []) as Array):
		if entity.get("id", -1) == entity_id:
			for key in fields:
				entity[key] = fields[key]
			return
	push_warning("LocalBOSSBridgeBackend: %s id=%d not found" % [collection, entity_id])
